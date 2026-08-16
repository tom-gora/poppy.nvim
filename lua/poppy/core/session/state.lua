local M = {}
---
---@class PoppyState
---@field wrapper_win integer|nil Window ID for the main outer wrapper
---@field wrapper_buf integer|nil Buffer ID for the main outer wrapper
---@field content_win integer|nil Window ID for the central content area
---@field content_buf integer|nil Buffer ID for the central content area
---@field menu_hint_win integer|nil Window ID for the menu navigation hints
---@field menu_hint_buf integer|nil Buffer ID for the menu navigation hints
---@field hints_win integer|nil Window ID for the general keybinding hints
---@field hints_buf integer|nil Buffer ID for the general keybinding hints
---@field list_win integer|nil Window ID for the selection list component
---@field list_buf integer|nil Buffer ID for the selection list component
---@field header_win integer|nil Window ID for the top header section
---@field header_buf integer|nil Buffer ID for the top header section
---@field current_poppy_name string|nil Name of the currently active popup/menu
---@field last_poppy_name string|nil Name of the previously active popup/menu
---@field is_landing boolean Whether the user is currently on the initial landing state
---@field hidden boolean Whether the sidebar panels are currently hidden (autohide mode)
---@field opts table|nil Configuration options passed down to the state instance

---Generates the default configuration and window tracking state.
---@return PoppyState # The initialised state object.
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
		hidden = false,
		opts = nil,
	}
end

M.windows = M.default_state()

M.poppies = {}

return M
