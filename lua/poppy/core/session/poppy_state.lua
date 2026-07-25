local M = {}

local state = require("poppy.core.session.state")
local util = require("poppy.core.util")

local _poppies = {}

-- ─── Internal storage API (used by modes, switching, killing, manager) ───

M.entries = function()
	return _poppies
end

M.runtime_get = function(name)
	return _poppies[name]
end

M.runtime_set = function(name, record)
	_poppies[name] = record
end

M.runtime_remove = function(name)
	_poppies[name] = nil
end

M.runtime_iter = function()
	return pairs(_poppies)
end

M.is_empty = function()
	return next(_poppies) == nil
end

M.array_length = function()
	return #_poppies
end

M.clear = function()
	for k in pairs(_poppies) do
		_poppies[k] = nil
	end
end

M.rebuild_from_sorted = function(sorted)
	for k in pairs(_poppies) do
		_poppies[k] = nil
	end
	for i, v in ipairs(sorted) do
		_poppies[i] = v
	end
end

M.ensure_entries_loaded = function()
	if #_poppies == 0 and state.opts and state.opts.poppies and next(state.opts.poppies) then
		M.rebuild_from_sorted(util.get_sorted_poppies(state.opts))
	end
end

M.landing_view_width = function()
	return util.compute_landing_view_width(state.opts, _poppies)
end

-- ─── Public read API (exposed via require("poppy").get_*) ───

local build_record = function(i, entry)
	local name = entry.name
	local runtime = _poppies[name]
	local opened = runtime ~= nil
	return {
		name = name,
		index = i,
		title = entry.config and entry.config.title or name,
		mode = entry.config and entry.config.mode,
		cat = util.cat(entry.config or {}),
		is_current = state.current_poppy_name == name,
		active = opened and runtime.active or false,
		hidden = opened and runtime.hidden or false,
		has_been_opened = opened,
		bufnr = opened and runtime.bufnr or nil,
		win = opened and runtime.win or nil,
	}
end

M.get_poppy_by_name = function(name)
	for i = 1, #_poppies do
		local entry = _poppies[i]
		if entry and entry.name == name then
			return build_record(i, entry)
		end
	end
	return nil
end

M.get_poppy_by_index = function(index)
	local entry = _poppies[index]
	if not entry or not entry.name then
		return nil
	end
	return build_record(index, entry)
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
	for i = 1, #_poppies do
		local entry = _poppies[i]
		if entry and entry.name then
			result[i] = M.get_poppy_by_name(entry.name)
		end
	end
	return result
end

return M