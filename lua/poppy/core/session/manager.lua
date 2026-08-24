local M = {}

local state = require("poppy.core.session.state")
local panels = require("poppy.core.ui.panels")
local wrapper = require("poppy.core.ui.wrapper")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local actions = require("poppy.core.session.actions")

-- Mark a poppy as no-longer-visible: drop active, set hidden, drop the
-- window reference. Idempotent. Lives in shared.lua so manager and
-- actions both use the same definition without duplicating.

-- Soft close (default): drops UI but keeps poppies alive for next open.
-- Hard close (drop_poppies=true): also kills every live poppy buffer.
local clear_poppies = function()
	for _, entry in ipairs(state.poppies) do
		local rt = entry.runtime_state
		if rt and rt.bufnr and vim.api.nvim_buf_is_valid(rt.bufnr) then
			vim.api.nvim_buf_delete(rt.bufnr, { force = true })
		end
	end
	state.poppies = {}
end

local cleanup = function(drop_poppies)
	if drop_poppies then
		clear_poppies()
	end

	if state.windows.current_poppy_name then
		shared.hide_poppy(state.windows.current_poppy_name)
	end

	local hint_buf = state.windows.menu_hint_buf
	shared.close_menu_hint()

	panels.unmount()

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
end

local setup_exclusive_float = function()
	---@type vim.api.keyset.create_autocmd
	local win_enter_autocmd = {
		group = "poppy_group",
		once = true,
		callback = function()
			vim.schedule(function()
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if not vim.api.nvim_win_is_valid(w) or shared.is_poppy_window(w) then
						goto continue
					end
					---@diagnostic disable: unnecessary-if
					if vim.api.nvim_win_get_config(w).relative ~= "" then
						vim.api.nvim_win_close(w, true)
					end
					::continue::
				end
			end)
		end,
	}
	vim.api.nvim_create_autocmd("WinEnter", win_enter_autocmd)
end

M.close = function()
	if not shared.ensure_setup() then return end
	cleanup(true)
end

M.toggle = function()
	if not shared.ensure_setup() then return end
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
	if not shared.ensure_setup() then return nil end
	if shared.session_is_open() then
		if poppy_name then
			actions.switch_by_name(poppy_name)
		end
		return state.windows.wrapper_win
	end

	if shared.opts_field("exclusive_float") then
		setup_exclusive_float()
	end

	local last_poppy = state.windows.current_poppy_name
	local has_content = poppy_name or (last_poppy and state.poppy(last_poppy) and state.poppy(last_poppy).runtime_state)
	local should_land = not has_content
	local landing_width = should_land and layout.compute_landing_view_width(state.windows.opts, state.poppies) or nil

	local win = open_wrapper(landing_width)
	state.windows.wrapper_win = win
	state.set_current_poppy_name(nil)
	state.windows.is_landing = should_land

	if has_content then
		actions.transition_to_content()
		actions.switch_by_name(poppy_name or last_poppy)
	else
		actions.enter_landing()
	end

	actions.refresh_panels()
	return state.windows.wrapper_win
end

return M
