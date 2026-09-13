require("poppy._types")

local M = {}

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

-- Closes any previous hint first; otherwise orphaned hints accumulate across switches.
M.show_menu_hint = function()
	M.close_menu_hint()
	local content_win = state.windows.content_win
	if content_win and vim.api.nvim_win_is_valid(content_win) then
		local render = require("poppy.core.ui.render")
		state.windows.menu_hint_win, state.windows.menu_hint_buf =
			render.hints.create_bottom_right(content_win, M.keys())
	end
end

M.close_menu_hint = function()
	if state.windows.menu_hint_win and vim.api.nvim_win_is_valid(state.windows.menu_hint_win) then
		vim.api.nvim_win_close(state.windows.menu_hint_win, true)
	end
	state.windows.menu_hint_win = nil
	state.windows.menu_hint_buf = nil
end

M.keys = function()
	return state.windows.opts and state.windows.opts.keys
end

---@param field string
---@return any
M.opts_field = function(field)
	if not state.windows.opts then return nil end
	return state.windows.opts[field]
end

---@param buf integer
---@param fn fun()
M.with_modifiable = function(buf, fn)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	fn()
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

---@type string[]
M.NORM_TERM_MODES = { "n", "t" }

M.ensure_setup = function()
	if state and state.windows and state.windows.opts then
		return true
	end
	vim.notify("Poppy: setup() must be called before opening", vim.log.levels.WARN)
	return false
end

---@param poppy PoppyResolvedConfig
---@return "exec"|"file"|"shell"
M.cat = function(poppy)
	if poppy.exec then
		return "exec"
	elseif poppy.file then
		return "file"
	end
	return "shell"
end

local WIN_MARKER = "poppy_window"

---@param win integer
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
