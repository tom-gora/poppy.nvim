require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local shared = require("poppy.core.shared")

-- Routes focus between content and list. With menu_autohide, also toggles
-- sidebar visibility (mount + narrow content / unmount + widen content).
M.toggle_menu = function()
	if not shared.ensure_setup() then
		return
	end
	if state.windows.is_landing or not shared.session_is_open() then
		return
	end

	local want_focus = not view.is_menu_focused()

	if shared.opts_field("menu_autohide") then
		view.set_visible(want_focus, state.windows.content_win)
	end

	local keymaps = require("poppy.core.session.keymaps")
	if want_focus then
		local list_buf = view.get_list_buf()
		if list_buf and api.nvim_buf_is_valid(list_buf) then
			keymaps.setup_list_keys(list_buf)
		end
	end

	view.set_focused(want_focus)

	view.refresh_poppies()

	if want_focus then
		keymaps.focus_list_with_cursor()
	else
		shared.try_focus_win(state.windows.content_win)
	end
end

M.exit_menu = function()
	if not shared.ensure_setup() then
		return
	end
	if not view.is_menu_focused() or state.windows.is_landing then
		return
	end

	if shared.opts_field("menu_autohide") then
		view.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	else
		view.set_focused(false)
	end

	view.refresh_poppies()
	if shared.try_focus_win(state.windows.content_win) then
		local cbuf = api.nvim_win_get_buf(state.windows.content_win)
		if vim.bo[cbuf].buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end
end

return M
