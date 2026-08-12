local M = {}
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")

---@param wrapper_win integer
---@param list_panel_width integer
---@return integer? win
---@return integer? buf
M.create = function(wrapper_win, list_panel_width)
	local buf = vim.api.nvim_create_buf(false, true)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local ext_nu = vim.o.number
	local ext_rnu = vim.o.relativenumber

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		-- account for solid border providing some padding for readability
		-- the bodrer does not exceed the wrapper's size
		width = math.min(wrapper_conf.width - list_panel_width - 2),
		height = wrapper_conf.height - 2,
		--
		anchor = "NW",
		col = 0,
		row = 0,
		style = "minimal",
		border = "solid",
		zindex = layout.POPPY_Z_INDEX,
		focusable = true,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, true, config)

	style.apply_content_style(win, ext_nu, ext_rnu)
	vim.api.nvim_win_set_var(win, "poppy_ui_window", true)
	return win, buf
end

return M
