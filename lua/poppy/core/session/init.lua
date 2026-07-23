local M = {}

local wrapper = require("poppy.core.ui.wrapper")
local panels = require("poppy.core.ui.panels")
local hints_panel = require("poppy.core.ui.hints_panel")
local list_panel = require("poppy.core.ui.list_panel")
local header_panel = require("poppy.core.ui.header_panel")
local content = require("poppy.core.ui.content")
local input = require("poppy.core.input")
local util = require("poppy.core.util")
local geometry = require("poppy.core.ui.geometry")

local function reset_state()
	return {
		wrapper_win = nil,
		wrapper_buf = nil,
		content_win = nil,
		content_buf = nil,
		current_poppy_name = nil,
		is_landing = false,
		menu_focused = false,
		hints_win = nil,
		hints_buf = nil,
		list_win = nil,
		list_buf = nil,
		header_win = nil,
		header_buf = nil,
		mw = 25,
		hidden = false,
		autohidden = false,
		hint_height = 1,
		header_height = 0,
		autohide_hint_win = nil,
		autohide_hint_buf = nil,
		poppies = {},
	}
end

local state = reset_state()
M.poppies = state.poppies

local function init_state()
	local preserved_opts = state.opts
	state = reset_state()
	state.opts = preserved_opts
	M.poppies = state.poppies
end

-- Ensure M.poppies holds the sorted list view. After init_state() (e.g. during
-- cleanup) state.poppies becomes {}, leaving the list panel empty even though
-- state.opts still has the user's poppy config. Copies sorted entries from
-- state.opts.poppies back into M.poppies's array portion when needed.
local function refresh_poppies_list()
	if #M.poppies == 0 and state.opts and state.opts.poppies and next(state.opts.poppies) then
		local new_poppies = util.get_sorted_poppies(state.opts)
		for i, v in ipairs(new_poppies) do
			M.poppies[i] = v
		end
	end
end

-- Focus the sidebar list window and land the cursor on the line of the
-- currently-active poppy (if any). Falls back to line 1 when no current
-- poppy or when the name isn't found in M.poppies's array portion.
local function focus_list_with_cursor()
	local list_win = panels.get_list_win()
	if not list_win or not vim.api.nvim_win_is_valid(list_win) then
		return
	end
	vim.api.nvim_set_current_win(list_win)
	if not state.current_poppy_name then
		return
	end
	for i = 1, #M.poppies do
		local entry = M.poppies[i]
		if type(entry) == "table" and entry.name == state.current_poppy_name then
			pcall(vim.api.nvim_win_set_cursor, list_win, { i, 0 })
			break
		end
	end
end

-- Landing width is a session-persistent derived constant.
-- Lives outside state; computed lazily and never reset.
local _landing_view_width

-- forward declarations for mutual references
local _recover
local _watch_content_window

_watch_content_window = function(win_id, menu_width)
	if not win_id then
		return
	end
	local mw = menu_width or 25
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = vim.api.nvim_create_augroup("poppy_ui", { clear = false }),
		callback = function()
			if not util.is_open(state.wrapper_win) then
				return
			end
			local c_win, c_buf = content.create(state.wrapper_win, mw)
			state.content_win = c_win
			state.content_buf = c_buf
			_watch_content_window(c_win, mw)
			if state.current_poppy_name then
				M.kill_current()
			else
				_recover()
			end
		end,
	})
end

