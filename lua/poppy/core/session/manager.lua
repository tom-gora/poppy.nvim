require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local menu = require("poppy.core.session.menu")
local dialog = require("poppy.core.session.dialog")
local autocommands = require("poppy.core.session.autocommands")

local MODES = {
	term = require("poppy.core.modes.term"),
	file = require("poppy.core.modes.file"),
}

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
---@return string?
local resolve = function(name_or_index)
	if type(name_or_index) == "number" then
		local configured = state.poppies_configured[name_or_index]
		if not configured then
			return nil
		end
		return configured.name
	end
	return name_or_index
end

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
		require("poppy.core.ui.style").restore_cursor_mode()

		if state.windows.current_poppy_name then
			shared.hide_poppy(state.windows.current_poppy_name)
		end

		local hint_buf = state.windows.menu_hint_buf
		shared.close_menu_hint()

		view.unmount()

		for _, win in ipairs({ state.windows.wrapper_win, state.windows.content_win }) do
			if win and api.nvim_win_is_valid(win) then
				api.nvim_win_close(win, true)
			end
		end

		state.windows.recovering = false

		-- File poppies reuse content_buf as the live file buffer (can hold unsaved edits).
		-- Panel scratch buffers are not in `in_use` and must be deleted even when a live poppy
		-- remains; the toggle path skips `clear_poppies` so without this they'd leak.
		local in_use = {}
		for _, rt in pairs(state.poppies_runtime) do
			if rt and rt.bufnr then
				in_use[rt.bufnr] = true
			end
		end

		local buffers = { state.windows.content_buf }
		for _, buf in ipairs({
			state.windows.wrapper_buf,
			state.windows.hints_buf,
			state.windows.menu_buf,
			state.windows.menu_header_buf,
			state.windows.header_buf,
			state.windows.menu_wrapper_buf,
			hint_buf,
		}) do
			if buf and api.nvim_buf_is_valid(buf) and not in_use[buf] then
				api.nvim_buf_delete(buf, { force = true })
			end
		end

		state.windows.wrapper_win = nil
		state.windows.content_win = nil
		state.windows.content_buf = nil
		state.windows.menu_wrapper_buf = nil
		state.windows.is_landing = false
		state.windows.menu_hidden = false
	end)
	if not ok then
		shared.notify_error("cleanup failed: %s", tostring(err))
		state.windows.recovering = false
	end
end

local open_wrapper = function(width_override)
	local win, wbuf = view.wrapper.ensure(state.windows.wrapper_buf, state.windows.opts, width_override)
	state.windows.wrapper_buf = wbuf
	return win
end

