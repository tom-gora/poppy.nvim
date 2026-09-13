require("poppy._types")

local M = {}

---@class PoppyState
---@field wrapper_win integer|nil
---@field wrapper_buf integer|nil
---@field content_win integer|nil
---@field content_buf integer|nil
---@field menu_hint_win integer|nil
---@field menu_hint_buf integer|nil
---@field hints_win integer|nil
---@field hints_buf integer|nil
---@field list_win integer|nil
---@field list_buf integer|nil
---@field header_win integer|nil
---@field header_buf integer|nil
---@field current_poppy_name string|nil
---@field last_poppy_name string|nil
---@field is_landing boolean
---@field hidden boolean
---@field opts PoppyMergedConfig?
---@field recovering boolean True while a recovery routine is mid-flight; WinClosed watcher bails when set so it doesn't recreate content mid-cleanup.

---@return PoppyState
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
		recovering = false,
	}
end

M.windows = M.default_state()

-- Array index == display order. Set once at setup; only `runtime_state` flips as poppies open/close.
---@type PoppySessionEntry[]
M.poppies = {}

-- Linear scan; ~5-30 entries typical.
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

---@param name string|nil
M.set_current_poppy_name = function(name)
	if name ~= nil and not M.poppy(name) then
		error("poppy: unknown poppy name: " .. tostring(name))
	end
	M.windows.current_poppy_name = name
end

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
