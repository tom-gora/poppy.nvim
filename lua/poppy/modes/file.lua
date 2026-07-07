local M = {}
local session = require("poppy.core.session")

M.run = function(poppy_name, opts, parent_win)
	local poppy_opts = opts.poppies[poppy_name]
	if not poppy_opts or not parent_win then
		return
	end

	local p_state = session.poppies[poppy_name]
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

	session.poppies[poppy_name] =
		{ active = true, hidden = false, bufnr = bufnr, win = parent_win, title = poppy_opts.title }
end

M.close_session = function(poppy_name)
	local p_state = session.poppies[poppy_name]
	local win = p_state and p_state.win
	if win and vim.api.nvim_win_is_valid(win) then
		if #vim.api.nvim_list_wins() == 1 then
			vim.cmd("enew")
		end
		vim.api.nvim_win_close(win, true)
	end
	if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
		vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
	end
	session.poppies[poppy_name] = nil
end

M.hide_session = function(poppy_name)
	local p_state = session.poppies[poppy_name]
	local win = p_state and p_state.win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	if p_state then
		p_state.active = false
		p_state.hidden = true
	end
end

return M

