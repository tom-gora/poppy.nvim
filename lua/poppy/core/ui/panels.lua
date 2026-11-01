-- Panel layout engine.
--
-- One place decides where every panel sits. The rules come from the annotated
-- screenshots in _visual_guide/:
--
--   borderless: one row of space at the bottom only (the borderless "visual
--               border space"); bordered has no padding — the border is the edge
--   header:     always two rows (title + separator), never padded
--   question:   its own height, between the header and the body
--   body:       starts flush under the header, exactly as tall as its text
--   hints:      separator + one row per hint, pinned to the bottom of the
--               wrapper (above the bottom padding when borderless); no gap
--               row between body and the separator — the body sits flush
--               against it (see image 01)
--
-- Padding is a position offset, not extra content: the header starts at row 0
-- in both modes, and the wrapper's height is `stacked_panels + bottom_padding`.
--
-- The wrapper's height is the sum of what it stacks, so it cannot disagree with
-- the panels inside it.

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
---@field width integer Panel width in columns.
---@field fill boolean When true the body takes all the space the hints and header leave, and the wrapper keeps the height it was given. The sidebar is a full-height column; the landing view is sized to its content.

---@class PoppyPanelsLayout
---@field width integer
---@field height integer
---@field padding integer
---@field header_height integer
---@field question_height integer
---@field body_height integer
---@field gap_height integer
---@field hints_height integer
---@field header_row integer
---@field question_row integer
---@field body_row integer
---@field gap_row integer
---@field hints_row integer

---Resolve the flags and measurements the engine needs.
---
---Every consumer reads these from here; nothing else re-derives them. The
---spec is asked per call because a dialog swaps the spec in and out.
---@param spec PoppyMenuSpec
---@param panel_width integer
---@param fill? boolean Sidebar: the body takes the leftover height.
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
		width = panel_width,
		fill = fill == true,
	}
end

---Compute where every panel goes.
---
---`spec.fill` is the sidebar: the body takes every row the header and hints
---leave, and the height is whatever the caller gave. Otherwise the height is
---the sum of what is stacked, which is how the landing view fits its content.
---@param spec PoppyPanelsSpec
---@param height? integer Height to fill, for the sidebar.
---@return PoppyPanelsLayout
M.compute = function(spec, height)
	-- Borderless pads by one row on top AND bottom; bordered has no padding
	-- (the border is the edge). The padding is a positional offset applied
	-- on both ends, so `row` starts at `padding`.
	local padding = spec.border and 0 or 1

	local header_height = spec.header and 2 or 0
	local question_height = spec.question and #spec.question_lines or 0
	-- No gap row between the body and the hints' separator. The hints panel
	-- draws its own separator as its first line; the body sits flush against
	-- it. A question panel's trailing blank provides visual breathing room
	-- above the body when one is up.
	local gap_height = 0
	-- The separator is the hints panel's own first line, so it is part of the
	-- panel rather than a row of its own.
	local hints_height = spec.hints and (1 + spec.hint_rows) or 0

	local row = padding
	local header_row = row
	row = row + header_height

	local question_row = row
	row = row + question_height

	local body_row = row

	local gap_row
	local hints_row
	if spec.fill then
		-- Sidebar fills the menu_wrapper: body takes the leftover height, hints
		-- pin to the bottom (above the bottom padding), with the body ending on
		-- the row immediately above the hints' top so they sit flush.
		-- `view.lua` opens the hints panel with anchor=SW and row=hints_row;
		-- the SW corner lands at hints_row and the panel extends UP, occupying
		-- rows `hints_row - hints_height + 1` to `hints_row`.
		hints_row = height - padding - hints_height + 2
		gap_row = hints_row - gap_height
		-- body_row is the TOP of the body; for sidebar fill, body sits below
		-- the padding, header, and any question, so it starts after all of them.
		local body_top = padding + header_height + question_height
		local body_height = (hints_row - hints_height) - body_top + 1
		return {
			width = spec.width,
			height = height,
			padding = padding,
			header_height = header_height,
			question_height = question_height,
			body_height = math.max(1, body_height),
			gap_height = gap_height,
			hints_height = hints_height,
			header_row = header_row,
			question_row = question_row,
			body_row = body_row,
			gap_row = gap_row,
			hints_row = hints_row,
		}
	end

	row = row + spec.body_rows
	gap_row = row
	row = row + gap_height

	-- Non-fill: hints' SW corner lands one row above the bottom padding so
	-- the hints panel sits at the bottom of the wrapper (matching the design
	-- rule from _visual_guide/).
	hints_row = row + hints_height
	row = row + hints_height

	return {
		width = spec.width,
		height = row + padding,
		padding = padding,
		header_height = header_height,
		question_height = question_height,
		body_height = spec.body_rows,
		gap_height = gap_height,
		hints_height = hints_height,
		header_row = header_row,
		question_row = question_row,
		body_row = body_row,
		gap_row = gap_row,
		hints_row = hints_row,
	}
end

return M
