local M = {}
local style = require("poppy.core.ui.style")
local namespace = vim.api.nvim_create_namespace("poppy_hints_panel")
local sb_width = 25

M.create = function(wrapper_win, width)
	if width then
		sb_width = width
	end
	local buf = vim.api.nvim_create_buf(false, true)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)

	local config = {
		relative = "win",
		width = sb_width,
		height = wrapper_conf.height,
		col = 0,
		row = 0,
		style = "minimal",
		border = "none",
		zindex = 201,
		focusable = false,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)
	return win, buf
end

M.update = function(buf, prefix, count)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

	local range = count > 0 and ("[1-%d]"):format(count) or ""
	local lines = {
		"",
		" " .. prefix .. "       Poppy Prefix",
		"",
		" " .. range .. "   Switch",
		" k       Kill",
	}

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.api.nvim_buf_set_extmark(buf, namespace, 1, 0, {
		end_row = 1,
		line_hl_group = "PoppyActive",
	})
end

return M
