local M = {}
local style = require("poppy.core.ui.style")

M.create = function(wrapper_win, list_panel_width, header_lines, hint_lines)
	local buf = vim.api.nvim_create_buf(false, true)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local hdr = header_lines or 0
	local hnt = hint_lines or 0

	local config = {
		relative = "win",
		width = wrapper_conf.width - list_panel_width - 2,
		height = wrapper_conf.height,
		col = 0,
		row = hdr,
		style = "minimal",
		border = "solid",
		zindex = 202,
		focusable = true,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, true, config)
	style.apply_content_style(win)
	return win, buf
end

return M
