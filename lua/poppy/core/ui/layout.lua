require("poppy._types")

local M = {}

-- 48 keeps us under Neovim's default 50 (completion pum, hovers, notifications) while staying above other plugin pickers.
M.POPPY_Z_INDEX = 48
M.DEFAULT_MENU_WIDTH = 25

-- The sidebar honours a declared menu_width exactly. These are only the bounds
-- it is pulled into when the declared value (or the legend) falls outside them.
M.MIN_MENU_WIDTH = 20
M.MAX_MENU_WIDTH = 35

local HEADER_HEIGHT = 3

local fn = vim.fn
local shared = require("poppy.core.shared")

-- The landing is sized to its content and never crops; the screen is the only
-- cap. Unlike the sidebar (which follows a declared menu_width and truncates
-- long titles), the landing's width comes from whichever section is widest.
--
-- Each section follows its own layout rule and is measured accordingly:
--   header  title centred in the panel      -- needs panel >= title width
--   hints   left-aligned at INDENT          -- needs panel >= hint width
--   list    left-aligned after the signcolumn -- needs panel >= row extent
-- The list rows are what bind in practice; the header and hints only become
-- binding if a key remap makes a hint longer than every row.
--
-- Each extent already includes its own left inset, so PANEL_PAD is only added
-- once, on the trailing side. That is what keeps the longest row's text the
-- same distance from the right edge as the separators are from the left.
--
-- Measured from the renderers rather than re-derived here -- the previous
-- version guessed the row format and measured the hints as one joined string,
-- which is how a legend could end up croppable.
local HEADER_TITLE = "P ◉ PPY.NVIM"

-- Trailing breathing room, matching the separators' inset from the left edge.
M.PANEL_PAD = 1

---@param opts? PoppyMergedConfig
---@param poppies {name: string, config: PoppyResolvedConfig}[]
---@return integer
M.landing_min_width = function(opts, poppies)
	local render = require("poppy.core.ui.render")

	local idx_width = #tostring(math.max(#poppies, 1))
	local widest_row = 0
	for _, item in ipairs(poppies) do
		local title = item.config.title or item.name
		widest_row = math.max(widest_row, render.measure_list_row(idx_width, title))
	end

	local keys = (opts and opts.keys) or { poppy_action = "<C-_>", select = "<CR>" }
	local widest_hint = math.max(
		render.measure_hint_line(keys.select, "Select"),
		render.measure_hint_line(keys.poppy_action, "Toggle Off")
	)

	-- Every extent above already includes its own left inset (the list row's
	-- sign column, the hint's indent), so PANEL_PAD is only added on the trailing
	-- side. The wrapper has no border -- only the content window does -- so there
	-- is nothing else to account for.
	local content = math.max(widest_row, widest_hint) + M.PANEL_PAD
	local chrome = fn.strdisplaywidth(HEADER_TITLE) + (M.PANEL_PAD * 2)
	return math.max(content, chrome)
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
M.evaluate_dimension = function(value, default, name)
	if type(value) ~= "function" then
		return value
	end
	local ok, result = pcall(value)
	if not ok then
		shared.notify_warn("%s function errored: %s; falling back to %s", name, tostring(result), tostring(default))
		return default
	end
	if type(result) ~= "number" then
		shared.notify_warn(
			"%s function returned %s, expected number; falling back to %s",
			name,
			type(result),
			tostring(default)
		)
		return default
	end
	return result
end
-- Local alias for the two in-module callers below.
local evaluate_dimension = M.evaluate_dimension

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
---@param content_width? integer Landing width: sized to its content, replacing win_width rather than competing with it. Only the screen caps it.
---@return integer width
---@return integer height
---@return integer row
M.compute_wrapper_dimensions = function(opts, vim_cols, vim_lines, content_width)
	opts = opts or {}

	local raw_w = evaluate_dimension(opts.win_width or 0.8, 0.8, "win_width")
	local raw_h = evaluate_dimension(opts.win_height or 0.75, 0.75, "win_height")

	-- A replacement, not a floor. Taking the max of the two let win_width win
	-- whenever its ratio exceeded the content, which is why the landing came up
	-- absurdly wide on launch but correctly narrow after a kill.
	local width = content_width and math.min(content_width, vim_cols) or resolve_dimension(raw_w, vim_cols, "win_width")
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
