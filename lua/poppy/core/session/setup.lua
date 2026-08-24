local M = {}

local state = require("poppy.core.session.state")
local actions = require("poppy.core.session.actions")
local manager = require("poppy.core.session.manager")
local menu = require("poppy.core.session.menu")
local style = require("poppy.core.ui.style")
local config = require("poppy.config")
local shared = require("poppy.core.shared")

-- Display order: exec first, then file, then shell. Cats not in the
-- order fall to the end (sorted by name below).
local CAT_ORDER = { exec = 0, file = 1, shell = 2 }

-- Inlined from shared.get_sorted_poppies because setup is the only
-- caller. Returns entries as `{name, config}` in display order.
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
	---@type vim.api.keyset.keymap
	local toggle_opts = { desc = "Poppy: Toggle UI" }
	vim.keymap.set(shared.NORM_TERM_MODES, shared.keys().poppy_action, function()
		manager.toggle()
	end, toggle_opts)
end

-- Register the :Poppy user command (toggle | close | menu | open [<name>]).
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
	---@type vim.api.keyset.user_command
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
	end, cmd_opts)
end

-- Register the autocmd set.
local setup_autocmds = function(opts, callbacks)
	vim.api.nvim_create_augroup("poppy_group", { clear = true })

	---@type vim.api.keyset.create_autocmd
	local buf_unload_autocmd = {
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
					if shared.is_poppy_window(cur) then
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

local init_or_reset_state = function()
	state.windows = state.default_state()
	state.poppies = {}
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
	style.define_icon_signs(state.windows.opts.icons)
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
		toggle_menu = M.toggle_menu,
	})
end

return M