local refresh = function(sorted_poppies)
	if state.is_landing and state.wrapper_win then
		list_panel.update(panels.get_list_buf(), sorted_poppies, M.poppies, state.opts and state.opts.icons)
		hints_panel.update(
			panels.get_hints_buf(),
			state.opts and state.opts.keys,
			#sorted_poppies,
			vim.api.nvim_win_get_width(state.wrapper_win),
			"landing",
			"landing"
		)
		return
	end
	if panels.is_autohidden() or panels.is_hidden() then
		return
	end
	local mw = (state.opts and state.opts.menu_width) or 25
	list_panel.update(panels.get_list_buf(), sorted_poppies, M.poppies, state.opts and state.opts.icons)
	local mode = state.menu_focused and "active_focused" or "active_menu"
	hints_panel.update(panels.get_hints_buf(), state.opts and state.opts.keys, #sorted_poppies, mw, "menu", mode)
end

local _active_width = function()
	local width = geometry.compute_dimensions(state.opts, vim.o.columns, vim.o.lines)
	return width
end

M.open = function(poppy_name)
	if util.is_open(state.wrapper_win) then
		if poppy_name then
			M.switch(poppy_name)
		end
		return state.wrapper_win
	end

	refresh_poppies_list()

	local last_poppy = state.current_poppy_name

	if poppy_name or (last_poppy and M.poppies[last_poppy]) then
		local mw = (state.opts and state.opts.menu_width) or 25
		local hdr = geometry.get_header_height(state.opts)
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
			M.switch(poppy_name)
		else
			M.switch(last_poppy)
		end

		input.setup_menu(panels.get_list_buf(), state.opts and state.opts.keys)
	else
		if not _landing_view_width then
			_landing_view_width = util.compute_landing_view_width(state.opts, M.poppies)
		end
		local win, wbuf
		if state.wrapper_buf and vim.api.nvim_buf_is_valid(state.wrapper_buf) then
			wbuf = state.wrapper_buf
			win = wrapper.recreate(wbuf, state.opts, _landing_view_width)
		else
			win, wbuf = wrapper.create(state.opts, _landing_view_width)
			state.wrapper_buf = wbuf
		end
		panels.create_landing(win, geometry.get_header_height(state.opts))
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

	refresh(M.poppies)

	return state.wrapper_win
end

M.toggle_menu = function()
	if state.is_landing or not util.is_open(state.wrapper_win) then
		return
	end

	if panels.is_autohidden() then
		if state.autohide_hint_win and vim.api.nvim_win_is_valid(state.autohide_hint_win) then
			vim.api.nvim_win_close(state.autohide_hint_win, true)
		end
		state.autohide_hint_win = nil
		state.autohide_hint_buf = nil
		panels.show_for_autohide(state.content_win)
		state.menu_focused = true
		focus_list_with_cursor()
		refresh(M.poppies)
	elseif panels.is_hidden() then
		panels.show(state.content_win)
		state.menu_focused = false
		refresh(M.poppies)
		if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
			vim.api.nvim_set_current_win(state.content_win)
		end
	else
		state.menu_focused = not state.menu_focused
		if state.menu_focused then
			panels.focus_menu()
			focus_list_with_cursor()
		else
			panels.unfocus_menu()
			if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
				vim.api.nvim_set_current_win(state.content_win)
			end
		end
		refresh(M.poppies)
	end
end

M.exit_menu = function()
	if not state.menu_focused or state.is_landing then
		return
	end
	state.menu_focused = false
	if state.opts and state.opts.menu_autohide then
		panels.hide_for_autohide(state.content_win)
		if state.autohide_hint_win and vim.api.nvim_win_is_valid(state.autohide_hint_win) then
			vim.api.nvim_win_close(state.autohide_hint_win, true)
		end
		state.autohide_hint_win = nil
		state.autohide_hint_buf = nil
		if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
			state.autohide_hint_win, state.autohide_hint_buf =
				hints_panel.create_bottom_right(state.content_win, state.opts.keys)
		end
	else
		panels.unfocus_menu()
	end
	refresh(M.poppies)
	if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
		vim.api.nvim_set_current_win(state.content_win)
		local cbuf = vim.api.nvim_win_get_buf(state.content_win)
		if vim.bo[cbuf].buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end
end

M.switch = function(poppy_name)
	if
		not util.is_open(state.wrapper_win)
		or not state.opts
		or not state.opts.poppies_resolved
		or not state.opts.poppies_resolved[poppy_name]
	then
		return
	end

	if state.current_poppy_name then
		local cur_state = M.poppies[state.current_poppy_name]
		if cur_state then
			cur_state.active = false
			cur_state.hidden = true
		end
	end

	if state.is_landing then
		panels.destroy()
		local mw = (state.opts and state.opts.menu_width) or 25
		local wc = vim.api.nvim_win_get_config(state.wrapper_win)
		local full_width = _active_width()
		vim.api.nvim_win_set_config(state.wrapper_win, {
			relative = wc.relative,
			width = full_width,
			height = wc.height,
			col = math.floor((vim.o.columns - full_width) / 2),
			row = wc.row,
		})
		local hdr = geometry.get_header_height(state.opts)
		local c_win, c_buf = content.create(state.wrapper_win, mw)
		panels.create(state.wrapper_win, mw, 4, hdr)
		_watch_content_window(c_win, mw)
		state.content_win = c_win
		state.content_buf = c_buf
		state.is_landing = false
		input.setup_menu(panels.get_list_buf(), state.opts and state.opts.keys)
	end

	local poppy_opts = state.opts.poppies_resolved[poppy_name]
	state.current_poppy_name = poppy_name

	local mode = poppy_opts.mode
	require("poppy.modes." .. mode).run(poppy_name, state.opts, state.content_win)

	input.setup_content(vim.api.nvim_win_get_buf(state.content_win), state.opts and state.opts.keys)

	state.menu_focused = false
	if state.opts.menu_autohide then
		panels.hide_for_autohide(state.content_win)
		if state.autohide_hint_win and vim.api.nvim_win_is_valid(state.autohide_hint_win) then
			vim.api.nvim_win_close(state.autohide_hint_win, true)
		end
		state.autohide_hint_win = nil
		state.autohide_hint_buf = nil
		if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
			state.autohide_hint_win, state.autohide_hint_buf =
				hints_panel.create_bottom_right(state.content_win, state.opts.keys)
		end
	else
		panels.unfocus_menu()
	end

	refresh(M.poppies)
	vim.api.nvim_set_current_win(state.content_win)

	if vim.bo[vim.api.nvim_win_get_buf(state.content_win)].buftype == "terminal" then
		vim.cmd("startinsert")
	end
end

M.switch_by_index = function(index)
	local item = M.poppies[index]
	if item then
		M.switch(item.name)
	end
end

M.switch_by_cursor = function()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
	if not line then
		return
	end
	local idx = line:match("%s+(%d+)%s")
	if idx then
		M.switch_by_index(tonumber(idx))
	end
end

M.kill_current = function()
	if not state.current_poppy_name then
		return
	end
	local target = state.current_poppy_name
	local p_state = M.poppies[target]
	local target_bufnr = p_state and p_state.bufnr

	M.poppies[target] = nil
	state.current_poppy_name = nil
	_recover()

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
		pcall(vim.api.nvim_set_current_win, state.content_win)
	end
end

M.kill_by_index = function(index)
	local item = M.poppies[index]
	if not item then
		return
	end
	local name = item.name

	if name == state.current_poppy_name then
		M.kill_current()
		return
	end

	local p_state = M.poppies[name]
	if not p_state then
		return
	end

	local target_bufnr = p_state.bufnr
	M.poppies[name] = nil

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if util.is_open(state.wrapper_win) and not state.is_landing then
		refresh(M.poppies)
	end
end

M.kill_by_cursor = function()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
	if not line then
		return
	end
	local idx = line:match("%s+(%d+)%s")
	if idx then
		M.kill_by_index(tonumber(idx))
	end
end

_recover = function()
	state.current_poppy_name = nil
	vim.schedule(function()
		if not util.is_open(state.wrapper_win) or state.is_landing or state.current_poppy_name then
			return
		end

		local fallback_name = nil
		for name, ps in pairs(M.poppies) do
			if ps.hidden then
				fallback_name = name
				break
			end
		end

		if fallback_name then
			M.switch(fallback_name)
		else
			panels.destroy()
			if state.autohide_hint_win then
				vim.api.nvim_win_close(state.autohide_hint_win, true)
			end
			state.autohide_hint_win = nil
			state.autohide_hint_buf = nil

			-- Wipe per-window WinClosed watchers before closing `state.content_win`;
			-- otherwise our own teardown would re-fire the watcher and try to
			-- recreate / recover state we are about to throw away.
			vim.api.nvim_create_augroup("poppy_ui", { clear = true })

			if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
				vim.api.nvim_win_close(state.content_win, true)
			end
			state.content_win = nil
			state.content_buf = nil

			if not _landing_view_width then
				_landing_view_width = util.compute_landing_view_width(state.opts, M.poppies)
			end
			local wc = vim.api.nvim_win_get_config(state.wrapper_win)
			vim.api.nvim_win_set_config(state.wrapper_win, {
				relative = wc.relative,
				width = _landing_view_width,
				height = wc.height,
				col = math.floor((vim.o.columns - _landing_view_width) / 2),
				row = wc.row,
			})
			panels.create_landing(state.wrapper_win, geometry.get_header_height(state.opts))
			state.is_landing = true

			local list_buf = panels.get_list_buf()
			vim.bo[list_buf].filetype = "poppy_menu"
			input.setup_menu(list_buf, state.opts and state.opts.keys)
			refresh(M.poppies)

			local list_win = panels.get_list_win()
			if list_win and vim.api.nvim_win_is_valid(list_win) then
				pcall(vim.api.nvim_set_current_win, list_win)
			end
		end
	end)
end

local cleanup = function()
	if state.current_poppy_name then
		local ps = M.poppies[state.current_poppy_name]
		if ps then
			ps.active = false
			ps.hidden = true
			ps.win = nil
		end
	end

	if state.autohide_hint_win and vim.api.nvim_win_is_valid(state.autohide_hint_win) then
		vim.api.nvim_win_close(state.autohide_hint_win, true)
	end
	local hint_buf = state.autohide_hint_buf
	state.autohide_hint_win = nil
	state.autohide_hint_buf = nil

	panels.destroy()

	-- Wipe per-window WinClosed watchers before closing windows; otherwise
	-- our own cleanup would re-fire the watchers and trigger content
	-- recreation / kill_current / _recover.
	vim.api.nvim_create_augroup("poppy_ui", { clear = true })

	for _, win in ipairs({ state.wrapper_win, state.content_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local has_running_popies = next(M.poppies) ~= nil
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
	for _, p_state in pairs(M.poppies) do
		if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
			vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
		end
	end
	for k in pairs(M.poppies) do
		M.poppies[k] = nil
	end
	cleanup()
end

M.close = function()
	hard_cleanup()
end

M.is_open = function()
	return util.is_open(state.wrapper_win)
end

M.toggle = function()
	if util.is_open(state.wrapper_win) then
		cleanup()
	else
		M.open()
	end
end

M.setup = function(user_opts)
	init_state()

	require("poppy.core.ui.style").setup()
	state.opts = require("poppy.config").merge(user_opts)

	local new_poppies = util.get_sorted_poppies(state.opts)
	for k in pairs(state.poppies) do
		state.poppies[k] = nil
	end
	for i, v in ipairs(new_poppies) do
		state.poppies[i] = v
	end

	input.setup_global(state.opts and state.opts.keys)

	vim.api.nvim_create_augroup("poppy_group", { clear = true })
	vim.api.nvim_create_autocmd("BufUnload", {
		group = "poppy_group",
		callback = function(ctx)
			local ok, poppy_name = pcall(vim.api.nvim_buf_get_var, ctx.buf, "poppy_popup")
			if not ok or not poppy_name or not M.poppies[poppy_name] then
				return
			end

			M.poppies[poppy_name] = nil
			if util.is_open(state.wrapper_win) and state.current_poppy_name == poppy_name then
				_recover()
			end
		end,
	})

	if state.opts and state.opts.menu_autohide then
		vim.api.nvim_create_autocmd("CursorHold", {
			group = "poppy_group",
			callback = function()
				if vim.bo.filetype == "poppy_menu" then
					M.exit_menu()
				end
			end,
		})
	end

	vim.api.nvim_create_user_command("Poppy", function(cmd_opts)
		local args = cmd_opts.args
		if args == "" or args == "toggle" then
			M.toggle()
		elseif args == "close" then
			M.close()
		elseif args == "menu" then
			M.toggle_menu()
		elseif args:sub(1, 5) == "open " then
			M.open(args:sub(6))
		else
			M.toggle()
		end
	end, {
		nargs = "?",
		complete = function(_, _, _)
			local keys = { "toggle", "open ", "close", "menu" }
			if state.opts and state.opts.poppies then
				for k, _ in pairs(state.opts.poppies) do
					table.insert(keys, "open " .. k)
				end
			end
			return keys
		end,
	})
end

M.get_current_poppy_name = function()
	return state.current_poppy_name
end

return M
