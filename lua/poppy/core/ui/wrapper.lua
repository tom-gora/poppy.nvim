require("poppy._types")

local M = {}
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

---@param buf integer
---@param poppy_opts? PoppyConfig
---@param width_override? integer
---@return integer? win
local open_with = function(buf, poppy_opts, width_override)
	local width, height, row = layout.compute_wrapper_dimensions(poppy_opts, vim.o.columns, vim.o.lines, width_override)
	---@type vim.api.keyset.win_config
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = row,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
	}
	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_border_style(win)
	shared.apply_win_marker(win)
	return win
end

---@param poppy_opts? PoppyConfig
---@param width_override? integer
---@return integer? win
---@return integer? buf
M.create = function(poppy_opts, width_override)
	local buf = vim.api.nvim_create_buf(false, true)
	local win = open_with(buf, poppy_opts, width_override)
	return win, buf
end

M.recreate = open_with

return M
