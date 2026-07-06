local M = {}
local style = require("poppy.ui.style")
local poppy_state = require("poppy.state")
local namespace = vim.api.nvim_create_namespace("poppy_sidebar_right")

M.create = function(wrapper_win)
	local buf = vim.api.nvim_create_buf(false, true)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	
	local width = 22
	local config = {
		relative = "win",
		width = width,
		height = wrapper_conf.height,
		col = wrapper_conf.width - width, -- Attached to right
		row = 0,
		style = "minimal",
		border = "none",
		zindex = 201,
		focusable = false,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_right_sidebar_style(win)
	return win, buf
end

M.update = function(buf, sorted_popups)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	
	local lines = { " Configured Popups:", "" }
	
	for i, item in ipairs(sorted_popups) do
		local title = item.config.title or item.name
		table.insert(lines, string.format(" [%d] %s", i, title))
	end
	
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

return M
