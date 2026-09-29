require("poppy._types")

local M = {}

-- 48 keeps us under Neovim's default 50 (completion pum, hovers, notifications) while staying above other plugin pickers.
M.POPPY_Z_INDEX = 48
M.DEFAULT_MENU_WIDTH = 25

local HEADER_HEIGHT = 3

local shared = require("poppy.core.shared")

---@param opts? PoppyMergedConfig
---@param poppies {name: string, config: PoppyResolvedConfig}[]
---@return integer
M.compute_landing_view_width = function(opts, poppies)
	local max_line = 0
	for i, item in ipairs(poppies) do
		local icon = (opts and opts.icons and opts.icons[shared.category_from_resolved(item.config)]) or " "
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

-- A dimension function is user code; a throw or a non-number return must not
-- abort the open. Falls back to the ratio default with a warn.
---@param value number|function
---@param default number
---@param name string
---@return number
local evaluate_dimension = function(value, default, name)
	if type(value) ~= "function" then
		return value
	end
	local ok, result = pcall(value)
	if not ok then
		shared.notify_warn("%s function errored: %s; falling back to %s", name, tostring(result), tostring(default))
		return default
	end
	if type(result) ~= "number" then
		shared.notify_warn("%s function returned %s, expected number; falling back to %s", name, type(result), tostring(default))
		return default
	end
	return result
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
			shared.notify_warn("%s %d too small, minimum is %d", name, value, min_v)
			value = min_v
		elseif value > total then
			shared.notify_warn("%s %d exceeds screen size %d", name, value, total)
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

	local raw_w = evaluate_dimension(opts.win_width or 0.8, 0.8, "win_width")
	local raw_h = evaluate_dimension(opts.win_height or 0.75, 0.75, "win_height")

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
