local M = {}

M.calculate_layout = function(popup_opts, opts)
	local width = math.floor(vim.o.columns * (popup_opts.width or opts.width))
	local height = math.floor(vim.o.lines * (popup_opts.height or opts.height))
	local position = popup_opts.position or opts.position or "center"
	local align = popup_opts.align_on_border or opts.align_on_border or "center"
	if align == "centre" then
		align = "center"
	end

	local col = 0
	if position == "left" then
		col = 0
	elseif position == "right" then
		col = vim.o.columns - width
	else -- center
		col = math.floor((vim.o.columns - width) / 2)
	end

	local row = math.floor((vim.o.lines - height) / 2)

	return width, height, row, col, align
end

M.get_win_opts = function(width, height, row, col, popup_opts, opts, align, hide_map, close_map)
	return {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = popup_opts.border or opts.border,
		title = " " .. (popup_opts.title or opts.title) .. " ",
		title_pos = align,
		footer = " " .. string.format("Close: %s | Hide: %s", hide_map, close_map) .. " ",
		footer_pos = align,
	}
end

return M
