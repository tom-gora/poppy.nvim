local M = {}

local state = require("poppy.core.session.state")
local panels = require("poppy.core.ui.panels")
local content = require("poppy.core.ui.content")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

local list_panel_update

local focus = function(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		return true
	end
	return false
end

local menu_width = function()
	return state.windows.opts and state.windows.opts.menu_width or 25
end

local cursor_to_poppy_index = function()
	local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
	if not ok then
		return nil
	end
	local idx = cursor[1]
	local item = state.poppies[idx]
	if type(item) == "table" and item.name then
		return idx
	end
	return nil
end

-- Resolve a name-or-index into {name, runtime}. runtime is nil if the
-- poppy has never been opened. Returns nil for invalid index or nil name.
local resolve = function(name_or_index)
	if type(name_or_index) == "number" then
		local item = state.poppies[name_or_index]
		if not item or not item.name then
			return nil
		end
		return { name = item.name, runtime = state.poppies[item.name] }
	end
	if not name_or_index then
		return nil
	end
	return { name = name_or_index, runtime = state.poppies[name_or_index] }
end

-- Mark a poppy as no-longer-visible: drop active, set hidden, drop the
-- window reference. Idempotent. Used in transitions (switching) and
-- teardown (cleanup).
local hide_poppy = function(name)
	local runtime = state.poppies[name]
	if not runtime then
		return
	end
	runtime.active = false
	runtime.hidden = true
	runtime.win = nil
end

-- Augroup for per-window WinClosed watchers; cleared on cleanup/recover.
vim.api.nvim_create_augroup("poppy_ui", { clear = false })

local watch_content_window
watch_content_window = function(win_id, menu_width)
	if not win_id then
		return
	end
	local menu_width = menu_width or 25
	---@type vim.api.keyset.create_autocmd
	local win_closed_autocmd = {
		pattern = tostring(win_id),
		once = true,
		group = "poppy_ui",
		callback = function()
			if not shared.session_is_open() then
				return
			end
			local c_win, c_buf = content.create(state.windows.wrapper_win, menu_width)
			state.windows.content_win = c_win
			state.windows.content_buf = c_buf
			watch_content_window(c_win, menu_width)
			if state.windows.current_poppy_name then
				M.kill_active()
			else
				M.recover()
			end
		end,
	}
	vim.api.nvim_create_autocmd("WinClosed", win_closed_autocmd)
end

M.transition_to_content = function()
	if state.windows.is_landing then
		panels.destroy()
		local wc = vim.api.nvim_win_get_config(state.windows.wrapper_win)
		local full_width = layout.compute_wrapper_dimensions(state.windows.opts, vim.o.columns, vim.o.lines)
		vim.api.nvim_win_set_config(state.windows.wrapper_win, {
			relative = wc.relative,
			width = full_width,
			height = wc.height,
			col = math.floor((vim.o.columns - full_width) / 2),
			row = wc.row,
		})
	end
	local panel_width = state.windows.opts and state.windows.opts.menu_width or 25
	local header_height = layout.get_header_height(state.windows.opts)
	local c_win, c_buf = content.create(state.windows.wrapper_win, panel_width)
	panels.create(state.windows.wrapper_win, panel_width, 4, header_height)
	watch_content_window(c_win, panel_width)
	state.windows.content_win = c_win
	state.windows.content_buf = c_buf
	state.windows.is_landing = false
end

M.enter_landing = function()
	panels.create_landing(state.windows.wrapper_win, layout.get_header_height(state.windows.opts))
	state.windows.content_win = nil
	state.windows.content_buf = nil
	state.windows.is_landing = true
	local list_buf = panels.get_list_buf()
	vim.bo[list_buf].filetype = "poppy_menu"
	local list_win = panels.get_list_win()
	if list_win and vim.api.nvim_win_is_valid(list_win) then
		vim.api.nvim_set_current_win(list_win)
	end
	require("poppy.core.session.menu").setup_list_keys(list_buf)
end

-- Refresh sidebar + hints after every pop-changing action.
M.refresh_panels = function(sorted_poppies)
	if state.windows.is_landing and state.windows.wrapper_win then
		local menu_width = vim.api.nvim_win_get_width(state.windows.wrapper_win)
		list_panel_update(sorted_poppies, menu_width)
		require("poppy.core.ui.hints_panel").update(
			panels.get_hints_buf(),
			shared.keys(),
			menu_width,
			"landing",
			"landing"
		)
		return
	end
	if state.windows.hidden then
		return
	end
	local panel_width = menu_width()
	list_panel_update(sorted_poppies, panel_width)
	local mode = state.windows.menu_focused and "active_focused" or "active_menu"
	require("poppy.core.ui.hints_panel").update(panels.get_hints_buf(), shared.keys(), panel_width, "menu", mode)
end

list_panel_update = function(sorted_poppies, menu_width)
	local list_panel = require("poppy.core.ui.list_panel")
	list_panel.update(
		panels.get_list_buf(),
		sorted_poppies,
		state.poppies,
		state.windows.opts and state.windows.opts.icons,
		menu_width
	)
end

M.switch_by_name = function(poppy_name)
	if
		not shared.session_is_open()
		or not state.windows.opts
		or not state.windows.opts.poppies_resolved
		or not state.windows.opts.poppies_resolved[poppy_name]
	then
		vim.notify(
			string.format("Poppy: unknown poppy '%s'", tostring(poppy_name)),
			vim.log.levels.WARN
		)
		return
	end

	if state.windows.current_poppy_name then
		hide_poppy(state.windows.current_poppy_name)
	end

	if state.windows.is_landing then
		M.transition_to_content()
	end

	local poppy_opts = state.windows.opts.poppies_resolved[poppy_name]
	if state.windows.current_poppy_name and state.windows.current_poppy_name ~= poppy_name then
		state.windows.last_poppy_name = state.windows.current_poppy_name
	end
	state.windows.current_poppy_name = poppy_name

	local mode = poppy_opts.mode
	require("poppy.core.modes." .. mode).run(poppy_name, state.windows.opts, state.windows.content_win)

	require("poppy.core.session.menu").setup_content_keys(vim.api.nvim_win_get_buf(state.windows.content_win))

	state.windows.menu_focused = false
	if state.windows.opts.menu_autohide then
		panels.hide_menu(state.windows.content_win)
		shared.show_menu_hint()
	else
		panels.unfocus_menu()
	end

	M.refresh_panels(state.poppies)
	if
		focus(state.windows.content_win)
		and vim.bo[vim.api.nvim_win_get_buf(state.windows.content_win)].buftype == "terminal"
	then
		vim.cmd("startinsert")
	end
end

M.switch_by_index = function(index)
	local resolved = resolve(index)
	if resolved then
		M.switch_by_name(resolved.name)
	end
end

M.switch_by_cursor = function()
	local idx = cursor_to_poppy_index()
	if idx then
		M.switch_by_index(idx)
	end
end

M.recover = function()
	state.windows.current_poppy_name = nil
	vim.schedule(function()
		if not shared.session_is_open() or state.windows.is_landing or state.windows.current_poppy_name then
			return
		end

		local fallback_name = nil
		if state.windows.last_poppy_name then
			local runtime = state.poppies[state.windows.last_poppy_name]
			if runtime and runtime.hidden then
				fallback_name = state.windows.last_poppy_name
			end
		end
		if not fallback_name then
			for name, runtime in pairs(state.poppies) do
				if runtime.hidden then
					fallback_name = name
					break
				end
			end
		end

		if fallback_name then
			M.switch_by_name(fallback_name)
		else
			panels.destroy()
			shared.close_menu_hint()

			vim.api.nvim_create_augroup("poppy_ui", { clear = true })

			if state.windows.content_win and vim.api.nvim_win_is_valid(state.windows.content_win) then
				vim.api.nvim_win_close(state.windows.content_win, true)
			end

			local landing_width = layout.compute_landing_view_width(state.windows.opts, state.poppies)
			local wc = vim.api.nvim_win_get_config(state.windows.wrapper_win)
			vim.api.nvim_win_set_config(state.windows.wrapper_win, {
				relative = wc.relative,
				width = landing_width,
				height = wc.height,
				col = math.floor((vim.o.columns - landing_width) / 2),
				row = wc.row,
			})

			M.enter_landing()

			M.refresh_panels(state.poppies)
		end
	end)
end

M.kill_active = function()
	if not state.windows.current_poppy_name then
		return
	end
	local target = state.windows.current_poppy_name
	local p_state = state.poppies[target]
	local target_bufnr = p_state and p_state.bufnr

	-- Drop the target buffer up-front so any callback recover() schedules
	-- (via vim.schedule) lands on a clean state without referencing a
	-- half-dead window's buffer.
	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	state.poppies[target] = nil
	state.windows.current_poppy_name = nil
	M.recover()

	focus(state.windows.content_win)
end

local _kill = function(resolved)
	if not resolved then
		return
	end
	if resolved.name == state.windows.current_poppy_name then
		return M.kill_active()
	end
	if not resolved.runtime then
		return
	end

	local target_bufnr = resolved.runtime.bufnr
	state.poppies[resolved.name] = nil

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if shared.session_is_open() and not state.windows.is_landing then
		M.refresh_panels(state.poppies)
	end
end

M.kill_by_name = function(name)
	return _kill(resolve(name))
end

M.kill_by_index = function(index)
	return _kill(resolve(index))
end

M.kill_by_cursor = function()
	local idx = cursor_to_poppy_index()
	if idx then
		M.kill_by_index(idx)
	end
end

return M
