local M = {}

local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local config = require("poppy.config")
local keymaps = require("poppy.core.session.keymaps")
local menu = require("poppy.core.session.menu")

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
			local ord_a = CAT_ORDER[shared.cat(a.config)] or 99
			local ord_b = CAT_ORDER[shared.cat(b.config)] or 99
			if ord_a ~= ord_b then
				return ord_a < ord_b
			end
			return a.name < b.name
		end)
	end
	return sorted
end

local setup_global_key = function()
	vim.keymap.set(shared.NORM_TERM_MODES, shared.keys().poppy_action, function()
		M.toggle()
	end, { desc = "Poppy: Toggle UI" })
end

---@param opts PoppyMergedConfig
---@param callbacks table
local setup_command = function(opts, callbacks)
	local sub_handlers = {
		toggle = function() callbacks.toggle() end,
		close = function() callbacks.close() end,
		menu = function() callbacks.toggle_menu() end,
		open = function(name) callbacks.open(name ~= "" and name or nil) end,
	}
	vim.api.nvim_create_user_command("Poppy", function(cmd_args)
		local sub = cmd_args.fargs[1]
		local handler = sub_handlers[sub or "toggle"]
		if not handler then
			vim.notify(
				string.format(
					"Poppy: unknown subcommand '%s' (valid: toggle, close, menu, open [<name>])",
					tostring(sub)
				),
				vim.log.levels.WARN
			)
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
			elseif cmd == nil or rest == "" then
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

---@param opts PoppyMergedConfig
---@param callbacks table
local setup_autocmds = function(opts, callbacks)
	vim.api.nvim_create_augroup("poppy_group", { clear = true })

	vim.api.nvim_create_autocmd("BufUnload", {
		group = "poppy_group",
		callback = function(e)
			if not shared.session_is_open() then
				return
			end
			local ok, poppy_name = pcall(vim.api.nvim_buf_get_var, e.buf, "poppy_popup")
			if not ok or not poppy_name or not state.poppy(poppy_name) then
				return
			end

			local entry = state.poppy(poppy_name)
			entry.runtime_state = nil
			if shared.session_is_open() and state.windows.current_poppy_name == poppy_name then
				M.recover()
			end
		end,
	})

	if opts and opts.menu_autohide then
		vim.api.nvim_create_autocmd("CursorHold", {
			group = "poppy_group",
			callback = function()
				if vim.bo.filetype == "poppy_menu" then
					menu.exit_menu()
				end
			end,
		})
	end

	if opts and opts.autoclose then
		vim.api.nvim_create_autocmd({ "WinLeave", "TermEnter" }, {
			group = "poppy_group",
			callback = function()
				if not shared.session_is_open() then
					return
				end
				-- Defer so nvim_get_current_win() reports the new window.
				vim.schedule(function()
					if not shared.session_is_open() then
						return
					end
					local cur = vim.api.nvim_get_current_win()
					if not vim.api.nvim_win_is_valid(cur) then
						return
					end
					if shared.is_poppy_window(cur) then
						return
					end
					-- Cmdline exempt: user may be typing :Poppy or any command.
					if vim.fn.win_gettype(cur) == "command" then
						return
					end
					callbacks.toggle()
				end)
			end,
		})
	end
end

local init_or_reset_state = function()
	state.windows = state.default_state()
	state.poppies = {}
end

M.setup = function(user_opts)
	init_or_reset_state()
	view.setup_style()
	vim.api.nvim_create_augroup("poppy_ui", { clear = true })
	state.windows.opts = config.merge(user_opts)
	view.define_icon_signs(state.windows.opts.icons)
	if next(state.windows.opts.poppies_resolved or {}) == nil then
		vim.notify(
			"Poppy: no poppies declared in setup({poppies = {...}}); the manager will open empty.",
			vim.log.levels.WARN
		)
	elseif #state.windows.opts.dropped_names > 0 then
		vim.notify(
			string.format(
				"Poppy: %d poppy(s) had no exec/file/shell and were dropped: %s",
				#state.windows.opts.dropped_names,
				table.concat(state.windows.opts.dropped_names, ", ")
			),
			vim.log.levels.WARN
		)
	end
	for _, sorted_entry in ipairs(sort_config(state.windows.opts)) do
		state.poppies[#state.poppies + 1] = {
			name = sorted_entry.name,
			config = sorted_entry.config,
			runtime_state = nil,
		}
	end
	setup_global_key()
	setup_autocmds(state.windows.opts, { toggle = M.toggle })
	setup_command(state.windows.opts, {
		toggle = M.toggle,
		open = M.open,
		close = M.close,
		toggle_menu = menu.toggle_menu,
	})
end

M.get_poppy_by_name = function(name)
	return state.poppy(name)
end

M.get_poppy_by_index = function(index)
	return state.poppies[index]
end

M.get_current_poppy = function()
	local name = state.windows.current_poppy_name
	return name and state.poppy(name) or nil
end

M.get_poppies = function()
	return state.poppies
end

M.get_current_poppy_name = shared.session_get_current_poppy_name
M.is_open = shared.session_is_open

local clear_poppies = function()
	for _, entry in ipairs(state.poppies) do
		local rt = entry.runtime_state
		if rt and rt.bufnr and vim.api.nvim_buf_is_valid(rt.bufnr) then
			vim.api.nvim_buf_delete(rt.bufnr, { force = true })
		end
	end
	state.poppies = {}
end

-- recovering guards the WinClosed watcher from re-firing during teardown.
local cleanup = function(drop_poppies)
	local ok, err = pcall(function()
		if drop_poppies then
			clear_poppies()
		end

		if state.windows.current_poppy_name then
			shared.hide_poppy(state.windows.current_poppy_name)
		end

		local hint_buf = state.windows.menu_hint_buf
		shared.close_menu_hint()

		view.unmount()

		state.windows.recovering = true
		vim.api.nvim_create_augroup("poppy_ui", { clear = true })

		for _, win in ipairs({ state.windows.wrapper_win, state.windows.content_win }) do
			if win and vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end

		state.windows.recovering = false

		local has_running_popies = next(state.poppies) ~= nil
		local buffers = { state.windows.content_buf }
		if not has_running_popies then
			table.insert(buffers, state.windows.wrapper_buf)
			table.insert(buffers, view.get_hints_buf())
			table.insert(buffers, view.get_list_buf())
			local hbuf = view.get_header_buf()
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
	end)
	if not ok then
		vim.notify("Poppy: cleanup failed: " .. tostring(err), vim.log.levels.ERROR)
		state.windows.recovering = false
	end
end

local setup_exclusive_float = function()
	vim.api.nvim_create_autocmd("WinEnter", {
		group = "poppy_group",
		once = true,
		callback = function()
			vim.schedule(function()
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if not vim.api.nvim_win_is_valid(w) or shared.is_poppy_window(w) then
						goto continue
					end
					if vim.api.nvim_win_get_config(w).relative ~= "" then
						vim.api.nvim_win_close(w, true)
					end
					::continue::
				end
			end)
		end,
	})
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
	local win, wbuf = view.wrapper.ensure(state.windows.wrapper_buf, state.windows.opts, width_override)
	state.windows.wrapper_buf = wbuf
	return win
end

---@param poppy_name? string
---@return integer?
M.open = function(poppy_name)
	if not shared.ensure_setup() then return nil end
	if shared.session_is_open() then
		if poppy_name then
			M.switch_by_name(poppy_name)
		end
		return state.windows.wrapper_win
	end

	if shared.opts_field("exclusive_float") then
		setup_exclusive_float()
	end

	local last_poppy = state.windows.current_poppy_name
	local last_entry = last_poppy and state.poppy(last_poppy)
	local has_content = poppy_name or (last_entry and last_entry.runtime_state)
	local should_land = not has_content
	local landing_width = should_land and layout.compute_landing_view_width(state.windows.opts, state.poppies) or nil

	local win = open_wrapper(landing_width)
	state.windows.wrapper_win = win
	state.set_current_poppy_name(nil)
	state.windows.is_landing = should_land

	if has_content then
		M.transition_to_content()
		M.switch_by_name(poppy_name or last_poppy)
		view.refresh_poppies()
	else
		M.enter_landing()
	end

	return state.windows.wrapper_win
end

local cursor_to_poppy_index = function()
	local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
	if not ok then
		return nil
	end
	local idx = cursor[1]
	if not state.poppies[idx] then
		return nil
	end
	return idx
end

---@param name_or_index string|integer|nil
local resolve = function(name_or_index)
	local entry
	if type(name_or_index) == "number" then
		entry = state.poppies[name_or_index]
		if not entry then
			return nil
		end
		name_or_index = entry.name
	end
	if not name_or_index then
		return nil
	end
	local state_entry = state.poppy(name_or_index)
	return { name = name_or_index, runtime = state_entry and state_entry.runtime_state }
end

M.switch_by_name = function(poppy_name)
	if not shared.ensure_setup() then return end
	if poppy_name == state.windows.current_poppy_name then return end
	if not shared.session_is_open() then return end

	local entry = state.poppy(poppy_name)
	if not entry then
		vim.notify(string.format("Poppy: unknown poppy '%s'", tostring(poppy_name)), vim.log.levels.WARN)
		return
	end

	if state.windows.current_poppy_name then
		shared.hide_poppy(state.windows.current_poppy_name)
	end

	if state.windows.is_landing then
		M.transition_to_content()
	end

	local poppy_opts = entry.config
	if state.windows.current_poppy_name and state.windows.current_poppy_name ~= poppy_name then
		state.windows.last_poppy_name = state.windows.current_poppy_name
	end
	state.set_current_poppy_name(poppy_name)

	require("poppy.core.modes." .. poppy_opts.mode).run(poppy_name, poppy_opts, state.windows.content_win)

	keymaps.setup_content_keys(vim.api.nvim_win_get_buf(state.windows.content_win))

	if shared.opts_field("menu_autohide") then
		view.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	else
		view.set_focused(false)
	end

	view.refresh_poppies()
	if
		shared.try_focus_win(state.windows.content_win)
		and vim.bo[vim.api.nvim_win_get_buf(state.windows.content_win)].buftype == "terminal"
	then
		vim.cmd("startinsert")
	end
end

M.switch_by_index = function(index)
	if not shared.ensure_setup() then return end
	local resolved = resolve(index)
	if resolved then
		M.switch_by_name(resolved.name)
	end
end

M.switch_by_cursor = function()
	if not shared.ensure_setup() then return end
	local idx = cursor_to_poppy_index()
	if idx then
		M.switch_by_index(idx)
	end
end

-- Drop the target buffer up-front so any callback recover() schedules lands on clean state.
M.kill_active = function()
	if not shared.ensure_setup() then return end
	if not state.windows.current_poppy_name then
		return
	end
	local target = state.windows.current_poppy_name
	local entry = state.poppy(target)
	local target_rt = entry and entry.runtime_state
	local target_bufnr = target_rt and target_rt.bufnr

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	state.poppy(target).runtime_state = nil
	state.set_current_poppy_name(nil)
	M.recover()
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
	state.poppy(resolved.name).runtime_state = nil

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if shared.session_is_open() and not state.windows.is_landing then
		view.refresh_poppies()
	end
end

M.kill_by_name = function(name)
	if not shared.ensure_setup() then return end
	return _kill(resolve(name))
end

M.kill_by_index = function(index)
	if not shared.ensure_setup() then return end
	return _kill(resolve(index))
end

M.kill_by_cursor = function()
	if not shared.ensure_setup() then return end
	local idx = cursor_to_poppy_index()
	if idx then
		M.kill_by_index(idx)
	end
end

-- Forward-declared so the WinClosed callback can recursively re-arm itself on the replacement content window.
local watch_content_window
watch_content_window = function(win_id, menu_w)
	if not win_id then
		return
	end
	local w = menu_w or 25
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = "poppy_ui",
		callback = function()
			if state.windows.recovering then
				return
			end
			if not shared.session_is_open() then
				return
			end
			local c_win, c_buf = view.content.create(state.windows.wrapper_win, w)
			state.windows.content_win = c_win
			state.windows.content_buf = c_buf
			watch_content_window(c_win, w)
			if state.windows.current_poppy_name then
				M.kill_active()
			else
				M.recover()
			end
		end,
	})
