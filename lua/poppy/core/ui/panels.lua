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
}

local function resize_content(win, height)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local cur = vim.api.nvim_win_get_config(win)
	vim.api.nvim_win_set_config(win, {
		relative = cur.relative,
		width = cur.width,
		height = height,
		col = cur.col,
		row = cur.row,
		win = cur.win,
	})
end

M.create = function(wrapper_win, sw)
	local hints_win, hints_buf = hints_panel.create(wrapper_win)
	local list_win, list_buf = list_panel.create(wrapper_win, sw)
	state.wrapper_win = wrapper_win
	state.hints_win = hints_win
	state.hints_buf = hints_buf
	state.list_win = list_win
	state.list_buf = list_buf
	state.sw = sw
	state.hidden = false

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
	resize_content(content_win, wc.height - 1)
end

M.show = function(content_win)
	if not state.hidden then
		return
	end
	local wc = vim.api.nvim_win_get_config(state.wrapper_win)
	local sw = state.sw

	state.hints_win = hints_panel.recreate(state.wrapper_win, state.hints_buf)
	state.list_win = list_panel.recreate(state.wrapper_win, state.list_buf, sw)
	state.hidden = false
	resize_content(content_win, wc.height - 3)
end

M.toggle = function(content_win)
	if state.hidden then
		M.show(content_win)
	else
		M.hide(content_win)
	end
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

M.get_hints_buf = function()
	return state.hints_buf
end

M.get_list_buf = function()
	return state.list_buf
end

return M