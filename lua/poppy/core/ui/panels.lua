-- Layout engine. One function returns row+height for every panel; view.lua
-- consumes the result and opens the windows. Borderless has 1 row of padding
-- at top and bottom; bordered has none (the border is the edge). The hints
-- panel draws its own separator as its first line; the body sits flush against
-- it. Spec swaps in and out per dialog, so resolve_spec is asked per call.

local shared = require("poppy.core.shared")

local M = {}

---@class PoppyPanelsSpec
---@field border boolean
---@field header boolean
---@field hints boolean
---@field question boolean
---@field body_rows integer
---@field hint_rows integer
---@field question_lines string[]
---@field fill boolean Sidebar: body fills leftover height; landing: body sizes to content.

---@class PoppyPanelsLayout
---@field padding integer
---@field header_height integer
---@field question_height integer
---@field body_height integer
---@field hints_height integer
---@field header_row integer
---@field question_row integer
---@field body_row integer
---@field hints_row integer

---@param spec PoppyMenuSpec
---@param panel_width integer
---@param fill? boolean
---@return PoppyPanelsSpec
M.resolve_spec = function(spec, panel_width, fill)
	local body_rows
	if type(spec.items) == "function" then
		body_rows = #(spec.items(panel_width) or {})
	else
		body_rows = #(spec.rows or {})
	end

	local question_lines = {}
	if spec.menu_header and #spec.menu_header > 0 then
		question_lines = spec.menu_header
	end

	return {
		border = shared.use_borders(),
		header = shared.opts_field("title_header") ~= false,
		hints = shared.opts_field("hints_footer") ~= false,
		question = #question_lines > 0,
		body_rows = math.max(1, body_rows),
		hint_rows = #spec.hints,
		question_lines = question_lines,
		fill = fill == true,
	}
end

---Sidebar (fill=true) keeps the wrapper's height and fills the body with
---leftover space; landing sizes the wrapper to fit its content.
---@param spec PoppyPanelsSpec
---@param height? integer Wrapper height; required when spec.fill is true.
---@return PoppyPanelsLayout
M.compute = function(spec, height)
	local padding = spec.border and 0 or 1

	local header_height = spec.header and 2 or 0
	local question_height = spec.question and #spec.question_lines or 0
	local hints_height = spec.hints and (1 + spec.hint_rows) or 0

	local row = padding
	local header_row = row
	row = row + header_height

	local question_row = row
	row = row + question_height

	local body_row = row

	if spec.fill then
		local use_borders = shared.use_borders()
		local hints_row = use_borders and height - padding - 2 or height - padding
		local body_top = padding + header_height + question_height
		local body_height = hints_row - hints_height - body_top
		return {
			padding = padding,
			header_height = header_height,
			question_height = question_height,
			body_height = math.max(1, body_height),
			hints_height = hints_height,
			header_row = header_row,
			question_row = question_row,
			body_row = body_row,
			hints_row = hints_row,
		}
	end

	row = row + spec.body_rows
	local hints_row = row + hints_height
	row = row + hints_height

	return {
		padding = padding,
		header_height = header_height,
		question_height = question_height,
		body_height = spec.body_rows,
		hints_height = hints_height,
		header_row = header_row,
		question_row = question_row,
		body_row = body_row,
		hints_row = hints_row,
		height = row + padding,
	}
end

return M
