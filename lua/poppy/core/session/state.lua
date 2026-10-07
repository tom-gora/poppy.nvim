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
---@field menu_win integer|nil
---@field menu_buf integer|nil
---@field menu_header_win integer|nil A menu's question panel. Not the header panel.
---@field menu_header_buf integer|nil
---@field header_win integer|nil
---@field header_buf integer|nil
---@field current_poppy_name string|nil
---@field last_poppy_name string|nil
---@field is_landing boolean
---@field hidden boolean
---@field opts PoppyMergedConfig?
---@field dialog {name: string, resume: fun(), buf: integer?}|nil A confirmation is up;
--- teardown routes are inert while set, and any forced close of the dialog's panels resolves the question.
---@field recovering boolean True while a recovery routine is mid-flight; WinClosed watcher bails when set.

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
		menu_win = nil,
		menu_buf = nil,
		menu_header_win = nil,
		menu_header_buf = nil,
		header_win = nil,
		header_buf = nil,
		current_poppy_name = nil,
		last_poppy_name = nil,
		is_landing = false,
		hidden = false,
		opts = nil,
		recovering = false,
		dialog = nil,
	}
end

M.windows = M.default_state()

---@type {name: string, config: PoppyResolvedConfig}[]
M.poppies_configured = {}

--@type table<string, PoppyRuntimeState?>
M.poppies_runtime = {}

---@param name string
---@return {name: string, config: PoppyResolvedConfig}?
M.poppy_configured = function(name)
	for _, entry in ipairs(M.poppies_configured) do
		if entry.name == name then
			return entry
		end
	end
	return nil
end

---@param name string
---@return integer?
M.poppy_index = function(name)
	for i, entry in ipairs(M.poppies_configured) do
		if entry.name == name then
			return i
		end
	end
	return nil
end

---@param name string
---@return PoppyRuntimeState?
M.runtime = function(name)
	return M.poppies_runtime[name]
end

---@param name string|nil
M.set_current_poppy_name = function(name)
	if name ~= nil and not M.poppy_configured(name) then
		error("poppy: unknown poppy name: " .. tostring(name))
	end
	M.windows.current_poppy_name = name
end

---@param name string
M.clear_runtime = function(name)
	M.poppies_runtime[name] = nil
end

return M
