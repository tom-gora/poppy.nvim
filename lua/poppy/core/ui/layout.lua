require("poppy._types")

local M = {}

-- 48 keeps us under Neovim's default 50 (completion pum, hovers, notifications) while staying above other plugin pickers.
M.POPPY_Z_INDEX = 48

local HEADER_HEIGHT = 3

local shared = require("poppy.core.shared")

---@param opts? PoppyMergedConfig
---@param poppies PoppySessionEntry[]
---@return integer
M.compute_landing_view_width = function(opts, poppies)
	local max_line = 0
	for i, item in ipairs(poppies) do
		local icon = (opts and opts.icons and opts.icons[shared.cat(item.config)]) or " "
		local title = item.config.title or item.name
		local line = string.format(" %s %s %d %s", " ", icon, i, title)
		max_line = math.max(max_line, #line)
	end
	local keys = (opts and opts.keys) or { poppy_action = "<C-_>", select = "<CR>" }
	local hints_text = string.format(" %s Select   %s Toggle Off ", keys.select, keys.poppy_action)
	local hints_len = #hints_text
	return math.max(max_line, hints_len) + 4
end

---@param opts? PoppyMergedConfig
---@return integer
M.get_header_height = function(opts)
	return (opts and opts.title_header ~= false) and HEADER_HEIGHT or 0
end

---@param value number|function|nil
---@param default number
---@return number|function
M.normalize_dimension = function(value, default)
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

-- >1 = absolute cells; <=1 = ratio of `total`.
---@param value number
---@param total integer
---@param name string
---@return integer
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

---@param opts? PoppyMergedConfig
---@param vim_cols integer
---@param vim_lines integer
---@param override_width? integer
---@return integer width
---@return integer height
---@return integer row
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
