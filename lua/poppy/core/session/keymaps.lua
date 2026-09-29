local M = {}

local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local shared = require("poppy.core.shared")

M.focus_list_with_cursor = function()
	local list_win = view.get_list_win()
	if not shared.try_focus_win(list_win) then
		return
	end
	local name = state.windows.current_poppy_name
	if not name then
		return
	end
	local idx = state.poppy_index(name)
	if not idx then
		return
	end
	pcall(vim.api.nvim_win_set_cursor, list_win, { idx, 0 })
end

---@param buf integer
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

---@param buf integer
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
