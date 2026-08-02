local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local panels = require("poppy.core.ui.panels")
local wrapper = require("poppy.core.ui.wrapper")
local input = require("poppy.core.input")
local shared = require("poppy.core.shared")
local actions = require("poppy.core.session.actions")
local events = require("poppy.core.session.events")

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
	shared.close_menu_hint()

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
	if shared.session_is_open() then
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
	if shared.session_is_open() then
		if poppy_name then
			actions.switch_by_name(poppy_name)
		end
		return state.wrapper_win
	end

	poppy_state.ensure_entries_loaded()
	if state.opts.exclusive_float then
		events.setup_exclusive_float()
	end

	local last_poppy = state.current_poppy_name
	local has_content = poppy_name or (last_poppy and poppy_state.runtime_get(last_poppy))
	local should_land = not has_content
	local landing_width = should_land and poppy_state.landing_view_width() or nil

	local win = open_wrapper(landing_width)
	state.wrapper_win = win
	state.current_poppy_name = nil
	state.is_landing = should_land

	if has_content then
		shared.transition_to_content()
		actions.switch_by_name(poppy_name or last_poppy)
	else
		shared.enter_landing()
	end

	input.setup_menu(panels.get_list_buf(), shared.keys())
	actions.refresh_panels(poppy_state.entries())
	return state.wrapper_win
end

return M
