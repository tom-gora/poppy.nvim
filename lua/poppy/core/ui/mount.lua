require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local layout = require("poppy.core.ui.layout")
local style = require("poppy.core.ui.style")
local render = require("poppy.core.ui.render")
local menu_ui = require("poppy.core.session.menu")

local shared = require("poppy.core.shared")

M.wrapper = {}
M.content = {}
M.menu_wrapper = {}

---@param wrapper_win integer
---@param panel_w integer
---@param panel_h integer
---@return integer? win
---@return integer? buf
M.menu_wrapper.create = function(wrapper_win, panel_w, panel_h)
	local buf = api.nvim_create_buf(false, true)
	local win = layout.open(buf, layout.menu_wrapper_config(wrapper_win, panel_w, panel_h), "panel")
	return win, buf
end

M.menu_wrapper.recreate = function(wrapper_win, buf, panel_w, panel_h)
	return layout.open(buf, layout.menu_wrapper_config(wrapper_win, panel_w, panel_h), "panel")
end

---@param buf integer
---@param poppy_opts? PoppyMergedConfig
---@param width_override? integer
---@param height_override? integer
---@return integer? win
local wrapper_open_with = function(buf, poppy_opts, width_override, height_override)
	return layout.open(
		buf,
		layout.wrapper_config(poppy_opts, width_override, height_override, M.min_wrapper_width()),
		"border"
	)
end

---@param poppy_opts? PoppyMergedConfig
---@param width_override? integer
---@param height_override? integer
---@return integer? win
---@return integer? buf
M.wrapper.create = function(poppy_opts, width_override, height_override)
	local buf = api.nvim_create_buf(false, true)
	local win = wrapper_open_with(buf, poppy_opts, width_override, height_override)
	return win, buf
end

M.wrapper.recreate = wrapper_open_with

---@param win integer|nil
local close_superseded_wrapper = function(win)
	if win and api.nvim_win_is_valid(win) then
		api.nvim_win_close(win, true)
	end
end

---@param buf integer|nil
---@param poppy_opts? PoppyMergedConfig
---@param width_override? integer
---@param height_override? integer
---@return integer? win
---@return integer? buf
M.wrapper.ensure = function(buf, poppy_opts, width_override, height_override)
	close_superseded_wrapper(state.windows.wrapper_win)
	if buf and api.nvim_buf_is_valid(buf) then
		return M.wrapper.recreate(buf, poppy_opts, width_override, height_override), buf
	end
	local win, wbuf = M.wrapper.create(poppy_opts, width_override, height_override)
	return win, wbuf
end

---@param wrapper_win integer
---@param list_panel_width integer
---@return integer? win
---@return integer? buf
M.content.create = function(wrapper_win, list_panel_width)
	local buf = api.nvim_create_buf(false, true)
	local sidebar_reserve = state.windows.menu_hidden and 0 or list_panel_width
	local desc = layout.content_config(wrapper_win, sidebar_reserve)
	local win = layout.open_enter(buf, desc, "content", true)
	return win, buf
end

---@param b integer|nil
---@return boolean
local valid_buf = function(b)
	return b ~= nil and api.nvim_buf_is_valid(b)
end

local close_all_panels = function()
	shared.close_win_if_valid(state.windows.hints_win)
	shared.close_win_if_valid(state.windows.menu_win)
	shared.close_win_if_valid(state.windows.menu_header_win)
	shared.close_win_if_valid(state.windows.header_win)
	shared.close_win_if_valid(state.windows.menu_wrapper_win)
	state.windows.hints_win = nil
	state.windows.menu_win = nil
	state.windows.menu_header_win = nil
	state.windows.header_win = nil
	state.windows.menu_wrapper_win = nil
end

---@param win integer|nil
---@param width integer
---@param height integer
---@param row? integer
---@return nil
local resize_content = function(win, width, height, row)
	layout.resize(win, {
		width = width,
		height = height,
		row = row,
	})
end

---@param buf_key string
---@param win_key string
---@param create fun():integer?,integer?
---@param recreate fun(buf:integer):integer?
---@param skip? boolean
---@return integer? win
---@return integer? buf
local ensure_panel = function(buf_key, win_key, create, recreate, skip)
	if skip then
		state.windows[win_key] = nil
		state.windows[buf_key] = nil
		return nil, nil
	end
	if valid_buf(state.windows[buf_key]) then
		local buf = state.windows[buf_key]
		state.windows[win_key] = recreate(buf)
		return state.windows[win_key], buf
	end
	local win, buf = create()
	state.windows[win_key] = win
	state.windows[buf_key] = buf
	return win, buf
end

