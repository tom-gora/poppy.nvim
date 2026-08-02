local M = {}

local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

-- The poppy registry. Indexed by both integer (list view order) and
-- string (runtime record lookup). External code reads/writes directly.
M.poppies = {}

M.hide = function(name)
	local ps = M.poppies[name]
	if not ps then
		return
	end
	ps.active = false
	ps.hidden = true
	ps.win = nil
end

local build_poppy_public_data = function(i, entry)
	local name = entry.name
	local runtime = M.poppies[name]
	local opened = runtime ~= nil
	return {
		name = name,
		index = i,
		title = entry.config and entry.config.title or name,
		mode = entry.config and entry.config.mode,
		cat = shared.cat(entry.config or {}),
		is_current = state.current_poppy_name == name,
		active = opened and runtime.active or false,
		hidden = opened and runtime.hidden or false,
		has_been_opened = opened,
		bufnr = opened and runtime.bufnr or nil,
		win = opened and runtime.win or nil,
	}
end

M.get_poppy_by_name = function(name)
	for i = 1, #M.poppies do
		local entry = M.poppies[i]
		if entry and entry.name == name then
			return build_poppy_public_data(i, entry)
		end
	end
	return nil
end

M.get_poppy_by_index = function(index)
	local entry = M.poppies[index]
	if not entry or not entry.name then
		return nil
	end
	return build_poppy_public_data(index, entry)
end

M.get_current_poppy = function()
	local current_name = state.current_poppy_name
	if not current_name then
		return nil
	end
	return M.get_poppy_by_name(current_name)
end

M.get_poppies = function()
	local result = {}
	for i = 1, #M.poppies do
		local entry = M.poppies[i]
		if entry and entry.name then
			result[i] = build_poppy_public_data(i, entry)
		end
	end
	return result
end

return M