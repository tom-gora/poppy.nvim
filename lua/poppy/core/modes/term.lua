local M = {}
local session = require("poppy.core.session")
local util = require("poppy.core.util")

local get_or_create_buffer = function(poppy_name, opts)
	local poppy_opts = opts.poppies_resolved[poppy_name]
	local p_state = session.poppies[poppy_name]
	local bufnr = (p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr))
			and p_state.bufnr
		or vim.api.nvim_create_buf(false, false)

	if not p_state or (not p_state.active and not p_state.hidden) then
		vim.api.nvim_buf_call(bufnr, function()
			pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
			util.term_spawn(util.term_resolve_command(poppy_opts), {
				on_exit = function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						vim.api.nvim_buf_delete(bufnr, { force = true })
					end
					if session.is_open() and session.get_current_poppy_name() == poppy_name then
						session.kill_current()
					else
						session.poppies[poppy_name] = nil
					end
				end,
			})
		end)
	end

	pcall(vim.api.nvim_buf_set_name, bufnr, " Poppy: " .. poppy_name .. " ")
	return bufnr
end

M.run = function(poppy_name, opts, parent_win)
	local poppy_opts = opts.poppies_resolved[poppy_name]
	if not poppy_opts or not parent_win then
		return
	end

	local bufnr = get_or_create_buffer(poppy_name, opts)

	vim.api.nvim_win_set_buf(parent_win, bufnr)

	session.poppies[poppy_name] =
		{ active = true, hidden = false, bufnr = bufnr, win = parent_win, title = poppy_opts.title }
end

return M
