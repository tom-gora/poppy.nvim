require("poppy._types")

local M = {}

-- 48: under Neovim's default 50 (completion pum, hovers, notifications), above other plugin pickers.
M.POPPY_Z_INDEX = 48
-- Question panel outranks the answers list: same-z floats get restacked on focus, and
-- focus_body runs after the panel is mounted, so the body would cover it otherwise.
M.POPPY_QUESTION_Z_INDEX = M.POPPY_Z_INDEX + 1
M.DEFAULT_MENU_WIDTH = 25

M.MIN_MENU_WIDTH = 20
M.MAX_MENU_WIDTH = 35

-- Floor on the content pane so the sidebar wins against the content for narrow wrappers.
M.MIN_CONTENT_WIDTH = 35

-- Below this the layout is not degraded, it is meaningless, so poppy refuses to open
-- rather than render one-cell panels and clipped hints. Width is the sidebar plus the
-- content floor and their gutter; height only has to fit the single-row picker, and
-- header/hints can be turned off in anything tighter.
M.MIN_COLS = M.MIN_MENU_WIDTH + M.MIN_CONTENT_WIDTH + 2
M.MIN_LINES = 10

---@return boolean
M.below_floor = function()
	return vim.o.columns < M.MIN_COLS or vim.o.lines < M.MIN_LINES
end

local HEADER_HEIGHT = 3

local fn = vim.fn
local shared = require("poppy.core.shared")

-- Drawn by render.header, measured by landing_min_width. One string, one place.
M.HEADER_TITLE = "P◉PPY.NVIM"

M.PANEL_PAD = 1

---@param opts? PoppyMergedConfig
---@param poppies {name: string, config: PoppyResolvedConfig}[]
---@return integer
M.landing_min_width = function(opts, poppies)
	local render = require("poppy.core.ui.render")

	local idx_width = #tostring(math.max(#poppies, 1))
	local widest_row = 0
	for _, item in ipairs(poppies) do
		local label = item.config.title or item.name
		widest_row = math.max(widest_row, render.measure_item(idx_width, label))
	end

	local keys = (opts and opts.keys) or { poppy_action = "<C-_>", select = "<CR>" }
	local widest_hint = math.max(
		render.measure_hint_line(shared.permanent_key("select") or keys.select, "Select"),
		render.measure_hint_line(keys.poppy_action, "Toggle Off")
	)

	-- Each extent already includes its own left inset, so PANEL_PAD is added once on the trailing side.
	local content = math.max(widest_row, widest_hint) + M.PANEL_PAD
	local chrome = fn.strdisplaywidth(M.HEADER_TITLE) + (M.PANEL_PAD * 2)
	return math.max(content, chrome) + 1
end

---@param opts? PoppyMergedConfig
---@param poppies {name: string, config: PoppyResolvedConfig}[]
---@param vim_cols integer
---@return integer
M.landing_width = function(opts, poppies, vim_cols)
	return math.min(M.landing_min_width(opts, poppies), vim_cols)
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
local evaluate_dimension = M.evaluate_dimension

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
---@param content_width? integer
---@param min_width? integer
---@return integer width
---@return integer height
---@return integer row
M.compute_wrapper_dimensions = function(opts, vim_cols, vim_lines, content_width, min_width)
	opts = opts or {}

	local raw_w = evaluate_dimension(opts.win_width or 0.8, 0.8, "win_width")
	local raw_h = evaluate_dimension(opts.win_height or 0.75, 0.75, "win_height")

	-- Replacement, not a floor: max(content, win_width) would let win_width win on launch.
	local width = content_width and math.min(content_width, vim_cols) or resolve_dimension(raw_w, vim_cols, "win_width")

	-- Ratio is a preference, not a promise: the wrapper grows on a screen too narrow for both.
	if min_width and not content_width and width < min_width then
		width = math.min(min_width, vim_cols)
	end

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
