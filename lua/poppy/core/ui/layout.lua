require("poppy._types")

local M = {}

local api = vim.api
local fn = vim.fn
local style = require("poppy.core.ui.style")
local shared = require("poppy.core.shared")
local state = require("poppy.core.session.state")

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

local NUMBER = vim.o.number
local RELATIVENUMBER = vim.o.relativenumber

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
M.MIN_LINES = 12

---@return boolean
M.below_floor = function()
	return vim.o.columns < M.MIN_COLS or vim.o.lines < M.MIN_LINES
end

---Editor rows excluding tabline/statusline (which nvim manages outside the grid).
---The current window may be a poppy float with height 1 once mounted; walk back to
---a real editor window instead so resizes during transition_to_content see the
---actual editor area, not the focused float.
---@return integer
M.editor_height = function()
	local cur = api.nvim_get_current_win()
	local cur_conf = api.nvim_win_get_config(cur)
	if cur_conf.relative == "" then
		return api.nvim_win_get_height(cur)
	end
	for _, w in ipairs(api.nvim_list_wins()) do
		local c = api.nvim_win_get_config(w)
		if c.relative == "" then
			return api.nvim_win_get_height(w)
		end
	end
	return vim.o.lines
end

local HEADER_HEIGHT = 3

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
		render.measure_hint_line(keys.select or shared.permanent_key("select"), "Select"),
		render.measure_hint_line(keys.poppy_action, "Toggle Off")
	)

	-- Each extent already includes its own left inset, so PANEL_PAD is added once on the trailing side.
	local content = math.max(widest_row, widest_hint) + M.PANEL_PAD
	local chrome = fn.strdisplaywidth(M.HEADER_TITLE) + (M.PANEL_PAD * 2)
	-- 2 trailing cells of right padding (always), plus 1 cell per side in bordered mode
	-- so the inner panel width matches borderless.
	return math.max(content, chrome) + 2 + (2 * shared.get_insets().inset)
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
---@param content_height? integer Landing wrapper sized to fit content; ignored when nil.
---@return integer width
---@return integer height
---@return integer row
M.compute_wrapper_dimensions = function(opts, vim_cols, vim_lines, content_width, min_width, content_height)
	opts = opts or {}

	local raw_w = evaluate_dimension(opts.win_width or 0.8, 0.8, "win_width")
	local raw_h = evaluate_dimension(opts.win_height or 0.75, 0.75, "win_height")

	-- Replacement, not a floor: max(content, win_width) would let win_width win on launch.
	local width = content_width and math.min(content_width, vim_cols) or resolve_dimension(raw_w, vim_cols, "win_width")

	-- Ratio is a preference, not a promise: the wrapper grows on a screen too narrow for both.
	if min_width and not content_width and width < min_width then
		width = math.min(min_width, vim_cols)
	end

	local height = content_height or resolve_dimension(raw_h, vim_lines, "win_height")

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

	local render = require("poppy.core.ui.render")
	local text_width = math.max(1, panel_width - render.measure_item(1, ""))
	local question_lines = {}
	if spec.menu_header and #spec.menu_header > 0 then
		for _, para in ipairs(spec.menu_header) do
			for _, l in ipairs(vim.split(para, "\n", { plain = true })) do
				question_lines[#question_lines + 1] = l
			end
		end
	end

	return {
		border = shared.use_borders(),
		header = shared.opts_field("title_header") ~= false,
		hints = shared.opts_field("hints_footer") ~= false,
		question = #question_lines > 0,
		body_rows = math.max(1, body_rows),
		hint_rows = #spec.hints,
		question_lines = question_lines,
		question_height = render.soft_wrap_height(question_lines, text_width),
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
	local question_height = spec.question and (spec.question_height or #spec.question_lines) or 0
	local hints_height = spec.hints and (1 + spec.hint_rows) or 0

	local row = padding
	local header_row = row
	row = row + header_height

	local question_row = row
	row = row + question_height

	local body_row = row

	if spec.fill then
		local use_borders = shared.use_borders()
		local is_dialog = state.windows.dialog and state.windows.dialog.kind == "kill_confirm"
		local hints_row = use_borders and height - padding - 2 or height - padding
		local body_row_gap = is_dialog and body_row + 1 or body_row
		local body_height = hints_row - hints_height - body_row_gap
		return {
			padding = padding,
			header_height = header_height,
			question_height = question_height,
			body_height = math.max(1, body_height),
			hints_height = hints_height,
			header_row = header_row,
			question_row = question_row,
			body_row = body_row_gap,
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

-- Per-window configs. Border decisions live here, not in view/mount orchestration.
---@class WindowDesc
---@field config vim.api.keyset.win_config
---@field options table<string, any>

---@param poppy_opts? PoppyMergedConfig
---@param width_override? integer
---@param height_override? integer
---@param min_width? integer
---@return WindowDesc
M.wrapper_config = function(poppy_opts, width_override, height_override, min_width)
	local width, height, row = M.compute_wrapper_dimensions(
		poppy_opts,
		vim.o.columns,
		M.editor_height(),
		width_override,
		min_width,
		height_override
	)
	return {
		config = {
			relative = "editor",
			width = width,
			height = height,
			col = math.floor((vim.o.columns - width) / 2),
			row = row,
			style = "minimal",
			border = "none",
			zindex = M.POPPY_Z_INDEX,
			focusable = false,
		},
		options = {},
	}
end

---@param wrapper_win integer
---@param panel_w integer
---@param panel_h integer
---@return WindowDesc
M.menu_wrapper_config = function(wrapper_win, panel_w, panel_h)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local cfg = require("poppy.core.session.menu").current_cfg()
	local is_sidebar = cfg.width_source == "menu"
	if is_sidebar and shared.use_borders() then
		panel_h = panel_h - 2
	end
	return {
		config = {
			relative = "win",
			win = wrapper_win,
			width = panel_w,
			height = panel_h,
			col = wrapper_conf.width - panel_w,
			row = 0,
			style = "minimal",
			border = state.windows.opts.border_style,
			zindex = M.POPPY_Z_INDEX,
			focusable = false,
		},
		options = {},
	}
end

---@param wrapper_win integer
---@param sidebar_reserve integer
---@return WindowDesc
M.content_config = function(wrapper_win, sidebar_reserve)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	return {
		config = {
			relative = "win",
			win = wrapper_win,
			width = math.max(1, math.min(wrapper_conf.width - sidebar_reserve - 2, wrapper_conf.width - 2)),
			height = wrapper_conf.height - 2,
			anchor = "NW",
			col = 0,
			row = 0,
			style = "minimal",
			border = shared.use_borders() and state.windows.opts.border_style or "solid",
			zindex = M.POPPY_Z_INDEX,
			focusable = true,
		},
		options = {},
	}
end

---@param menu_wrapper integer
---@param width integer
---@param height integer
---@param row integer
---@param col integer
---@param anchor string
---@param zindex integer
---@param focusable boolean
---@return WindowDesc
M.body_config = function(menu_wrapper, width, height, row, col, anchor, zindex, focusable)
	return {
		config = {
			relative = "win",
			win = menu_wrapper,
			width = width - 1,
			height = height,
			row = row,
			col = col,
			anchor = anchor,
			style = "minimal",
			border = "none",
			zindex = zindex,
			focusable = focusable,
		},
		options = { signcolumn = "yes:2", cursorline = true },
	}
end

---Question panel: same shape as body, but cursorline off and wrap on.
---@param menu_wrapper integer
---@param width integer
---@param height integer
---@param row integer
---@param col integer
---@param anchor string
---@param zindex integer
---@param focusable boolean
---@return WindowDesc
M.body_plain_config = function(menu_wrapper, width, height, row, col, anchor, zindex, focusable)
	local d = M.body_config(menu_wrapper, width, height, row, col, anchor, zindex, focusable)
	d.options.cursorline = false
	d.options.wrap = true
	d.options.linebreak = true
	return d
end

---@param menu_wrapper integer
---@param width integer
---@param height integer
---@param row integer
---@param col integer
---@param anchor string
---@param zindex integer
---@return WindowDesc
M.header_config = function(menu_wrapper, width, height, row, col, anchor, zindex)
	return {
		config = {
			relative = "win",
			win = menu_wrapper,
			width = width - 1,
			height = height,
			row = row,
			col = col + 1,
			anchor = anchor,
			style = "minimal",
			border = "none",
			zindex = zindex,
			focusable = false,
		},
		options = {},
	}
end

---@param menu_wrapper integer
---@param width integer
---@param height integer
---@param row integer
---@param col integer
---@param anchor string
---@param zindex integer
---@return WindowDesc
M.hints_config = function(menu_wrapper, width, height, row, col, anchor, zindex)
	-- Soft-wrap would duplicate the trailing cell onto a second visual row.
	return {
		config = {
			relative = "win",
			win = menu_wrapper,
			width = width - 1,
			height = height,
			row = row,
			col = col + 1,
			anchor = anchor,
			style = "minimal",
			border = "none",
			zindex = zindex,
			focusable = false,
		},
		options = { wrap = false, linebreak = false },
	}
end

---@param parent_win integer
---@param text string
---@return WindowDesc
M.menu_hint_badge_config = function(parent_win, text)
	local win_conf = api.nvim_win_get_config(parent_win)
	return {
		config = {
			relative = "win",
			width = #text,
			height = 1,
			col = math.max(0, win_conf.width) + 1,
			row = math.max(0, win_conf.height) + 1,
			anchor = "SE",
			style = "minimal",
			border = "none",
			zindex = M.POPPY_Z_INDEX + 1,
			focusable = false,
			win = parent_win,
		},
		options = {},
	}
end

-- ─── Open / close / resize ──────────────────────────────────────────────────
-- Style label drives which style.apply_* is called after open. Single source
-- of truth for "which style does this window get."

---@param win integer?
---@param style_label "panel"|"body"|"content"|"hints"|"border"|nil
local apply_style = function(win, style_label)
	if style_label == "panel" then
		style.apply_panel_style(win)
	elseif style_label == "body" then
		style.apply_body_style(win)
	elseif style_label == "content" then
		style.apply_content_style(win, NUMBER, RELATIVENUMBER)
	elseif style_label == "hints" then
		style.apply_hints_panel_style(win)
	elseif style_label == "border" then
		style.apply_border_style(win)
	end
end

local WIN_MARKER = "poppy_window"
local mark = function(win)
	api.nvim_win_set_var(win, WIN_MARKER, true)
end

---@param buf integer
---@param desc WindowDesc
---@param style_label? "panel"|"body"|"content"|"hints"|"border"
---@return integer? win
M.open = function(buf, desc, style_label)
	if not buf or not api.nvim_buf_is_valid(buf) then
		return nil
	end
	local win = api.nvim_open_win(buf, false, desc.config)
	for k, v in pairs(desc.options or {}) do
		vim.wo[win][k] = v
	end
	apply_style(win, style_label)
	mark(win)
	return win
end

---@param buf integer
---@param desc WindowDesc
---@param style_label? string
---@param enter? boolean Enter the window after open.
---@return integer? win
M.open_enter = function(buf, desc, style_label, enter)
	if not buf or not api.nvim_buf_is_valid(buf) then
		return nil
	end
	local win = api.nvim_open_win(buf, enter == true, desc.config)
	for k, v in pairs(desc.options or {}) do
		vim.wo[win][k] = v
	end
	apply_style(win, style_label)
	mark(win)
	return win
end

---Create a fresh unmodifiable scratch buffer and open a window on it.
---@param desc WindowDesc
---@param style_label? string
---@param enter? boolean
---@return integer? win
---@return integer buf
M.open_scratch = function(desc, style_label, enter)
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	local win = M.open_enter(buf, desc, style_label, enter)
	return win, buf
end

---@param win integer?
M.close = function(win)
	if win and api.nvim_win_is_valid(win) then
		api.nvim_win_close(win, true)
	end
end

---@param win integer?
---@param partial table Fields override the existing win_config; the rest is preserved.
---@return nil
M.resize = function(win, partial)
	if not win or not api.nvim_win_is_valid(win) then
		return
	end
	local wc = api.nvim_win_get_config(win)
	-- tbl_extend("force", defaults, partial): partial overrides defaults on conflict.
	api.nvim_win_set_config(
		win,
		vim.tbl_extend("force", {
			relative = wc.relative,
			col = wc.col,
			row = wc.row,
			win = wc.win,
			anchor = wc.anchor,
		}, partial)
	)
end

return M
