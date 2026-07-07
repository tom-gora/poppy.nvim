local M = {}
local style = require("poppy.ui.style")

M.create = function(wrapper_win, sidebar_left_width, sidebar_right_width)
	local buf = vim.api.nvim_create_buf(false, true)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)

	local width = wrapper_conf.width - sidebar_left_width - sidebar_right_width

	local config = {
		relative = "win",
		width = width - 2,
		height = wrapper_conf.height,
		col = sidebar_left_width + 1,
		row = 0,
		style = "minimal",
		border = "none",
		zindex = 202,
		focusable = true,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, true, config)
	style.apply_content_style(win)
	return win, buf
end

return M
