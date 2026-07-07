local M = {}
local style = require("poppy.core.ui.style")
local namespace = vim.api.nvim_create_namespace("poppy_list_panel")
local sb_width = 25

M.create = function(wrapper_win, width)
	if width then
		sb_width = width
	end
	local buf = vim.api.nvim_create_buf(false, true)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)

	local config = {
		relative = "win",
		width = sb_width,
		height = wrapper_conf.height,
		col = wrapper_conf.width - sb_width,
		row = 0,
		style = "minimal",
		border = "none",
		zindex = 201,
		focusable = false,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_list_panel_style(win)
	return win, buf
end

local trim_title = function(title, display_idx, width)
	local prefix = string.format(" [%d] ", display_idx)
	local max_title = (width - 1) - #prefix
	if max_title < 4 then
		return ""
	end
	if #title > max_title then
		local trimmed = title:sub(1, max_title - 3)
		local last_space = trimmed:match("^.*()%s+")
		if last_space and last_space > math.floor(max_title * 0.4) then
			trimmed = trimmed:sub(1, last_space - 1)
		end
		trimmed = trimmed:gsub("[^%w]+$", "")
		if #trimmed == 0 then
			trimmed = title:sub(1, max_title - 3):gsub("[^%w]+$", "")
		end
		return trimmed .. " ..."
	end
	return title
end

M.update = function(buf, sorted_poppies, poppies)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

	local lines = { "" }
	local prev_cat = nil
	local display_idx = 0
	local rows = {}

	for _, item in ipairs(sorted_poppies) do
		local cat = item.config.cat or item.config.mode
		if prev_cat and cat ~= prev_cat then
			table.insert(lines, "")
		end
		prev_cat = cat
		display_idx = display_idx + 1
		local title = trim_title(item.config.title or item.name, display_idx, sb_width)
		table.insert(lines, string.format(" [%d] %s", display_idx, title))
		table.insert(rows, { row = #lines - 1, name = item.name })
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	for _, entry in ipairs(rows) do
		local ps = poppies[entry.name]
		local hl = nil
		if ps then
			if ps.active then
				hl = "PoppyActive"
			elseif ps.hidden then
				hl = nil
			end
		else
			hl = "PoppyInactive"
		end
		if hl then
			vim.api.nvim_buf_set_extmark(buf, namespace, entry.row, 0, {
				end_row = entry.row,
				line_hl_group = hl,
			})
		end
	end
end

return M
