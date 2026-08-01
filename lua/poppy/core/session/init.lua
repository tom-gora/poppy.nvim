local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local actions = require("poppy.core.session.actions")
local manager = require("poppy.core.session.manager")
local events = require("poppy.core.session.events")
local commands = require("poppy.core.session.commands")
local style = require("poppy.core.ui.style")
local config = require("poppy.config")
local input = require("poppy.core.input")
local util = require("poppy.core.util")

-- Public session API.
M.open = manager.open
M.close = manager.close
M.toggle = manager.toggle
M.toggle_menu = actions.toggle_menu
M.exit_menu = actions.exit_menu
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
M.get_current_poppy_name = util.session_get_current_poppy_name
M.is_open = util.session_is_open

M.setup = function(user_opts)
	state.init()
	style.setup()
	state.opts = config.merge(user_opts)
	poppy_state.rebuild_from_sorted(util.get_sorted_poppies(state.opts))
	input.setup_global(util.keys())
	events.setup(state.opts, { toggle = M.toggle })
	commands.setup(state.opts, {
		toggle = M.toggle,
		open = M.open,
		close = M.close,
		toggle_menu = M.toggle_menu,
	})
end

return M