local HINT_LINE_LEAD_CELL = 1
local hint_line_floor = function()
	local keys = shared.keys()
	if not keys then
		return layout.MIN_MENU_WIDTH
	end
	return math.max(
		render.measure_hint_line(keys.select or shared.permanent_key("select"), "Select") + HINT_LINE_LEAD_CELL,
		render.measure_hint_line(keys.kill or shared.permanent_key("kill"), "Kill") + HINT_LINE_LEAD_CELL,
		render.measure_hint_line(keys.exit_menu or shared.permanent_key("exit_menu"), "Exit menu") + HINT_LINE_LEAD_CELL,
		render.measure_hint_line(keys.poppy_action, "Toggle off") + HINT_LINE_LEAD_CELL
	)
end

local warned_widths = {}

---@param wrapper_width? integer
---@return integer
local menu_width = function(wrapper_width)
	local declared = layout.evaluate_dimension(shared.opts_field("menu_width"), layout.DEFAULT_MENU_WIDTH, "menu_width")
	-- 0 or negative passes evaluate_dimension; nvim_open_win rejects it.
	local w = math.max(1, declared)

	if w < layout.MIN_MENU_WIDTH or w > layout.MAX_MENU_WIDTH then
		local clamped = math.min(math.max(w, layout.MIN_MENU_WIDTH), layout.MAX_MENU_WIDTH)
		if not warned_widths[declared] then
			warned_widths[declared] = true
			shared.notify_warn(
				"menu_width %d is outside [%d, %d]; using %d",
				declared,
				layout.MIN_MENU_WIDTH,
				layout.MAX_MENU_WIDTH,
				clamped
			)
		end
		w = clamped
	end

	local legend = hint_line_floor()
	if legend > w and legend > layout.MAX_MENU_WIDTH then
		w = legend
	end

	if not wrapper_width then
		return w
	end
	local reserved = layout.MIN_CONTENT_WIDTH + 2
	return math.min(w, math.max(1, wrapper_width - reserved))
end

M.min_wrapper_width = function()
	return menu_width() + layout.MIN_CONTENT_WIDTH + 2
end

---Dialogs own their buffer so their keymaps and settings cannot leak into the list.
---@return integer?
local active_body_buf = function()
	local dialog = state.windows.dialog
	if dialog and dialog.body_buf and api.nvim_buf_is_valid(dialog.body_buf) then
		return dialog.body_buf
	end
	return state.windows.menu_buf
end

M.active_body_buf = active_body_buf

local mount_panels = function(wrapper_win)
	local wc = api.nvim_win_get_config(wrapper_win)
	local mw = menu_width(wc.width)
	local cfg = menu_ui.current_cfg()
	local is_sidebar = cfg.width_source == "menu"

	local panel_w = is_sidebar and mw or wc.width

	local menu = menu_ui.current_spec()
	local q_lines = menu_ui.menu_header_lines(menu, panel_w)

	local fill = is_sidebar
	local wrapper_h = wc.height
	local spec = layout.resolve_spec(menu, panel_w, fill)
	local placement = layout.compute(spec, wrapper_h)

	ensure_panel("menu_wrapper_buf", "menu_wrapper_win", function()
		local buf = api.nvim_create_buf(false, true)
		return layout.open(buf, layout.menu_wrapper_config(wrapper_win, panel_w, wrapper_h), "panel"), buf
	end, function(buf)
		return layout.open(buf, layout.menu_wrapper_config(wrapper_win, panel_w, wrapper_h), "panel")
	end)

	local menu_wrapper = state.windows.menu_wrapper_win
	if not menu_wrapper or not api.nvim_win_is_valid(menu_wrapper) then
		return
	end

	local use_borders = shared.use_borders()

	local mw_cfg = api.nvim_win_get_config(menu_wrapper)
	local inset = shared.get_insets().inset

	local body_buf_key = (state.windows.dialog and state.windows.dialog.body_buf) and "dialog_body_buf" or "menu_buf"
	local body_width = is_sidebar and mw_cfg.width or mw_cfg.width - 2 * inset
	local col = is_sidebar and mw_cfg.width or inset - 1
	-- adjust for non-standard but imho best looking paddings
	if not use_borders and not is_sidebar then
		col = col + 1
	end
	local body_desc = layout.body_config(
		menu_wrapper,
		body_width,
		placement.body_height,
		placement.body_row,
		col,
		is_sidebar and "NE" or "NW",
		layout.POPPY_Z_INDEX,
		cfg.focusable
	)
	ensure_panel(body_buf_key, "menu_win", function()
		local buf = api.nvim_create_buf(false, true)
		render.body_attach_guards(buf)
		return layout.open(buf, body_desc, "body"), buf
	end, function(buf)
		return layout.open(buf, body_desc, "body")
	end)

	local hints_desc = layout.hints_config(
		menu_wrapper,
		mw_cfg.width - 2 * inset,
		placement.hints_height,
		placement.hints_row,
		0,
		"SW",
		layout.POPPY_Z_INDEX
	)
	ensure_panel("hints_buf", "hints_win", function()
		local buf = api.nvim_create_buf(false, true)
		return layout.open(buf, hints_desc, "hints"), buf
	end, function(buf)
		return layout.open(buf, hints_desc, "hints")
	end, not spec.hints)

	if not spec.question and state.windows.menu_header_buf then
		shared.close_win_if_valid(state.windows.menu_header_win)
		api.nvim_buf_delete(state.windows.menu_header_buf, { force = true })
		state.windows.menu_header_win = nil
		state.windows.menu_header_buf = nil
	end

	if spec.question then
		local q_desc = layout.body_plain_config(
			menu_wrapper,
			mw_cfg.width - 2 * inset,
			placement.question_height,
			placement.question_row,
			inset,
			"NW",
			layout.POPPY_QUESTION_Z_INDEX,
			false
		)
		ensure_panel("menu_header_buf", "menu_header_win", function()
			local buf = api.nvim_create_buf(false, true)
			local win = layout.open(buf, q_desc, "panel")
			shared.with_modifiable(buf, function()
				api.nvim_buf_set_lines(buf, 0, -1, false, q_lines)
			end)
			return win, buf
		end, function(buf)
			local win = layout.open(buf, q_desc, "panel")
			shared.with_modifiable(buf, function()
				api.nvim_buf_set_lines(buf, 0, -1, false, q_lines)
			end)
			return win
		end)
	end

	local header_desc = layout.header_config(
		menu_wrapper,
		mw_cfg.width - 2 * inset,
		placement.header_height,
		placement.header_row,
		inset,
		"NW",
		layout.POPPY_Z_INDEX
	)
	ensure_panel("header_buf", "header_win", function()
		local buf = api.nvim_create_buf(false, true)
		local win = layout.open(buf, header_desc, "panel")
		render.header_paint(win, buf, header_desc.config.width)
		return win, buf
	end, function(buf)
		local win = layout.open(buf, header_desc, "panel")
		render.header_paint(win, buf, header_desc.config.width)
		return win
	end, not spec.header)

	local body_buf = active_body_buf()
	if valid_buf(body_buf) then
		render.body.paint_items(body_buf, render.rowset(menu, panel_w - inset))
		if valid_buf(state.windows.hints_buf) then
			render.hints.write_spec(state.windows.hints_buf, shared.keys(), menu.hints, panel_w - inset)
		end
		if cfg.focusable then
			menu_ui.bind(body_buf, menu.keymaps)
		end
	end

	state.windows.wrapper_win = wrapper_win
	state.windows.menu_hidden = false
