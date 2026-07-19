-- core/geometry.lua
--
-- Single source of truth for window-size normalization. Used at config-time
-- (sanitize) and at open-time (compute). Before this module existed, the
-- ratio/pixel branching lived in three places (`config.lua`,
-- `core/ui/wrapper.lua`, `core/session/init.lua`), each handling the "ratio vs
-- absolute pixel" branch independently and each emitting its own
-- `vim.notify` warnings.
--
-- The boundary between `normalize_ratio_or_pixels` (config-time,
-- screen-independent, type/range only) and `compute_dimensions` (open-time,
-- screen-dependent, validates against actual screen size) is real and is
-- preserved here.

local M = {}

-- Normalize a value that is either nil, a function (deferred), or a number
-- (ratio 0.2–1.0 or absolute pixels >1).
--
-- Returns the canonical form: a number (ratio values clamped to [0.2, 1.0],
-- pixel values left as-is for compute-time validation) or the function
-- unchanged (compute_dimensions will call it).
--
-- Falls back to `default` for nil or invalid types. No screen-size
-- knowledge — pure type/range normalization.
function M.normalize_ratio_or_pixels(value, default)
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

-- Compute the wrapper's final width, height, and row from user opts and the
-- current screen size.
--
-- - `opts`: typically `state.opts`; can be nil (defaults applied).
-- - `screen_cols`, `screen_lines`: the dimensions to size against. Passed in
--   rather than read from `vim.o.*` so the function is testable in isolation.
-- - `override_width`: when provided, takes precedence over `opts.win_width`.
--   Used by the landing view to lock the wrapper width to the largest
--   poppies-list line.
--
-- Returns: width, height, row.
function M.compute_dimensions(opts, screen_cols, screen_lines, override_width)
	opts = opts or {}

	local raw_w = opts.win_width
	if type(raw_w) == "function" then
		raw_w = raw_w()
	end
	raw_w = raw_w or 0.8

	local width
	if override_width then
		width = override_width
	elseif raw_w > 1 then
		local min_w = math.floor(screen_cols / 3)
		if raw_w < min_w then
			vim.notify(
				string.format("Poppy: win_width %d too small, minimum is %d", raw_w, min_w),
				vim.log.levels.WARN
			)
			raw_w = min_w
		elseif raw_w > screen_cols then
			vim.notify(
				string.format("Poppy: win_width %d exceeds screen width %d", raw_w, screen_cols),
				vim.log.levels.WARN
			)
			raw_w = screen_cols
		end
		width = math.floor(raw_w)
	else
		local ratio = math.min(math.max(raw_w, 0.2), 1.0)
		width = math.floor(screen_cols * ratio)
	end

	local raw_h = opts.win_height
	if type(raw_h) == "function" then
		raw_h = raw_h()
	end
	raw_h = raw_h or 0.75

	local height
	if raw_h > 1 then
		local min_h = math.floor(screen_lines / 3)
		if raw_h < min_h then
			vim.notify(
				string.format("Poppy: win_height %d too small, minimum is %d", raw_h, min_h),
				vim.log.levels.WARN
			)
			raw_h = min_h
		elseif raw_h > screen_lines then
			vim.notify(
				string.format("Poppy: win_height %d exceeds screen height %d", raw_h, screen_lines),
				vim.log.levels.WARN
			)
			raw_h = screen_lines
		end
		height = math.floor(raw_h)
	else
		local ratio = math.min(math.max(raw_h, 0.2), 1.0)
		height = math.floor(screen_lines * ratio)
	end

	local location = opts.win_location or "center"
	local row
	if location == "top" then
		row = 0
	elseif location == "bottom" then
		row = screen_lines - height
	else
		row = math.floor((screen_lines - height) / 2)
	end

	return width, height, row
end

return M