end

M.transition_to_content = function()
	if state.windows.is_landing then
		view.unmount()
		local wc = vim.api.nvim_win_get_config(state.windows.wrapper_win)
		local full_width = layout.compute_wrapper_dimensions(state.windows.opts, vim.o.columns, vim.o.lines)
		vim.api.nvim_win_set_config(state.windows.wrapper_win, {
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
	watch_content_window(c_win, panel_width)
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
	if list_win and vim.api.nvim_win_is_valid(list_win) then
		vim.api.nvim_set_current_win(list_win)
	end
	keymaps.setup_list_keys(list_buf)
	view.refresh_poppies()
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

			local fallback_name = nil
			if state.windows.last_poppy_name then
				local entry = state.poppy(state.windows.last_poppy_name)
				if entry and entry.runtime_state and entry.runtime_state.hidden then
					fallback_name = state.windows.last_poppy_name
				end
			end
			if not fallback_name then
				for _, entry in ipairs(state.poppies_runtime()) do
					if entry.runtime_state and entry.runtime_state.hidden then
						fallback_name = entry.name
						break
					end
				end
			end

			if fallback_name then
				M.switch_by_name(fallback_name)
			else
				view.unmount()
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
			end
		end)
		state.windows.recovering = false
		if not ok then
			vim.notify("Poppy: recover failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end)
end

return M
