require("poppy._types")

local M = {}
local session = require("poppy.core.session")
local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

---@param poppy_name string
---@param poppy_opts PoppyResolvedConfig
---@param p_state PoppySessionEntry?
---@return integer|nil bufnr
---@return boolean reused
local term_get_or_create_buffer = function(poppy_name, poppy_opts, p_state)
	local rt = p_state and p_state.runtime_state
	if rt and rt.hidden and rt.bufnr and vim.api.nvim_buf_is_valid(rt.bufnr) then
		return rt.bufnr, true
	end
	local bufnr = vim.api.nvim_create_buf(false, false)
	pcall(vim.api.nvim_buf_set_name, bufnr, " Poppy: " .. poppy_name .. " ")
	return bufnr, false
end

---@param poppy_opts PoppyResolvedConfig
---@return string|string[]|function|nil
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

---@param command string|string[]|function|nil
---@param opts table
---@return integer|nil
local term_spawn = function(command, opts)
	if type(command) == "function" then
		command = command()
	end
	if not command then
		return nil
	end
	if vim.fn.has("nvim-0.11") == 1 then
		opts.term = true
		return vim.fn.jobstart(command, opts)
	else
		---@diagnostic disable-next-line: deprecated
		return vim.fn.termopen(command, opts)
	end
end

---@param poppy_name string
---@param poppy_opts PoppyResolvedConfig
---@param parent_win integer
---@return void
M.run = function(poppy_name, poppy_opts, parent_win)
	if not poppy_opts or not parent_win then
		return
	end

	local p_state = state.poppy(poppy_name)
	local bufnr, reused = term_get_or_create_buffer(poppy_name, poppy_opts, p_state)
	if not bufnr then
		return
	end

	if not reused then
		vim.api.nvim_buf_call(bufnr, function()
			---@type vim.api.keyset.option
			local modified_opts = { buf = bufnr }
			vim.api.nvim_set_option_value("modified", false, modified_opts)
			---@type table
			local spawn_opts = {
				on_exit = function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						vim.api.nvim_buf_delete(bufnr, { force = true })
					end
					if shared.session_is_open() and shared.session_get_current_poppy_name() == poppy_name then
						session.kill_active()
					else
						local entry = state.poppy(poppy_name)
						if entry then
							entry.runtime_state = nil
						end
					end
				end,
			}
			local job_id = term_spawn(term_resolve_command(poppy_opts), spawn_opts)
			if not job_id then
				vim.notify(
					string.format(
						"Poppy exec command resolved to nil. Cannot spawn. Have you provided correct exec key in your config for poppy '%s'?",
						poppy_name
					),
					vim.log.levels.ERROR
				)
				bufnr = nil
			end
		end)
	end

	if not bufnr then
		return
	end

	vim.api.nvim_win_set_buf(parent_win, bufnr)

	state.poppy(poppy_name).runtime_state = {
		active = true,
		hidden = false,
		bufnr = bufnr,
		win = parent_win,
		title = poppy_opts.title,
	}
end

return M
