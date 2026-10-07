require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local layout = require("poppy.core.ui.layout")
local style = require("poppy.core.ui.style")
local shared = require("poppy.core.shared")
local config = require("poppy.config")
local keymaps = require("poppy.core.session.keymaps")
local menu = require("poppy.core.session.menu")
local dialog = require("poppy.core.session.dialog")
local autocommands = require("poppy.core.session.autocommands")

-- Static dispatch keeps the mode modules visible to the LSP; a dynamic require("...modes."..mode) hides them.
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

-- setup() is documented as call-once, but re-sourcing a config re-calls it. Tearing down
-- through the public close() before init_or_reset_state() keeps one teardown path and
-- dereferences live windows. The opts check is what keeps a first call silent: M.close
-- would otherwise trip ensure_setup's "setup() must be called first".
---@return nil
local teardown_live_session = function()
	if state.windows.opts and shared.session_is_open() then
		M.close()
	end
end

local init_or_reset_state = function()
	state.windows = state.default_state()
	state.poppies_configured = {}
	state.poppies_runtime = {}
end

---@param user_opts? PoppyConfig
---@return nil
M.setup = function(user_opts)
	teardown_live_session()
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

-- Destroys every live poppy buffer. Keeps poppies_configured intact: that's the user's
-- declared config, not runtime state.
local clear_poppies = function()
	for _, configured in ipairs(state.poppies_configured) do
		local rt = state.runtime(configured.name)
		if rt and rt.bufnr and api.nvim_buf_is_valid(rt.bufnr) then
			api.nvim_buf_delete(rt.bufnr, { force = true })
		end
	end
	state.poppies_runtime = {}
end

