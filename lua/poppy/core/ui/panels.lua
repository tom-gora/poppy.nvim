local M = {}
local hints_panel = require("poppy.core.ui.hints_panel")
local list_panel = require("poppy.core.ui.list_panel")

local state = {
	wrapper_win = nil,
	hints_win = nil,
	hints_buf = nil,
	list_win = nil,
	list_buf = nil,
	sw = 25,
	hidden = false,
	autohidden = false,
	hint_lines = 1,
}

local function resize_content(win, width, height)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local cur = vim.api.nvim_win_get_config(win)
	vim.api.nvim_win_set_config(win, {
		relative = cur.relative,
		width = width,
		height = height,
		col = cur.col,
		row = cur.row,
		win = cur.win,
	})
end

M.create = function(wrapper_win, sw, hint_lines)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hl = hint_lines or 1
	local list_win, list_buf = list_panel.create(wrapper_win, sw, false, hl)
	local hints_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[hints_buf].modifiable = false
	local hints_win = hints_panel.recreate(wrapper_win, hints_buf, sw, wc.width - sw, wc.height - hl)
	state.wrapper_win = wrapper_win
	state.hints_win = hints_win
	state.hints_buf = hints_buf
	state.list_win = list_win
	state.list_buf = list_buf
	state.sw = sw
	state.hidden = false
	state.autohidden = false
	state.hint_lines = hl

	return {
		hints_win = hints_win,
		hints_buf = hints_buf,
		list_win = list_win,
		list_buf = list_buf,
	}
end

M.create_landing = function(wrapper_win)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local list_win, list_buf = list_panel.create(wrapper_win, wc.width, true)
	local hints_win, hints_buf = hints_panel.create(wrapper_win)
	state.wrapper_win = wrapper_win
	state.hints_win = hints_win
	state.hints_buf = hints_buf
	state.list_win = list_win
	state.list_buf = list_buf
	state.sw = wc.width
	state.hidden = false
	state.autohidden = false
	state.hint_lines = 1

	return {
		hints_win = hints_win,
		hints_buf = hints_buf,
		list_win = list_win,
		list_buf = list_buf,
	}
end

M.hide = function(content_win)
	if state.hidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	vim.api.nvim_win_close(state.hints_win, true)
	vim.api.nvim_win_close(state.list_win, true)
	state.hints_win = nil
	state.list_win = nil
	state.hidden = true
	resize_content(content_win, wc.width - 2, wc.height - 1)
end

M.show = function(content_win)
	if not state.hidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	local sw = state.sw
	local hl = 1

	state.list_win = list_panel.recreate(state.wrapper_win, state.list_buf, sw, false, hl)
	state.hints_win = hints_panel.recreate(state.wrapper_win, state.hints_buf, sw, wc.width - sw, wc.height - hl, hl)
	state.hidden = false
	state.hint_lines = hl
	resize_content(content_win, wc.width - sw - 2, wc.height - 3)
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
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	local sw = state.sw
	local hl = 2

	vim.api.nvim_win_close(state.hints_win, true)
	vim.api.nvim_win_close(state.list_win, true)
	state.list_win = list_panel.recreate(state.wrapper_win, state.list_buf, sw, true, hl)
	state.hints_win = hints_panel.recreate(state.wrapper_win, state.hints_buf, sw, wc.width - sw, wc.height - hl, hl)
	state.hint_lines = hl
end

M.unfocus_sidebar = function()
	if state.autohidden or state.hidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	local sw = state.sw
	local hl = 1

	vim.api.nvim_win_close(state.hints_win, true)
	vim.api.nvim_win_close(state.list_win, true)
	state.list_win = list_panel.recreate(state.wrapper_win, state.list_buf, sw, false, hl)
	state.hints_win = hints_panel.recreate(state.wrapper_win, state.hints_buf, sw, wc.width - sw, wc.height - hl, hl)
	state.hint_lines = hl
end

M.hide_for_autohide = function(content_win)
	if state.hidden or state.autohidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	vim.api.nvim_win_close(state.hints_win, true)
	vim.api.nvim_win_close(state.list_win, true)
	state.hints_win = nil
	state.list_win = nil
	state.autohidden = true
	resize_content(content_win, wc.width - 2, wc.height - 1)
end

M.show_for_autohide = function(content_win)
	if not state.autohidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	local sw = state.sw
	local hl = 2

	state.list_win = list_panel.recreate(state.wrapper_win, state.list_buf, sw, true, hl)
	state.hints_win = hints_panel.recreate(state.wrapper_win, state.hints_buf, sw, wc.width - sw, wc.height - hl, hl)
	state.autohidden = false
	state.hint_lines = hl
	resize_content(content_win, wc.width - sw - 2, wc.height - 3)
end

M.destroy = function()
	for _, win in ipairs({ state.hints_win, state.list_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	state.hints_win = nil
	state.list_win = nil
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