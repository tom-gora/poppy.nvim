require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local shared = require("poppy.core.shared")
local config = require("poppy.config")
local autocommands = require("poppy.core.session.autocommands")
local menu = require("poppy.core.session.menu")
local manager = require("poppy.core.session.manager")

local CATEGORY_ORDER = { exec = 0, file = 1, shell = 2 }

---@param opts? PoppyMergedConfig
---@return {name: string, config: PoppyResolvedConfig}[]
local sort_config = function(opts)
	local sorted = {}
	if opts and opts.poppies_resolved then
		for name, p_resolved in pairs(opts.poppies_resolved) do
			table.insert(sorted, { name = name, config = p_resolved })
		end
		table.sort(sorted, function(a, b)
			local ord_a = CATEGORY_ORDER[shared.category_from_resolved(a.config)] or 99
			local ord_b = CATEGORY_ORDER[shared.category_from_resolved(b.config)] or 99
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
	local bound, _ = shared.resolve_key(keys.poppy_action)
	vim.keymap.set(shared.NORM_TERM_MODES, bound, function()
		manager.toggle()
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

-- Tearing down through manager.close() keeps one teardown path. The opts check keeps a
-- first call silent: manager.close would otherwise trip ensure_setup's "must be called first".
local teardown_live_session = function()
	if state.windows.opts and shared.session_is_open() then
		manager.close()
	end
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
		toggle = manager.toggle,
		open = manager.open,
		close = manager.close,
		toggle_menu = menu.toggle_menu,
	})
end

M.open = manager.open
M.close = manager.close
M.toggle = manager.toggle
M.transition_to_content = manager.transition_to_content
M.recover = manager.recover

M.switch_by_name = manager.switch_by_name
M.switch_by_index = manager.switch_by_index
M.switch_by_cursor = manager.switch_by_cursor

M.kill_active = manager.kill_active
M.kill_by_name = manager.kill_by_name
M.kill_by_index = manager.kill_by_index
M.kill_by_cursor = manager.kill_by_cursor

M.get_poppy_by_name = manager.get_poppy_by_name
M.get_poppy_by_index = manager.get_poppy_by_index
M.get_current_poppy = manager.get_current_poppy
M.get_poppies = manager.get_poppies
M.get_current_poppy_name = shared.session_get_current_poppy_name
M.is_open = shared.session_is_open

return M
