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
	mw = 25,
	hidden = false,
	autohidden = false,
	hint_height = 1,
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

local rebuild = function(hl, focusable)
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	local mw = state.mw
	local hdr = state.header_height

	close_panel(state.hints_win)
	close_panel(state.list_win)
	close_panel(state.header_win)

	if hdr > 0 and valid_buf(state.header_buf) then
		state.header_win = header_panel.recreate(state.wrapper_win, state.header_buf, mw, wc.width - mw)
	end
	state.list_win = list_panel.recreate(state.wrapper_win, state.list_buf, mw, focusable, hl, hdr)
	state.hints_win = hints_panel.recreate(state.wrapper_win, state.hints_buf, mw, wc.width, wc.height, hl, "menu")
	state.hint_height = hl
end

M.create = function(wrapper_win, mw, hint_height, header_height)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hl = hint_height or 1
	local hdr = header_height or 0

	local list_win, list_buf
	if valid_buf(state.list_buf) then
		list_buf = state.list_buf
		list_win = list_panel.recreate(wrapper_win, list_buf, mw, false, hl, hdr)
	else
		list_win, list_buf = list_panel.create(wrapper_win, mw, false, hl, hdr)
	end

	local hints_win, hints_buf
	if valid_buf(state.hints_buf) then
		hints_buf = state.hints_buf
		hints_win = hints_panel.recreate(wrapper_win, hints_buf, mw, wc.width, wc.height - 1, hl, "menu")
	else
		hints_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[hints_buf].modifiable = false
		hints_win = hints_panel.recreate(wrapper_win, hints_buf, mw, wc.width, wc.height - 1, hl, "menu")
	end

	local header_win, header_buf = nil, nil
	if hdr > 0 then
		if valid_buf(state.header_buf) then
			header_buf = state.header_buf
			header_win = header_panel.recreate(wrapper_win, header_buf, mw, wc.width - mw)
		else
			header_win, header_buf = header_panel.create(wrapper_win, mw, wc.width - mw)
		end
	end

	state.wrapper_win = wrapper_win
	state.hints_win = hints_win
	state.hints_buf = hints_buf
	state.list_win = list_win
	state.list_buf = list_buf
	state.header_win = header_win
	state.header_buf = header_buf
	state.mw = mw
	state.hidden = false
	state.autohidden = false
	state.hint_height = hl
	state.header_height = hdr

	return { hints_win = hints_win, hints_buf = hints_buf, list_win = list_win, list_buf = list_buf }
end

M.create_landing = function(wrapper_win, header_height)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hdr = header_height or 0

	local list_win, list_buf
	if valid_buf(state.list_buf) then
		list_buf = state.list_buf
		list_win = list_panel.recreate(wrapper_win, list_buf, wc.width, true, nil, hdr)
	else
		list_win, list_buf = list_panel.create(wrapper_win, wc.width, true, nil, hdr)
	end

	local hints_win, hints_buf
	if valid_buf(state.hints_buf) then
		hints_buf = state.hints_buf
		hints_win = hints_panel.recreate(wrapper_win, hints_buf, nil, nil, nil, nil, "landing")
	else
		hints_win, hints_buf = hints_panel.create(wrapper_win, "landing")
	end

	local header_win, header_buf = nil, nil
	if hdr > 0 then
		if valid_buf(state.header_buf) then
			header_buf = state.header_buf
			header_win = header_panel.recreate(wrapper_win, header_buf)
		else
			header_win, header_buf = header_panel.create(wrapper_win)
		end
	end

	state.wrapper_win = wrapper_win
	state.hints_win = hints_win
	state.hints_buf = hints_buf
	state.list_win = list_win
	state.list_buf = list_buf
	state.header_win = header_win
	state.header_buf = header_buf
	state.mw = wc.width
	state.hidden = false
	state.autohidden = false
	state.hint_height = 1
	state.header_height = hdr

	return { hints_win = hints_win, hints_buf = hints_buf, list_win = list_win, list_buf = list_buf }
end

local hide = function(content_win)
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

local show = function(content_win)
	if not state.hidden then
		return
	end
	rebuild(4, false)
	state.hidden = false
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	resize_content(content_win, wc.width - state.mw - 2, wc.height - 2)
end

local toggle = function(content_win)
	if state.hidden then
		show(content_win)
	else
		hide(content_win)
	end
end

M.focus_menu = function()
	if state.autohidden or state.hidden then
		return
	end
	rebuild(3, true)
end

M.unfocus_menu = function()
	if state.autohidden or state.hidden then
		return
	end
	rebuild(4, false)
end

M.hide_for_autohide = function(content_win)
	if state.hidden or state.autohidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	close_panel(state.hints_win)
	close_panel(state.list_win)
	close_panel(state.header_win)
	state.hints_win = nil
	state.list_win = nil
	state.header_win = nil
	state.autohidden = true
	resize_content(content_win, wc.width - 2, wc.height - 2, 0)
end

M.show_for_autohide = function(content_win)
	if not state.autohidden then
		return
	end
	rebuild(3, true)
	state.autohidden = false
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	resize_content(content_win, wc.width - state.mw - 2, wc.height - 2)
end

M.destroy = function()
	for _, win in ipairs({ state.hints_win, state.list_win, state.header_win }) do
		close_panel(win)
	end
	state.hints_win = nil
	state.list_win = nil
	state.header_win = nil
end

M.is_hidden = function()
	return state.hidden
end
M.is_autohidden = function()
	return state.autohidden
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
local get_hints_win = function()
	return state.hints_win
end
M.get_header_buf = function()
	return state.header_buf
end

return M
