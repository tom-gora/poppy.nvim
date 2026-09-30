require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local config = require("poppy.config")
local keymaps = require("poppy.core.session.keymaps")
local menu = require("poppy.core.session.menu")
local autocommands = require("poppy.core.session.autocommands")

-- Static dispatch: a dynamic require("poppy.core.modes." .. mode) resolves
-- fine at runtime but hides the mode modules from the LSP.
local MODES = {
	term = require("poppy.core.modes.term"),
	file = require("poppy.core.modes.file"),
}

local CAT_ORDER = { exec = 0, file = 1, shell = 2 }

---@param opts? PoppyMergedConfig
---@return {name: string, config: PoppyResolvedConfig}[]
local sort_config = function(opts)
	local sorted = {}
	if opts and opts.poppies_resolved then
		for name, p_resolved in pairs(opts.poppies_resolved) do
			table.insert(sorted, { name = name, config = p_resolved })
		end
		table.sort(sorted, function(a, b)
			local ord_a = CAT_ORDER[shared.category_from_resolved(a.config)] or 99
			local ord_b = CAT_ORDER[shared.category_from_resolved(b.config)] or 99
			if ord_a ~= ord_b then
				return ord_a < ord_b
			end
			return a.name < b.name
		end)
	end
	return sorted
end

local setup_global_key = function()
	local keys = shared.keys()
	if not keys then
		return
	end
	vim.keymap.set(shared.NORM_TERM_MODES, keys.poppy_action, function()
		M.toggle()
	end, { desc = "Poppy: Toggle UI" })
end

