local M = {}

M.create = function(opts)
	local width = opts.width or math.floor(vim.o.columns - 2)
	local height = opts.height or math.floor(vim.o.lines * 0.75)

	-- The wrapper window itself doesn't need a buffer, or it can have an empty one
	local buf = vim.api.nvim_create_buf(false, true)
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = (vim.o.columns - width) / 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = "rounded",
		zindex = 200,
		focusable = false, -- It's just a wrapper
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	return win, buf
end

return M
