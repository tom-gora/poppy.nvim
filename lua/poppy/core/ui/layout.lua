local M = {}

-- Stacking priority for all poppy UI windows. We sit just below
-- Neovim's default of 50 (used by completion pum, hover/documentation
-- floats, preview windows, diagnostics, notifications, :help, etc.)
-- so those transient overlays reliably appear on top of the poppy
-- UI rather than being obscured by it. Other plugin pickers
-- (Telescope, Snacks, aerial code actions, etc.) typically sit at
-- z=200+, so they continue to render above us as well.
M.POPPY_Z_INDEX = 48

local HEADER_HEIGHT = 3

M.get_header_height = function(opts)
	return (opts and opts.title_header ~= false) and HEADER_HEIGHT or 0
end

M.normalize_ratio_or_pixels = function(value, default)
	if value == nil then
		return default
	end
	if type(value) == "function" then
		return value
	end
	if type(value) == "number" then
		if value > 1 then
			return value
		end
		return math.min(math.max(value, 0.2), 1.0)
	end
	return default
end

-- Resolve a raw dimension value (already resolved from function/static)
-- to its final integer cell count. >1 means absolute columns/lines;
-- <=1 means a ratio of `total`. Clamps to sane bounds and notifies.
local resolve_dimension = function(value, total, name)
	if value > 1 then
		local min_v = math.floor(total / 3)
		if value < min_v then
			vim.notify(string.format("Poppy: %s %d too small, minimum is %d", name, value, min_v), vim.log.levels.WARN)
			value = min_v
		elseif value > total then
			vim.notify(string.format("Poppy: %s %d exceeds screen size %d", name, value, total), vim.log.levels.WARN)
			value = total
		end
		return math.floor(value)
	end
	local ratio = math.min(math.max(value, 0.2), 1.0)
	return math.floor(total * ratio)
end

M.compute_wrapper_dimensions = function(opts, vim_cols, vim_lines, override_width)
	opts = opts or {}

	local raw_w = opts.win_width
	if type(raw_w) == "function" then
		raw_w = raw_w()
	end
	raw_w = raw_w or 0.8

	local raw_h = opts.win_height
	if type(raw_h) == "function" then
		raw_h = raw_h()
	end
	raw_h = raw_h or 0.75

	local width = override_width or resolve_dimension(raw_w, vim_cols, "win_width")
	local height = resolve_dimension(raw_h, vim_lines, "win_height")

	local location = opts.win_location or "center"
	local row
	if location == "top" then
		row = 0
	elseif location == "bottom" then
		row = vim_lines - height
	else
		row = math.floor((vim_lines - height) / 2)
	end

	return width, height, row
end

return M
