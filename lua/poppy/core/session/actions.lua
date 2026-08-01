local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local panels = require("poppy.core.ui.panels")
local hints_panel = require("poppy.core.ui.hints_panel")
local content = require("poppy.core.ui.content")
local input = require("poppy.core.input")
local layout = require("poppy.core.ui.layout")
local util = require("poppy.core.util")

local list_panel_update

-- Refresh sidebar + hints after every pop-changing action.
M.refresh_panels = function(sorted_poppies)
	if state.is_landing and state.wrapper_win then
		local menu_width = vim.api.nvim_win_get_width(state.wrapper_win)
		list_panel_update(sorted_poppies, menu_width)
		hints_panel.update(
			panels.get_hints_buf(),
			util.keys(),
			#sorted_poppies,
			menu_width,
			"landing",
			"landing"
		)
		return
	end
	if panels.is_hidden() then
		return
	end
	local menu_width = util.menu_width()
	list_panel_update(sorted_poppies, menu_width)
	local mode = state.menu_focused and "active_focused" or "active_menu"
	hints_panel.update(panels.get_hints_buf(), util.keys(), #sorted_poppies, menu_width, "menu", mode)
end

list_panel_update = function(sorted_poppies, menu_width)
	local list_panel = require("poppy.core.ui.list_panel")
	list_panel.update(panels.get_list_buf(), sorted_poppies, poppy_state.entries(), state.opts and state.opts.icons, menu_width)
end

local focus_list_with_cursor = function()
	local list_win = panels.get_list_win()
	if not util.focus(list_win) then
		return
	end
	if not state.current_poppy_name then
		return
	end
	for i = 1, poppy_state.array_length() do
		local entry = poppy_state.entries()[i]
		if type(entry) == "table" and entry.name == state.current_poppy_name then
			pcall(vim.api.nvim_win_set_cursor, list_win, { i, 0 })
			break
		end
	end
end
M.focus_list_with_cursor = focus_list_with_cursor

local show_menu_hint_or_close = function()
	util.close_menu_hint()
	if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
		state.menu_hint_win, state.menu_hint_buf =
			hints_panel.create_bottom_right(state.content_win, util.keys())
	end
end

M.switch_by_name = function(poppy_name)
	if
		not util.session_is_open()
		or not state.opts
		or not state.opts.poppies_resolved
		or not state.opts.poppies_resolved[poppy_name]
	then
		return
	end

	if state.current_poppy_name then
		poppy_state.hide(state.current_poppy_name)
	end

	if state.is_landing then
		util.transition_to_content()
		input.setup_menu(panels.get_list_buf(), util.keys())
	end

	local poppy_opts = state.opts.poppies_resolved[poppy_name]
	state.current_poppy_name = poppy_name

	local mode = poppy_opts.mode
	require("poppy.core.modes." .. mode).run(poppy_name, state.opts, state.content_win)

	input.setup_content(vim.api.nvim_win_get_buf(state.content_win), util.keys())

	state.menu_focused = false
	if state.opts.menu_autohide then
		panels.hide_menu(state.content_win)
		show_menu_hint_or_close()
	else
		panels.unfocus_menu()
	end

	M.refresh_panels(poppy_state.entries())
	if util.focus(state.content_win) and vim.bo[vim.api.nvim_win_get_buf(state.content_win)].buftype == "terminal" then
		vim.cmd("startinsert")
	end
end

M.switch_by_index = function(index)
	local resolved = poppy_state.resolve(index)
	if resolved then
		M.switch_by_name(resolved.name)
	end
end

M.switch_by_cursor = function()
	local idx = util.cursor_to_poppy_index(poppy_state.entries())
	if idx then
		M.switch_by_index(idx)
	end
end

M.toggle_menu = function()
	if state.is_landing or not util.session_is_open() then
		return
	end

	if panels.is_hidden() then
		util.close_menu_hint()
		panels.show_menu(state.content_win)
		state.menu_focused = true
		focus_list_with_cursor()
		M.refresh_panels(poppy_state.entries())
	else
		state.menu_focused = not state.menu_focused
		if state.menu_focused then
			panels.focus_menu()
			focus_list_with_cursor()
		else
			panels.unfocus_menu()
			util.focus(state.content_win)
		end
		M.refresh_panels(poppy_state.entries())
	end
end

M.exit_menu = function()
	if not state.menu_focused or state.is_landing then
		return
	end
	state.menu_focused = false
	if state.opts and state.opts.menu_autohide then
		panels.hide_menu(state.content_win)
		show_menu_hint_or_close()
	else
		panels.unfocus_menu()
	end
	M.refresh_panels(poppy_state.entries())
	if util.focus(state.content_win) then
		local cbuf = vim.api.nvim_win_get_buf(state.content_win)
		if vim.bo[cbuf].buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end
end

M.recover = function()
	state.current_poppy_name = nil
	vim.schedule(function()
		if not util.session_is_open() or state.is_landing or state.current_poppy_name then
			return
		end

		local fallback_name = nil
		for name, ps in poppy_state.iter() do
			if ps.hidden then
				fallback_name = name
				break
			end
		end

		if fallback_name then
			M.switch_by_name(fallback_name)
		else
			panels.destroy()
			util.close_menu_hint()

			vim.api.nvim_create_augroup("poppy_ui", { clear = true })

			if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
				vim.api.nvim_win_close(state.content_win, true)
			end

			local landing_width = poppy_state.landing_view_width()
			local wc = vim.api.nvim_win_get_config(state.wrapper_win)
			vim.api.nvim_win_set_config(state.wrapper_win, {
				relative = wc.relative,
				width = landing_width,
				height = wc.height,
				col = math.floor((vim.o.columns - landing_width) / 2),
				row = wc.row,
			})

			util.enter_landing()

			input.setup_menu(panels.get_list_buf(), util.keys())
			M.refresh_panels(poppy_state.entries())
		end
	end)
end

M.kill_active = function()
	if not state.current_poppy_name then
		return
	end
	local target = state.current_poppy_name
	local p_state = poppy_state.runtime_get(target)
	local target_bufnr = p_state and p_state.bufnr

	-- Drop the target buffer up-front so any callback recover() schedules
	-- (via vim.schedule) lands on a clean state without referencing a
	-- half-dead window's buffer.
	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	poppy_state.runtime_remove(target)
	state.current_poppy_name = nil
	M.recover()

	util.focus(state.content_win)
end

local _kill = function(resolved)
	if not resolved then
		return
	end
	if resolved.name == state.current_poppy_name then
		return M.kill_active()
	end
	if not resolved.runtime then
		return
	end

	local target_bufnr = resolved.runtime.bufnr
	poppy_state.runtime_remove(resolved.name)

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if util.session_is_open() and not state.is_landing then
		M.refresh_panels(poppy_state.entries())
	end
end

M.kill_by_name = function(name)
	return _kill(poppy_state.resolve(name))
end

M.kill_by_index = function(index)
	return _kill(poppy_state.resolve(index))
end

M.kill_by_cursor = function()
	local idx = util.cursor_to_poppy_index(poppy_state.entries())
	if idx then
		M.kill_by_index(idx)
	end
end

return M