require("poppy._types")

local M = {}
local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

local normalize = function(path)
	return fn.fnamemodify(path, ":p")
end

-- Returns a hidden buffer only if it still points at `file_path`. A dynamic
-- file function can resolve elsewhere between opens, and a buffer for the old
-- path is dropped rather than reattached under the new file's name.
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

-- Open the file for real in the target window. A buffer built by hand
-- (readfile + set_lines + set_name) is modifiable but Vim still treats it as
-- never-read-from-disk, so :w fails with E13 "File exists (add ! to
-- override)". Going through :edit gives a genuine file buffer and, for free,
-- filetype detection, checktime and the rest of the normal load path.
--
-- Only ever called for a fresh open. Reloading a reused buffer is done in
-- place instead, because :edit! would unload that buffer and the BufUnload
-- handler would read it as the poppy dying.
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
---@param on_die? fun(poppy_name: string)  -- accepted for interface symmetry with modes/term.lua; unused
---@return boolean ok
M.run = function(poppy_name, poppy_opts, parent_win, _on_die)
	local raw_val
	if type(poppy_opts.file) == "function" then
		raw_val = poppy_opts.file()
	else
		raw_val = poppy_opts.file
	end
	if raw_val == nil or raw_val == "" then
		shared.notify_warn("poppy '%s' file function returned %s at open; dropping", poppy_name, raw_val == nil and "nil" or "empty string")
		return false
	end
	local file_path = fn.expand(raw_val)

	local reused = reusable(poppy_name, file_path)
	local is_fresh = reused == nil

	-- Every callsite below is on a fresh-open path: the mkdir/writefile block is
	-- guarded by is_fresh, and open_file is only reached on the `not reused`
	-- branch. So there is no adopted buffer here to protect or clean up. If a
	-- fail path is ever added to the reuse branch, buffer handling belongs there.
	---@param reason string
	---@return false
	local fail = function(reason)
		shared.drop_poppy(poppy_name, reason)
		return false
	end

	local file_missing = fn.filereadable(file_path) ~= 1
	if file_missing and is_fresh then
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
		file_missing = false
	end

	local bufnr
	if reused then
		-- A clean buffer whose file still exists is re-read, so external edits
		-- show up. A modified one is reattached untouched, and a file that
		-- vanished is left alone -- :w recreates it at the same path.
		local modified = api.nvim_get_option_value("modified", { buf = reused })
		if not file_missing and not modified then
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

return M
