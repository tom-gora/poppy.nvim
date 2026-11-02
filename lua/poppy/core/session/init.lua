require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.mount")
local shared = require("poppy.core.shared")
local config = require("poppy.config")
local autocommands = require("poppy.core.session.autocommands")
local menu = require("poppy.core.session.menu")
local manager = require("poppy.core.session.manager")

local CATEGORY_ORDER = { exec = 0, file = 1, shell = 2 }

---@param opts PoppyMergedConfig
---@return {name: string, config: PoppyResolvedConfig}[]
local sort_config = function(opts)
	local sorted = {}
	for name, p_resolved in pairs(opts.poppies_resolved) do
		table.insert(sorted, { name = name, config = p_resolved })
	end
	table.sort(sorted, function(a, b)
		local ord_a = CATEGORY_ORDER[a.config.mode] or 99
		local ord_b = CATEGORY_ORDER[b.config.mode] or 99
		if ord_a ~= ord_b then
			return ord_a < ord_b
		end
		return a.name < b.name
	end)
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
	-- A trapped dialog blocks manager.close(), so its transient buffer would be
	-- orphaned by the reset. Release it before the state is dropped.
	local dialog = require("poppy.core.session.dialog")
	if dialog.trapped() then
		dialog.force_release()
	end
	state.windows = state.default_state()
	state.poppies_configured = {}
	state.poppies_runtime = {}
end

local teardown_live_session = function()
	if state.windows.opts and shared.session_is_open() then
		manager.close()
	end
end

---Lazy bootstrap used by lazy API stubs. Runs setup({}) if no config has been set,
---landing the plugin in the empty/misconfigured state. Subsequent open attempts warn.
M.ensure_loaded = function()
	if not state.windows.opts then
		M.setup({})
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
	if #state.windows.opts.dropped_names > 0 then
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

for _, name in ipairs({
	"open",
	"close",
	"toggle",
	"transition_to_content",
	"recover",
	"switch_by_name",
	"switch_by_index",
	"switch_by_cursor",
	"kill_active",
	"kill_by_name",
	"kill_by_index",
	"kill_by_cursor",
	"get_poppy_by_name",
	"get_poppy_by_index",
	"get_current_poppy",
	"get_poppies",
}) do
	M[name] = manager[name]
end
M.get_current_poppy_name = shared.session_get_current_poppy_name
M.is_open = shared.session_is_open

return M
