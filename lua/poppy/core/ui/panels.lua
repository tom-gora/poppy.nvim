local M = {}
local hints_panel = require("poppy.core.ui.hints_panel")
local list_panel = require("poppy.core.ui.list_panel")
local header_panel = require("poppy.core.ui.header_panel")

local state = {
	wrapper_win = nil,
	hints_win = nil,
	hints_buf = nil,
	list_win = nil,
	list_buf = nil,
	header_win = nil,
	header_buf = nil,
	menu_width = 25,
	hidden = false,
	header_height = 0,
}

local valid_buf = function(b)
	return b and vim.api.nvim_buf_is_valid(b)
end

local resize_content = function(win, width, height, row)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local cur = vim.api.nvim_win_get_config(win)
	vim.api.nvim_win_set_config(win, {
		relative = cur.relative,
		width = width,
		height = height,
		col = cur.col,
		row = row or cur.row,
		win = cur.win,
	})
end

local close_panel = function(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

-- Reuse the existing buffer if valid, else create. `create` returns
-- (win, buf); `recreate` takes the buf and returns the win. `skip`
-- nils out the state entries (matches the original hdr==0 path).
local ensure_panel = function(buf_key, win_key, create, recreate, skip)
	if skip then
		state[win_key] = nil
		state[buf_key] = nil
		return nil, nil
	end
	if valid_buf(state[buf_key]) then
		local buf = state[buf_key]
		state[win_key] = recreate(buf)
		return state[win_key], buf
	end
	local win, buf = create()
	state[win_key] = win
	state[buf_key] = buf
	return win, buf
end

local rebuild = function(hl, focusable)
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	local menu_width = state.menu_width
	local hdr = state.header_height

	close_panel(state.hints_win)
	close_panel(state.list_win)
	close_panel(state.header_win)

	if hdr > 0 and valid_buf(state.header_buf) then
		state.header_win = header_panel.recreate(state.wrapper_win, state.header_buf, menu_width, wc.width - menu_width)
	end
	state.list_win = list_panel.recreate(state.wrapper_win, state.list_buf, menu_width, focusable, hl, hdr)
	state.hints_win = hints_panel.recreate(state.wrapper_win, state.hints_buf, menu_width, wc.width, wc.height, hl, "menu")
end

M.create = function(wrapper_win, menu_width, hint_height, header_height)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hl = hint_height or 1
	local hdr = header_height or 0

	local list_win, list_buf = ensure_panel("list_buf", "list_win",
		function() return list_panel.create(wrapper_win, menu_width, false, hl, hdr) end,
		function(buf) return list_panel.recreate(wrapper_win, buf, menu_width, false, hl, hdr) end)

	local hints_win, hints_buf = ensure_panel("hints_buf", "hints_win",
		function() return hints_panel.create(wrapper_win, menu_width, wc.width, wc.height - 1, hl, "menu") end,
		function(buf) return hints_panel.recreate(wrapper_win, buf, menu_width, wc.width, wc.height - 1, hl, "menu") end)

	local header_win, header_buf = ensure_panel("header_buf", "header_win",
		function() return header_panel.create(wrapper_win, menu_width, wc.width - menu_width) end,
		function(buf) return header_panel.recreate(wrapper_win, buf, menu_width, wc.width - menu_width) end,
		hdr == 0)

	state.wrapper_win = wrapper_win
	state.menu_width = menu_width
	state.hidden = false
	state.header_height = hdr

	return { hints_win = hints_win, hints_buf = hints_buf, list_win = list_win, list_buf = list_buf }
end

M.create_landing = function(wrapper_win, header_height)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hdr = header_height or 0

	local list_win, list_buf = ensure_panel("list_buf", "list_win",
		function() return list_panel.create(wrapper_win, wc.width, true, nil, hdr) end,
		function(buf) return list_panel.recreate(wrapper_win, buf, wc.width, true, nil, hdr) end)

	local hints_win, hints_buf = ensure_panel("hints_buf", "hints_win",
		function() return hints_panel.create(wrapper_win, nil, nil, nil, nil, "landing") end,
		function(buf) return hints_panel.recreate(wrapper_win, buf, nil, nil, nil, nil, "landing") end)

	local header_win, header_buf = ensure_panel("header_buf", "header_win",
		function() return header_panel.create(wrapper_win) end,
		function(buf) return header_panel.recreate(wrapper_win, buf) end,
		hdr == 0)

	state.wrapper_win = wrapper_win
	state.menu_width = wc.width
	state.hidden = false
	state.header_height = hdr

	return { hints_win = hints_win, hints_buf = hints_buf, list_win = list_win, list_buf = list_buf }
end

M.focus_menu = function()
	if state.hidden then
		return
	end
	rebuild(3, true)
end

M.unfocus_menu = function()
	if state.hidden then
		return
	end
	rebuild(4, false)
end

M.hide_menu = function(content_win)
	if state.hidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	close_panel(state.hints_win)
	close_panel(state.list_win)
	close_panel(state.header_win)
	state.hints_win = nil
	state.list_win = nil
	state.header_win = nil
	state.hidden = true
	resize_content(content_win, wc.width - 2, wc.height - 2, 0)
end

M.show_menu = function(content_win)
	if not state.hidden then
		return
	end
	rebuild(3, true)
	state.hidden = false
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	resize_content(content_win, wc.width - state.menu_width - 2, wc.height - 2)
end

M.destroy = function()
	for _, win in ipairs({ state.hints_win, state.list_win, state.header_win }) do
		close_panel(win)
	end
	state.hints_win = nil
	state.list_win = nil
	state.header_win = nil
	state.wrapper_win = nil
end

M.is_hidden = function()
	return state.hidden
end
M.get_hints_buf = function()
	return state.hints_buf
end
M.get_list_buf = function()
	return state.list_buf
end
M.get_list_win = function()
	return state.list_win
end
M.get_header_buf = function()
	return state.header_buf
end

return M
