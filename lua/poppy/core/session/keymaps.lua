---@diagnostic disable: param-type-mismatch
local M = {}

local state = require("poppy.core.session.state")
local panels = require("poppy.core.ui.panels")
local shared = require("poppy.core.shared")

-- Lazy-requires the session facade inside keymap callbacks only. Callbacks
-- fire long after module load, so the facade is already fully loaded by
-- the time these closures run; this avoids a static cycle while keeping
-- the import surface minimal.

M.focus_list_with_cursor = function()
	local list_win = panels.get_list_win()
	if not shared.try_focus_win(list_win) then
		return
	end
	if not state.windows.current_poppy_name then
		return
	end
	local current_entry = state.poppy(state.windows.current_poppy_name)
	if current_entry then
		local idx = state.poppy_index(state.windows.current_poppy_name)
		if idx then
			pcall(vim.api.nvim_win_set_cursor, list_win, { idx, 0 })
		end
	end
end

-- Buffer-local keymaps for the list and content panes. Bound to the
-- buffer because there are multiple windows in the plugin UI and we
-- only want these to fire when the relevant pane is focused.

M.setup_list_keys = function(buf)
	local keys = shared.keys()

	local function opts_for(desc)
		return { buffer = buf, desc = desc }
	end

	vim.keymap.set(shared.NORM_TERM_MODES, keys.select, function()
		local session = require("poppy.core.session")
		if vim.v.count > 0 then
			session.switch_by_index(vim.v.count)
		else
			session.switch_by_cursor()
		end
	end, opts_for("Poppy: Select"))

	vim.keymap.set(shared.NORM_TERM_MODES, keys.kill, function()
		local session = require("poppy.core.session")
		if vim.v.count > 0 then
			session.kill_by_index(vim.v.count)
		else
			session.kill_by_cursor()
		end
	end, opts_for("Poppy: Kill"))

	vim.keymap.set(shared.NORM_TERM_MODES, keys.exit_menu, function()
		local menu = require("poppy.core.session.menu")
		menu.exit_menu()
	end, opts_for("Poppy: Exit menu"))
end

M.setup_content_keys = function(buf)
	local keys = shared.keys()

	local function opts_for(desc)
		return { buffer = buf, desc = desc }
	end

	vim.keymap.set(shared.NORM_TERM_MODES, keys.poppy_action, function()
		local menu = require("poppy.core.session.menu")
		menu.toggle_menu()
	end, opts_for("Poppy: Toggle menu"))
end

return M