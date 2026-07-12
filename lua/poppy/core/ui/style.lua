local M = {}

local PANELS_BG_LIGHTEN_FACTOR = 0.10
local HIDDEN_LIST_ITEM_DARKEN_FACTOR = -0.5

local function adjust_brightness(color, factor)
	local target = factor >= 0 and 255 or 0
	local f = math.abs(factor)
	local r = math.floor(color / 65536)
	local g = math.floor((color % 65536) / 256)
	local b = color % 256
	r = math.max(0, math.min(255, math.floor(r + (target - r) * f)))
	g = math.max(0, math.min(255, math.floor(g + (target - g) * f)))
	b = math.max(0, math.min(255, math.floor(b + (target - b) * f)))
	return r * 65536 + g * 256 + b
end

M.setup = function()
	vim.api.nvim_set_hl(0, "NormalPoppyContent", { link = "NormalFloat" })

	local nf = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
	if nf.bg then
		vim.api.nvim_set_hl(0, "NormalPoppyUIPanel", { bg = adjust_brightness(nf.bg, PANELS_BG_LIGHTEN_FACTOR), fg = nf.fg })
	else
		vim.api.nvim_set_hl(0, "NormalPoppyUIPanel", { link = "StatusLine" })
	end
	local panel_hl = vim.api.nvim_get_hl(0, { name = "NormalPoppyUIPanel" })
	local err = vim.api.nvim_get_hl(0, { name = "ErrorMsg" })
	vim.api.nvim_set_hl(0, "PoppyRed", { fg = err.fg, bg = panel_hl.bg })
	local str = vim.api.nvim_get_hl(0, { name = "Label" })
	vim.api.nvim_set_hl(0, "PoppyBorder", { fg = str.fg, bg = nf.bg })

	local sl = vim.api.nvim_get_hl(0, { name = "StatusLine" })
	local comment = vim.api.nvim_get_hl(0, { name = "Comment" })
	vim.api.nvim_set_hl(0, "PoppyInactive", { fg = comment.fg, bg = sl.bg })
	vim.api.nvim_set_hl(0, "PoppyActive", { link = "IncSearch" })

	local type_hl = vim.api.nvim_get_hl(0, { name = "Type" })
	local string_hl = vim.api.nvim_get_hl(0, { name = "String" })
	local func_hl = vim.api.nvim_get_hl(0, { name = "Function" })

	vim.api.nvim_set_hl(0, "PoppyFile", { fg = type_hl.fg })
	vim.api.nvim_set_hl(0, "PoppyExec", { fg = string_hl.fg })
	vim.api.nvim_set_hl(0, "PoppyShell", { fg = func_hl.fg })

	if type_hl.fg then
		vim.api.nvim_set_hl(0, "PoppyFileHidden", { fg = adjust_brightness(type_hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR) })
	else
		vim.api.nvim_set_hl(0, "PoppyFileHidden", { link = "Comment" })
	end
	if string_hl.fg then
		vim.api.nvim_set_hl(0, "PoppyExecHidden", { fg = adjust_brightness(string_hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR) })
	else
		vim.api.nvim_set_hl(0, "PoppyExecHidden", { link = "Comment" })
	end
	if func_hl.fg then
		vim.api.nvim_set_hl(0, "PoppyShellHidden", { fg = adjust_brightness(func_hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR) })
	else
		vim.api.nvim_set_hl(0, "PoppyShellHidden", { link = "Comment" })
	end

	vim.api.nvim_set_hl(0, "PoppyActiveDot", { link = "Normal" })
end

M.apply_hints_panel_style = function(win)
	vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppyUIPanel", { win = win })
end

M.apply_list_panel_style = function(win)
	vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppyUIPanel", { win = win })
end

M.apply_content_style = function(win)
	vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppyContent", { win = win })
end

M.apply_border_style = function(win)
	vim.api.nvim_set_option_value("winhl", "FloatBorder:PoppyBorder", { win = win })
end

return M
