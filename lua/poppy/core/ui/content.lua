local M = {}
local style = require("poppy.core.ui.style")

M.create = function(wrapper_win, hints_panel_width, list_panel_width)
	local buf = vim.api.nvim_create_buf(false, true)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)

	local width = wrapper_conf.width - hints_panel_width - list_panel_width
	local col = hints_panel_width > 0 and hints_panel_width + 1 or 0

	local config = {
		relative = "win",
		width = width - 2,
		height = wrapper_conf.height - 2,
		col = col,
		row = 0,
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
