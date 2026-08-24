require("poppy._types")

local M = {}
local state = require("poppy.core.session.state")
local layout = require("poppy.core.ui.layout")
local hints_panel = require("poppy.core.ui.hints_panel")
local list_panel = require("poppy.core.ui.list_panel")
local header_panel = require("poppy.core.ui.header_panel")
local shared = require("poppy.core.shared")

---@param b integer|nil
---@return boolean
local valid_buf = function(b)
	return b and vim.api.nvim_buf_is_valid(b)
end

---@param win integer|nil
---@return void
local close_panel = function(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
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
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local win_conf = vim.api.nvim_win_get_config(win)
	vim.api.nvim_win_set_config(win, {
		relative = win_conf.relative,
		width = width,
		height = height,
		col = win_conf.col,
		row = row or win_conf.row,
		win = win_conf.win,
	})
end

-- Reuse the existing buffer if valid, else create. `create` returns
-- (win, buf); `recreate` takes the buf and returns the win. `skip`
-- nils out the state entries (matches the original header_height==0 path).
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
	return shared.opts_field("menu_width") or 25
end

local mount_sidebar_panels = function(wrapper_win)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local mw = menu_width()
	local hh = header_height()
	local hl = hints_panel.HINT_LINES.menu

	ensure_panel("list_buf", "list_win", function()
		return list_panel.create(wrapper_win, mw, false, hl, hh)
	end, function(buf)
		return list_panel.recreate(wrapper_win, buf, mw, false, hl + 2, hh)
	end)

	ensure_panel("hints_buf", "hints_win", function()
		return hints_panel.create(wrapper_win, {
			width = mw,
			col = wc.width,
			row = wc.height - 1,
			height = hl,
			kind = "menu",
		})
	end, function(buf)
		return hints_panel.recreate(wrapper_win, buf, {
			width = mw,
			col = wc.width,
			row = wc.height - 1,
			height = hl,
			kind = "menu",
		})
	end)

	ensure_panel("header_buf", "header_win", function()
		return header_panel.create(wrapper_win, mw, wc.width - mw)
	end, function(buf)
		return header_panel.recreate(wrapper_win, buf, mw, wc.width - mw)
	end, hh == 0)

	if valid_buf(state.windows.hints_buf) then
		hints_panel.write_static(state.windows.hints_buf, shared.keys(), "menu", mw)
	end

	state.windows.wrapper_win = wrapper_win
	state.windows.hidden = false
end

local mount_landing_panels = function(wrapper_win)
	local wc = vim.api.nvim_win_get_config(wrapper_win)
	local hh = header_height()
	local hl = hints_panel.HINT_LINES.landing + 2

	ensure_panel("list_buf", "list_win", function()
		return list_panel.create(wrapper_win, wc.width, true, hl, hh)
	end, function(buf)
		return list_panel.recreate(wrapper_win, buf, wc.width, true, hl, hh)
	end)

	ensure_panel("hints_buf", "hints_win", function()
		return hints_panel.create(wrapper_win, { kind = "landing" })
	end, function(buf)
		return hints_panel.recreate(wrapper_win, buf, { kind = "landing" })
	end)

	ensure_panel("header_buf", "header_win", function()
		return header_panel.create(wrapper_win)
	end, function(buf)
		return header_panel.recreate(wrapper_win, buf)
	end, hh == 0)

	if valid_buf(state.windows.hints_buf) then
		hints_panel.write_static(state.windows.hints_buf, shared.keys(), "landing", wc.width)
	end

	state.windows.wrapper_win = wrapper_win
	state.windows.hidden = false
end

---@param wrapper_win integer
---@return void
M.mount = function(wrapper_win)
	M.unmount()
	if state.windows.is_landing then
		mount_landing_panels(wrapper_win)
	else
		mount_sidebar_panels(wrapper_win)
	end
end

---@return void
M.unmount = function()
	close_all_panels()
end

-- Sidebar visibility (autohide mode). No-op in landing. When visible=true,
-- mounts the sidebar panels and shrinks content to leave room; when
-- visible=false, closes panels and grows content back to wrapper width.
---@param visible boolean
---@param content_win integer
---@return void
M.set_visible = function(visible, content_win)
	if state.windows.is_landing or not state.windows.wrapper_win then
		return
	end
	local wrapper_win = state.windows.wrapper_win
	if not vim.api.nvim_win_is_valid(wrapper_win) then
		return
	end
	local wc = vim.api.nvim_win_get_config(wrapper_win)

	if visible then
		if not state.windows.hidden then
			return
		end
		mount_sidebar_panels(wrapper_win)
		if content_win and vim.api.nvim_win_is_valid(content_win) then
			resize_content(content_win, wc.width - menu_width() - 2, wc.height - 2)
		end
	else
		if state.windows.hidden then
			return
		end
		close_all_panels()
		state.windows.hidden = true
		if content_win and vim.api.nvim_win_is_valid(content_win) then
			resize_content(content_win, wc.width - 2, wc.height - 2, 0)
		end
	end
end

-- The only runtime dial within sidebar: flip the list panel's focusable.
-- No rebuild — just sets the focusable option on the existing window.
---@param focused boolean
---@return void
M.set_focused = function(focused)
	local list_win = state.windows.list_win
	if not list_win or not vim.api.nvim_win_is_valid(list_win) then
		return
	end
	local conf = vim.api.nvim_win_get_config(list_win)
	if conf.focusable ~= focused then
		conf.focusable = focused
		vim.api.nvim_win_set_config(list_win, conf)
	end
end

-- Derived from Neovim's current window. No sync point needed.
---@return boolean
M.is_menu_focused = function()
	local list_win = state.windows.list_win
	if not list_win or not vim.api.nvim_win_is_valid(list_win) then
		return false
	end
	return vim.api.nvim_get_current_win() == list_win
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

-- Exposed so callers (e.g. actions.lua) can read the same default-handled
-- value without re-implementing the `state.windows.opts and ... or 25` chain.
M.menu_width = menu_width

return M
