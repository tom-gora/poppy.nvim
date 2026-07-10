local M = {}
local style = require("poppy.core.ui.style")
local namespace = vim.api.nvim_create_namespace("poppy_hints_bar")

M.create = function(wrapper_win)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return M.recreate(wrapper_win, buf), buf
end

M.recreate = function(wrapper_win, buf, width_override, col_override, row_override, height_override)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local row = row_override or (wrapper_conf.height - 1)
	local col = col_override or 0
	local width = width_override or wrapper_conf.width
	local height = height_override or 1

	local config = {
		relative = "win",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "none",
		zindex = 201,
		focusable = false,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)
	return win
end

M.update = function(buf, keys, count, wrapper_width, mode)
	if not keys then
		return
	end

	local line_specs
	if mode == "landing" then
		line_specs = {
			{
				{ text = " " .. keys.select .. " Select ", hl = "HighlightPoppyUIPanel" },
				{ text = "  ", hl = nil },
				{ text = keys.poppy_action .. " Toggle Off ", hl = "HighlightPoppyUIPanel" },
			},
		}
	elseif mode == "active_sidebar" then
		line_specs = {
			{
				{ text = " " .. keys.poppy_action .. " Menu ", hl = "HighlightPoppyUIPanel" },
			},
		}
	elseif mode == "active_focused" then
		line_specs = {
			{
				{ text = " " .. keys.select .. " Select ", hl = "HighlightPoppyUIPanel" },
				{ text = "  ", hl = nil },
				{ text = keys.kill .. " Kill ", hl = "HighlightPoppyUIPanel" },
			},
			{
				{ text = " " .. keys.dismiss_menu .. " Hide Menu ", hl = "HighlightPoppyUIPanel" },
				{ text = "  ", hl = nil },
				{ text = keys.poppy_action .. " Toggle Off ", hl = "HighlightPoppyUIPanel" },
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