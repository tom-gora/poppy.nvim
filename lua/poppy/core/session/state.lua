local M = {}

-- All UI runtime state: windows, buffers, mode flags, current poppy, config.
-- Folded from the former state.lua + panels.lua local-state block.
M.windows = {
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
	is_landing = false,
	menu_focused = false,
	hidden = false,
	menu_width = 25,
	header_height = 0,
	opts = nil,
}

-- The poppy registry: indexed by integer (list view order) and string
-- (runtime record lookup). External code reads/writes directly.
M.poppies = {}

return M