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
	sw = 25,
	hidden = false,
	autohidden = false,
	hint_lines = 1,
	header_lines = 0,
}

local function resize_content(win, width, height, row)
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

local function close_panel(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

local function rebuild(hl, focusable)
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	local sw = state.sw
	local hdr = state.header_lines

	close_panel(state.hints_win)
	close_panel(state.list_win)
	close_panel(state.header_win)

	if hdr > 0 then
		state.header_win = header_panel.recreate(state.wrapper_win, state.header_buf, sw, wc.width - sw)
	end
	state.list_win = list_panel.recreate(state.wrapper_win, state.list_buf, sw, focusable, hl, hdr)
	state.hints_win = hints_panel.recreate(state.wrapper_win, state.hints_buf, sw, wc.width, wc.height, hl)
	state.hint_lines = hl
end

M.create = function(wrapper_win, sw, hint_lines, header_lines)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hl = hint_lines or 1
	local hdr = header_lines or 0
	local list_win, list_buf = list_panel.create(wrapper_win, sw, false, hl, hdr)
	local hints_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[hints_buf].modifiable = false
	local hints_win = hints_panel.recreate(wrapper_win, hints_buf, sw, wc.width, wc.height - 1, hl)

	local header_win, header_buf = nil, nil
	if hdr > 0 then
		header_win, header_buf = header_panel.create(wrapper_win, sw, wc.width - sw)
	end

	state.wrapper_win = wrapper_win
	state.hints_win = hints_win
	state.hints_buf = hints_buf
	state.list_win = list_win
	state.list_buf = list_buf
	state.header_win = header_win
	state.header_buf = header_buf
	state.sw = sw
	state.hidden = false
	state.autohidden = false
	state.hint_lines = hl
	state.header_lines = hdr

	return { hints_win = hints_win, hints_buf = hints_buf, list_win = list_win, list_buf = list_buf }
end

M.create_landing = function(wrapper_win, header_lines)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hdr = header_lines or 0
	local list_win, list_buf = list_panel.create(wrapper_win, wc.width, true, nil, hdr)
	local hints_win, hints_buf = hints_panel.create(wrapper_win)
	local header_win, header_buf = nil, nil
	if hdr > 0 then
		header_win, header_buf = header_panel.create(wrapper_win)
	end

	state.wrapper_win = wrapper_win
	state.hints_win = hints_win
	state.hints_buf = hints_buf
	state.list_win = list_win
	state.list_buf = list_buf
	state.header_win = header_win
	state.header_buf = header_buf
	state.sw = wc.width
	state.hidden = false
	state.autohidden = false
	state.hint_lines = 1
	state.header_lines = hdr

	return { hints_win = hints_win, hints_buf = hints_buf, list_win = list_win, list_buf = list_buf }
end

M.hide = function(content_win)
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

M.show = function(content_win)
	if not state.hidden then
		return
	end
	rebuild(4, false)
	state.hidden = false
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	resize_content(content_win, wc.width - state.sw - 2, wc.height - 2)
end

M.toggle = function(content_win)
	if state.hidden then
		M.show(content_win)
	else
		M.hide(content_win)
	end
end

M.focus_sidebar = function()
	if state.autohidden or state.hidden then
		return
	end
	rebuild(3, true)
end

M.unfocus_sidebar = function()
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
	resize_content(content_win, wc.width - state.sw - 2, wc.height - 2)
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
M.get_hints_win = function()
	return state.hints_win
end

return M