end

---@param wrapper_win integer
---@return nil
M.mount = function(wrapper_win)
	M.unmount()
	mount_panels(wrapper_win)
end

---@return nil
M.unmount = function()
	close_all_panels()
end

---@param visible boolean
---@param content_win integer|nil
---@return nil
M.set_visible = function(visible, content_win)
	local wrapper_win = state.windows.wrapper_win
	if state.windows.is_landing or not wrapper_win or not api.nvim_win_is_valid(wrapper_win) then
		return
	end

	local wc = api.nvim_win_get_config(wrapper_win)
	if visible then
		mount_panels(wrapper_win)
		local mw = menu_width(wc.width)
		local cw = math.max(1, math.min(wc.width - mw - 2, wc.width - 2))
		resize_content(content_win, cw, wc.height - 2)
	else
		close_all_panels()
		state.windows.menu_hidden = true
		resize_content(content_win, wc.width - 2, wc.height - 2, 0)
	end
end

---@param focused boolean
---@return nil
M.set_focused = function(focused)
	local menu_win = state.windows.menu_win
	if not menu_win or not api.nvim_win_is_valid(menu_win) then
		return
	end
	local conf = api.nvim_win_get_config(menu_win)
	if conf.focusable ~= focused then
		conf.focusable = focused
		api.nvim_win_set_config(menu_win, conf)
	end
end

---@return boolean
M.is_menu_focused = function()
	local menu_win = state.windows.menu_win
	if not menu_win or not api.nvim_win_is_valid(menu_win) then
		return false
	end
	return api.nvim_get_current_win() == menu_win
end

M.menu_width = menu_width

M.refresh_menu_when_visible = function()
	if state.windows.menu_hidden then
		return
	end
	local width
	if state.windows.is_landing and state.windows.wrapper_win then
		width = api.nvim_win_get_width(state.windows.wrapper_win)
	else
		width = menu_width(state.windows.wrapper_win and api.nvim_win_get_width(state.windows.wrapper_win))
	end
	local body_buf = active_body_buf()
	if not valid_buf(body_buf) then
		return
	end
	local inset = shared.get_insets().inset
	local menu = menu_ui.current_spec()
	render.body.paint_items(body_buf, render.rowset(menu, width - inset))
end

M.setup_style = style.setup
M.define_icon_signs = style.define_icon_signs

return M
