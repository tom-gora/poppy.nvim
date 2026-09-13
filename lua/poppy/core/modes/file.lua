require("poppy._types")

local M = {}
local state = require("poppy.core.session.state")

---@param name string
---@return integer|nil
local usable = function(name)
	local entry = state.poppy(name)
	local runtime = entry and entry.runtime_state
	if not (runtime and runtime.hidden and runtime.bufnr) then
		return nil
	end
	if not vim.api.nvim_buf_is_valid(runtime.bufnr) then
		return nil
	end
	return runtime.bufnr
end

---@param poppy_name string
---@param poppy_opts PoppyResolvedConfig
---@param parent_win integer
---@return void
M.run = function(poppy_name, poppy_opts, parent_win)
	local bufnr = usable(poppy_name)
	if bufnr then
		vim.api.nvim_buf_set_var(bufnr, "poppy_popup", poppy_name)
	else
		bufnr = vim.api.nvim_create_buf(false, false)
		local file_val = type(poppy_opts.file) == "function" and poppy_opts.file() or poppy_opts.file
		local file_path = vim.fn.expand(file_val)
		if vim.fn.filereadable(file_path) ~= 1 then
			vim.fn.writefile({}, file_path)
		end
		-- Load via buffer API rather than :edit: :edit is window-level and
		-- can load into a different buffer than `bufnr` when no window
		-- owns it yet. Manual BufRead fires ftplugin/autocmds like :edit does.
		local lines = vim.fn.readfile(file_path, "b")
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		pcall(vim.api.nvim_buf_set_name, bufnr, file_path)
		pcall(vim.api.nvim_exec_autocmds, "BufRead", {
			buffer = bufnr,
			modeline = false,
		})
		-- Reset 'modified' so a later :bd doesn't need "!"
		vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
		vim.bo[bufnr].buflisted = false
		vim.bo[bufnr].bufhidden = "hide"
		vim.bo[bufnr].swapfile = false
		vim.api.nvim_buf_set_var(bufnr, "poppy_popup", poppy_name)
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
