local M = {}

M.setup = function()
	vim.api.nvim_set_hl(0, "NormalPoppySidebar", { link = "StatusLine" })
end

M.apply_left_sidebar_style = function(win)
	vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppySidebar", { win = win })
end

M.apply_right_sidebar_style = function(win)
	vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppySidebar", { win = win })
end

return M
