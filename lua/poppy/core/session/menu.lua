local M = {}

local state = require("poppy.core.session.state")
local panels = require("poppy.core.ui.panels")
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
	if not state.windows.current_poppy_name then
		return
	end
	for i = 1, #state.poppies do
		local entry = state.poppies[i]
		if type(entry) == "table" and entry.name == state.windows.current_poppy_name then
			pcall(vim.api.nvim_win_set_cursor, list_win, { i, 0 })
			break
		end
	end
end
M.focus_list_with_cursor = focus_list_with_cursor

-- menu only needs `refresh_panels` from actions; lazy-require keeps the
-- dependency one-way (actions doesn't import menu).
local refresh = function()
	require("poppy.core.session.actions").refresh_panels(state.poppies)
end

M.toggle_menu = function()
	if state.windows.is_landing or not shared.session_is_open() then
		return
	end

	if state.windows.hidden then
		shared.close_menu_hint()
		panels.show_menu(state.windows.content_win)
		state.windows.menu_focused = true
		focus_list_with_cursor()
		refresh()
	else
		state.windows.menu_focused = not state.windows.menu_focused
		if state.windows.menu_focused then
			panels.focus_menu()
			focus_list_with_cursor()
		else
			panels.unfocus_menu()
			focus(state.windows.content_win)
		end
		refresh()
	end
end

M.exit_menu = function()
	if not state.windows.menu_focused or state.windows.is_landing then
		return
	end
	state.windows.menu_focused = false
	if state.windows.opts and state.windows.opts.menu_autohide then
		panels.hide_menu(state.windows.content_win)
		shared.show_menu_hint()
	else
		panels.unfocus_menu()
	end
	refresh()
	if focus(state.windows.content_win) then
		local cbuf = vim.api.nvim_win_get_buf(state.windows.content_win)
		if vim.bo[cbuf].buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end
end

-- Buffer-local keymaps for the list and content panes. Bound to the
-- buffer because there are multiple windows in the plugin UI and we only
-- want these to fire when the relevant pane is focused. Called from
-- `actions.transition_to_content` and `actions.switch_by_name`.

local actions = require("poppy.core.session.actions")

M.setup_list_keys = function(buf)
	local keys = shared.keys()

	---@param desc string
	---@return vim.api.keyset.keymap
	local opts_for = function(desc)
		return { buffer = buf, desc = desc }
	end

	vim.keymap.set(shared.NORM_TERM_MODES, keys.select, function()
		if vim.v.count > 0 then
			actions.switch_by_index(vim.v.count)
		else
			actions.switch_by_cursor()
		end
	end, opts_for("Poppy: Select"))

	vim.keymap.set(shared.NORM_TERM_MODES, keys.kill, function()
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

	---@param desc string
	---@return vim.api.keyset.keymap
	local opts_for = function(desc)
		return { buffer = buf, desc = desc }
	end

	vim.keymap.set(shared.NORM_TERM_MODES, keys.poppy_action, function()
		M.toggle_menu()
	end, opts_for("Poppy: Toggle menu"))
end

return M
