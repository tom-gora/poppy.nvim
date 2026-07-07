local M = {}

M.setup = function()
	vim.api.nvim_set_hl(0, "NormalPoppySidebar", { link = "StatusLine" })
	vim.api.nvim_set_hl(0, "NormalPoppyContent", { link = "NormalFloat" })

	local nf = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
	local str = vim.api.nvim_get_hl(0, { name = "Label" })
	vim.api.nvim_set_hl(0, "PoppyBorder", { fg = str.fg, bg = nf.bg })

	local sl = vim.api.nvim_get_hl(0, { name = "StatusLine" })
	local comment = vim.api.nvim_get_hl(0, { name = "Comment" })
	vim.api.nvim_set_hl(0, "PoppyInactive", { fg = comment.fg, bg = sl.bg })
	vim.api.nvim_set_hl(0, "PoppyActive", { link = "IncSearch" })
end

M.apply_hints_panel_style = function(win)
	vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppySidebar", { win = win })
end

M.apply_list_panel_style = function(win)
	vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppySidebar", { win = win })
end

M.apply_content_style = function(win)
	vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppyContent", { win = win })
end

M.apply_border_style = function(win)
	vim.api.nvim_set_option_value("winhl", "FloatBorder:PoppyBorder", { win = win })
end

return M

