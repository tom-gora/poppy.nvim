local M = {}
local poppy_state = require("poppy.core.session.poppy_state")

-- Reuse a hidden poppy's buffer if it's still alive. Returns nil otherwise.
local usable = function(name)
	local ps = poppy_state.poppies[name]
	if not (ps and ps.hidden and ps.bufnr) then
		return nil
	end
	if not vim.api.nvim_buf_is_valid(ps.bufnr) then
		return nil
	end
	return ps.bufnr
end

M.run = function(poppy_name, opts, parent_win)
	local poppy_opts = opts.poppies_resolved[poppy_name]
	if not poppy_opts or not parent_win then
		return
	end

	local bufnr = usable(poppy_name)
	if bufnr then
		vim.api.nvim_buf_set_var(bufnr, "poppy_popup", poppy_name)
	else
		bufnr = vim.api.nvim_create_buf(false, false)
		local file_val = poppy_opts.file
		if type(file_val) == "function" then
			file_val = file_val()
		end
		local file_path = vim.fn.expand(file_val)
		if vim.fn.filereadable(file_path) ~= 1 then
			vim.fn.writefile({}, file_path)
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

	poppy_state.poppies[poppy_name] = {
		active = true,
		hidden = false,
		bufnr = bufnr,
		win = parent_win,
		title = poppy_opts.title,
	}
end

return M