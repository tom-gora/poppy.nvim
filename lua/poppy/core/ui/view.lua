require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local layout = require("poppy.core.ui.layout")
local style = require("poppy.core.ui.style")
local render = require("poppy.core.ui.render")
local shared = require("poppy.core.shared")

M.wrapper = {}
M.content = {}

---@param buf integer
---@param poppy_opts? PoppyMergedConfig
---@param width_override? integer
---@return integer? win
local wrapper_open_with = function(buf, poppy_opts, width_override)
	local width, height, row = layout.compute_wrapper_dimensions(poppy_opts, vim.o.columns, vim.o.lines, width_override)
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
		width = math.min(wrapper_conf.width - list_panel_width - 2),
		height = wrapper_conf.height - 2,
		anchor = "NW",
		col = 0,
		row = 0,
		style = "minimal",
		border = "solid",
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
	close_panel(state.windows.list_win)
	close_panel(state.windows.header_win)
	state.windows.hints_win = nil
	state.windows.list_win = nil
	state.windows.header_win = nil
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

local menu_width = function()
	local v = shared.opts_field("menu_width")
	if type(v) == "function" then v = v() end
	return v or layout.DEFAULT_MENU_WIDTH
end

local SIDEBAR = {
	width_source = "menu",
	list_focusable = false,
	hints_kind = "menu",
	hints_lines_source = "menu",
	hints_opts = function(wc, mw)
		return { width = mw, col = wc.width, row = wc.height - 1, height = render.HINT_LINES.menu, kind = "menu" }
	end,
	header = function(wc, mw)
		return mw, wc.width - mw
	end,
	write_static_width_source = "menu",
}

local LANDING = {
	width_source = "wrapper",
	list_focusable = true,
	hints_kind = "landing",
	hints_lines_source = "landing_plus_2",
	hints_opts = function()
		return { kind = "landing" }
	end,
	header = function()
		return nil, nil
	end,
	write_static_width_source = "wrapper",
}

local mount_panels = function(wrapper_win)
	local wc = api.nvim_win_get_config(wrapper_win)
	local hh = header_height()
	local mw = menu_width()
	local is_landing = state.windows.is_landing
	local cfg = is_landing and LANDING or SIDEBAR

	local list_w = (cfg.width_source == "menu") and mw or wc.width
	local hints_hl = (cfg.hints_lines_source == "menu") and render.HINT_LINES.menu or render.HINT_LINES.landing + 2

	ensure_panel("list_buf", "list_win", function()
		return render.list.create(wrapper_win, list_w, cfg.list_focusable, hints_hl, hh)
	end, function(buf)
		-- Landing's hints_hl already has +2 separator padding; sidebar's doesn't.
		local list_hint = is_landing and hints_hl or (hints_hl + 2)
		return render.list.recreate(wrapper_win, buf, list_w, cfg.list_focusable, list_hint, hh)
	end)

	ensure_panel("hints_buf", "hints_win", function()
		return render.hints.create(wrapper_win, cfg.hints_opts(wc, mw))
	end, function(buf)
		return render.hints.recreate(wrapper_win, buf, cfg.hints_opts(wc, mw))
	end)

	local header_w, header_col = cfg.header(wc, mw)
	ensure_panel("header_buf", "header_win", function()
		return render.header.create(wrapper_win, header_w, header_col)
	end, function(buf)
		return render.header.recreate(wrapper_win, buf, header_w, header_col)
	end, hh == 0)

	if valid_buf(state.windows.hints_buf) then
		local write_w = (cfg.write_static_width_source == "menu") and mw or wc.width
		render.hints.write_static(state.windows.hints_buf, shared.keys(), cfg.hints_kind, write_w)
	end

	-- Populate the list at mount so first show isn't stale (kill-then-show under autohide, etc.).
	if valid_buf(state.windows.list_buf) then
		render.list.update(state.windows.list_buf, state.poppies_configured, shared.opts_field("icons"), list_w)
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
	-- Already in the requested state; nothing to do.
	if state.windows.hidden == (not visible) then
		return
	end

	local wc = api.nvim_win_get_config(wrapper_win)
	if visible then
		mount_panels(wrapper_win)
		if content_win and api.nvim_win_is_valid(content_win) then
			resize_content(content_win, wc.width - menu_width() - 2, wc.height - 2)
		end
	else
		close_all_panels()
		state.windows.hidden = true
		if content_win and api.nvim_win_is_valid(content_win) then
			resize_content(content_win, wc.width - 2, wc.height - 2, 0)
		end
	end
end

---@param focused boolean
---@return void
M.set_focused = function(focused)
	local list_win = state.windows.list_win
	if not list_win or not api.nvim_win_is_valid(list_win) then
		return
	end
	local conf = api.nvim_win_get_config(list_win)
	if conf.focusable ~= focused then
		conf.focusable = focused
		api.nvim_win_set_config(list_win, conf)
	end
end

---@return boolean
M.is_menu_focused = function()
	local list_win = state.windows.list_win
	if not list_win or not api.nvim_win_is_valid(list_win) then
		return false
	end
	return api.nvim_get_current_win() == list_win
end

---@return integer|nil
M.get_hints_buf = function()
	return state.windows.hints_buf
end

---@return integer|nil
M.get_list_buf = function()
	return state.windows.list_buf
end

---@return integer|nil
M.get_list_win = function()
	return state.windows.list_win
end

---@return integer|nil
M.get_header_buf = function()
	return state.windows.header_buf
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
		width = menu_width()
	end
	render.list.update(state.windows.list_buf, state.poppies_configured, shared.opts_field("icons"), width)
end

M.setup_style = style.setup
M.define_icon_signs = style.define_icon_signs

return M
