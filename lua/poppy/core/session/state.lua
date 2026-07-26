local M = {}

M.init = function()
	M.wrapper_win = nil
	M.wrapper_buf = nil
	M.content_win = nil
	M.content_buf = nil
	M.current_poppy_name = nil
	M.is_landing = false
	M.menu_focused = false
	M.menu_hint_win = nil
	M.menu_hint_buf = nil
	M.opts = nil
end

return M
