local M = {}
local style = require("poppy.core.ui.style")

M.create = function(poppy_opts, width_override)
	poppy_opts = poppy_opts or {}

	local raw = poppy_opts.win_width
	if type(raw) == "function" then
		raw = raw()
	end
	raw = raw or 0.8

	local width
	if width_override then
		width = width_override
	elseif raw > 1 then
		local min_w = math.floor(vim.o.columns / 3)
		if raw < min_w then
			vim.notify(string.format("Poppy: win_width %d too small, minimum is %d", raw, min_w), vim.log.levels.WARN)
			raw = min_w
		elseif raw > vim.o.columns then
			vim.notify(
				string.format("Poppy: win_width %d exceeds screen width %d", raw, vim.o.columns),
				vim.log.levels.WARN
			)
			raw = vim.o.columns
		end
		width = math.floor(raw)
	else
		local ratio = math.min(math.max(raw, 0.2), 1.0)
		width = math.floor(vim.o.columns * ratio)
	end

	local raw = poppy_opts.win_height
	if type(raw) == "function" then
		raw = raw()
	end
	raw = raw or 0.75

	local height
	if raw > 1 then
		local min_h = math.floor(vim.o.lines / 3)
		if raw < min_h then
			vim.notify(string.format("Poppy: win_height %d too small, minimum is %d", raw, min_h), vim.log.levels.WARN)
			raw = min_h
		elseif raw > vim.o.lines then
			vim.notify(
				string.format("Poppy: win_height %d exceeds screen height %d", raw, vim.o.lines),
				vim.log.levels.WARN
			)
			raw = vim.o.lines
		end
		height = math.floor(raw)
	else
		local ratio = math.min(math.max(raw, 0.2), 1.0)
		height = math.floor(vim.o.lines * ratio)
	end

	local location = poppy_opts.win_location or "center"
	local row
	if location == "top" then
		row = 0
	elseif location == "bottom" then
		row = vim.o.lines - height
	else
		row = math.floor((vim.o.lines - height) / 2)
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = row,
		style = "minimal",
		border = "none",
		zindex = 200,
		focusable = false,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_border_style(win)
	return win, buf
end

return M