-- Returns true if nothing was missing (caller proceeds) or false if a dialog is now up.
local function drain_missing_file_queue(on_complete)
	if dialog.trapped() then
		return false
	end
	local missing = {}
	for _, p in ipairs(state.poppies_configured) do
		if dialog.needs_file_decision(p.name) then
			missing[#missing + 1] = p.name
		end
	end
	if #missing == 0 then
		return true
	end
	dialog.open_missing_file(missing, on_complete)
	return false
end

local enter_landing = function()
	state.windows.is_landing = true
	view.mount(state.windows.wrapper_win)
	state.windows.content_win = nil
	shared.drop_scratch_buffer(state.windows.content_buf)
	state.windows.content_buf = nil
	vim.bo[state.windows.menu_buf].filetype = "poppy_menu"
	menu.focus_body()
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

---@param poppy_name? string
---@return integer?
M.open = function(poppy_name)
	if not shared.ensure_setup() then
		return nil
	end
	-- Checked here rather than only in switch_by_name: by the time M.open delegates, it has
	-- already transitioned to content mode, leaving a session with no current poppy.
	if not is_known_poppy(poppy_name) then
		return nil
	end
	-- on_complete is the missing-file queue's continuation; it re-invokes M.open() with no name
	-- so the user lands on a fresh poppies list after the queue drains.
	if shared.session_is_open() then
		if not drain_missing_file_queue(function()
			M.open()
		end) then
			return state.windows.wrapper_win
		end
		if poppy_name == nil then
			M.close()
			M.toggle()
			return state.windows.wrapper_win
		end
	end

	if shared.opts_field("close_other_floats_on_open") then
		autocommands.setup_float_sweep()
	end

	local last_poppy = state.windows.current_poppy_name
	local last_runtime = last_poppy and state.runtime(last_poppy)
	local has_content = poppy_name or (last_runtime ~= nil)
	local should_land = not has_content
	local landing_w
	if should_land then
		landing_w = layout.landing_width(state.windows.opts, state.poppies_configured, vim.o.columns)
	end

	local win = open_wrapper(landing_w)
	state.windows.wrapper_win = win
	state.set_current_poppy_name(nil)
	state.windows.is_landing = should_land

	-- on_complete re-invokes M.open to continue the original caller's flow after the queue resolves.
	if not drain_missing_file_queue(function()
		M.open(poppy_name)
	end) then
		return state.windows.wrapper_win
	end

	if has_content then
		M.transition_to_content()
		M.switch_by_name(poppy_name or last_poppy)
	else
		enter_landing()
	end

	return state.windows.wrapper_win
end

M.transition_to_content = function()
	if state.windows.is_landing then
		view.unmount()
		local wc = api.nvim_win_get_config(state.windows.wrapper_win)
		local full_width = layout.compute_wrapper_dimensions(
			state.windows.opts,
			vim.o.columns,
			vim.o.lines,
			nil,
			view.min_wrapper_width()
		)
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
		if not shared.session_is_open() then
			return
		end
		if shared.session_get_current_poppy_name() == name then
			M.kill_active()
		elseif not state.windows.is_landing then
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

	require("poppy.core.session.keymaps").bind_poppy_action(api.nvim_win_get_buf(state.windows.content_win))

	if shared.opts_field("autohide_menu") then
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

	-- A dead content pane is recoverable: rebuild rather than bail. Skipped on landing:
	-- do_switch creates it.
	local function rebuild_content_pane()
		if not shared.session_is_open() then
			return false
		end
		M.transition_to_content()
		local cw = state.windows.content_win
		return cw and api.nvim_win_is_valid(cw)
	end

	if
		not state.windows.is_landing
		and (not state.windows.content_win or not api.nvim_win_is_valid(state.windows.content_win))
		and not rebuild_content_pane()
	then
		shared.notify_error("cannot switch to '%s': no content pane", tostring(poppy_name))
		state.set_current_poppy_name(nil)
		return
	end

	local ok, err = pcall(do_switch, configured, poppy_name)
	if ok then
		state.windows.retrying_after_failure = false
		return
	end

	-- Session is half-switched: current_poppy_name names a poppy whose sidebar row, focus,
	-- and hints were never settled.
	shared.notify_error("switch to '%s' failed: %s", tostring(poppy_name), tostring(err))
	state.set_current_poppy_name(nil)

	-- One retry, no more. recover() switches to a fallback; if that throws the same error
	-- it would re-enter recover() and walk fallbacks forever.
	if state.windows.retrying_after_failure then
		shared.notify_error("switch failed again; not retrying")
		return
	end
	state.windows.retrying_after_failure = true
	M.recover()
end

---@param index integer
---@return nil
M.switch_by_index = function(index)
	if not shared.ensure_setup() then
		return
	end
	local name = resolve(index)
	if name then
		M.switch_by_name(name)
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

---@param name string
---@return nil
local kill_live_poppy = function(name)
	if not state.runtime(name) then
		return
	end
	_kill(name, function()
		if _kill_now(name) then
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
	return kill_live_poppy(name)
end

---@param index integer
---@return nil
M.kill_by_index = function(index)
	if not shared.ensure_setup() then
		return
	end
	local name = resolve(index)
	if name then
		return kill_live_poppy(name)
	end
end

---@return nil
M.kill_by_cursor = function()
	if not shared.ensure_setup() then
		return
	end
	local idx = cursor_to_poppy_index()
	if idx then
		local name = resolve(idx)
		if name then
			return kill_live_poppy(name)
		end
	end
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

-- Caller must hold state.windows.recovering = true so the WinClosed watcher doesn't re-fire.
local recover_goto_landing = function()
	view.unmount()
	shared.close_menu_hint()

	api.nvim_create_augroup("poppy_ui", { clear = true })

	if state.windows.content_win and api.nvim_win_is_valid(state.windows.content_win) then
		api.nvim_win_close(state.windows.content_win, true)
	end

	local landing_w = layout.landing_width(state.windows.opts, state.poppies_configured, vim.o.columns)
	local wc = api.nvim_win_get_config(state.windows.wrapper_win)
	api.nvim_win_set_config(state.windows.wrapper_win, {
		relative = wc.relative,
		width = landing_w,
		height = wc.height,
		col = math.floor((vim.o.columns - landing_w) / 2),
		row = wc.row,
	})

	enter_landing()
end

M.recover = function()
	state.set_current_poppy_name(nil)
	vim.schedule(function()
		-- recovering gates the WinClosed watcher.
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

---@param name string
---@return PoppySessionEntry?
M.get_poppy_by_name = function(name)
	local configured = state.poppy_configured(name)
	if not configured then
		return nil
	end
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
	if not configured then
		return nil
	end
	return {
		name = configured.name,
		config = configured.config,
		runtime_state = state.runtime(configured.name),
	}
end

---@return PoppySessionEntry?
M.get_current_poppy = function()
	local name = state.windows.current_poppy_name
	if not name then
		return nil
	end
	local configured = state.poppy_configured(name)
	if not configured then
		return nil
	end
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

return M
