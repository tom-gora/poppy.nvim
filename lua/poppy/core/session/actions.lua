local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
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
	return state.opts and state.opts.menu_width or 25
end

local cursor_to_poppy_index = function()
	local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
	if not ok then
		return nil
	end
	local idx = cursor[1]
	local item = poppy_state.poppies[idx]
	if type(item) == "table" and item.name then
		return idx
	end
	return nil
end

-- Resolve a name-or-index into {name, runtime}. runtime is nil if the
-- poppy has never been opened. Returns nil for invalid index or nil name.
local resolve = function(name_or_index)
	if type(name_or_index) == "number" then
		local item = poppy_state.poppies[name_or_index]
		if not item or not item.name then
			return nil
		end
		return { name = item.name, runtime = poppy_state.poppies[item.name] }
	end
	if not name_or_index then
		return nil
	end
	return { name = name_or_index, runtime = poppy_state.poppies[name_or_index] }
end

-- Augroup for per-window WinClosed watchers; cleared on cleanup/recover.
vim.api.nvim_create_augroup("poppy_ui", { clear = false })

local watch_content_window
watch_content_window = function(win_id, menu_width)
	if not win_id then
		return
	end
	local menu_width = menu_width or 25
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = "poppy_ui",
		callback = function()
			if not shared.session_is_open() then
				return
			end
			local c_win, c_buf = content.create(state.wrapper_win, menu_width)
			state.content_win = c_win
			state.content_buf = c_buf
			watch_content_window(c_win, menu_width)
			if state.current_poppy_name then
				M.kill_active()
			else
				M.recover()
			end
		end,
	})
end

M.transition_to_content = function()
	if state.is_landing then
		panels.destroy()
		local wc = vim.api.nvim_win_get_config(state.wrapper_win)
		local full_width = layout.compute_wrapper_dimensions(state.opts, vim.o.columns, vim.o.lines)
		vim.api.nvim_win_set_config(state.wrapper_win, {
			relative = wc.relative,
			width = full_width,
			height = wc.height,
			col = math.floor((vim.o.columns - full_width) / 2),
			row = wc.row,
		})
	end
	local mw = state.opts and state.opts.menu_width or 25
	local hdr = layout.get_header_height(state.opts)
	local c_win, c_buf = content.create(state.wrapper_win, mw)
	panels.create(state.wrapper_win, mw, 4, hdr)
	watch_content_window(c_win, mw)
	state.content_win = c_win
	state.content_buf = c_buf
	state.is_landing = false

	require("poppy.core.session.menu").setup_list_keys(panels.get_list_buf())
end

M.enter_landing = function()
	panels.create_landing(state.wrapper_win, layout.get_header_height(state.opts))
	state.content_win = nil
	state.content_buf = nil
	state.is_landing = true
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
	if state.is_landing and state.wrapper_win then
		local menu_width = vim.api.nvim_win_get_width(state.wrapper_win)
		list_panel_update(sorted_poppies, menu_width)
		require("poppy.core.ui.hints_panel").update(
			panels.get_hints_buf(),
			shared.keys(),
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
	local mw = menu_width()
	list_panel_update(sorted_poppies, mw)
	local mode = state.menu_focused and "active_focused" or "active_menu"
	require("poppy.core.ui.hints_panel").update(
		panels.get_hints_buf(),
		shared.keys(),
		#sorted_poppies,
		mw,
		"menu",
		mode
	)
end

list_panel_update = function(sorted_poppies, menu_width)
	local list_panel = require("poppy.core.ui.list_panel")
	list_panel.update(
		panels.get_list_buf(),
		sorted_poppies,
		poppy_state.poppies,
		state.opts and state.opts.icons,
		menu_width
	)
end

M.switch_by_name = function(poppy_name)
	if
		not shared.session_is_open()
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
		M.transition_to_content()
	end

	local poppy_opts = state.opts.poppies_resolved[poppy_name]
	state.current_poppy_name = poppy_name

	local mode = poppy_opts.mode
	require("poppy.core.modes." .. mode).run(poppy_name, state.opts, state.content_win)

	require("poppy.core.session.menu").setup_content_keys(vim.api.nvim_win_get_buf(state.content_win))

	state.menu_focused = false
	if state.opts.menu_autohide then
		panels.hide_menu(state.content_win)
		shared.show_menu_hint()
	else
		panels.unfocus_menu()
	end

	M.refresh_panels(poppy_state.poppies)
	if focus(state.content_win) and vim.bo[vim.api.nvim_win_get_buf(state.content_win)].buftype == "terminal" then
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
	state.current_poppy_name = nil
	vim.schedule(function()
		if not shared.session_is_open() or state.is_landing or state.current_poppy_name then
			return
		end

		local fallback_name = nil
		for name, ps in pairs(poppy_state.poppies) do
			if ps.hidden then
				fallback_name = name
				break
			end
		end

		if fallback_name then
			M.switch_by_name(fallback_name)
		else
			panels.destroy()
			shared.close_menu_hint()

			vim.api.nvim_create_augroup("poppy_ui", { clear = true })

			if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
				vim.api.nvim_win_close(state.content_win, true)
			end

			local landing_width = layout.compute_landing_view_width(state.opts, poppy_state.poppies)
			local wc = vim.api.nvim_win_get_config(state.wrapper_win)
			vim.api.nvim_win_set_config(state.wrapper_win, {
				relative = wc.relative,
				width = landing_width,
				height = wc.height,
				col = math.floor((vim.o.columns - landing_width) / 2),
				row = wc.row,
			})

			M.enter_landing()

			M.refresh_panels(poppy_state.poppies)
		end
	end)
end

M.kill_active = function()
	if not state.current_poppy_name then
		return
	end
	local target = state.current_poppy_name
	local p_state = poppy_state.poppies[target]
	local target_bufnr = p_state and p_state.bufnr

	-- Drop the target buffer up-front so any callback recover() schedules
	-- (via vim.schedule) lands on a clean state without referencing a
	-- half-dead window's buffer.
	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	poppy_state.poppies[target] = nil
	state.current_poppy_name = nil
	M.recover()

	focus(state.content_win)
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
	poppy_state.poppies[resolved.name] = nil

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if shared.session_is_open() and not state.is_landing then
		M.refresh_panels(poppy_state.poppies)
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