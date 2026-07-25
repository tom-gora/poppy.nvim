local M = {}

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
		local cat_order = { exec = 0, file = 1, shell = 2 }
		table.sort(sorted, function(a, b)
			local cat_a = cat_order[M.cat(a.config)] or 99
			local cat_b = cat_order[M.cat(b.config)] or 99
			if cat_a ~= cat_b then
				return cat_a < cat_b
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
	elseif mode == "exec" then
		if type(value) == "table" then
			return vim.fs.basename(value[1])
		end
		return vim.fs.basename(vim.split(value, " ")[1])
	elseif mode == "term" then
		if type(value) == "table" then
			return vim.fs.basename(value[1])
		end
		return vim.fs.basename(vim.split(value, " ")[1])
	end
	return "POPPY"
end

M.is_open = function(wrapper_win)
	return wrapper_win ~= nil and vim.api.nvim_win_is_valid(wrapper_win)
end

-- Derive the user-facing category ("exec" | "file" | "shell") from the
-- raw poppy config. Exactly one of `exec`, `file`, `shell` is set per
-- the validation in resolve_poppy, so the first truthy field wins.
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
