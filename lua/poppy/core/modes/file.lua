require("poppy._types")

local M = {}
local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

---@param name string
---@return integer|nil
local usable = function(name)
	local runtime = state.runtime(name)
	if not (runtime and runtime.hidden and runtime.bufnr) then
		return nil
	end
	if not api.nvim_buf_is_valid(runtime.bufnr) then
		return nil
	end
	return runtime.bufnr
end

---@param poppy_name string
---@param bufnr integer
---@param parent_win integer
---@param title string
local attach = function(poppy_name, bufnr, parent_win, title)
	vim.bo[bufnr].buflisted = false
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].swapfile = false
	api.nvim_buf_set_var(bufnr, "poppy_popup", poppy_name)
	api.nvim_win_set_buf(parent_win, bufnr)
	state.poppies_runtime[poppy_name] = {
		active = true,
		hidden = false,
		bufnr = bufnr,
		win = parent_win,
		title = title,
	}
end

---@param poppy_name string
---@param poppy_opts PoppyResolvedConfig
---@param parent_win integer
---@param on_die? fun(poppy_name: string)  -- accepted for interface symmetry with modes/term.lua; unused
---@return boolean ok
M.run = function(poppy_name, poppy_opts, parent_win, _on_die)
	local bufnr = usable(poppy_name)
	if not bufnr then
		bufnr = api.nvim_create_buf(false, false)
	end

	local raw_val
	if type(poppy_opts.file) == "function" then
		raw_val = poppy_opts.file()
	else
		raw_val = poppy_opts.file
	end
	if raw_val == nil or raw_val == "" then
		shared.notify_warn("poppy '%s' file function returned %s at open; dropping", poppy_name, raw_val == nil and "nil" or "empty string")
		pcall(api.nvim_buf_delete, bufnr, { force = true })
		return false
	end
	local file_path = fn.expand(raw_val)

	---@param reason string
	---@return false
	local fail = function(reason)
		shared.drop_poppy(poppy_name, reason)
		pcall(api.nvim_buf_delete, bufnr, { force = true })
		return false
	end

	if fn.filereadable(file_path) ~= 1 then
		local parent = vim.fs.dirname(file_path)
		if parent ~= "" then
			local mk_ok, mk_err = pcall(fn.mkdir, parent, "p")
			if not mk_ok then
				shared.notify_warn("poppy '%s' could not create %s: %s", poppy_name, parent, tostring(mk_err))
				return fail("mkdir failed at open")
			end
		end
		local wr_ok, wr_err = pcall(fn.writefile, {}, file_path)
		if not wr_ok then
			shared.notify_warn("poppy '%s' could not write %s: %s", poppy_name, file_path, tostring(wr_err))
			return fail("writefile failed at open")
		end
	end

	local lines = fn.readfile(file_path, "b")
	api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	pcall(api.nvim_buf_set_name, bufnr, file_path)
	pcall(api.nvim_exec_autocmds, "BufRead", {
		buffer = bufnr,
		modeline = false,
	})
	api.nvim_set_option_value("modified", false, { buf = bufnr })

	attach(poppy_name, bufnr, parent_win, poppy_opts.title)
	return true
end

return M
