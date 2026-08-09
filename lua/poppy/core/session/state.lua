local M = {}

M.default_state = function()
	return {
		wrapper_win = nil,
		wrapper_buf = nil,
		content_win = nil,
		content_buf = nil,
		menu_hint_win = nil,
		menu_hint_buf = nil,
		hints_win = nil,
		hints_buf = nil,
		list_win = nil,
		list_buf = nil,
		header_win = nil,
		header_buf = nil,
		current_poppy_name = nil,
		last_poppy_name = nil,
		is_landing = false,
		menu_focused = false,
		hidden = false,
		menu_width = 25,
		header_height = 0,
		opts = nil,
	}
end

M.windows = M.default_state()

M.poppies = {}

return M