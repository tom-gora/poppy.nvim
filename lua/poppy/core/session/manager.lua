require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.mount")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local menu = require("poppy.core.session.menu")
local dialog = require("poppy.core.session.dialog")
local autocommands = require("poppy.core.session.autocommands")
local keymaps = require("poppy.core.session.keymaps")

local MODES = {
	exec = require("poppy.core.modes.term"),
	shell = require("poppy.core.modes.term"),
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
local resolve_poppy_name = function(name_or_index)
	if type(name_or_index) == "string" then
		return name_or_index
	end
	if type(name_or_index) == "number" then
		local configured = state.poppies_configured[name_or_index]
		if not configured then
			return nil
		end
		return configured.name
	end
	return nil
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

-- Both halves are the teardown signal: `recovering` gates in-flight recover() callbacks,
-- clearing `poppy_ui` stops the WinClosed watcher from rebuilding the content pane.
local begin_teardown = function()
	state.windows.recovering = true
	api.nvim_create_augroup("poppy_ui", { clear = true })
end

-- `begin_teardown` runs first: clear_poppies deletes poppy buffers while the content
-- window still shows one, firing WinClosed; without the gate the watcher re-mounts content.
local teardown_panels = function()
	local ok, err = pcall(function()
		require("poppy.core.ui.style").restore_cursor_mode()

		if state.windows.current_poppy_name then
			shared.hide_poppy(state.windows.current_poppy_name)
		end

		local hint_buf = state.windows.menu_hint_buf
		shared.close_menu_hint()

		view.unmount()

		for _, win in ipairs({ state.windows.wrapper_win, state.windows.content_win }) do
			shared.close_win_if_valid(win)
		end

		-- Sweep floats orphaned by an earlier path: no state handle points at them.
		for _, win in ipairs(api.nvim_list_wins()) do
			if api.nvim_win_is_valid(win) and shared.is_poppy_window(win) then
				shared.close_win_if_valid(win)
			end
		end

		state.windows.recovering = false

		-- File poppies reuse content_buf as their live file buffer; the in_use set keeps
		-- that alive while letting panel scratch buffers get deleted.
		local in_use = {}
		for _, rt in pairs(state.poppies_runtime) do
			if rt and rt.bufnr then
				in_use[rt.bufnr] = true
			end
		end

		for _, buf in ipairs({
			state.windows.content_buf,
			state.windows.wrapper_buf,
			state.windows.hints_buf,
			state.windows.menu_buf,
			state.windows.dialog_body_buf,
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
		state.windows.dialog_body_buf = nil
		state.windows.is_landing = false
		state.windows.menu_hidden = false
		state.windows.retrying_after_failure = false
		state.windows.last_poppy_name = state.windows.current_poppy_name
		state.windows.current_poppy_name = nil
	end)
	if not ok then
		shared.notify_error("cleanup failed: %s", tostring(err))
		state.windows.recovering = false
	end
end

local cleanup = function()
	begin_teardown()
	clear_poppies()
	teardown_panels()
end

local cleanup_partial = function()
	begin_teardown()
	teardown_panels()
end

-- Warn every attempt so the user gets loud feedback while misconfigured.
local bail_empty = function()
	shared.notify_warn("no poppies available; configure poppies in setup({poppies = {...}})")
	if shared.session_is_open() then
		cleanup()
	end
end

local open_wrapper = function(width_override, height_override)
	local win, wbuf =
		view.wrapper.ensure(state.windows.wrapper_buf, state.windows.opts, width_override, height_override)
	state.windows.wrapper_buf = wbuf
	return win
end

---Returns true when the queue is empty (caller proceeds) or false when a dialog is now up.
local drain_missing_file_queue = function(on_complete)
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
	if dialog.trapped() then
		return
	end
	cleanup()
end

M.toggle = function()
	-- A live question owns the session: toggling off would tear down the buffer it asks about.
	if dialog.trapped() then
		return
	end
	if shared.session_is_open() then
		cleanup_partial()
	else
		M.open()
	end
end

---@param poppy_name? string
---@return integer?
M.open = function(poppy_name)
	-- Before any state work: below the floor there is no layout worth building.
	if layout.below_floor() then
		shared.notify_warn(
			"terminal too small (%dx%d); poppy needs at least %dx%d",
			vim.o.columns,
			vim.o.lines,
			layout.MIN_COLS,
			layout.MIN_LINES
		)
		return nil
	end
	-- Bail rather than mount an empty picker.
	if #state.poppies_configured == 0 then
		bail_empty()
		return nil
	end
	-- Checked here rather than only in switch_by_name: by the time M.open delegates, it has
	-- already transitioned to content mode with no current poppy.
	if not is_known_poppy(poppy_name) then
		return nil
	end
	-- Live missing-file dialog owns the session; the resume callback re-invokes M.open.
	if shared.session_is_open() then
		if not drain_missing_file_queue(function()
			M.open(poppy_name)
		end) then
			return state.windows.wrapper_win
		end
		if poppy_name == nil then
			-- Bare open on a live session: tear down so the next M.open re-picks the last poppy.
			cleanup_partial()
			state.set_current_poppy_name(nil)
			M.open()
			return state.windows.wrapper_win
		end
	end

	if shared.opts_field("close_other_floats_on_open") then
		autocommands.setup_float_sweep()
	end

	local last_poppy = state.windows.last_poppy_name or state.windows.current_poppy_name
	local last_runtime = last_poppy and state.runtime(last_poppy)
	-- A named open always has a target; a bare open falls back to the last opened poppy.
	local target = poppy_name or (last_runtime and last_poppy)
	local should_land = target == nil
	local landing_w, landing_h
	if should_land then
		landing_w = layout.landing_width(state.windows.opts, state.poppies_configured, vim.o.columns)
		local spec = menu.spec_poppy_list(menu.LANDING)
		landing_h = layout.compute(layout.resolve_spec(spec, landing_w)).height
	end

	local win = open_wrapper(landing_w, landing_h)
	state.windows.wrapper_win = win
	state.set_current_poppy_name(nil)
	state.windows.is_landing = should_land

	-- Catches a bare open where the only poppy is missing (live-session callers already drained above).
	if not drain_missing_file_queue(function()
		M.open(poppy_name)
	end) then
		return state.windows.wrapper_win
	end

	if target then
		M.transition_to_content()
		M.switch_by_name(target)
	else
		enter_landing()
	end

	return state.windows.wrapper_win
end

M.transition_to_content = function()
	local full_width, full_height, full_row = layout.compute_wrapper_dimensions(
		state.windows.opts,
		vim.o.columns,
		layout.editor_height(),
		nil,
		view.min_wrapper_width()
	)
	local wrapper_width = api.nvim_win_get_width(state.windows.wrapper_win)
	if wrapper_width < full_width then
		view.unmount()
		layout.resize(state.windows.wrapper_win, {
			width = full_width,
			height = full_height,
			col = math.floor((vim.o.columns - full_width) / 2),
			row = full_row,
		})
	end
	state.windows.is_landing = false
	-- Clamp against the wrapper, not the raw config: sidebar is the binding constraint
	-- on a narrow wrapper and content.create's subtraction would otherwise go negative.
	wrapper_width = api.nvim_win_get_width(state.windows.wrapper_win)
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

	local mode = MODES[poppy_opts.mode]
	if not mode then
		shared.notify_warn("unknown mode '%s' for poppy '%s'", tostring(poppy_opts.mode), poppy_name)
		return
	end
	local mode_ok = mode.run(poppy_name, poppy_opts, state.windows.content_win)
	if not mode_ok then
		-- Mode rejected: it already dropped the poppy and refreshed the sidebar.
		state.set_current_poppy_name(nil)
		M.recover()
		return
	end

	keymaps.bind_poppy_action(api.nvim_win_get_buf(state.windows.content_win))

	if shared.opts_field("autohide_menu") then
		view.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	else
		view.set_focused(false)
	end

	view.refresh_menu_when_visible()
	-- Park the sidebar cursor on the active poppy so highlight and active dot agree (no-op under autohide).
	local active_index = state.poppy_index(poppy_name)
	if active_index then
		menu.set_row(state.windows.menu_win, active_index)
	end
	shared.focus_content_in_insert()
end

---@param poppy_name string
---@return nil
M.switch_by_name = function(poppy_name)
	if not is_known_poppy(poppy_name) then
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
		return
	end

	-- Rebuild a dead content pane rather than bail (skipped on landing; do_switch creates it).
	local rebuild_content_pane = function()
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

	-- Switch failed mid-flight: sidebar row, focus, and hints were never settled for the target.
	shared.notify_error("switch to '%s' failed: %s", tostring(poppy_name), tostring(err))
	state.set_current_poppy_name(nil)

	-- Cap at one retry: a failing recover() would otherwise re-enter and loop forever.
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
	local name = resolve_poppy_name(index)
	if name then
		M.switch_by_name(name)
	end
end

---@return nil
M.switch_by_cursor = function()
	local idx = cursor_to_poppy_index()
	if idx then
		M.switch_by_index(idx)
	end
end

---@param name string
---@return boolean was_active
local kill_now = function(name)
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
local kill_maybe_confirm = function(name, resume)
	if resume and dialog.needs_confirmation(name) then
		dialog.open(name, resume)
		return
	end
	resume()
end

---@return nil
M.kill_active = function()
	local name = state.windows.current_poppy_name
	if not name then
		return
	end
	kill_maybe_confirm(name, function()
		kill_now(name)
		M.recover()
	end)
end

---@param name string
---@return nil
local kill_live_poppy = function(name)
	if not state.runtime(name) then
		return
	end
	kill_maybe_confirm(name, function()
		if kill_now(name) then
			M.recover()
		elseif shared.session_is_open() and not state.windows.is_landing then
			view.refresh_menu_when_visible()
		end
	end)
end

---@param name string
---@return nil
M.kill_by_name = function(name)
	if not is_known_poppy(name) then
		return
	end
	return kill_live_poppy(name)
end

---@param index integer
---@return nil
M.kill_by_index = function(index)
	local name = resolve_poppy_name(index)
	if name then
		return kill_live_poppy(name)
	end
end

---@return nil
M.kill_by_cursor = function()
	local idx = cursor_to_poppy_index()
	if idx then
		local name = resolve_poppy_name(idx)
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
	for _, configured in ipairs(state.poppies_configured) do
		local rt = state.runtime(configured.name)
		if rt and rt.hidden then
			return configured.name
		end
	end
	return nil
end

-- Caller must hold state.windows.recovering = true: otherwise the WinClosed watcher
-- fires and re-creates the content window.
local recover_goto_landing = function()
	view.unmount()
	shared.close_menu_hint()

	api.nvim_create_augroup("poppy_ui", { clear = true })

	shared.close_win_if_valid(state.windows.content_win)

	local landing_w = layout.landing_width(state.windows.opts, state.poppies_configured, vim.o.columns)
	local landing_spec = menu.spec_poppy_list(menu.LANDING)
	local landing_h = layout.compute(layout.resolve_spec(landing_spec, landing_w)).height
	local _, _, landing_row = layout.compute_wrapper_dimensions(
		state.windows.opts,
		vim.o.columns,
		layout.editor_height(),
		landing_w,
		nil,
		landing_h
	)
	layout.resize(state.windows.wrapper_win, {
		width = landing_w,
		height = landing_h,
		col = math.floor((vim.o.columns - landing_w) / 2),
		row = landing_row,
	})

	enter_landing()
end

M.recover = function()
	state.set_current_poppy_name(nil)
	-- Set synchronously: any WinClosed between here and the scheduled callback
	-- (e.g. the content window closing as part of the kill we're recovering from)
	-- must see the gate, not race the schedule.
	state.windows.recovering = true
	vim.schedule(function()
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

---@return nil
M.goto_landing = function()
	if not shared.session_is_open() then
		return
	end
	state.set_current_poppy_name(nil)
	state.windows.recovering = true
	recover_goto_landing()
	state.windows.recovering = false
end

---@param configured {name: string, config: PoppyResolvedConfig}
---@return PoppySessionEntry
local entry_for = function(configured)
	return {
		name = configured.name,
		config = configured.config,
		runtime_state = state.runtime(configured.name),
	}
end

---@param name string
---@return PoppySessionEntry?
M.get_poppy_by_name = function(name)
	local configured = state.poppy_configured(name)
	if not configured then
		return nil
	end
	return entry_for(configured)
end

---@param index integer
---@return PoppySessionEntry?
M.get_poppy_by_index = function(index)
	local configured = state.poppies_configured[index]
	if not configured then
		return nil
	end
	return entry_for(configured)
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
	return entry_for(configured)
end

---@return PoppySessionEntry[]
M.get_poppies = function()
	local result = {}
	for _, configured in ipairs(state.poppies_configured) do
		result[#result + 1] = entry_for(configured)
	end
	return result
end

return M
