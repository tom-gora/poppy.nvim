local M = {}

local state = require("poppy.core.session.state")
local panels = require("poppy.core.ui.panels")
local wrapper = require("poppy.core.ui.wrapper")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local actions = require("poppy.core.session.actions")

-- Mark a poppy as no-longer-visible: drop active, set hidden, drop the
-- window reference. Idempotent. Same logic as actions.hide_poppy —
-- duplicated here so manager doesn't need to lazy-require actions.
local hide_poppy = function(name)
	local runtime = state.poppies[name]
	if not runtime then
		return
	end
	runtime.active = false
	runtime.hidden = true
	runtime.win = nil
end

-- Soft close (default): drops UI but keeps poppies alive for next open.
-- Hard close (drop_poppies=true): also kills every live poppy buffer.
local clear_poppies = function()
	for _, p_state in pairs(state.poppies) do
		if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
			vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
		end
	end
	for k in pairs(state.poppies) do
		state.poppies[k] = nil
	end
end

local cleanup = function(drop_poppies)
	if drop_poppies then
		clear_poppies()
	end

	if state.windows.current_poppy_name then
		hide_poppy(state.windows.current_poppy_name)
	end

	local hint_buf = state.windows.menu_hint_buf
	shared.close_menu_hint()

	panels.destroy()

	-- Wipe WinClosed watchers before closing windows to avoid re-fire.
	vim.api.nvim_create_augroup("poppy_ui", { clear = true })

	for _, win in ipairs({ state.windows.wrapper_win, state.windows.content_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local has_running_popies = next(state.poppies) ~= nil
	local buffers = { state.windows.content_buf }
	if not has_running_popies then
		table.insert(buffers, state.windows.wrapper_buf)
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

	state.windows.wrapper_win = nil
	state.windows.content_win = nil
	state.windows.content_buf = nil
	state.windows.is_landing = false
	state.windows.menu_focused = false
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
	if state.windows.wrapper_buf and vim.api.nvim_buf_is_valid(state.windows.wrapper_buf) then
		return wrapper.recreate(state.windows.wrapper_buf, state.windows.opts, width_override)
	end
	local win, wbuf = wrapper.create(state.windows.opts, width_override)
	state.windows.wrapper_buf = wbuf
	return win
end

M.open = function(poppy_name)
	if shared.session_is_open() then
		if poppy_name then
			actions.switch_by_name(poppy_name)
		end
		return state.windows.wrapper_win
	end

	-- Lazy first-time population of the registry from config if the user
	-- reopens without going through the public init entry.
	if #state.poppies == 0 and state.windows.opts and state.windows.opts.poppies and next(state.windows.opts.poppies) then
		for i, v in ipairs(shared.get_sorted_poppies(state.windows.opts)) do
			state.poppies[i] = v
		end
	end
	if state.windows.opts.exclusive_float then
		require("poppy.core.session.setup").setup_exclusive_float()
	end

	local last_poppy = state.windows.current_poppy_name
	local has_content = poppy_name or (last_poppy and state.poppies[last_poppy])
	local should_land = not has_content
	local landing_width = should_land and layout.compute_landing_view_width(state.windows.opts, state.poppies) or nil

	local win = open_wrapper(landing_width)
	state.windows.wrapper_win = win
	state.windows.current_poppy_name = nil
	state.windows.is_landing = should_land

	if has_content then
		actions.transition_to_content()
		actions.switch_by_name(poppy_name or last_poppy)
	else
		actions.enter_landing()
	end

	actions.refresh_panels(state.poppies)
	return state.windows.wrapper_win
end

return M