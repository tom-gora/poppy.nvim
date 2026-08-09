local M = {}
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local namespace = vim.api.nvim_create_namespace("poppy_header_panel")

M.create = function(wrapper_win, width_override, col_override)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return M.recreate(wrapper_win, buf, width_override, col_override), buf
end

M.recreate = function(wrapper_win, buf, width_override, col_override)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local width = width_override or wc.width
	local col = col_override or 0

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
	vim.api.nvim_win_set_var(win, "poppy_ui_window", true)

	local title = "P◉PPY.NVIM"
	local title_w = vim.fn.strdisplaywidth(title)
	local title_col = math.max(0, math.floor((width - title_w) / 2))
	local sep = " " .. string.rep("─", width - 2) .. " "
	local title_line = string.rep(" ", title_col) .. title

	shared.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", title_line, sep })
	end)

	vim.api.nvim_buf_set_extmark(buf, namespace, 1, 0, { end_col = #title_line, hl_group = "NormalPoppyUIPanel" })
	-- ◉ is the 2nd char of the title (byte offset 2, 1-indexed); leading
	-- spaces are ASCII so byte == cell here. dot_start lands on the
	-- 3-byte UTF-8 sequence for ◉.
	local dot_start = title_col + 1
	local dot_end = dot_start + 3
	vim.api.nvim_buf_set_extmark(buf, namespace, 1, dot_start, { end_col = dot_end, hl_group = "PoppyRed" })
	return win
end

return M
