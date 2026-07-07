local M = {}
local state = require("poppy.state")
local utils = require("poppy.modes.utils")

local active_wins = {}

M.run = function(poppy_name, opts, parent_win)
	local poppy_opts = opts.poppies[poppy_name]
	if not poppy_opts or not parent_win then return end

	local p_state = state.poppies[poppy_name]
	local bufnr = (p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr)) and p_state.bufnr or vim.api.nvim_create_buf(false, false)

	vim.api.nvim_win_set_buf(parent_win, bufnr)
	active_wins[poppy_name] = parent_win

	if not p_state or not p_state.hidden then
		vim.api.nvim_buf_call(bufnr, function()
			utils.spawn_term(os.getenv("SHELL") or "bash", {
				on_exit = function()
					if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
					state.poppies[poppy_name] = nil
					active_wins[poppy_name] = nil
					local manager = require("poppy.ui.manager")
					if manager.is_open() and manager.current_poppy_name == poppy_name then
						manager.kill_current()
					end
				end,
			})
		end)
	end

	pcall(vim.api.nvim_buf_set_name, bufnr, " Poppy: " .. poppy_name .. " ")
	state.poppies[poppy_name] = { active = true, hidden = false, bufnr = bufnr, win = active_wins[poppy_name], title = poppy_opts.title }
end

M.close_session = function(poppy_name)
	local win = active_wins[poppy_name]
	if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	local p_state = state.poppies[poppy_name]
	if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
		vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
	end
	state.poppies[poppy_name] = nil
	active_wins[poppy_name] = nil
	vim.cmd("redrawstatus")
end

M.hide_session = function(poppy_name)
	local win = active_wins[poppy_name]
	if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	if state.poppies[poppy_name] then
		state.poppies[poppy_name].active = false
		state.poppies[poppy_name].hidden = true
	end
	active_wins[poppy_name] = nil
	vim.cmd("redrawstatus")
end

return M
