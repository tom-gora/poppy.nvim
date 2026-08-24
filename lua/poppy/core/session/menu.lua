---@diagnostic disable: param-type-mismatch
local M = {}

local state = require("poppy.core.session.state")
local panels = require("poppy.core.ui.panels")
local shared = require("poppy.core.shared")

M.focus_list_with_cursor = function()
	local list_win = panels.get_list_win()
	if not shared.try_focus_win(list_win) then
		return
	end
	if not state.windows.current_poppy_name then
		return
	end
	local current_entry = state.poppy(state.windows.current_poppy_name)
	if current_entry then
		local idx = state.poppy_index(state.windows.current_poppy_name)
		if idx then
			pcall(vim.api.nvim_win_set_cursor, list_win, { idx, 0 })
		end
	end
end

-- One path for both autohide on/off: the autohide flag only decides
-- whether to also toggle sidebar visibility; focusability toggles
-- unconditionally because the list panel exists in both modes (just
-- not visible when autohide hides it).
M.toggle_menu = function()
	if not shared.ensure_setup() then return end
	if state.windows.is_landing or not shared.session_is_open() then
		return
	end

	local want_focus = not panels.is_menu_focused()

	if shared.opts_field("menu_autohide") then
		panels.set_visible(want_focus, state.windows.content_win)
	end
	panels.set_focused(want_focus)

	-- Lazy require to break the actions.lua <-> menu.lua cycle. actions.lua
	-- doesn't depend on menu at module scope; this is the only call site.
	require("poppy.core.session.actions").refresh_panels()
	if want_focus then
		M.focus_list_with_cursor()
	else
		shared.try_focus_win(state.windows.content_win)
	end
end

M.exit_menu = function()
	if not shared.ensure_setup() then return end
	if not panels.is_menu_focused() or state.windows.is_landing then
		return
	end

	if shared.opts_field("menu_autohide") then
		panels.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	else
		panels.set_focused(false)
	end

	require("poppy.core.session.actions").refresh_panels()
	if shared.try_focus_win(state.windows.content_win) then
		local cbuf = vim.api.nvim_win_get_buf(state.windows.content_win)
		if vim.bo[cbuf].buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end
end

-- Buffer-local keymaps for the list and content panes. Bound to the
-- buffer because there are multiple windows in the plugin UI and we
-- only want these to fire when the relevant pane is focused.

M.setup_list_keys = function(buf)
	local keys = shared.keys()

	local function opts_for(desc)
		return { buffer = buf, desc = desc }
	end

	vim.keymap.set(shared.NORM_TERM_MODES, keys.select, function()
		-- Lazy require to break the actions.lua <-> menu.lua cycle.
		local actions = require("poppy.core.session.actions")
		if vim.v.count > 0 then
			actions.switch_by_index(vim.v.count)
		else
			actions.switch_by_cursor()
		end
	end, opts_for("Poppy: Select"))

	vim.keymap.set(shared.NORM_TERM_MODES, keys.kill, function()
		local actions = require("poppy.core.session.actions")
		if vim.v.count > 0 then
			actions.kill_by_index(vim.v.count)
		else
			actions.kill_by_cursor()
		end
	end, opts_for("Poppy: Kill"))

	vim.keymap.set(shared.NORM_TERM_MODES, keys.exit_menu, function()
		M.exit_menu()
	end, opts_for("Poppy: Exit menu"))
end

M.setup_content_keys = function(buf)
	local keys = shared.keys()

	local function opts_for(desc)
		return { buffer = buf, desc = desc }
	end

	vim.keymap.set(shared.NORM_TERM_MODES, keys.poppy_action, function()
		M.toggle_menu()
	end, opts_for("Poppy: Toggle menu"))
end

return M
