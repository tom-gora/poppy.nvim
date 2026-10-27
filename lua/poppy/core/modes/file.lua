require("poppy._types")

local M = {}
local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

local normalize = function(path)
	return fn.fnamemodify(path, ":p")
end

-- A reused buffer is only valid if it still points at `file_path`; a dynamic file function
-- can resolve elsewhere between opens.
---@param name string
---@param file_path string
---@return integer|nil
local reusable = function(name, file_path)
	local runtime = state.runtime(name)
	if not (runtime and runtime.hidden and runtime.bufnr) then
		return nil
	end
	if not api.nvim_buf_is_valid(runtime.bufnr) then
		return nil
	end
	if normalize(api.nvim_buf_get_name(runtime.bufnr)) ~= normalize(file_path) then
		pcall(api.nvim_buf_delete, runtime.bufnr, { force = true })
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

-- :edit gives a real file buffer (filetype, checktime, normal load path); a hand-built buffer
-- is modifiable but treated as never-read-from-disk and :w would fail with E13.
---@param parent_win integer
---@param file_path string
---@return integer? bufnr
local open_file = function(parent_win, file_path)
	local ok, err = pcall(api.nvim_win_call, parent_win, function()
		vim.cmd("edit " .. fn.fnameescape(file_path))
	end)
	if not ok then
		shared.notify_warn("could not open %s: %s", file_path, tostring(err))
		return nil
	end
	return api.nvim_win_get_buf(parent_win)
end

---@param poppy_name string
---@param poppy_opts PoppyResolvedConfig
---@param parent_win integer
---@return boolean ok
M.run = function(poppy_name, poppy_opts, parent_win)
	if poppy_opts.mode ~= "file" then
		return false
	end

	local file_path = shared.expand_file_value(poppy_opts.value)
	if file_path == "" then
		shared.notify_warn("poppy '%s' file value resolved to empty at open; dropping", poppy_name)
		return false
	end

	local reused = reusable(poppy_name, file_path)

	---@param reason string
	---@return false
	local fail = function(reason)
		shared.drop_poppy(poppy_name, reason)
		return false
	end

	local file_missing = fn.filereadable(file_path) ~= 1
	if file_missing and not reused then
		local ok, err = M.create_file_with_parents(file_path)
		if not ok then
			shared.notify_warn("poppy '%s' could not create %s: %s", poppy_name, file_path, tostring(err))
			return fail("create failed at open")
		end
		file_missing = false
	end

	local bufnr
	if reused then
		-- Clean + file still exists: re-read so external edits show up.
		-- Modified: reattach untouched. Vanished: leave alone, :w recreates at the same path.
		if not vim.bo[reused].modified then
			api.nvim_buf_set_lines(reused, 0, -1, false, fn.readfile(file_path))
			api.nvim_set_option_value("modified", false, { buf = reused })
		end
		bufnr = reused
	else
		bufnr = open_file(parent_win, file_path)
		if not bufnr then
			return fail("edit failed at open")
		end
	end

	attach(poppy_name, bufnr, parent_win, poppy_opts.title)
	return true
end

---@param path string Absolute path.
---@return boolean ok
---@return string? err
M.create_file_with_parents = function(path)
	local parent = vim.fs.dirname(path)
	if parent ~= "" then
		local mk_ok, mk_err = pcall(fn.mkdir, parent, "p")
		if not mk_ok then
			return false, "could not create " .. parent .. ": " .. tostring(mk_err)
		end
	end
	local wr_ok, wr_err = pcall(fn.writefile, {}, path)
	if not wr_ok then
		return false, tostring(wr_err)
	end
	return true
end

return M
