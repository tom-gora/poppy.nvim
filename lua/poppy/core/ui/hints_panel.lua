local M = {}
local style = require("poppy.core.ui.style")
local namespace = vim.api.nvim_create_namespace("poppy_hints_bar")

local PADDING = { landing = 1, menu = 3 }
local ROW_OFFSET = { landing = 0, menu = -1 }
local CONTENT_HEIGHT = { landing = 3, menu = 4 }
local INDENT = "  "
local KEY_COL = 5
local COL_GAP = "  "

local fmt_hint = function(key, label)
	local padded = key .. string.rep(" ", math.max(0, KEY_COL - #key))
	return INDENT .. padded .. COL_GAP .. label .. " "
end

M.create = function(wrapper_win, layout)
	layout = layout or "menu"
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return M.recreate(wrapper_win, buf, nil, nil, nil, nil, layout), buf
end

M.create_bottom_right = function(parent_win, keys)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false

	local text = " " .. keys.poppy_action .. " Menu "
	local pw = vim.api.nvim_win_get_config(parent_win)
	local row = math.max(0, pw.height)
	local col = math.max(0, pw.width + 1)

	local config = {
		relative = "win",
		width = #text,
		height = 1,
		col = col,
		row = row,
		anchor = "NE",
		style = "minimal",
		border = "none",
		zindex = 204,
		focusable = false,
		win = parent_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	return win, buf
end

M.recreate = function(wrapper_win, buf, width_override, col_override, row_override, height_override, layout)
	layout = layout or "menu"
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local row = row_override or (wrapper_conf.height + ROW_OFFSET[layout])
	local col = col_override or wrapper_conf.width
	local width = width_override or wrapper_conf.width
	local height = height_override or CONTENT_HEIGHT[layout]

	local config = {
		relative = "win",
		width = width,
		height = height + PADDING[layout],
		col = col,
		row = row,
		anchor = "SE",
		style = "minimal",
		border = "none",
		zindex = 203,
		focusable = false,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)
	return win
end

M.update = function(buf, keys, count, wrapper_width, layout, mode)
	if not keys then
		return
	end
	layout = layout or "menu"
	local sep = INDENT .. string.rep("─", math.max(0, wrapper_width - #INDENT - 1)) .. " "
	local line_specs
	if layout == "landing" then
		line_specs = {
			{
				{ text = sep, hl = nil },
			},
			{
				{ text = fmt_hint(keys.select, "Select"), hl = nil },
			},
			{
				{ text = fmt_hint(keys.poppy_action, "Toggle Off"), hl = nil },
			},
		}
	elseif mode == "active_menu" or mode == "active_focused" then
		line_specs = {
			{
				{ text = sep, hl = nil },
			},
			{
				{ text = fmt_hint(keys.select, "Select"), hl = nil },
			},
			{
				{ text = fmt_hint(keys.kill, "Kill"), hl = nil },
			},
			{
				{ text = fmt_hint(keys.exit_menu, "Exit menu"), hl = nil },
			},
			{
				{ text = fmt_hint(keys.poppy_action, "Toggle off"), hl = nil },
			},
		}
	else
		line_specs = {}
	end

	local lines = {}
	local per_line_segments = {}

	for line_idx, segments in ipairs(line_specs) do
		local left_len = 0
		for _, seg in ipairs(segments) do
			left_len = left_len + #seg.text
		end
		local padding = math.max(1, wrapper_width - left_len)
		table.insert(segments, { text = string.rep(" ", padding), hl = nil })

		local line = {}
		for _, seg in ipairs(segments) do
			table.insert(line, seg.text)
		end
		table.insert(lines, table.concat(line))
		table.insert(per_line_segments, segments)
	end

	if #lines == 0 then
		table.insert(lines, "")
		table.insert(per_line_segments, {})
	end

	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	for line_idx, segments in ipairs(per_line_segments) do
		local col = 0
		for _, seg in ipairs(segments) do
			if seg.hl then
				vim.api.nvim_buf_set_extmark(buf, namespace, line_idx - 1, col, {
					end_col = col + #seg.text,
					hl_group = seg.hl,
				})
			end
			col = col + #seg.text
		end
	end
end

return M
