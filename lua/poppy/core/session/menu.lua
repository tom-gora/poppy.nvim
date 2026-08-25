---@diagnostic disable: param-type-mismatch
local M = {}

local state = require("poppy.core.session.state")
local panels = require("poppy.core.ui.panels")
local shared = require("poppy.core.shared")

-- <C-_> is the single focus router between content and the list panel,
-- but what "toggling off" means depends on menu_autohide:
--
--   autohide = false: sidebar is always visible. Toggle just moves
--                     focus between content_win and list_win; visibility
--                     is never touched.
--
--   autohide = true:  sidebar was hidden on switch_by_name. Toggle
--                     brings the sidebar back (narrower content) and
--                     focuses list; toggle again hides it again
--                     (full-width content, hint shown).
M.toggle_menu = function()
	if not shared.ensure_setup() then
		return
	end
	if state.windows.is_landing or not shared.session_is_open() then
		return
	end

	local want_focus = not panels.is_menu_focused()

	if shared.opts_field("menu_autohide") then
		panels.set_visible(want_focus, state.windows.content_win)
	end

	local keymaps = require("poppy.core.session.keymaps")
	-- Remounting the sidebar in autohide mode produces a fresh list_buf;
	-- rebind the list keys so <Esc>/select/kill work after the toggle.
	if want_focus then
		local list_buf = panels.get_list_buf()
		if list_buf and vim.api.nvim_buf_is_valid(list_buf) then
			keymaps.setup_list_keys(list_buf)
		end
	end

	panels.set_focused(want_focus)

	panels.refresh_poppies()

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
	if not panels.is_menu_focused() or state.windows.is_landing then
		return
	end

	if shared.opts_field("menu_autohide") then
		panels.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	else
		panels.set_focused(false)
	end

	panels.refresh_poppies()
	if shared.try_focus_win(state.windows.content_win) then
		local cbuf = vim.api.nvim_win_get_buf(state.windows.content_win)
		if vim.bo[cbuf].buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end
end

return M