-- `recovering` and the augroup clear both belong at the top: clear_poppies() deletes poppy
-- buffers while the content window is showing one, so WinClosed fires from inside that loop.
-- Unguarded, the watcher re-creates the content window and overwrites content_buf.
local cleanup = function(drop_poppies)
	state.windows.recovering = true
	api.nvim_create_augroup("poppy_ui", { clear = true })

	if drop_poppies then
		clear_poppies()
	end

	local ok, err = pcall(function()
		-- Restore the global 'guicursor' first; the list window may have overridden it.
		style.restore_cursor_mode()

		if state.windows.current_poppy_name then
			shared.hide_poppy(state.windows.current_poppy_name)
		end

		local hint_buf = state.windows.menu_hint_buf
		shared.close_menu_hint()

		view.unmount()

		for _, win in ipairs({ state.windows.wrapper_win, state.windows.content_win }) do
			if not win or not api.nvim_win_is_valid(win) then
				goto continue
			end
			api.nvim_win_close(win, true)
			::continue::
		end

		state.windows.recovering = false

		-- in_use skips any live poppy's bufnr from deletion: file poppies reuse content_buf
		-- as the live file buffer (can hold unsaved edits). Panel scratch buffers (wrapper,
		-- hints, menu, header) are not in `in_use` and must be deleted even when a live
		-- poppy remains; the toggle path skips `clear_poppies` so without this they'd leak.
		local in_use = {}
		for _, rt in pairs(state.poppies_runtime) do
			if rt and rt.bufnr then
				in_use[rt.bufnr] = true
			end
		end

		local function add_buffer(list, buf)
			if buf and api.nvim_buf_is_valid(buf) then
				list[#list + 1] = buf
			end
		end

		local buffers = { state.windows.content_buf }
		add_buffer(buffers, state.windows.wrapper_buf)
		add_buffer(buffers, view.get_hints_buf())
		add_buffer(buffers, view.get_menu_buf())
		add_buffer(buffers, view.get_menu_header_buf())
		add_buffer(buffers, view.get_header_buf())
		add_buffer(buffers, hint_buf)

		for _, buf in ipairs(buffers) do
			if not in_use[buf] then
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
	-- A live question owns the session: toggling off would tear down the buffer it's asking about.
	if dialog.trapped() then
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

-- One place decides whether a name is real so entry points can reject before touching state.
---@param name? string nil is always fine
---@return boolean
local is_known_poppy = function(name)
	if name == nil then
		return true
	end
	if state.poppy_configured(name) then
		return true
	end
	shared.notify_warn("'%s' does not exist", tostring(name))
	return false
end

---@param poppy_name? string Name to open; nil opens the manager on the landing view.
--- A name that was never configured is rejected with a warning: nothing opens,
--- and an already-open session is left untouched.
---@return integer? win wrapper window, or nil if nothing opened
M.open = function(poppy_name)
	if not shared.ensure_setup() then
		return nil
	end
	-- Checked here rather than only in switch_by_name: by the time M.open delegates, it has
	-- already transitioned to content mode, which would leave a session with no current poppy.
	if not is_known_poppy(poppy_name) then
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
	local landing_width = should_land and M.landing_width() or nil

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

---@param configured {name: string, config: PoppyResolvedConfig}
---@param poppy_name string
---@return nil
local do_switch = function(configured, poppy_name)
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
		-- Mode rejected: it already dropped the poppy and refreshed.
		state.set_current_poppy_name(nil)
		M.recover()
		return
	end

	keymaps.bind_poppy_action(api.nvim_win_get_buf(state.windows.content_win))

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

-- Set while recovery re-drives a switch that already failed once. See switch_by_name's failure branch.
local retrying_after_failure = false

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
	if not is_known_poppy(poppy_name) or not configured then
		return
	end

	-- A dead content pane is recoverable: rebuild rather than bail. Normal after a poppy's
	-- buffer is deleted (the pane goes with the buffer). Skipped on landing: do_switch creates it.
	local function rebuild_content_pane()
		if not shared.session_is_open() then
			return false
		end
		M.transition_to_content()
		local cw = state.windows.content_win
		return cw and api.nvim_win_is_valid(cw)
	end

	if not state.windows.is_landing then
		if not state.windows.content_win or not api.nvim_win_is_valid(state.windows.content_win) then
			if not rebuild_content_pane() then
				shared.notify_error("cannot switch to '%s': no content pane", tostring(poppy_name))
				state.set_current_poppy_name(nil)
				return
			end
		end
	end

	local ok, err = pcall(do_switch, configured, poppy_name)
	if ok then
		retrying_after_failure = false
		return
	end

	-- Something threw partway. Session is half-switched: current_poppy_name names a poppy whose
	-- sidebar row, focus, and hints were never settled.
	shared.notify_error("switch to '%s' failed: %s", tostring(poppy_name), tostring(err))
	state.set_current_poppy_name(nil)

	-- One retry, no more. recover() switches to a fallback; if that throws the same error it
	-- would re-enter recover() and walk fallbacks forever.
	if retrying_after_failure then
		shared.notify_error("switch failed again; not retrying")
		return
	end
	retrying_after_failure = true
	M.recover()
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

---@param name string
---@return boolean was_active
local _kill_now = function(name)
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

---Run `resume` either now or after a confirmation dialog if the buffer has unsaved edits.
---Never deletes anything itself: resume is the only caller of _kill_now, so a "Go back" answer
---(buffer still modified) cannot re-trigger the question.
---@param name string
---@param resume fun()
---@return nil
local _kill = function(name, resume)
	if resume and dialog.needs_confirmation(name) then
		dialog.open(name, resume)
		return
	end
	resume()
end

---@return nil
M.kill_active = function()
	if not shared.ensure_setup() then
		return
	end
	local name = state.windows.current_poppy_name
	if not name then
		return
	end
	_kill(name, function()
		_kill_now(name)
		M.recover()
	end)
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
	_kill(resolved.name, function()
		if _kill_now(resolved.name) then
			M.recover()
		elseif shared.session_is_open() and not state.windows.is_landing then
			view.refresh_poppies()
		end
	end)
end

---@param name string
---@return nil
M.kill_by_name = function(name)
	if not shared.ensure_setup() then
		return
	end
	if not is_known_poppy(name) then
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
		local full_width = layout.compute_wrapper_dimensions(
			state.windows.opts, vim.o.columns, vim.o.lines, nil, view.min_wrapper_width())
		api.nvim_win_set_config(state.windows.wrapper_win, {
			relative = wc.relative,
			width = full_width,
			height = wc.height,
			col = math.floor((vim.o.columns - full_width) / 2),
			row = wc.row,
		})
		state.windows.is_landing = false
	end
	-- Clamp against the wrapper, not the raw config: on a narrow wrapper the sidebar is the
	-- binding constraint and content.create's subtraction would otherwise go negative.
	local wrapper_width = api.nvim_win_get_width(state.windows.wrapper_win)
	local panel_width = view.menu_width(wrapper_width)
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
	shared.drop_scratch_buffer(state.windows.content_buf)
	state.windows.content_buf = nil
	local menu_buf = view.get_menu_buf()
	vim.bo[menu_buf].filetype = "poppy_menu"
	require("poppy.core.session.menu").focus_body()
end

-- Landing width, from content, capped by the screen. Single source for launch and recover paths.
M.landing_width = function()
	return math.min(
		layout.landing_min_width(state.windows.opts, state.poppies_configured),
		vim.o.columns
	)
end

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
-- Caller must hold state.windows.recovering = true so the WinClosed watcher doesn't re-fire.
local recover_goto_landing = function()
	view.unmount()
	shared.close_menu_hint()

	api.nvim_create_augroup("poppy_ui", { clear = true })

	if state.windows.content_win and api.nvim_win_is_valid(state.windows.content_win) then
		api.nvim_win_close(state.windows.content_win, true)
	end

	local landing_width = M.landing_width()
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
		-- recovering gates the WinClosed watcher; closing content_win below would re-fire it.
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
