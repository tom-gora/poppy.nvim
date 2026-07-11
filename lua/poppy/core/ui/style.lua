local M = {}

local function lighten(color, factor)
	local r = math.floor(color / 65536)
	local g = math.floor((color % 65536) / 256)
	local b = color % 256
	r = math.min(255, math.floor(r + (255 - r) * factor))
	g = math.min(255, math.floor(g + (255 - g) * factor))
	b = math.min(255, math.floor(b + (255 - b) * factor))
	return r * 65536 + g * 256 + b
end

local function desaturate(color, factor)
	local r = math.floor(color / 65536)
	local g = math.floor((color % 65536) / 256)
	local b = color % 256
	local gray = math.floor(0.299 * r + 0.587 * g + 0.114 * b)
	r = math.floor(r + (gray - r) * factor)
	g = math.floor(g + (gray - g) * factor)
	b = math.floor(b + (gray - b) * factor)
	return math.max(0, r) * 65536 + math.max(0, g) * 256 + math.max(0, b)
end

M.setup = function()
	vim.api.nvim_set_hl(0, "NormalPoppyContent", { link = "NormalFloat" })

	local nf = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
	if nf.bg then
		vim.api.nvim_set_hl(0, "NormalPoppyUIPanel", { bg = lighten(nf.bg, 0.10), fg = nf.fg })
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
		vim.api.nvim_set_hl(0, "PoppyFileHidden", { fg = desaturate(type_hl.fg, 0.6) })
	else
		vim.api.nvim_set_hl(0, "PoppyFileHidden", { link = "Comment" })
	end
	if string_hl.fg then
		vim.api.nvim_set_hl(0, "PoppyExecHidden", { fg = desaturate(string_hl.fg, 0.6) })
	else
		vim.api.nvim_set_hl(0, "PoppyExecHidden", { link = "Comment" })
	end
	if func_hl.fg then
		vim.api.nvim_set_hl(0, "PoppyShellHidden", { fg = desaturate(func_hl.fg, 0.6) })
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
