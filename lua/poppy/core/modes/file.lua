require("poppy._types")

local M = {}
local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

local normalize = function(path)
	return fn.fnamemodify(path, ":p")
end

-- A reused buffer is only valid if it still points at `file_path`. A dynamic file function
-- can resolve elsewhere between opens; a buffer for the old path is dropped, not reattached.
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
	---@param on_die? fun(poppy_name: string)
	local attach = function(poppy_name, bufnr, parent_win, title, on_die)
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
		-- Background file poppies need a repaint when their buffer goes away. The active case is
		-- already handled by the plugin-level BufUnload autocmd in session/autocommands.lua; skip
		-- on_die here to avoid a double recover.
		if on_die and state.windows.current_poppy_name ~= poppy_name then
			api.nvim_create_autocmd("BufUnload", {
				group = "poppy_group",
				buffer = bufnr,
				once = true,
				callback = function()
					if state.runtime(poppy_name) and not state.windows.current_poppy_name then
						on_die(poppy_name)
					end
				end,
			})
		end
	end

-- :edit gives a real file buffer (filetype, checktime, normal load path). A hand-built
-- buffer (readfile + set_lines + set_name) is modifiable but treated as never-read-from-disk;
-- :w would fail with E13. Only called on a fresh open -- reuse reloads in place because
-- :edit! would unload the buffer and the BufUnload handler would read it as the poppy dying.
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

	-- Fail path is on a fresh-open path: no adopted buffer to clean up.
	---@param reason string
	---@return false
	local fail = function(reason)
		shared.drop_poppy(poppy_name, reason)
		return false
	end

	local file_missing = fn.filereadable(file_path) ~= 1
	if file_missing and is_fresh then
		local ok, err = create_file_with_parents(file_path)
		if not ok then
			shared.notify_warn("poppy '%s' could not create %s: %s", poppy_name, file_path, tostring(err))
			return fail("create failed at open")
		end
		file_missing = false
	end

	---@param path string Absolute path to create.
	---@return boolean ok
	---@return string? err
	local function create_file_with_parents(path)
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

	local bufnr
	if reused then
		-- Clean + file still exists: re-read so external edits show up.
	-- Modified: reattach untouched. Vanished: leave alone, :w recreates at the same path.
	-- (Comment spans the if/else; the line below sets `modified` for the unmodified branch.)
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

	attach(poppy_name, bufnr, parent_win, poppy_opts.title, on_die)
	return true
end

---Create an empty file at `path`, including any missing parent directories.
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
