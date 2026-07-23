local M = {}
local style = require("poppy.core.ui.style")
local geometry = require("poppy.core.ui.geometry")

local open_with = function(buf, poppy_opts, width_override)
	local width, height, row = geometry.compute_dimensions(poppy_opts, vim.o.columns, vim.o.lines, width_override)
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = row,
		style = "minimal",
		border = "none",
		zindex = 200,
		focusable = false,
	}
	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_border_style(win)
	vim.api.nvim_win_set_var(win, "poppy_ui_window", true)
	return win
end

M.create = function(poppy_opts, width_override)
	local buf = vim.api.nvim_create_buf(false, true)
	local win = open_with(buf, poppy_opts, width_override)
	return win, buf
end

M.recreate = function(buf, poppy_opts, width_override)
	return open_with(buf, poppy_opts, width_override)
end

return M
