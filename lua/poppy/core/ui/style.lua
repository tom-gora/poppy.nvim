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

M.setup = function()
	vim.api.nvim_set_hl(0, "NormalPoppyUIPanel", { link = "StatusLine" })
	vim.api.nvim_set_hl(0, "NormalPoppyContent", { link = "NormalFloat" })

	local nf = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
	local str = vim.api.nvim_get_hl(0, { name = "Label" })
	vim.api.nvim_set_hl(0, "PoppyBorder", { fg = str.fg, bg = nf.bg })

	local sl = vim.api.nvim_get_hl(0, { name = "StatusLine" })
	local comment = vim.api.nvim_get_hl(0, { name = "Comment" })
	vim.api.nvim_set_hl(0, "PoppyInactive", { fg = comment.fg, bg = sl.bg })
	vim.api.nvim_set_hl(0, "PoppyActive", { link = "IncSearch" })

	if sl.bg then
		vim.api.nvim_set_hl(0, "HighlightPoppyUIPanel", { bg = lighten(sl.bg, 0.1) })
	end
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

