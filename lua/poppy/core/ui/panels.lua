local M = {}
local state = require("poppy.core.session.state")
local hints_panel = require("poppy.core.ui.hints_panel")
local list_panel = require("poppy.core.ui.list_panel")
local header_panel = require("poppy.core.ui.header_panel")

local valid_buf = function(b)
	return b and vim.api.nvim_buf_is_valid(b)
end

local resize_content = function(win, width, height, row)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local win_conf = vim.api.nvim_win_get_config(win)
	vim.api.nvim_win_set_config(win, {
		relative = win_conf.relative,
		width = width,
		height = height,
		col = win_conf.col,
		row = row or win_conf.row,
		win = win_conf.win,
	})
end

local close_panel = function(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

-- Tear down the side panel trio (hints/list/header) in one place. Used by
-- destroy() and hide_menu() — both walk the same three windows and zero
-- out the corresponding state fields. Module-private; callers outside
-- panels shouldn't be closing these directly.
local close_all_panels = function()
	close_panel(state.windows.hints_win)
	close_panel(state.windows.list_win)
	close_panel(state.windows.header_win)
	state.windows.hints_win = nil
	state.windows.list_win = nil
	state.windows.header_win = nil
end

-- Reuse the existing buffer if valid, else create. `create` returns
-- (win, buf); `recreate` takes the buf and returns the win. `skip`
-- nils out the state entries (matches the original header_height==0 path).
local ensure_panel = function(buf_key, win_key, create, recreate, skip)
	if skip then
		state.windows[win_key] = nil
		state.windows[buf_key] = nil
		return nil, nil
	end
	if valid_buf(state.windows[buf_key]) then
		local buf = state.windows[buf_key]
		state.windows[win_key] = recreate(buf)
		return state.windows[win_key], buf
	end
	local win, buf = create()
	state.windows[win_key] = win
	state.windows[buf_key] = buf
	return win, buf
end

local rebuild = function(hl, focusable)
	local wc = vim.api.nvim_win_get_config(state.windows.wrapper_win)
	local menu_width = state.windows.menu_width
	local header_height = state.windows.header_height

	close_panel(state.windows.hints_win)
	close_panel(state.windows.list_win)
	close_panel(state.windows.header_win)

	if header_height > 0 and valid_buf(state.windows.header_buf) then
		state.windows.header_win = header_panel.recreate(
			state.windows.wrapper_win,
			state.windows.header_buf,
			menu_width,
			wc.width - menu_width
		)
	end
	state.windows.list_win =
		list_panel.recreate(state.windows.wrapper_win, state.windows.list_buf, menu_width, focusable, hl, header_height)
	state.windows.hints_win = hints_panel.recreate(state.windows.wrapper_win, state.windows.hints_buf, {
		width = menu_width,
		col = wc.width,
		row = wc.height,
		height = hl,
		kind = "menu",
	})
end

M.create = function(wrapper_win, menu_width, hint_height, header_height)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hl = hint_height or 1
	local header_height = header_height or 0

	local list_win, list_buf = ensure_panel("list_buf", "list_win", function()
		return list_panel.create(wrapper_win, menu_width, false, hl, header_height)
	end, function(buf)
		return list_panel.recreate(wrapper_win, buf, menu_width, false, hl, header_height)
	end)

	local hints_win, hints_buf = ensure_panel("hints_buf", "hints_win", function()
		return hints_panel.create(
			wrapper_win,
			{ width = menu_width, col = wc.width, row = wc.height - 1, height = hl, kind = "menu" }
		)
	end, function(buf)
		return hints_panel.recreate(
			wrapper_win,
			buf,
			{ width = menu_width, col = wc.width, row = wc.height - 1, height = hl, kind = "menu" }
		)
	end)

	local header_win, header_buf = ensure_panel("header_buf", "header_win", function()
		return header_panel.create(wrapper_win, menu_width, wc.width - menu_width)
	end, function(buf)
		return header_panel.recreate(wrapper_win, buf, menu_width, wc.width - menu_width)
	end, header_height == 0)

	state.windows.wrapper_win = wrapper_win
	state.windows.menu_width = menu_width
	state.windows.hidden = false
	state.windows.header_height = header_height

	return { hints_win = hints_win, hints_buf = hints_buf, list_win = list_win, list_buf = list_buf }
end

M.create_landing = function(wrapper_win, header_height)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local header_height = header_height or 0

	local list_win, list_buf = ensure_panel("list_buf", "list_win", function()
		return list_panel.create(wrapper_win, wc.width, true, nil, header_height)
	end, function(buf)
		return list_panel.recreate(wrapper_win, buf, wc.width, true, nil, header_height)
	end)

	local hints_win, hints_buf = ensure_panel("hints_buf", "hints_win", function()
		return hints_panel.create(wrapper_win, { kind = "landing" })
	end, function(buf)
		return hints_panel.recreate(wrapper_win, buf, { kind = "landing" })
	end)

	local header_win, header_buf = ensure_panel("header_buf", "header_win", function()
		return header_panel.create(wrapper_win)
	end, function(buf)
		return header_panel.recreate(wrapper_win, buf)
	end, header_height == 0)

	state.windows.wrapper_win = wrapper_win
	state.windows.menu_width = wc.width
	state.windows.hidden = false
	state.windows.header_height = header_height

	return { hints_win = hints_win, hints_buf = hints_buf, list_win = list_win, list_buf = list_buf }
end

M.focus_menu = function()
	if state.windows.hidden then
		return
	end
	rebuild(3, true)
end

M.unfocus_menu = function()
	if state.windows.hidden then
		return
	end
	rebuild(4, false)
end

M.hide_menu = function(content_win)
	if state.windows.hidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.windows.wrapper_win)
	close_all_panels()
	state.windows.hidden = true
	resize_content(content_win, wc.width - 2, wc.height - 2, 0)
end

M.show_menu = function(content_win)
	if not state.windows.hidden then
		return
	end
	rebuild(3, true)
	state.windows.hidden = false
	local wc = vim.api.nvim_win_get_config(state.windows.wrapper_win)
	resize_content(content_win, wc.width - state.windows.menu_width - 2, wc.height - 2)
end

M.destroy = function()
	close_all_panels()
end

-- The single rule for "is this window one of ours?" Wrappers/content/list/
-- hints/header/bottom-right all set the marker on creation. Internal hop
-- detection (events.lua) reads it here. Add the marker via
-- `M.mark_poppy_window(win)` for any new panel type.
local UI_WINDOW_MARK = "poppy_ui_window"

M.mark_poppy_window = function(win)
	vim.api.nvim_win_set_var(win, UI_WINDOW_MARK, true)
end

M.is_poppy_window = function(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	local _, val = pcall(vim.api.nvim_win_get_var, win, UI_WINDOW_MARK)
	return val == true
end
M.get_hints_buf = function()
	return state.windows.hints_buf
end
M.get_list_buf = function()
	return state.windows.list_buf
end
M.get_list_win = function()
	return state.windows.list_win
end
M.get_header_buf = function()
	return state.windows.header_buf
end

return M
