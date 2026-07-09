local M = {}
local style = require("poppy.core.ui.style")
local namespace = vim.api.nvim_create_namespace("poppy_hints_bar")

M.create = function(wrapper_win)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return M.recreate(wrapper_win, buf), buf
end

M.recreate = function(wrapper_win, buf)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)

	local config = {
		relative = "win",
		width = wrapper_conf.width,
		height = 1,
		col = 0,
		row = wrapper_conf.height - 1,
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

M.update = function(buf, prefix, count, wrapper_width, mode)
	local range = count > 0 and ("[1-%d]"):format(count) or ""

	local segments
	if mode == "landing" then
		segments = {
			{ text = " Switch " .. range .. " ", hl = "HighlightPoppyUIPanel" },
			{ text = " ", hl = nil },
		}
	else
		segments = {
			{ text = " Switch " .. range .. " ", hl = "HighlightPoppyUIPanel" },
			{ text = " ", hl = nil },
			{ text = " Kill k ", hl = "HighlightPoppyUIPanel" },
			{ text = " ", hl = nil },
			{ text = " Hide UI h ", hl = "HighlightPoppyUIPanel" },
			{ text = " ", hl = nil },
		}
	end

	local left_len = 0
	for _, seg in ipairs(segments) do
		left_len = left_len + #seg.text
	end

	local prefix_text = " Poppy Prefix " .. prefix .. " "
	local padding = math.max(1, wrapper_width - left_len - #prefix_text)
	table.insert(segments, { text = string.rep(" ", padding), hl = nil })
	table.insert(segments, { text = prefix_text, hl = "HighlightPoppyUIPanel" })

	local line = {}
	for _, seg in ipairs(segments) do
		table.insert(line, seg.text)
	end
	local line_str = table.concat(line)

	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line_str })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	local col = 0
	for _, seg in ipairs(segments) do
		if seg.hl then
			vim.api.nvim_buf_set_extmark(buf, namespace, 0, col, {
				end_col = col + #seg.text,
				hl_group = seg.hl,
			})
		end
		col = col + #seg.text
	end
end

return M