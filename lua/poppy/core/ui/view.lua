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

-- Read once per mount. Reads opts each call so toggling border at setup() takes effect on
-- the next mount without rebuilding this module.
local function is_borders()
	return state.windows.opts and state.windows.opts.use_borders or false
end

---@param wrapper_win integer
---@param panel_w integer Width of the panel content area (sidebar mw or full wrapper width in landing).
---@param panel_h integer Height of the panel content area (full wrapper height).
---@return integer? win
---@return integer? buf
M.menu_wrapper.create = function(wrapper_win, panel_w, panel_h)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local bordered = is_borders()
	-- Bordered mode: content is panel_w/panel_h minus 1 on each side (border takes a cell
	-- each), so the visual extent (content + 2) fits exactly inside the wrapper.
	local outer_w = bordered and panel_w or panel_w
	local outer_h = bordered and (panel_h - 2) or panel_h
	-- Borders occupy the outer cells, content starts 1 cell inside.
	local outer_col_offset = bordered and 0 or 0
	local outer_row_offset = bordered and 0 or 0

	local buf = api.nvim_create_buf(false, true)
	local win = api.nvim_open_win(buf, false, {
		relative = "win",
		win = wrapper_win,
		width = outer_w,
		height = outer_h,
		col = wrapper_conf.width - panel_w + outer_col_offset,
		row = outer_row_offset,
		style = "minimal",
		border = state.windows.opts.border_style,
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
	})
	style.apply_panel_style(win)
	shared.apply_win_marker(win)
	return win, buf
end

M.menu_wrapper.recreate = function(wrapper_win, buf, panel_w, panel_h)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local bordered = is_borders()
	local outer_w = bordered and panel_w or panel_w
	local outer_h = bordered and (panel_h - 2) or panel_h
	local outer_col_offset = bordered and 0 or 0
	local outer_row_offset = bordered and 0 or 0

	local win = api.nvim_open_win(buf, false, {
		relative = "win",
		win = wrapper_win,
		width = outer_w,
		height = outer_h,
		col = wrapper_conf.width - panel_w + outer_col_offset,
		row = outer_row_offset,
		style = "minimal",
		border = state.windows.opts.border_style,
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
	})
	style.apply_panel_style(win)
	shared.apply_win_marker(win)
	return win
end

M.menu_wrapper.ensure = function(buf, wrapper_win, panel_w, panel_h)
	if buf and api.nvim_buf_is_valid(buf) then
		return M.menu_wrapper.recreate(wrapper_win, buf, panel_w, panel_h), buf
	end
	local win, wbuf = M.menu_wrapper.create(wrapper_win, panel_w, panel_h)
	return win, wbuf
end

---@param buf integer
---@param poppy_opts? PoppyMergedConfig
---@param width_override? integer
---@return integer? win
local wrapper_open_with = function(buf, poppy_opts, width_override)
	local width, height, row =
		layout.compute_wrapper_dimensions(poppy_opts, vim.o.columns, vim.o.lines, width_override, M.min_wrapper_width())
	-- wrapper window: the editor-anchored float that holds every panel.
	---@type vim.api.keyset.win_config
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = row,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
	}
	local win = api.nvim_open_win(buf, false, config)
	style.apply_border_style(win)
	shared.apply_win_marker(win)
	return win
end

---@param poppy_opts? PoppyMergedConfig
---@param width_override? integer
---@return integer? win
---@return integer? buf
M.wrapper.create = function(poppy_opts, width_override)
	local buf = api.nvim_create_buf(false, true)
	local win = wrapper_open_with(buf, poppy_opts, width_override)
	return win, buf
end

M.wrapper.recreate = wrapper_open_with

---@param buf integer|nil
---@param poppy_opts? PoppyMergedConfig
---@param width_override? integer
---@return integer? win
---@return integer? buf
M.wrapper.ensure = function(buf, poppy_opts, width_override)
	if buf and api.nvim_buf_is_valid(buf) then
		return M.wrapper.recreate(buf, poppy_opts, width_override), buf
	end
	local win, wbuf = M.wrapper.create(poppy_opts, width_override)
	return win, wbuf
end

---@param wrapper_win integer
---@param list_panel_width integer
---@return integer? win
---@return integer? buf
M.content.create = function(wrapper_win, list_panel_width)
	local buf = api.nvim_create_buf(false, true)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local ext_nu = vim.o.number
	local ext_rnu = vim.o.relativenumber

	-- content window: shows the active poppy's buffer; takes the left slot inside the wrapper.
	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = math.max(1, math.min(wrapper_conf.width - list_panel_width - 2, wrapper_conf.width - 2)),
		height = wrapper_conf.height - 2,
		anchor = "NW",
		col = 0,
		row = 0,
		style = "minimal",
		border = state.windows.opts.use_borders and state.windows.opts.border_style or "solid",
		zindex = layout.POPPY_Z_INDEX,
		focusable = true,
		win = wrapper_win,
	}

	local win = api.nvim_open_win(buf, true, config)

	style.apply_content_style(win, ext_nu, ext_rnu)
	shared.apply_win_marker(win)
	return win, buf
