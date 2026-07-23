local M = {}
local style = require("poppy.core.ui.style")

M.create = function(wrapper_win, list_panel_width)
	local buf = vim.api.nvim_create_buf(false, true)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local ext_nu = vim.o.number
	local ext_rnu = vim.o.relativenumber

	local config = {
		relative = "win",
		width = wrapper_conf.width - list_panel_width - 2,
		height = wrapper_conf.height - 2,
		col = 0,
		row = 0,
		style = "minimal",
		border = "solid",
		zindex = 202,
		focusable = true,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, true, config)

	style.apply_content_style(win, { number = ext_nu, relativenumber = ext_rnu })
	vim.api.nvim_win_set_var(win, "poppy_ui_window", true)
	return win, buf
end

return M
