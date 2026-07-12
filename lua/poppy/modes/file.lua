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
		if vim.fn.filereadable(file_path) ~= 1 then
			pcall(vim.fn.writefile, {}, file_path)
		end
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("edit " .. vim.fn.fnameescape(file_path))
		end)
		vim.bo[bufnr].buflisted = false
		vim.bo[bufnr].bufhidden = "hide"
		vim.bo[bufnr].swapfile = false
		vim.api.nvim_buf_set_var(bufnr, "poppy_popup", poppy_name)
	end

	vim.api.nvim_win_set_buf(parent_win, bufnr)

	session.poppies[poppy_name] =
		{ active = true, hidden = false, bufnr = bufnr, win = parent_win, title = poppy_opts.title }
end

return M

