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
---@field current_poppy_name string|nil Name of the currently active poppy
---@field last_poppy_name string|nil Name of the previously active poppy
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

-- Poppy registry, sorted once at setup (category then name) and never
-- mutated in shape afterwards. Array index == display order. Entries
-- get a runtime_state table or nil as poppies open/close; the array
-- itself stays stable for the session lifetime.
---@type PoppySessionEntry[]
M.poppies = {}

-- Lookup by name: linear scan. ~5-30 entries typical; the encapsulation
-- is for callers, not perf.
---@param name string
---@return PoppySessionEntry?
M.poppy = function(name)
	for _, entry in ipairs(M.poppies) do
		if entry.name == name then
			return entry
		end
	end
	return nil
end

-- Index lookup by name. Returns the array position (= display row) or nil.
---@param name string
---@return integer?
M.poppy_index = function(name)
	for i, entry in ipairs(M.poppies) do
		if entry.name == name then
			return i
		end
	end
	return nil
end

-- Set the active poppy name. Pass nil to clear. Validates against the
-- configured set so callers can't drift.
---@param name string|nil
M.set_current_poppy_name = function(name)
	if name ~= nil and not M.poppy(name) then
		error("poppy: unknown poppy name: " .. tostring(name))
	end
	M.windows.current_poppy_name = name
end

-- Subset of poppies that are currently open (runtime_state ~= nil).
-- Returns a flat list in the same sort order as M.poppies.
---@return PoppySessionEntry[]
M.poppies_runtime = function()
	local result = {}
	for _, entry in ipairs(M.poppies) do
		if entry.runtime_state then
			result[#result + 1] = entry
		end
	end
	return result
end

return M