---@param opts PoppyMergedConfig
---@param callbacks table
local setup_command = function(opts, callbacks)
	local sub_handlers = {
		toggle = function()
			callbacks.toggle()
		end,
		close = function()
			callbacks.close()
		end,
		menu = function()
			callbacks.toggle_menu()
		end,
		open = function(name)
			callbacks.open(name ~= "" and name or nil)
		end,
	}
	api.nvim_create_user_command("Poppy", function(cmd_args)
		local sub = cmd_args.fargs[1]
		local handler = sub_handlers[sub or "toggle"]
		if not handler then
			shared.notify_warn("unknown subcommand '%s' (valid: toggle, close, menu, open [<name>])", tostring(sub))
			return
		end
		handler(table.concat(cmd_args.fargs, " ", 2))
	end, {
		nargs = "*",
		complete = function(arg_lead, cmd_line)
			local body = cmd_line:gsub("^%s*:?[Pp]oppy%s+", "")
			local cmd, rest = body:match("^(%S+)%s*(.*)")

			if cmd == "open" and rest ~= "" then
				local names = {}
				if opts and opts.poppies then
					for k, _ in pairs(opts.poppies) do
						if k:sub(1, #arg_lead) == arg_lead then
							table.insert(names, k)
						end
					end
				end
				return names
			end

			if cmd == nil or rest == "" then
				local subs = { "toggle", "close", "menu", "open" }
				local out = {}
				for _, s in ipairs(subs) do
					if s:sub(1, #arg_lead) == arg_lead then
						table.insert(out, s)
					end
				end
				return out
			end

			return {}
		end,
	})
end

local init_or_reset_state = function()
	state.windows = state.default_state()
	state.poppies_configured = {}
	state.poppies_runtime = {}
end

---@param user_opts? PoppyConfig
---@return nil
M.setup = function(user_opts)
	init_or_reset_state()
	view.setup_style()
	api.nvim_create_augroup("poppy_ui", { clear = true })
	state.windows.opts = config.merge(user_opts)
	view.define_icon_signs(state.windows.opts.icons)
	if next(state.windows.opts.poppies_resolved or {}) == nil then
		shared.notify_warn("no poppies declared in setup({poppies = {...}}); the manager will open empty.")
	elseif #state.windows.opts.dropped_names > 0 then
		shared.notify_warn(
			"%d poppy(s) had no exec/file/shell and were dropped: %s",
			#state.windows.opts.dropped_names,
			table.concat(state.windows.opts.dropped_names, ", ")
		)
	end
	for _, sorted_entry in ipairs(sort_config(state.windows.opts)) do
		state.poppies_configured[#state.poppies_configured + 1] = {
			name = sorted_entry.name,
			config = sorted_entry.config,
		}
	end
	setup_global_key()
	autocommands.setup(state.windows.opts)
	setup_command(state.windows.opts, {
		toggle = M.toggle,
		open = M.open,
		close = M.close,
		toggle_menu = menu.toggle_menu,
	})
end

---@param name string
---@return PoppySessionEntry?
M.get_poppy_by_name = function(name)
	local configured = state.poppy_configured(name)
	if not configured then return nil end
	return {
		name = configured.name,
		config = configured.config,
		runtime_state = state.runtime(name),
	}
end

---@param index integer
---@return PoppySessionEntry?
M.get_poppy_by_index = function(index)
	local configured = state.poppies_configured[index]
	if not configured then return nil end
	return {
		name = configured.name,
		config = configured.config,
		runtime_state = state.runtime(configured.name),
	}
end

---@return PoppySessionEntry?
M.get_current_poppy = function()
	local name = state.windows.current_poppy_name
	if not name then return nil end
	local configured = state.poppy_configured(name)
	if not configured then return nil end
	return {
		name = configured.name,
		config = configured.config,
		runtime_state = state.runtime(name),
	}
end

---@return PoppySessionEntry[]
M.get_poppies = function()
	local result = {}
	for _, configured in ipairs(state.poppies_configured) do
		result[#result + 1] = {
			name = configured.name,
			config = configured.config,
			runtime_state = state.runtime(configured.name),
		}
	end
	return result
end

M.get_current_poppy_name = shared.session_get_current_poppy_name
M.is_open = shared.session_is_open

-- Destroys every live poppy buffer, forcing a full rebuild on the next open.
-- Deliberately keeps poppies_configured intact: the registry is the user's
-- declared config, not runtime state, and clearing it made the manager
-- permanently empty after one :Poppy close.
local clear_poppies = function()
	for _, configured in ipairs(state.poppies_configured) do
		local rt = state.runtime(configured.name)
		if rt and rt.bufnr and api.nvim_buf_is_valid(rt.bufnr) then
			api.nvim_buf_delete(rt.bufnr, { force = true })
		end
	end
	state.poppies_runtime = {}
end

-- recovering guards the WinClosed watcher from re-firing during teardown.
local cleanup = function(drop_poppies)
	if drop_poppies then
		clear_poppies()
	end

	local ok, err = pcall(function()
		if state.windows.current_poppy_name then
			shared.hide_poppy(state.windows.current_poppy_name)
		end

		local hint_buf = state.windows.menu_hint_buf
		shared.close_menu_hint()

		view.unmount()

		state.windows.recovering = true
		api.nvim_create_augroup("poppy_ui", { clear = true })

		for _, win in ipairs({ state.windows.wrapper_win, state.windows.content_win }) do
			if win and api.nvim_win_is_valid(win) then
				api.nvim_win_close(win, true)
			end
		end

		state.windows.recovering = false

		-- A poppy buffer currently in use must never be wiped here: it can
		-- hold unsaved edits, and it is what the next open restores. Since
		-- file poppies are opened with :edit, the content window's own buffer
		-- *is* the poppy's buffer, so this is the normal case, not a corner one.
		local in_use = {}
		for _, rt in pairs(state.poppies_runtime) do
			if rt and rt.bufnr then
				in_use[rt.bufnr] = true
			end
		end

		local has_live_poppy = next(state.poppies_runtime) ~= nil
		local buffers = { state.windows.content_buf }
		if not has_live_poppy then
			table.insert(buffers, state.windows.wrapper_buf)
			table.insert(buffers, view.get_hints_buf())
			table.insert(buffers, view.get_list_buf())
			local hbuf = view.get_header_buf()
			if hbuf then
				table.insert(buffers, hbuf)
			end
		end
		if hint_buf and api.nvim_buf_is_valid(hint_buf) then
			table.insert(buffers, hint_buf)
		end

		for _, buf in ipairs(buffers) do
			if buf and not in_use[buf] and api.nvim_buf_is_valid(buf) then
				api.nvim_buf_delete(buf, { force = true })
			end
		end

		state.windows.wrapper_win = nil
		state.windows.content_win = nil
		state.windows.content_buf = nil
		state.windows.is_landing = false
	end)
	if not ok then
		shared.notify_error("cleanup failed: %s", tostring(err))
		state.windows.recovering = false
	end
end

M.close = function()
	if not shared.ensure_setup() then
		return
	end
	cleanup(true)
end

M.toggle = function()
	if not shared.ensure_setup() then
		return
	end
	if shared.session_is_open() then
		cleanup()
	else
		M.open()
	end
end

local open_wrapper = function(width_override)
	local win, wbuf = view.wrapper.ensure(state.windows.wrapper_buf, state.windows.opts, width_override)
	state.windows.wrapper_buf = wbuf
	return win
end

---@param poppy_name? string
---@return integer?
M.open = function(poppy_name)
	if not shared.ensure_setup() then
		return nil
	end
	if shared.session_is_open() then
		if poppy_name then
			M.switch_by_name(poppy_name)
		end
		return state.windows.wrapper_win
	end

	if shared.opts_field("exclusive_float") then
		autocommands.setup_exclusive_float()
	end

	local last_poppy = state.windows.current_poppy_name
	local last_runtime = last_poppy and state.runtime(last_poppy)
	local has_content = poppy_name or (last_runtime ~= nil)
	local should_land = not has_content
	local landing_width =
		should_land and layout.compute_landing_view_width(state.windows.opts, state.poppies_configured) or nil

	local win = open_wrapper(landing_width)
	state.windows.wrapper_win = win
	state.set_current_poppy_name(nil)
	state.windows.is_landing = should_land

	if has_content then
		M.transition_to_content()
		M.switch_by_name(poppy_name or last_poppy)
	else
		M.enter_landing()
	end

	return state.windows.wrapper_win
end

local cursor_to_poppy_index = function()
	local ok, cursor = pcall(api.nvim_win_get_cursor, 0)
	if not ok then
		return nil
	end
	local idx = cursor[1]
	if not state.poppies_configured[idx] then
		return nil
	end
	return idx
end

---@param name_or_index string|integer|nil
---@return { name: string, runtime: PoppyRuntimeState? }?
local resolve = function(name_or_index)
	if type(name_or_index) == "number" then
		local configured = state.poppies_configured[name_or_index]
		if not configured then
			return nil
		end
		name_or_index = configured.name
	end
	if not name_or_index then
		return nil
	end
	return { name = name_or_index, runtime = state.runtime(name_or_index) }
end

---@param poppy_name string
---@return nil
M.switch_by_name = function(poppy_name)
	if not shared.ensure_setup() then
		return
	end
	if poppy_name == state.windows.current_poppy_name then
		return
	end
	if not shared.session_is_open() then
		return
	end

	local configured = state.poppy_configured(poppy_name)
	if not configured then
		shared.notify_warn("unknown poppy '%s'", tostring(poppy_name))
		return
	end

	if state.windows.current_poppy_name then
		shared.hide_poppy(state.windows.current_poppy_name)
	end

	if state.windows.is_landing then
		M.transition_to_content()
	end

	local poppy_opts = configured.config
	if state.windows.current_poppy_name and state.windows.current_poppy_name ~= poppy_name then
		state.windows.last_poppy_name = state.windows.current_poppy_name
	end
	state.set_current_poppy_name(poppy_name)

	local on_die = function(name)
		if shared.session_is_open() and shared.session_get_current_poppy_name() == name then
			M.kill_active()
		elseif shared.session_is_open() and not state.windows.is_landing then
			view.refresh_poppies()
		end
	end

	local mode = MODES[poppy_opts.mode]
	if not mode then
		shared.notify_warn("unknown mode '%s' for poppy '%s'", tostring(poppy_opts.mode), poppy_name)
		return
	end
	local mode_ok = mode.run(poppy_name, poppy_opts, state.windows.content_win, on_die)
	if not mode_ok then
		-- Mode rejected the poppy (e.g. file() couldn't resolve). The mode
		-- plugin already dropped it from state and refreshed the list;
		-- recover to land somewhere sensible.
		state.set_current_poppy_name(nil)
		M.recover()
		return
	end

	keymaps.setup_content_keys(api.nvim_win_get_buf(state.windows.content_win))

	if shared.opts_field("menu_autohide") then
		view.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	else
		view.set_focused(false)
	end

	view.refresh_poppies()
	local cbuf = api.nvim_win_get_buf(state.windows.content_win)
	local is_terminal = vim.bo[cbuf].buftype == "terminal"
	if shared.try_focus_win(state.windows.content_win) and is_terminal then
		vim.cmd("startinsert")
	end
end

---@param index integer
---@return nil
M.switch_by_index = function(index)
	if not shared.ensure_setup() then
		return
	end
	local resolved = resolve(index)
	if resolved then
		M.switch_by_name(resolved.name)
	end
end

---@return nil
M.switch_by_cursor = function()
	if not shared.ensure_setup() then
		return
	end
	local idx = cursor_to_poppy_index()
	if idx then
		M.switch_by_index(idx)
	end
end

-- Tear down a poppy's runtime state. Returns true if this was the active poppy.
---@param name string
---@return boolean
local _kill = function(name)
	if not name then
		return false
	end
	local rt = state.runtime(name)
	if not rt then
		return state.windows.current_poppy_name == name
	end

	local bufnr = rt.bufnr
	if bufnr and api.nvim_buf_is_valid(bufnr) then
		api.nvim_buf_delete(bufnr, { force = true })
	end

	state.poppies_runtime[name] = nil
	local was_active = state.windows.current_poppy_name == name
	if was_active then
		state.set_current_poppy_name(nil)
	end
	return was_active
end

-- Drop the target buffer up-front so any callback recover() schedules lands on clean state.
---@return nil
M.kill_active = function()
	if not shared.ensure_setup() then
		return
	end
	if not state.windows.current_poppy_name then
		return
	end
	_kill(state.windows.current_poppy_name)
	M.recover()
end

---@param resolved { name: string, runtime: PoppyRuntimeState? }?
---@return nil
local _kill_then_refresh = function(resolved)
	if not resolved then
		return
	end
	if not resolved.runtime then
		return
	end
	if _kill(resolved.name) then
		M.recover()
	elseif shared.session_is_open() and not state.windows.is_landing then
		view.refresh_poppies()
	end
end

---@param name string
---@return nil
M.kill_by_name = function(name)
	if not shared.ensure_setup() then
		return
	end
	return _kill_then_refresh(resolve(name))
end

---@param index integer
---@return nil
M.kill_by_index = function(index)
	if not shared.ensure_setup() then
		return
	end
	return _kill_then_refresh(resolve(index))
end

---@return nil
M.kill_by_cursor = function()
	if not shared.ensure_setup() then
		return
	end
	local idx = cursor_to_poppy_index()
	if idx then
		return _kill_then_refresh(resolve(idx))
	end
end

M.transition_to_content = function()
	if state.windows.is_landing then
		view.unmount()
		local wc = api.nvim_win_get_config(state.windows.wrapper_win)
		local full_width = layout.compute_wrapper_dimensions(state.windows.opts, vim.o.columns, vim.o.lines)
		api.nvim_win_set_config(state.windows.wrapper_win, {
			relative = wc.relative,
			width = full_width,
			height = wc.height,
			col = math.floor((vim.o.columns - full_width) / 2),
			row = wc.row,
		})
		state.windows.is_landing = false
	end
	local panel_width = view.menu_width()
	local c_win, c_buf = view.content.create(state.windows.wrapper_win, panel_width)
	view.mount(state.windows.wrapper_win)
	autocommands.watch_content_window(c_win, panel_width)
	state.windows.content_win = c_win
	state.windows.content_buf = c_buf
end

M.enter_landing = function()
	state.windows.is_landing = true
	view.mount(state.windows.wrapper_win)
	state.windows.content_win = nil
	state.windows.content_buf = nil
	local list_buf = view.get_list_buf()
	vim.bo[list_buf].filetype = "poppy_menu"
	local list_win = view.get_list_win()
	if list_win and api.nvim_win_is_valid(list_win) then
		api.nvim_set_current_win(list_win)
	end
	keymaps.setup_list_keys(list_buf)
end

-- Pick a previously-hidden poppy to restore, preferring last_poppy_name.
-- Returns nil when there is nothing to restore.
---@return string?
local recover_pick_fallback = function()
	if state.windows.last_poppy_name then
		local rt = state.runtime(state.windows.last_poppy_name)
		if rt and rt.hidden then
			return state.windows.last_poppy_name
		end
	end
	for name, rt in pairs(state.poppies_runtime) do
		if rt.hidden then
			return name
		end
	end
	return nil
end

-- Tear down content, resize wrapper to landing width, re-enter landing.
-- Caller must hold state.windows.recovering = true so the WinClosed watcher
-- doesn't re-fire.
local recover_goto_landing = function()
	view.unmount()
	shared.close_menu_hint()

	api.nvim_create_augroup("poppy_ui", { clear = true })

	if state.windows.content_win and api.nvim_win_is_valid(state.windows.content_win) then
		api.nvim_win_close(state.windows.content_win, true)
	end

	local landing_width = layout.compute_landing_view_width(state.windows.opts, state.poppies_configured)
	local wc = api.nvim_win_get_config(state.windows.wrapper_win)
	api.nvim_win_set_config(state.windows.wrapper_win, {
		relative = wc.relative,
		width = landing_width,
		height = wc.height,
		col = math.floor((vim.o.columns - landing_width) / 2),
		row = wc.row,
	})

	M.enter_landing()
end

M.recover = function()
	state.set_current_poppy_name(nil)
	vim.schedule(function()
		-- recovering gates the WinClosed watcher; closing content_win below would otherwise re-fire it.
		state.windows.recovering = true
		local ok, err = pcall(function()
			if not shared.session_is_open() or state.windows.is_landing or state.windows.current_poppy_name then
				return
			end

			local fallback = recover_pick_fallback()
			if fallback then
				M.switch_by_name(fallback)
			else
				recover_goto_landing()
			end
		end)
		state.windows.recovering = false
		if not ok then
			shared.notify_error("recover failed: %s", tostring(err))
		end
	end)
end

return M
