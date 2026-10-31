require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")

local MULTIPLEXER_FALLBACKS = {
	["<C-/>"] = "<C-_>",
}

local in_multiplexer = function()
	return os.getenv("TMUX") ~= nil or os.getenv("STY") ~= nil
end

---@param user_value string
---@return string bound
---@return string display
M.resolve_key = function(user_value)
	local fallback = MULTIPLEXER_FALLBACKS[user_value]
	if not fallback then
		return user_value, user_value
	end
	local assume = state.windows.opts and state.windows.opts.assume_multiplexer == true
	if not assume and not in_multiplexer() then
		return user_value, user_value
	end
	return fallback, user_value
end

-- <C-i>/<C-m>/<C-?> share a byte with a non-ctrl key; binding the aliased form collides
-- with that key. <C-[> is excluded: the kitty protocol distinguishes it from <Esc>.
local ALIASED_KEYS = {
	["<C-i>"] = "<Tab>",
	["<C-m>"] = "<CR>",
	["<C-?>"] = "<BS>",
}

---@param key string
---@return string? alias The key this collides with, or nil if it's not aliased.
M.key_alias = function(key)
	return ALIASED_KEYS[key]
end

-- Always-on keys on the menu/list/dialog buffer, independent of the user's config.
-- Completions-style: <C-y> accepts, <C-e> aborts, <C-x> cancels the pending action.
M.PERMANENT_KEYS = {
	select = "<C-y>",
	exit_menu = "<C-e>",
	kill = "<C-x>",
}

---@param field string A PoppyKeys field name.
---@return string? key
M.permanent_key = function(field)
	return M.PERMANENT_KEYS[field]
end

---@param win integer|nil
---@return boolean
M.try_focus_win = function(win)
	if win and api.nvim_win_is_valid(win) then
		api.nvim_set_current_win(win)
		return true
	end
	return false
end

---Close a window if it's currently valid. No-op for nil or already-closed handles.
---@param win integer|nil
M.close_win_if_valid = function(win)
	if win and api.nvim_win_is_valid(win) then
		api.nvim_win_close(win, true)
	end
end

---Focus the content pane and enter insert mode if it shows a terminal buffer.
M.focus_content_in_insert = function()
	if not M.try_focus_win(state.windows.content_win) then
		return
	end
	local cbuf = api.nvim_win_get_buf(state.windows.content_win)
	if vim.bo[cbuf].buftype == "terminal" then
		vim.cmd("startinsert")
	end
end

---@return boolean
M.session_is_open = function()
	return state.windows.wrapper_win ~= nil and api.nvim_win_is_valid(state.windows.wrapper_win)
end

---@return string|nil
M.session_get_current_poppy_name = function()
	return state.windows.current_poppy_name
end

---@param name string
M.hide_poppy = function(name)
	local runtime = state.runtime(name)
	if not runtime then
		return
	end
	runtime.active = false
	runtime.hidden = true
	runtime.win = nil
end

-- Closes any previous hint first; otherwise orphans accumulate across switches.
M.show_menu_hint = function()
	M.close_menu_hint()
	local content_win = state.windows.content_win
	if content_win and api.nvim_win_is_valid(content_win) then
		local render = require("poppy.core.ui.render")
		state.windows.menu_hint_win, state.windows.menu_hint_buf =
			render.hints.create_bottom_right(content_win, M.keys())
	end
end

M.close_menu_hint = function()
	M.close_win_if_valid(state.windows.menu_hint_win)
	state.windows.menu_hint_win = nil
	state.windows.menu_hint_buf = nil
end

---@return PoppyKeys?
M.keys = function()
	return state.windows.opts and state.windows.opts.keys
end

---@param field string
---@return any
M.opts_field = function(field)
	if not state.windows.opts then
		return nil
	end
	return state.windows.opts[field]
end

---@param buf integer
---@param apply fun()
M.with_modifiable = function(buf, apply)
	api.nvim_set_option_value("modifiable", true, { buf = buf })
	local ok, err = xpcall(apply, debug.traceback)
	-- If apply() died because the buffer was deleted, the second set_option raises "Invalid buffer id".
	pcall(api.nvim_set_option_value, "modifiable", false, { buf = buf })
	if not ok then
		error(err, 0)
	end
end

---@type string[]
M.NORM_TERM_MODES = { "n", "t" }

---First whitespace-delimited token of a string, or the first element of a string list.
---Nil when there is no token at all (empty or whitespace-only).
---@param command string|string[]|function|nil
---@return string?
M.argv0 = function(command)
	if type(command) == "string" then
		return command:match("^%s*(%S+)")
	end
	if type(command) == "table" and #command > 0 and type(command[1]) == "string" then
		return command[1]:match("^%s*(%S+)")
	end
	return nil
end

---@return string
M.default_shell = function()
	return os.getenv("SHELL") or "bash"
end

---Resolve a `file` field to an absolute path. `raw` may be a string, a function, or nil.
---Returns empty string if the value is nil/empty/non-string.
---@param raw string|function|nil
---@return string
M.expand_file_value = function(raw)
	if type(raw) == "function" then
		raw = raw()
	end
	if type(raw) ~= "string" or raw == "" then
		return ""
	end
	return vim.fn.expand(raw)
end

---@return boolean
M.use_borders = function()
	return state.windows.opts and state.windows.opts.use_borders or false
end

local insets_cache_opts, insets_cache_value
---Insets derived from use_borders(). Memoized on opts reference identity:
---a fresh setup() (which assigns a new opts table) forces recompute.
---@return { inset: integer, inset_inv: integer }
M.get_insets = function()
	local opts = state.windows.opts
	if opts ~= insets_cache_opts then
		local inset = opts and opts.use_borders and 1 or 0
		insets_cache_opts = opts
		insets_cache_value = { inset = inset, inset_inv = inset == 0 and 1 or 0 }
	end
	return insets_cache_value
end

---@param template string
---@param ... any
M.notify_warn = function(template, ...)
	vim.notify("Poppy: " .. string.format(template, ...), vim.log.levels.WARN)
end

---@param template string
---@param ... any
M.notify_error = function(template, ...)
	vim.notify("Poppy: " .. string.format(template, ...), vim.log.levels.ERROR)
end

-- Skip if the buffer is a live file (file mode reuses content_buf) or in active use
-- (poppy owns it / a window is showing it). The buftype check is the safety.
---@param buf integer|nil
---@return boolean dropped
M.drop_scratch_buffer = function(buf)
	if not buf or not api.nvim_buf_is_valid(buf) then
		return false
	end
	if vim.bo[buf].buftype ~= "nofile" then
		return false
	end
	for _, rt in pairs(state.poppies_runtime) do
		if rt and rt.bufnr == buf then
			return false
		end
	end
	for _, win in ipairs(api.nvim_list_wins()) do
		if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
			return false
		end
	end
	api.nvim_buf_delete(buf, { force = true })
	return true
end

local WIN_MARKER = "poppy_window"

---@param win integer
M.apply_win_marker = function(win)
	api.nvim_win_set_var(win, WIN_MARKER, true)
end

---@param win integer|nil
---@return boolean
M.is_poppy_window = function(win)
	if not win or not api.nvim_win_is_valid(win) then
		return false
	end
	local _, val = pcall(api.nvim_win_get_var, win, WIN_MARKER)
	return val == true
end

---Keep insert mode out of a buffer that cannot be edited.
---Scoped to the buffer, so unrelated windows never trigger it.
---@param buf integer
M.guard_insert_mode = function(buf)
	local group = api.nvim_create_augroup("no_insert_mode_in_menus_guard_group", { clear = false })
	api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		buffer = buf,
		callback = function()
			vim.cmd("stopinsert")
		end,
	})
end

---@param name string
---@param reason? string
---@return boolean was_active
M.drop_poppy = function(name, reason)
	for i, entry in ipairs(state.poppies_configured) do
		if entry.name == name then
			table.remove(state.poppies_configured, i)
			break
		end
	end
	state.poppies_runtime[name] = nil
	if state.windows.opts then
		state.windows.opts.poppies[name] = nil
		state.windows.opts.poppies_resolved[name] = nil
		table.insert(state.windows.opts.dropped_names, name)
	end
	local was_active = state.windows.current_poppy_name == name
	if was_active then
		state.windows.current_poppy_name = nil
	end
	if state.windows.last_poppy_name == name then
		state.windows.last_poppy_name = nil
	end
	if reason then
		M.notify_warn("dropped poppy '%s': %s", name, reason)
	end
	if M.session_is_open() then
		local view = require("poppy.core.ui.view")
		view.refresh_menu_when_visible()
	end
	return was_active
end

return M
