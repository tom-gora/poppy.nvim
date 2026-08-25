local M = {}

-- state.lua has no deps, so the require is safe at module load time.
local state = require("poppy.core.session.state")

M.try_focus_win = function(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		return true
	end
	return false
end

M.session_is_open = function()
	return state.windows.wrapper_win ~= nil and vim.api.nvim_win_is_valid(state.windows.wrapper_win)
end

M.session_get_current_poppy_name = function()
	return state.windows.current_poppy_name
end

---@param name string
M.hide_poppy = function(name)
	local entry = state.poppy(name)
	local runtime = entry and entry.runtime_state
	if not runtime then
		return
	end
	runtime.active = false
	runtime.hidden = true
	runtime.win = nil
end

-- Pair: open or refresh the bottom-right menu-hint window. Lazy-requires
-- render to avoid a load-time cycle (render imports shared).
-- Closes any previous hint first to prevent orphaned windows accumulating
-- across switch operations.
M.show_menu_hint = function()
	M.close_menu_hint()
	local content_win = state.windows.content_win
	if content_win and vim.api.nvim_win_is_valid(content_win) then
		local render = require("poppy.core.ui.render")
		state.windows.menu_hint_win, state.windows.menu_hint_buf =
			render.hints.create_bottom_right(content_win, M.keys())
	end
end

-- Close the bottom-right menu-hint window (if any) and drop the state
-- pointer. The hint lives in session state — not panels state — because
-- hints_panel owns the open+text but the rest of the session owns "is
-- the hint currently showing".
M.close_menu_hint = function()
	if state.windows.menu_hint_win and vim.api.nvim_win_is_valid(state.windows.menu_hint_win) then
		vim.api.nvim_win_close(state.windows.menu_hint_win, true)
	end
	state.windows.menu_hint_win = nil
	state.windows.menu_hint_buf = nil
end

-- Accessors for state.windows.opts fields. The `state.windows.opts and state.windows.opts.X`
-- chain was scattered across 10+ call sites; these centralize the
-- nil-safety and make the call sites read cleanly.
M.keys = function()
	return state.windows.opts and state.windows.opts.keys
end

-- Generic accessor for any state.windows.opts field. Returns nil if
-- setup() hasn't run. Use when you need a single field without a
-- dedicated accessor (e.g. one-off reads in modes or UI helpers).
---@param field string
---@return any
M.opts_field = function(field)
	if not state.windows.opts then return nil end
	return state.windows.opts[field]
end

M.with_modifiable = function(buf, fn)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	fn()
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

---@type string[]
M.NORM_TERM_MODES = { "n", "t" }

-- Setup gate. Returns true if state.windows.opts is set (i.e. setup()
-- has run); emits a WARN and returns false otherwise. No latch —
-- caller pays for every miss.
M.ensure_setup = function()
	if state and state.windows and state.windows.opts then
		return true
	end
	vim.notify("Poppy: setup() must be called before opening", vim.log.levels.WARN)
	return false
end

-- User-facing category from raw poppy config. Validation in
-- resolve_poppy guarantees exactly one of exec/file/shell is set.
M.cat = function(poppy)
	if poppy.exec then
		return "exec"
	elseif poppy.file then
		return "file"
	else
		return "shell"
	end
end

local WIN_MARKER = "poppy_window"

---@param win integer
---@return void
M.apply_win_marker = function(win)
	vim.api.nvim_win_set_var(win, WIN_MARKER, true)
end

---@param win integer|nil
---@return boolean
M.is_poppy_window = function(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	local _, val = pcall(vim.api.nvim_win_get_var, win, WIN_MARKER)
	return val == true
end

return M
