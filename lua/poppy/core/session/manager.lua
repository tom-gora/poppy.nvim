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

-- Augroup for per-window WinClosed watchers; cleared on cleanup/recover.
vim.api.nvim_create_augroup("poppy_ui", { clear = false })

M.watch_content_window = function(win_id, menu_width)
	if not win_id then
		return
	end
	local menu_width = menu_width or 25
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = "poppy_ui",
		callback = function()
			if not util.session_is_open() then
				return
			end
			local c_win, c_buf = content.create(state.wrapper_win, menu_width)
			state.content_win = c_win
			state.content_buf = c_buf
			M.watch_content_window(c_win, menu_width)
			if state.current_poppy_name then
				killing.kill_active()
			else
				killing.recover()
			end
		end,
	})
end

-- Soft close (default): drops UI but keeps poppies alive for next open.
-- Hard close (drop_poppies=true): also kills every live poppy buffer.
local cleanup = function(drop_poppies)
	if drop_poppies then
		for _, p_state in poppy_state.iter() do
			if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
				vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
			end
		end
		poppy_state.clear()
	end

	if state.current_poppy_name then
		poppy_state.hide(state.current_poppy_name)
	end

	local hint_buf = state.menu_hint_buf
	util.close_menu_hint()

	panels.destroy()

	-- Wipe WinClosed watchers before closing windows to avoid re-fire.
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

M.close = function()
	cleanup(true)
end

M.toggle = function()
	if util.session_is_open() then
		cleanup()
	else
		M.open()
	end
end

local open_wrapper = function(width_override)
	if state.wrapper_buf and vim.api.nvim_buf_is_valid(state.wrapper_buf) then
		return wrapper.recreate(state.wrapper_buf, state.opts, width_override)
	end
	local win, wbuf = wrapper.create(state.opts, width_override)
	state.wrapper_buf = wbuf
	return win
end

M.open = function(poppy_name)
	if util.session_is_open() then
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
	local has_content = poppy_name or (last_poppy and poppy_state.runtime_get(last_poppy))
	local menu_width = util.menu_width()
	local hdr = layout.get_header_height(state.opts)
	local should_land = not has_content
	local landing_width = should_land and poppy_state.landing_view_width() or nil

	local win = open_wrapper(landing_width)
	state.wrapper_win = win
	state.current_poppy_name = nil
	state.is_landing = should_land

	if has_content then
		local c_win, c_buf = content.create(win, menu_width)
		panels.create(win, menu_width, 4, hdr)
		M.watch_content_window(c_win, menu_width)
		state.content_win = c_win
		state.content_buf = c_buf
		switching.switch_by_name(poppy_name or last_poppy)
	else
		panels.create_landing(win, hdr)
		state.content_win = nil
		state.content_buf = nil
		local list_buf = panels.get_list_buf()
		vim.bo[list_buf].filetype = "poppy_menu"
		local list_win = panels.get_list_win()
		if list_win and vim.api.nvim_win_is_valid(list_win) then
			vim.api.nvim_set_current_win(list_win)
		end
	end

	input.setup_menu(panels.get_list_buf(), util.keys())
	switching.refresh_panels(poppy_state.entries())
	return state.wrapper_win
end

return M
