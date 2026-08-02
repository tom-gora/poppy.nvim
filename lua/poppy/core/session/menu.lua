local M = {}

local state = require("poppy.core.session.state")
local panels = require("poppy.core.ui.panels")
local poppy_state = require("poppy.core.session.poppy_state")
local shared = require("poppy.core.shared")

local focus = function(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		return true
	end
	return false
end

local focus_list_with_cursor = function()
	local list_win = panels.get_list_win()
	if not focus(list_win) then
		return
	end
	if not state.current_poppy_name then
		return
	end
	for i = 1, #poppy_state.poppies do
		local entry = poppy_state.poppies[i]
		if type(entry) == "table" and entry.name == state.current_poppy_name then
			pcall(vim.api.nvim_win_set_cursor, list_win, { i, 0 })
			break
		end
	end
end
M.focus_list_with_cursor = focus_list_with_cursor

-- Refresh the bottom-right hint to reflect the current keys.
local show_menu_hint = function()
	shared.close_menu_hint()
	local content_win = state.content_win
	if content_win and vim.api.nvim_win_is_valid(content_win) then
		local hints_panel = require("poppy.core.ui.hints_panel")
		state.menu_hint_win, state.menu_hint_buf =
			hints_panel.create_bottom_right(content_win, shared.keys())
	end
end

-- menu only needs `refresh_panels` from actions; lazy-require keeps the
-- dependency one-way (actions doesn't import menu).
local refresh = function()
	require("poppy.core.session.actions").refresh_panels(poppy_state.poppies)
end

M.toggle_menu = function()
	if state.is_landing or not shared.session_is_open() then
		return
	end

	if panels.is_hidden() then
		shared.close_menu_hint()
		panels.show_menu(state.content_win)
		state.menu_focused = true
		focus_list_with_cursor()
		refresh()
	else
		state.menu_focused = not state.menu_focused
		if state.menu_focused then
			panels.focus_menu()
			focus_list_with_cursor()
		else
			panels.unfocus_menu()
			focus(state.content_win)
		end
		refresh()
	end
end

M.exit_menu = function()
	if not state.menu_focused or state.is_landing then
		return
	end
	state.menu_focused = false
	if state.opts and state.opts.menu_autohide then
		panels.hide_menu(state.content_win)
		show_menu_hint()
	else
		panels.unfocus_menu()
	end
	refresh()
	if focus(state.content_win) then
		local cbuf = vim.api.nvim_win_get_buf(state.content_win)
		if vim.bo[cbuf].buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end
end

-- Buffer-local keymaps for the list and content panes. Bound to the
-- buffer because there are multiple windows in the plugin UI and we only
-- want these to fire when the relevant pane is focused. Called from
-- `actions.transition_to_content` and `actions.switch_by_name` (lazy-
-- required from there to break the actions <-> menu cycle).

local actions = require("poppy.core.session.actions")

M.setup_list_keys = function(buf)
	local keys = shared.keys()
	vim.keymap.set({ "n", "t" }, keys.select, function()
		if vim.v.count > 0 then
			actions.switch_by_index(vim.v.count)
		else
			actions.switch_by_cursor()
		end
	end, { buffer = buf, desc = "Poppy: Select" })

	vim.keymap.set({ "n", "t" }, keys.kill, function()
		if vim.v.count > 0 then
			actions.kill_by_index(vim.v.count)
		else
			actions.kill_by_cursor()
		end
	end, { buffer = buf, desc = "Poppy: Kill" })

	vim.keymap.set({ "n", "t" }, keys.exit_menu, function()
		M.exit_menu()
	end, { buffer = buf, desc = "Poppy: Exit menu" })
end

M.setup_content_keys = function(buf)
	local keys = shared.keys()
	vim.keymap.set({ "n", "t" }, keys.poppy_action, function()
		M.toggle_menu()
	end, { buffer = buf, desc = "Poppy: Toggle menu" })
end

return M