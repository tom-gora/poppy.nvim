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

---@type table<string, PoppySessionEntry>
M.poppies = {}

-- Encapsulation helpers: a thin layer over the raw `state.poppies` /
-- `state.windows` tables. Not full OOP — these are read-only accessors
-- plus one high-stakes mutator. The rest of the state stays wide open.

---@param name string
---@return PoppySessionEntry?
M.poppy = function(name)
	return M.poppies[name]
end

-- Set the active poppy name. Pass nil to clear. Validates that a non-nil
-- name exists in `state.poppies` so callers can't drift from the
-- configured set. All existing call sites passed valid names or nil,
-- so this just turns silent drift into a raised error.
---@param name string|nil
M.set_current_poppy_name = function(name)
	if name ~= nil and not M.poppies[name] then
		error("poppy: unknown poppy name: " .. tostring(name))
	end
	M.windows.current_poppy_name = name
end

-- Return the subset of poppies that are currently open (have a
-- non-nil runtime_state). Returns a map `name -> entry` mirroring
-- `state.poppies`. Used by `actions.recover`'s fallback loop; lives
-- here so it's testable and discoverable as state-level concern.
---@return table<string, PoppySessionEntry>
M.poppies_runtime = function()
	local result = {}
	for name, entry in pairs(M.poppies) do
		if entry.runtime_state then
			result[name] = entry
		end
	end
	return result
end

return M
