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
	return M.menu_wrapper.recreate(wrapper_win, buf, panel_w, panel_h), buf
end

M.menu_wrapper.recreate = function(wrapper_win, buf, panel_w, panel_h)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local outer_h = shared.use_borders() and (panel_h - 2) or panel_h

	local win = api.nvim_open_win(buf, false, {
		relative = "win",
		win = wrapper_win,
		width = panel_w,
		height = outer_h,
		col = wrapper_conf.width - panel_w,
		row = 0,
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

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = math.max(1, math.min(wrapper_conf.width - list_panel_width - 2, wrapper_conf.width - 2)),
		height = wrapper_conf.height - 2,
		anchor = "NW",
		col = 0,
		row = 0,
		style = "minimal",
		border = shared.use_borders() and state.windows.opts.border_style or "solid",
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
	return b ~= nil and api.nvim_buf_is_valid(b)
end

---@param win integer|nil
---@return nil
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
---@return nil
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

-- Widest hint line the sidebar can ever need; +1 for the hints separator's lead space.
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

local warned_widths = {}

-- Centralised so mount_panels, set_visible, and refresh_poppies agree on one width.
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

	local legend = legend_floor()
	if legend > w and legend > layout.MAX_MENU_WIDTH then
		w = legend
	end

	if not wrapper_width then
		return w
	end
	local reserved = layout.MIN_CONTENT_WIDTH + 2
	return math.min(w, math.max(1, wrapper_width - reserved))
end

-- Passed to compute_wrapper_dimensions so a narrow screen widens the wrapper instead of crushing the sidebar.
M.min_wrapper_width = function()
	return menu_width() + layout.MIN_CONTENT_WIDTH + 2
end

-- Only width and height reach the hints panel; the panel anchors itself.
local GEOMETRY = {
	sidebar = function(_, mw, h)
		return { width = mw, height = h }
	end,
	landing = function(wc, _, h)
		return { width = wc.width, height = h }
	end,
}

-- A present panel contributes its height to everything below it; an absent one contributes nothing.
-- That lets `title_header = false` drop the title bar and a dialog's menu_header sit directly on
-- top of the body with no per-case arithmetic.
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

	-- menu_wrapper is a quiet sizing container in borderless mode; in bordered mode it grows the
	-- rounded border and sub-panels inset 1 cell via shared.get_insets().
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

	-- focusable = false on the question panel so cursor stays in the answers buffer.
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
		local q_row = shared.use_borders() and (hh - 1) or hh
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

	ensure_panel("header_buf", "header_win", function()
		return render.header.create(menu_wrapper)
	end, function(buf)
		return render.header.recreate(menu_wrapper, buf)
	end, hh == 0)

	-- First-show under autohide would otherwise be stale (kill-then-show).
	if valid_buf(state.windows.menu_buf) then
		local inset = shared.get_insets().inset
		render.body.paint_items(state.windows.menu_buf, render.rowset(menu, panel_w - inset))
		if valid_buf(state.windows.hints_buf) then
			render.hints.write_spec(state.windows.hints_buf, shared.keys(), menu.hints, panel_w - inset)
		end
		-- Bind only on focusable bodies; get_keymap would still report bindings as claimed on an unfocusable one.
		if cfg.focusable then
			menu_ui.bind(state.windows.menu_buf, menu.keymaps)
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
	if state.windows.is_landing or not wrapper_win then
		return
	end
	if not api.nvim_win_is_valid(wrapper_win) then
		return
	end
	if state.windows.menu_hidden == not visible then
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

M.refresh_poppies = function()
	if state.windows.menu_hidden then
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
	local inset = shared.get_insets().inset
	local menu = menu_ui.current_spec()
	render.body.paint_items(state.windows.menu_buf, render.rowset(menu, width - inset))
end

M.setup_style = style.setup
M.define_icon_signs = style.define_icon_signs

return M
