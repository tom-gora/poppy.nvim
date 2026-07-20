local M = {}
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

M.compute_dimensions = function(opts, vim_cols, vim_lines, override_width)
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
		local min_w = math.floor(vim_cols / 3)
		if raw_w < min_w then
			vim.notify(string.format("Poppy: win_width %d too small, minimum is %d", raw_w, min_w), vim.log.levels.WARN)
			raw_w = min_w
		elseif raw_w > vim_cols then
			vim.notify(
				string.format("Poppy: win_width %d exceeds screen width %d", raw_w, vim_cols),
				vim.log.levels.WARN
			)
			raw_w = vim_cols
		end
		width = math.floor(raw_w)
	else
		local ratio = math.min(math.max(raw_w, 0.2), 1.0)
		width = math.floor(vim_cols * ratio)
	end

	local raw_h = opts.win_height
	if type(raw_h) == "function" then
		raw_h = raw_h()
	end
	raw_h = raw_h or 0.75

	local height
	if raw_h > 1 then
		local min_h = math.floor(vim_lines / 3)
		if raw_h < min_h then
			vim.notify(
				string.format("Poppy: win_height %d too small, minimum is %d", raw_h, min_h),
				vim.log.levels.WARN
			)
			raw_h = min_h
		elseif raw_h > vim_lines then
			vim.notify(
				string.format("Poppy: win_height %d exceeds screen height %d", raw_h, vim_lines),
				vim.log.levels.WARN
			)
			raw_h = vim_lines
		end
		height = math.floor(raw_h)
	else
		local ratio = math.min(math.max(raw_h, 0.2), 1.0)
		height = math.floor(vim_lines * ratio)
	end

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
