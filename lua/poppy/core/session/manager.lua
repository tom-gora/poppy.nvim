local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local panels = require("poppy.core.ui.panels")
local wrapper = require("poppy.core.ui.wrapper")
local content = require("poppy.core.ui.content")
local input = require("poppy.core.input")
local layout = require("poppy.core.ui.layout")
local util = require("poppy.core.util")
local switching = require("poppy.core.session.switching")
local killing = require("poppy.core.session.killing")
local events = require("poppy.core.session.events")

-- Augroup for per-window WinClosed watchers created by _watch_content_window.
-- Cleared (not destroyed) during cleanup / recover via nvim_create_augroup(_, {clear=true}).
vim.api.nvim_create_augroup("poppy_ui", { clear = false })

-- Forward decl for mutual reference inside the autocmd callback.
local _watch_content_window

_watch_content_window = function(win_id, menu_width)
	if not win_id then
		return
	end
	local mw = menu_width or 25
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = "poppy_ui",
		callback = function()
			if not util.is_open(state.wrapper_win) then
				return
			end
			local c_win, c_buf = content.create(state.wrapper_win, mw)
			state.content_win = c_win
			state.content_buf = c_buf
			_watch_content_window(c_win, mw)
			if state.current_poppy_name then
				killing.kill_active()
			else
				killing.recover()
			end
		end,
	})
end

M.watch_content_window = _watch_content_window

local cleanup = function()
	if state.current_poppy_name then
		local ps = poppy_state.runtime_get(state.current_poppy_name)
		if ps then
			ps.active = false
			ps.hidden = true
			ps.win = nil
		end
	end

	if state.menu_hint_win and vim.api.nvim_win_is_valid(state.menu_hint_win) then
		vim.api.nvim_win_close(state.menu_hint_win, true)
	end
	local hint_buf = state.menu_hint_buf
	state.menu_hint_win = nil
	state.menu_hint_buf = nil

	panels.destroy()

	-- Wipe per-window WinClosed watchers before closing windows; otherwise
	-- our own cleanup would re-fire the watchers and trigger content
	-- recreation / kill_active / recover.
	vim.api.nvim_create_augroup("poppy_ui", { clear = true })

	for _, win in ipairs({ state.wrapper_win, state.content_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local has_running_popies = not poppy_state.is_empty()
	local buffers = { state.content_buf }
	if not has_running_popies then
		table.insert(buffers, state.wrapper_buf)
		table.insert(buffers, panels.get_hints_buf())
		table.insert(buffers, panels.get_list_buf())
		local hbuf = panels.get_header_buf()
		if hbuf then
			table.insert(buffers, hbuf)
		end
	end
	if hint_buf and vim.api.nvim_buf_is_valid(hint_buf) then
		table.insert(buffers, hint_buf)
	end

	for _, buf in ipairs(buffers) do
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	state.wrapper_win = nil
	state.content_win = nil
	state.content_buf = nil
	state.is_landing = false
	state.menu_focused = false
end

local hard_cleanup = function()
	for _, p_state in poppy_state.runtime_iter() do
		if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
			vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
		end
	end
	poppy_state.clear()
	cleanup()
end

M.close = function()
	hard_cleanup()
end

M.toggle = function()
	if util.is_open(state.wrapper_win) then
		cleanup()
	else
		M.open()
	end
end

M.open = function(poppy_name)
	if util.is_open(state.wrapper_win) then
		if poppy_name then
			switching.switch_by_name(poppy_name)
		end
		return state.wrapper_win
	end

	poppy_state.ensure_entries_loaded()

	if state.opts.exclusive_float then
		events.setup_exclusive_float()
	end

	local last_poppy = state.current_poppy_name

	if poppy_name or (last_poppy and poppy_state.runtime_get(last_poppy)) then
		local mw = (state.opts and state.opts.menu_width) or 25
		local hdr = layout.get_header_height(state.opts)
		local win, wbuf
		if state.wrapper_buf and vim.api.nvim_buf_is_valid(state.wrapper_buf) then
			wbuf = state.wrapper_buf
			win = wrapper.recreate(wbuf, state.opts)
		else
			win, wbuf = wrapper.create(state.opts)
			state.wrapper_buf = wbuf
		end
		local c_win, c_buf = content.create(win, mw)
		panels.create(win, mw, 4, hdr)
		_watch_content_window(c_win, mw)

		state.wrapper_win = win
		state.content_win = c_win
		state.content_buf = c_buf
		state.current_poppy_name = nil
		state.is_landing = false

		if poppy_name then
			switching.switch_by_name(poppy_name)
		else
			switching.switch_by_name(last_poppy)
		end

		input.setup_menu(panels.get_list_buf(), state.opts and state.opts.keys)
	else
		local landing_width = poppy_state.landing_view_width()
		local win, wbuf
		if state.wrapper_buf and vim.api.nvim_buf_is_valid(state.wrapper_buf) then
			wbuf = state.wrapper_buf
			win = wrapper.recreate(wbuf, state.opts, landing_width)
		else
			win, wbuf = wrapper.create(state.opts, landing_width)
			state.wrapper_buf = wbuf
		end
		panels.create_landing(win, layout.get_header_height(state.opts))
		state.wrapper_win = win
		state.content_win = nil
		state.content_buf = nil
		state.current_poppy_name = nil
		state.is_landing = true

		local list_buf = panels.get_list_buf()
		vim.bo[list_buf].filetype = "poppy_menu"
		input.setup_menu(list_buf, state.opts and state.opts.keys)
		local list_win = panels.get_list_win()
		if list_win and vim.api.nvim_win_is_valid(list_win) then
			vim.api.nvim_set_current_win(list_win)
		end
	end

	switching.refresh_panels(poppy_state.entries())

	return state.wrapper_win
end

return M
