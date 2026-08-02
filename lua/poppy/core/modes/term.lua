local M = {}
local actions = require("poppy.core.session.actions")
local poppy_state = require("poppy.core.session.poppy_state")
local shared = require("poppy.core.shared")

local term_get_or_create_buffer = function(poppy_name, opts, p_state)
	local poppy_opts = opts.poppies_resolved and opts.poppies_resolved[poppy_name]
	if not poppy_opts then
		return nil
	end
	local bufnr = (p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr))
			and p_state.bufnr
		or vim.api.nvim_create_buf(false, false)
	pcall(vim.api.nvim_buf_set_name, bufnr, " Poppy: " .. poppy_name .. " ")
	return bufnr
end

local term_resolve_command = function(poppy_opts)
	if poppy_opts.mode == "term" and poppy_opts.shell then
		local shell = poppy_opts.shell
		if type(shell) == "function" then
			shell = shell()
		end
		return (shell and shell ~= "default") and shell or os.getenv("SHELL") or "bash"
	end
	return poppy_opts.exec
end

local term_spawn = function(command, opts)
	if type(command) == "function" then
		command = command()
	end
	if vim.fn.has("nvim-0.11") == 1 then
		opts.term = true
		return vim.fn.jobstart(command, opts)
	else
		---@diagnostic disable-next-line: deprecated
		return vim.fn.termopen(command, opts)
	end
end

M.run = function(poppy_name, opts, parent_win)
	local poppy_opts = opts.poppies_resolved[poppy_name]
	if not poppy_opts or not parent_win then
		return
	end

	local p_state = poppy_state.poppies[poppy_name]
	local bufnr = term_get_or_create_buffer(poppy_name, opts, p_state)
	if not bufnr then
		return
	end

	if not (p_state and (p_state.active or p_state.hidden)) then
		vim.api.nvim_buf_call(bufnr, function()
			vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
			term_spawn(term_resolve_command(poppy_opts), {
				on_exit = function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						vim.api.nvim_buf_delete(bufnr, { force = true })
					end
					if shared.session_is_open() and shared.session_get_current_poppy_name() == poppy_name then
						actions.kill_active()
					else
						poppy_state.poppies[poppy_name] = nil
					end
				end,
			})
		end)
	end

	vim.api.nvim_win_set_buf(parent_win, bufnr)

	poppy_state.poppies[poppy_name] = {
		active = true,
		hidden = false,
		bufnr = bufnr,
		win = parent_win,
		title = poppy_opts.title,
	}
end

return M