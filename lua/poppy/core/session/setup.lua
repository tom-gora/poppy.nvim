local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local actions = require("poppy.core.session.actions")
local manager = require("poppy.core.session.manager")
local menu = require("poppy.core.session.menu")
local style = require("poppy.core.ui.style")
local config = require("poppy.config")
local shared = require("poppy.core.shared")

local setup_global_key = function()
	vim.keymap.set({ "n", "t" }, shared.keys().poppy_action, function()
		manager.toggle()
	end, { desc = "Poppy: Toggle UI" })
end

-- Register the :Poppy user command (toggle | close | menu | open [<name>]).
M.setup_command = function(opts, callbacks)
	local sub_handlers = {
		toggle = function() callbacks.toggle() end,
		close = function() callbacks.close() end,
		menu = function() callbacks.toggle_menu() end,
		open = function(name) callbacks.open(name ~= "" and name or nil) end,
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

-- Register the autocmd set.
M.setup_autocmds = function(opts, callbacks)
	vim.api.nvim_create_augroup("poppy_group", { clear = true })

	vim.api.nvim_create_autocmd("BufUnload", {
		group = "poppy_group",
		callback = function(ctx)
			if not shared.session_is_open() then
				return
			end
			local ok, poppy_name = pcall(vim.api.nvim_buf_get_var, ctx.buf, "poppy_popup")
			if not ok or not poppy_name or not poppy_state.poppies[poppy_name] then
				return
			end

			poppy_state.poppies[poppy_name] = nil
			if shared.session_is_open() and state.current_poppy_name == poppy_name then
				actions.recover()
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
		})
	end
end

M.setup_exclusive_float = function()
	vim.api.nvim_create_autocmd("WinEnter", {
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
	})
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

M.get_poppies = poppy_state.get_poppies
M.get_poppy_by_name = poppy_state.get_poppy_by_name
M.get_poppy_by_index = poppy_state.get_poppy_by_index
M.get_current_poppy = poppy_state.get_current_poppy
M.get_current_poppy_name = shared.session_get_current_poppy_name
M.is_open = shared.session_is_open

M.setup = function(user_opts)
	state.init()
	style.setup()
	state.opts = config.merge(user_opts)
	for k in pairs(poppy_state.poppies) do
		poppy_state.poppies[k] = nil
	end
	local sorted = shared.get_sorted_poppies(state.opts)
	for i, v in ipairs(sorted) do
		poppy_state.poppies[i] = v
	end
	setup_global_key()
	M.setup_autocmds(state.opts, { toggle = M.toggle })
	M.setup_command(state.opts, {
		toggle = M.toggle,
		open = M.open,
		close = M.close,
		toggle_menu = M.toggle_menu,
	})
end

return M