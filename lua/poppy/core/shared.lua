local M = {}

-- state.lua has no deps, so the require is safe at module load time.
local state = require("poppy.core.session.state")

-- Display order: exec first, then file, then shell. Cats not in the
-- order fall to the end (sorted by name below).
local CAT_ORDER = { exec = 0, file = 1, shell = 2 }

M.try_focus_win = function(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		return true
	end
	return false
end

M.session_is_open = function()
	return state.windows.wrapper_win ~= nil and vim.api.nvim_win_is_valid(state.windows.wrapper_win)
end

M.session_get_current_poppy_name = function()
	return state.windows.current_poppy_name
end

---@param name string
M.hide_poppy = function(name)
	local entry = state.poppies[name]
	local runtime = entry and entry.runtime_state
	if not runtime then
		return
	end
	runtime.active = false
	runtime.hidden = true
	runtime.win = nil
end

-- Pair: open or refresh the bottom-right menu-hint window. Lazy-requires
-- hints_panel to avoid a load-time cycle (hints_panel imports shared).
-- Closes any previous hint first to prevent orphaned windows accumulating
-- across switch operations.
M.show_menu_hint = function()
	M.close_menu_hint()
	local content_win = state.windows.content_win
	if content_win and vim.api.nvim_win_is_valid(content_win) then
		local hints_panel = require("poppy.core.ui.hints_panel")
		state.windows.menu_hint_win, state.windows.menu_hint_buf =
			hints_panel.create_bottom_right(content_win, M.keys())
	end
end

-- Close the bottom-right menu-hint window (if any) and drop the state
-- pointer. The hint lives in session state — not panels state — because
-- hints_panel owns the open+text but the rest of the session owns "is
-- the hint currently showing".
M.close_menu_hint = function()
	if state.windows.menu_hint_win and vim.api.nvim_win_is_valid(state.windows.menu_hint_win) then
		vim.api.nvim_win_close(state.windows.menu_hint_win, true)
	end
	state.windows.menu_hint_win = nil
	state.windows.menu_hint_buf = nil
end

-- Accessors for state.windows.opts fields. The `state.windows.opts and state.windows.opts.X`
-- chain was scattered across 10+ call sites; these centralize the
-- nil-safety and make the call sites read cleanly.
M.keys = function()
	return state.windows.opts and state.windows.opts.keys
end

M.with_modifiable = function(buf, fn)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	fn()
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

---@type string[]
M.NORM_TERM_MODES = { "n", "t" }

M.get_sorted_poppies = function(opts)
	local sorted = {}
	if opts and opts.poppies_resolved then
		for name, p_resolved in pairs(opts.poppies_resolved) do
			table.insert(sorted, { name = name, config = p_resolved })
		end
		table.sort(sorted, function(a, b)
			local ord_a = CAT_ORDER[M.cat(a.config)] or 99
			local ord_b = CAT_ORDER[M.cat(b.config)] or 99
			if ord_a ~= ord_b then
				return ord_a < ord_b
			end
			return a.name < b.name
		end)
	end
	return sorted
end

-- User-facing category from raw poppy config. Validation in
-- resolve_poppy guarantees exactly one of exec/file/shell is set.
M.cat = function(poppy)
	if poppy.exec then
		return "exec"
	elseif poppy.file then
		return "file"
	else
		return "shell"
	end
end

local WIN_MARKER = "poppy_window"

---@param win integer
---@return void
M.apply_win_marker = function(win)
	vim.api.nvim_win_set_var(win, WIN_MARKER, true)
end

---@param win integer|nil
---@return boolean
M.is_poppy_window = function(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	local _, val = pcall(vim.api.nvim_win_get_var, win, WIN_MARKER)
	return val == true
end

return M
