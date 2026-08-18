require("poppy._types")

local M = {}
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local namespace = vim.api.nvim_create_namespace("poppy_header_panel")

---@param wrapper_win integer
---@param width_override? integer
---@param col_override? integer
---@return integer? win
---@return integer? buf
M.create = function(wrapper_win, width_override, col_override)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return M.recreate(wrapper_win, buf, width_override, col_override), buf
end

---@param wrapper_win integer
---@param buf integer
---@param width_override? integer
---@param col_override? integer
---@return integer? win
M.recreate = function(wrapper_win, buf, width_override, col_override)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local width = width_override or wc.width
	local col = col_override or 0

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = width,
		height = 3,
		col = col,
		row = 0,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_list_panel_style(win)
	shared.apply_win_marker(win)

	local title = "P◉PPY.NVIM"
	local title_w = vim.fn.strdisplaywidth(title)
	local title_col = math.max(0, math.floor((width - title_w) / 2))
	local sep = " " .. string.rep("─", width - 2) .. " "
	local title_line = string.rep(" ", title_col) .. title

	shared.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", title_line, sep })
	end)

	---@type vim.api.keyset.extmark
	local title_extmark = { end_col = #title_line, hl_group = "NormalPoppyUIPanel" }
	vim.api.nvim_buf_set_extmark(buf, namespace, 1, 0, title_extmark)
	-- ◉ is the 2nd char of the title (byte offset 2, 1-indexed); leading
	-- spaces are ASCII so byte == cell here. dot_start lands on the
	-- 3-byte UTF-8 sequence for ◉.
	local dot_start = title_col + 1
	local dot_end = dot_start + 3
	---@type vim.api.keyset.extmark
	local dot_extmark = { end_col = dot_end, hl_group = "PoppyRed" }
	vim.api.nvim_buf_set_extmark(buf, namespace, 1, dot_start, dot_extmark)
	return win
end

return M
