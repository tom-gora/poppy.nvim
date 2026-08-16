local M = {}

local state = require("poppy.core.session.state")
local actions = require("poppy.core.session.actions")
local manager = require("poppy.core.session.manager")
local menu = require("poppy.core.session.menu")
local style = require("poppy.core.ui.style")
local config = require("poppy.config")
local shared = require("poppy.core.shared")

local setup_global_key = function()
	---@type vim.api.keyset.keymap
	local toggle_opts = { desc = "Poppy: Toggle UI" }
	vim.keymap.set(shared.NORM_TERM_MODES, shared.keys().poppy_action, function()
		manager.toggle()
	end, toggle_opts)
end

-- Register the :Poppy user command (toggle | close | menu | open [<name>]).
M.setup_command = function(opts, callbacks)
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
	---@type vim.api.keyset.create_user_command
	local cmd_opts = {
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
	}
	vim.api.nvim_create_user_command("Poppy", function(cmd_opts)
		local sub = cmd_opts.fargs[1]
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
		handler(table.concat(cmd_opts.fargs, " ", 2))
	end, cmd_opts)
end

-- Register the autocmd set.
M.setup_autocmds = function(opts, callbacks)
	vim.api.nvim_create_augroup("poppy_group", { clear = true })

	---@type vim.api.keyset.create_autocmd
	local buf_unload_autocmd = {
		group = "poppy_group",
		callback = function(e)
			if not shared.session_is_open() then
				return
			end
			local ok, poppy_name = pcall(vim.api.nvim_buf_get_var, e.buf, "poppy_popup")
			if not ok or not poppy_name or not state.poppies[poppy_name] then
				return
			end

			state.poppies[poppy_name] = nil
			if shared.session_is_open() and state.windows.current_poppy_name == poppy_name then
				actions.recover()
			end
		end,
	}
	vim.api.nvim_create_autocmd("BufUnload", buf_unload_autocmd)

	if opts and opts.menu_autohide then
		---@type vim.api.keyset.create_autocmd
		local cursor_hold_autocmd = {
			group = "poppy_group",
			callback = function()
				if vim.bo.filetype == "poppy_menu" then
					menu.exit_menu()
				end
			end,
		}
		vim.api.nvim_create_autocmd("CursorHold", cursor_hold_autocmd)
	end

	if opts and opts.autoclose then
		---@type vim.api.keyset.create_autocmd
		local autoclose_autocmd = {
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
					-- Internal hop: destination is a poppy window, stay open.
					if require("poppy.core.ui.panels").is_poppy_window(cur) then
						return
					end
					-- Cmdline is exempt: user may be typing :Poppy or any command.
					if vim.fn.win_gettype(cur) == "command" then
						return
					end
					callbacks.toggle()
				end)
			end,
		}
		vim.api.nvim_create_autocmd({ "WinLeave", "TermEnter" }, autoclose_autocmd)
	end
end

M.setup_exclusive_float = function()
	---@type vim.api.keyset.create_autocmd
	local win_enter_autocmd = {
		group = "poppy_group",
		once = true,
		callback = function()
			vim.schedule(function()
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if not vim.api.nvim_win_is_valid(w) or require("poppy.core.ui.panels").is_poppy_window(w) then
						goto continue
					end
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

local init_or_reset_state = function()
	state.windows = state.default_state()
	state.poppies = {}
end

-- Projection: build the public-facing shape for a poppy entry at index i.
local build_poppy_public_data = function(i, entry)
	local name = entry.name
	local runtime = state.poppies[name]
	local opened = runtime ~= nil
	return {
		name = name,
		index = i,
		title = entry.config and entry.config.title or name,
		mode = entry.config and entry.config.mode,
		cat = shared.cat(entry.config or {}),
		is_current = state.windows.current_poppy_name == name,
		active = opened and runtime.active or false,
		hidden = opened and runtime.hidden or false,
		has_been_opened = opened,
		bufnr = opened and runtime.bufnr or nil,
		win = opened and runtime.win or nil,
	}
end

M.get_poppy_by_name = function(name)
	for i = 1, #state.poppies do
		local entry = state.poppies[i]
		if entry and entry.name == name then
			return build_poppy_public_data(i, entry)
		end
	end
	return nil
end

M.get_poppy_by_index = function(index)
	local entry = state.poppies[index]
	if not entry or not entry.name then
		return nil
	end
	return build_poppy_public_data(index, entry)
end

M.get_current_poppy = function()
	local current_name = state.windows.current_poppy_name
	if not current_name then
		return nil
	end
	return M.get_poppy_by_name(current_name)
end

M.get_poppies = function()
	local result = {}
	for i = 1, #state.poppies do
		local entry = state.poppies[i]
		if entry and entry.name then
			result[i] = build_poppy_public_data(i, entry)
		end
	end
	return result
end

-- Public session API surface (re-exported from each module's M).
M.open = manager.open
M.close = manager.close
M.toggle = manager.toggle
M.toggle_menu = menu.toggle_menu
M.exit_menu = menu.exit_menu
M.switch_by_name = actions.switch_by_name
M.switch_by_index = actions.switch_by_index
M.switch_by_cursor = actions.switch_by_cursor
M.kill_active = actions.kill_active
M.kill_by_name = actions.kill_by_name
M.kill_by_index = actions.kill_by_index
M.kill_by_cursor = actions.kill_by_cursor

M.get_current_poppy_name = shared.session_get_current_poppy_name
M.is_open = shared.session_is_open

M.setup = function(user_opts)
	init_or_reset_state()
	style.setup()
	vim.api.nvim_create_augroup("poppy_ui", { clear = true })
	state.windows.opts = config.merge(user_opts)
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
	local sorted = shared.get_sorted_poppies(state.windows.opts)
	for i, v in ipairs(sorted) do
		state.poppies[i] = v
	end
	setup_global_key()
	M.setup_autocmds(state.windows.opts, { toggle = M.toggle })
	M.setup_command(state.windows.opts, {
		toggle = M.toggle,
		open = M.open,
		close = M.close,
		toggle_menu = M.toggle_menu,
	})
end

return M