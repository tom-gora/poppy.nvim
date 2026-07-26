local M = {}

-- state.lua has no deps, so the require is safe at module load time.
local state = require("poppy.core.session.state")

-- Display order: exec first, then file, then shell. Cats not in the
-- order fall to the end (sorted by name below).
local CAT_ORDER = { exec = 0, file = 1, shell = 2 }

M.session_is_open = function()
	return state.wrapper_win ~= nil and vim.api.nvim_win_is_valid(state.wrapper_win)
end

M.session_get_current_poppy_name = function()
	return state.current_poppy_name
end

-- Close the bottom-right menu-hint window (if any) and drop the state
-- pointer. The hint lives in session state — not panels state — because
-- hints_panel owns the open+text but the rest of the session owns "is
-- the hint currently showing".
M.close_menu_hint = function()
	if state.menu_hint_win and vim.api.nvim_win_is_valid(state.menu_hint_win) then
		vim.api.nvim_win_close(state.menu_hint_win, true)
	end
	state.menu_hint_win = nil
	state.menu_hint_buf = nil
end

-- Accessors for state.opts fields. The `state.opts and state.opts.X`
-- chain was scattered across 10+ call sites; these centralize the
-- nil-safety and make the call sites read cleanly.
M.keys = function()
	return state.opts and state.opts.keys
end

M.menu_width = function()
	return state.opts and state.opts.menu_width or 25
end

M.term_spawn = function(command, opts)
	if type(command) == "function" then
		command = command()
	end
	if vim.fn.has("nvim-0.11") == 1 then
		opts.term = true
		return vim.fn.jobstart(command, opts)
	else
		---@diagnostic disable-next-line: deprecated
		return vim.fn.termopen(command, opts)
	end
end

M.term_resolve_command = function(poppy_opts)
	if poppy_opts.mode == "term" and poppy_opts.shell then
		local shell = poppy_opts.shell
		if type(shell) == "function" then
			shell = shell()
		end
		return (shell and shell ~= "default") and shell or os.getenv("SHELL") or "bash"
	end
	return poppy_opts.exec
end

M.term_get_or_create_buffer = function(poppy_name, opts, p_state)
	local poppy_opts = opts.poppies_resolved and opts.poppies_resolved[poppy_name]
	if not poppy_opts then
		return nil
	end
	local bufnr = (p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr))
			and p_state.bufnr
		or vim.api.nvim_create_buf(false, false)
	pcall(vim.api.nvim_buf_set_name, bufnr, " Poppy: " .. poppy_name .. " ")
	return bufnr
end

M.cursor_to_poppy_index = function(poppies)
	local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
	if not ok then
		return nil
	end
	local idx = cursor[1]
	local item = poppies[idx]
	if type(item) == "table" and item.name then
		return idx
	end
	return nil
end

M.compute_landing_view_width = function(opts, poppies)
	local max_line = 0
	for i, item in ipairs(poppies) do
		local icon = (opts and opts.icons and opts.icons[M.cat(item.config)]) or " "
		local title = item.config.title or item.name
		local line = string.format(" %s %s %d %s", " ", icon, i, title)
		max_line = math.max(max_line, #line)
	end
	local keys = (opts and opts.keys) or { poppy_action = "<C-_>", select = "<CR>" }
	local hints_text = string.format(" %s Select   %s Toggle Off ", keys.select, keys.poppy_action)
	local hints_len = #hints_text
	return math.max(max_line, hints_len) + 4
end

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

M.title_fallback = function(mode, value)
	if type(value) == "function" then
		value = value()
	end
	if mode == "file" then
		return vim.fs.basename(vim.fn.expand(value))
	end
	-- mode is "term" (the only other resolved mode; "exec" is mapped to it
	-- in config.resolve_poppy and so never reaches here).
	local first_arg = type(value) == "table" and value[1] or vim.split(value, " ")[1]
	return vim.fs.basename(first_arg)
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

return M
