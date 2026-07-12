local M = {}
local style = require("poppy.core.ui.style")

local function compute_geometry(poppy_opts, width_override)
	poppy_opts = poppy_opts or {}

	local raw_w = poppy_opts.win_width
	if type(raw_w) == "function" then
		raw_w = raw_w()
	end
	raw_w = raw_w or 0.8

	local width
	if width_override then
		width = width_override
	elseif raw_w > 1 then
		local min_w = math.floor(vim.o.columns / 3)
		if raw_w < min_w then
			vim.notify(string.format("Poppy: win_width %d too small, minimum is %d", raw_w, min_w), vim.log.levels.WARN)
			raw_w = min_w
		elseif raw_w > vim.o.columns then
			vim.notify(
				string.format("Poppy: win_width %d exceeds screen width %d", raw_w, vim.o.columns),
				vim.log.levels.WARN
			)
			raw_w = vim.o.columns
		end
		width = math.floor(raw_w)
	else
		local ratio = math.min(math.max(raw_w, 0.2), 1.0)
		width = math.floor(vim.o.columns * ratio)
	end

	local raw_h = poppy_opts.win_height
	if type(raw_h) == "function" then
		raw_h = raw_h()
	end
	raw_h = raw_h or 0.75

	local height
	if raw_h > 1 then
		local min_h = math.floor(vim.o.lines / 3)
		if raw_h < min_h then
			vim.notify(string.format("Poppy: win_height %d too small, minimum is %d", raw_h, min_h), vim.log.levels.WARN)
			raw_h = min_h
		elseif raw_h > vim.o.lines then
			vim.notify(
				string.format("Poppy: win_height %d exceeds screen height %d", raw_h, vim.o.lines),
				vim.log.levels.WARN
			)
			raw_h = vim.o.lines
		end
		height = math.floor(raw_h)
	else
		local ratio = math.min(math.max(raw_h, 0.2), 1.0)
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

	return width, height, row
end

local function open_with(buf, poppy_opts, width_override)
	local width, height, row = compute_geometry(poppy_opts, width_override)
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
	return win
end

M.create = function(poppy_opts, width_override)
	local buf = vim.api.nvim_create_buf(false, true)
	local win = open_with(buf, poppy_opts, width_override)
	return win, buf
end

M.recreate = function(buf, poppy_opts, width_override)
	return open_with(buf, poppy_opts, width_override)
end

return M
