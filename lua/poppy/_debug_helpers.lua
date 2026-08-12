local M = {}

M.layout__setup_highlights = function()
	vim.api.nvim_set_hl(0, "DebugDistinctHl", { link = "IncSearch", force = true })
end

M.layout__hightlight_window_visually = function(win)
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		vim.api.nvim_win_set_config(win, { zindex = 230 })
		vim.api.nvim_set_option_value("winhl", "Normal:DebugDistinctHl", { scope = "local", win = win })
	end)
end

return M
