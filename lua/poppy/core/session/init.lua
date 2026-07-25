local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local killing = require("poppy.core.session.killing")
local switching = require("poppy.core.session.switching")
local manager = require("poppy.core.session.manager")
local events = require("poppy.core.session.events")
local commands = require("poppy.core.session.commands")
local util = require("poppy.core.util")

-- Public API: thin wrappers to the session submodules.
M.open = manager.open
M.close = manager.close
M.toggle = manager.toggle
M.toggle_menu = switching.toggle_menu
M.exit_menu = switching.exit_menu
M.switch_by_name = switching.switch_by_name
M.switch_by_index = switching.switch_by_index
M.switch_by_cursor = switching.switch_by_cursor
M.kill_active = killing.kill_active
M.kill_by_name = killing.kill_by_name
M.kill_by_index = killing.kill_by_index
M.kill_by_cursor = killing.kill_by_cursor

-- Read-only data getters for users building custom UIs.
M.get_poppies = poppy_state.get_poppies
M.get_poppy_by_name = poppy_state.get_poppy_by_name
M.get_poppy_by_index = poppy_state.get_poppy_by_index
M.get_current_poppy = poppy_state.get_current_poppy
M.get_current_poppy_name = util.session_get_current_poppy_name
M.is_open = util.session_is_open

M.setup = function(user_opts)
	state.init()
	require("poppy.core.ui.style").setup()
	state.opts = require("poppy.config").merge(user_opts)
	poppy_state.rebuild_from_sorted(util.get_sorted_poppies(state.opts))
	require("poppy.core.input").setup_global(state.opts and state.opts.keys)
	events.setup(state.opts, { toggle = M.toggle })
	commands.setup(state.opts, {
		toggle = M.toggle,
		open = M.open,
		close = M.close,
		toggle_menu = M.toggle_menu,
	})
end

return M