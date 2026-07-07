local M = {}
local state = require("poppy.state")

local active_wins = {}

M.run = function(poppy_name, opts, parent_win)
	local poppy_opts = opts.poppies[poppy_name]
	if not poppy_opts or not parent_win then return end

	local p_state = state.poppies[poppy_name]
	local bufnr
	if p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
		bufnr = p_state.bufnr
		pcall(vim.api.nvim_buf_set_var, bufnr, "poppy_popup", poppy_name)
	else
		bufnr = vim.api.nvim_create_buf(false, false)
		local file_val = poppy_opts.file
		if type(file_val) == "function" then
			file_val = file_val()
		end
		local file_path = vim.fn.expand(file_val)
		if vim.fn.filereadable(file_path) == 1 then
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("edit " .. vim.fn.fnameescape(file_path))
			end)
		end
		vim.bo[bufnr].buflisted = false
		vim.bo[bufnr].bufhidden = "hide"
		vim.bo[bufnr].swapfile = false
		vim.api.nvim_buf_set_var(bufnr, "poppy_popup", poppy_name)
	end

	vim.api.nvim_win_set_buf(parent_win, bufnr)
	active_wins[poppy_name] = parent_win

	state.poppies[poppy_name] = { active = true, hidden = false, bufnr = bufnr, win = active_wins[poppy_name], title = poppy_opts.title }
	vim.cmd("redrawstatus")
end

M.close_session = function(poppy_name)
	local win = active_wins[poppy_name]
	if win and vim.api.nvim_win_is_valid(win) then
		if #vim.api.nvim_list_wins() == 1 then vim.cmd("enew") end
		vim.api.nvim_win_close(win, true)
	end
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