end

---@param b integer|nil
---@return boolean
local valid_buf = function(b)
	return b and api.nvim_buf_is_valid(b)
end

---@param win integer|nil
---@return void
local close_panel = function(win)
	if win and api.nvim_win_is_valid(win) then
		api.nvim_win_close(win, true)
	end
end

local close_all_panels = function()
	close_panel(state.windows.hints_win)
	close_panel(state.windows.menu_win)
	close_panel(state.windows.menu_header_win)
	close_panel(state.windows.header_win)
	close_panel(state.windows.menu_wrapper_win)
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
---@return void
local resize_content = function(win, width, height, row)
	if not win or not api.nvim_win_is_valid(win) then
		return
	end
	local win_conf = api.nvim_win_get_config(win)
	api.nvim_win_set_config(win, {
		relative = win_conf.relative,
		width = width,
		height = height,
		col = win_conf.col,
		row = row or win_conf.row,
		win = win_conf.win,
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

local header_height = function()
	return layout.get_header_height(state.windows.opts)
end

-- Widest hint line the sidebar can ever need. The +1 is the hints separator's lead space.
local legend_floor = function()
	local keys = shared.keys()
	if not keys then
		return layout.MIN_MENU_WIDTH
	end
	return math.max(
		render.measure_hint_line(keys.select, "Select") + 1,
		render.measure_hint_line(keys.kill, "Kill") + 1,
		render.measure_hint_line(keys.exit_menu, "Exit menu") + 1,
		render.measure_hint_line(keys.poppy_action, "Toggle off") + 1
	)
end

-- Already warned about, so a repaint does not re-notify on every mount.
local warned_widths = {}

-- Centralised here so mount_panels, set_visible, and refresh_poppies agree on one width.
---@param wrapper_width? integer
---@return integer
local menu_width = function(wrapper_width)
	local declared = layout.evaluate_dimension(shared.opts_field("menu_width"), layout.DEFAULT_MENU_WIDTH, "menu_width")
	-- Floor at 1: 0 or negative passes evaluate_dimension, and nvim_open_win rejects it.
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

	-- Only overrides a declared width if a remapped key makes it impossible to honour even at MAX.
	local legend = legend_floor()
	if legend > w and legend > layout.MAX_MENU_WIDTH then
		w = legend
	end

	if not wrapper_width then
		return w
	end
	-- Sidebar gives way to keep MIN_CONTENT_WIDTH for the content pane.
	local reserved = layout.MIN_CONTENT_WIDTH + 2
	return math.min(w, math.max(1, wrapper_width - reserved))
end

-- Passed to compute_wrapper_dimensions so a narrow screen widens the wrapper instead of crushing the sidebar.
M.min_wrapper_width = function()
	return menu_width() + layout.MIN_CONTENT_WIDTH + 2
end

-- Geometry only. Which presentation is showing, focusability, and the legend live in the menu
-- backend; this layer adds only offsets and the header split.
local GEOMETRY = {
	sidebar = function(wc, mw, h)
		return { width = mw, col = wc.width, row = wc.height - 1, row_offset = 1, height = h }
	end,
	landing = function(wc, mw, h)
		return { width = wc.width, col = wc.width, row = wc.height, height = h }
	end,
	sidebar_header = function(wc, mw)
		return mw, wc.width - mw
	end,
	landing_header = function()
		return nil, nil
	end,
}

-- A panel present contributes its height to everything below it; an absent one contributes nothing.
-- That is what lets `title_header = false` drop the title bar and a dialog's menu_header sit
-- directly on top of the body with no per-case arithmetic.
local mount_panels = function(wrapper_win)
	local wc = api.nvim_win_get_config(wrapper_win)
	local hh = header_height()
	local mw = menu_width(wc.width)
	local cfg = menu_ui.current_cfg()
	local is_sidebar = cfg.width_source == "menu"
	local hint_geom = is_sidebar and GEOMETRY.sidebar or GEOMETRY.landing

	local panel_w = is_sidebar and mw or wc.width
	local panel_h = wc.height

	local menu = menu_ui.current_spec()
	local legend_h = menu_ui.legend_height(menu.hints)
	local hints_on = shared.opts_field("hints_footer") ~= false
	local effective_legend_h = hints_on and legend_h or 0
	local q_lines, q_h = menu_ui.menu_header_lines(menu, panel_w)
	local above_body = hh + q_h

	-- menu_wrapper sits behind the panel area as a quiet sizing container in
	-- borderless mode, and grows a rounded border in bordered mode (with sub-
	-- panels inset 1 cell via render.lua's border_inset()).
	ensure_panel("menu_wrapper_buf", "menu_wrapper_win", function()
		return M.menu_wrapper.create(wrapper_win, panel_w, panel_h)
	end, function(buf)
		return M.menu_wrapper.recreate(wrapper_win, buf, panel_w, panel_h)
	end)

	local menu_wrapper = state.windows.menu_wrapper_win
	if not menu_wrapper or not api.nvim_win_is_valid(menu_wrapper) then
		-- Without a menu_wrapper the sub-panels have nothing to anchor to.
		return
	end

	ensure_panel("menu_buf", "menu_win", function()
		return render.body.create(menu_wrapper, panel_w, cfg.focusable, effective_legend_h, above_body)
	end, function(buf)
		return render.body.recreate(menu_wrapper, buf, panel_w, cfg.focusable, effective_legend_h, above_body)
	end)

	ensure_panel("hints_buf", "hints_win", function()
		return render.hints.create(menu_wrapper, hint_geom(wc, mw, #menu.hints))
	end, function(buf)
		return render.hints.recreate(menu_wrapper, buf, hint_geom(wc, mw, #menu.hints))
	end, not hints_on)

	-- focusable = false on the question panel: cursor stays in the answers buffer.
	-- wrap + linebreak stay on as a safety net for narrower-than-wrapped widths.
	if q_h == 0 and state.windows.menu_header_buf then
		-- Stale question panel from a prior dialog or re-render.
		close_panel(state.windows.menu_header_win)
		api.nvim_buf_delete(state.windows.menu_header_buf, { force = true })
		state.windows.menu_header_win = nil
		state.windows.menu_header_buf = nil
	end

	if q_h > 0 then
		-- menu_header_buf occupies the rows the body yields to it: the body's own start row.
		local q_row = is_borders() and (hh - 1) or hh
		ensure_panel("menu_header_buf", "menu_header_win", function()
			local win, buf = render.body.create_plain(menu_wrapper, panel_w, q_h, q_row)
			vim.wo[win].wrap = true
			vim.wo[win].linebreak = true
			shared.with_modifiable(buf, function()
				api.nvim_buf_set_lines(buf, 0, -1, false, q_lines)
			end)
			return win, buf
		end, function(buf)
			return render.body.recreate_plain(menu_wrapper, buf, panel_w, q_h, q_row)
		end)
	end

	-- Header is anchored to menu_wrapper so it sits inside the rounded border along with
	-- the rest of the panel stack; render.lua handles the inset based on opts.use_borders.
	ensure_panel("header_buf", "header_win", function()
		return render.header.create(menu_wrapper)
	end, function(buf)
		return render.header.recreate(menu_wrapper, buf)
	end, hh == 0)

	-- First-show under autohide would otherwise be stale (kill-then-show).
	if valid_buf(state.windows.menu_buf) then
		local inset = is_borders() and 1 or 0
		render.body.paint_items(state.windows.menu_buf, render.rowset(menu, panel_w - inset))
		if valid_buf(state.windows.hints_buf) then
			render.hints.write_spec(state.windows.hints_buf, shared.keys(), menu.hints, panel_w - inset)
		end
		-- Bind only on focusable bodies; get_keymap would still report bindings as claimed on an unfocusable one.
		if cfg.focusable then
			menu_ui.bind_spec(state.windows.menu_buf, menu)
		end
	end

	state.windows.wrapper_win = wrapper_win
	state.windows.hidden = false
end

---@param wrapper_win integer
---@return void
M.mount = function(wrapper_win)
	M.unmount()
	mount_panels(wrapper_win)
end

---@return void
M.unmount = function()
	close_all_panels()
end

---@param visible boolean
---@param content_win integer
---@return void
M.set_visible = function(visible, content_win)
	if state.windows.is_landing or not state.windows.wrapper_win then
		return
	end
	local wrapper_win = state.windows.wrapper_win
	if not api.nvim_win_is_valid(wrapper_win) then
		return
	end
	if state.windows.hidden == not visible then
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
		state.windows.hidden = true
		resize_content(content_win, wc.width - 2, wc.height - 2, 0)
	end
end

---@param focused boolean
---@return void
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

---@return integer|nil
M.get_hints_buf = function()
	return state.windows.hints_buf
end

---@return integer|nil
M.get_menu_header_buf = function()
	return state.windows.menu_header_buf
end

---@return integer|nil
M.get_menu_buf = function()
	return state.windows.menu_buf
end

---@return integer|nil
M.get_menu_win = function()
	return state.windows.menu_win
end

---@return integer|nil
M.get_header_buf = function()
	return state.windows.header_buf
end

---@return integer|nil
M.get_menu_wrapper_buf = function()
	return state.windows.menu_wrapper_buf
end

M.menu_width = menu_width

M.refresh_poppies = function()
	if state.windows.hidden then
		return
	end
	local width
	if state.windows.is_landing and state.windows.wrapper_win then
		width = api.nvim_win_get_width(state.windows.wrapper_win)
	else
		width = menu_width(state.windows.wrapper_win and api.nvim_win_get_width(state.windows.wrapper_win))
	end
	if not valid_buf(state.windows.menu_buf) then
		return
	end
	local inset = is_borders() and 1 or 0
	local menu = menu_ui.current_spec()
	render.body.paint_items(state.windows.menu_buf, render.rowset(menu, width - inset))
end

M.setup_style = style.setup
M.define_icon_signs = style.define_icon_signs

return M
