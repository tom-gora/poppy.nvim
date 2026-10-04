require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")

---@param win integer|nil
---@return boolean
M.try_focus_win = function(win)
	if win and api.nvim_win_is_valid(win) then
		api.nvim_set_current_win(win)
		return true
	end
	return false
end

---@return boolean
M.session_is_open = function()
	return state.windows.wrapper_win ~= nil and api.nvim_win_is_valid(state.windows.wrapper_win)
end

---@return string|nil
M.session_get_current_poppy_name = function()
	return state.windows.current_poppy_name
end

---@param name string
M.hide_poppy = function(name)
	local runtime = state.runtime(name)
	if not runtime then
		return
	end
	runtime.active = false
	runtime.hidden = true
	runtime.win = nil
end

-- Closes any previous hint first; otherwise orphaned hints accumulate across switches.
M.show_menu_hint = function()
	M.close_menu_hint()
	local content_win = state.windows.content_win
	if content_win and api.nvim_win_is_valid(content_win) then
		local render = require("poppy.core.ui.render")
		state.windows.menu_hint_win, state.windows.menu_hint_buf =
			render.hints.create_bottom_right(content_win, M.keys())
	end
end

M.close_menu_hint = function()
	if state.windows.menu_hint_win and api.nvim_win_is_valid(state.windows.menu_hint_win) then
		api.nvim_win_close(state.windows.menu_hint_win, true)
	end
	state.windows.menu_hint_win = nil
	state.windows.menu_hint_buf = nil
end

---@return PoppyKeys?
M.keys = function()
	return state.windows.opts and state.windows.opts.keys
end

---@param field string
---@return any
M.opts_field = function(field)
	if not state.windows.opts then
		return nil
	end
	return state.windows.opts[field]
end

---@param buf integer
---@param apply fun()
M.with_modifiable = function(buf, apply)
	api.nvim_set_option_value("modifiable", true, { buf = buf })
	local ok, err = xpcall(apply, debug.traceback)
	-- pcall the restore too: if apply() died because the buffer was deleted,
	-- setting the option again raises "Invalid buffer id" and would mask the
	-- real error. Every caller passes a panel created nomodifiable, so false
	-- is the value to put back.
	pcall(api.nvim_set_option_value, "modifiable", false, { buf = buf })
	if not ok then
		error(err, 0)
	end
end

---@type string[]
M.NORM_TERM_MODES = { "n", "t" }

---@return boolean
M.ensure_setup = function()
	if state and state.windows and state.windows.opts then
		return true
	end
	M.notify_error("setup() must be called before using poppy.nvim")
	return false
end

---@param template string
---@param ... any
M.notify_warn = function(template, ...)
	vim.notify("Poppy: " .. string.format(template, ...), vim.log.levels.WARN)
end

---@param template string
---@param ... any
M.notify_error = function(template, ...)
	vim.notify("Poppy: " .. string.format(template, ...), vim.log.levels.ERROR)
end

---@param poppy PoppyResolvedConfig
---@return "exec"|"file"|"shell"
M.category_from_resolved = function(poppy)
	return poppy.exec and "exec" or poppy.file and "file" or "shell"
end

-- The pane's own scratch (from view.content.create) is a |scratch-buffer|: the
-- docs are explicit that it is kept when its window closes and must be deleted
-- explicitly. Two places dropped the reference without doing that --
-- M.enter_landing and the WinClosed rebuild in session/autocommands.lua -- so
-- both call this instead.
--
-- The buftype test is the guard that makes it safe. In file mode
-- state.windows.content_buf IS the live file buffer, so deleting by identity
-- would destroy it; a file buffer has buftype="" and a terminal has
-- buftype="terminal", so this can only ever reach a scratch. The two further
-- guards keep that true whatever the pane's bookkeeping does: never a buffer a
-- live poppy owns (the same in_use test cleanup() already applies), and never
-- one currently on screen.
---@param buf integer|nil
---@return boolean dropped
M.drop_scratch_buffer = function(buf)
	if not buf or not api.nvim_buf_is_valid(buf) then
		return false
	end
	if vim.bo[buf].buftype ~= "nofile" then
		return false
	end
	for _, rt in pairs(state.poppies_runtime) do
		if rt and rt.bufnr == buf then
			return false
		end
	end
	for _, win in ipairs(api.nvim_list_wins()) do
		if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
			return false
		end
	end
	api.nvim_buf_delete(buf, { force = true })
	return true
end

local WIN_MARKER = "poppy_window"

---@param win integer
M.apply_win_marker = function(win)
	api.nvim_win_set_var(win, WIN_MARKER, true)
end

---@param win integer|nil
---@return boolean
M.is_poppy_window = function(win)
	if not win or not api.nvim_win_is_valid(win) then
		return false
	end
	local _, val = pcall(api.nvim_win_get_var, win, WIN_MARKER)
	return val == true
end

-- Drop a poppy. Called from failure paths: missing binary, file()
-- returning nil/empty, defensive post-spawn jobstart failure. At the
-- moment this runs, the poppy has never been successfully opened,
-- so poppies_runtime[name] is already nil.
---@param name string
---@param reason? string
---@return boolean was_active
M.drop_poppy = function(name, reason)
	for i, entry in ipairs(state.poppies_configured) do
		if entry.name == name then
			table.remove(state.poppies_configured, i)
			break
		end
	end
	state.poppies_runtime[name] = nil
	if state.windows.opts then
		state.windows.opts.poppies[name] = nil
		state.windows.opts.poppies_resolved[name] = nil
		table.insert(state.windows.opts.dropped_names, name)
	end
	local was_active = state.windows.current_poppy_name == name
	if was_active then
		state.windows.current_poppy_name = nil
	end
	if state.windows.last_poppy_name == name then
		state.windows.last_poppy_name = nil
	end
	if reason then
		M.notify_warn("dropped poppy '%s': %s", name, reason)
	end
	if M.session_is_open() then
		local view = require("poppy.core.ui.view")
		view.refresh_poppies()
	end
	return was_active
end

return M
