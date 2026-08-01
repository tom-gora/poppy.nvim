local M = {}
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local util = require("poppy.core.util")
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

-- Each entry is `[config_key, label]`. `config_key` is looked up on
-- `keys` (so all four keybindings stay in one place); `label` is the
-- hint text shown to the user.
local ACTIVE = {
	{ "select", "Select" },
	{ "kill", "Kill" },
	{ "exit_menu", "Exit menu" },
	{ "poppy_action", "Toggle off" },
}
local HINT_SPECS = {
	landing = {
		{ "select", "Select" },
		{ "poppy_action", "Toggle Off" },
	},
	active_menu = ACTIVE,
	active_focused = ACTIVE,
}

M.create = function(wrapper_win, opts)
	opts = opts or {}
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return M.recreate(wrapper_win, buf, opts), buf
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
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
		win = parent_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)

	util.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
	end)

	vim.api.nvim_win_set_var(win, "poppy_ui_window", true)

	return win, buf
end

M.recreate = function(wrapper_win, buf, opts)
	opts = opts or {}
	local kind = opts.kind or "menu"
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local row = opts.row or (wrapper_conf.height + ROW_OFFSET[kind])
	local col = opts.col or wrapper_conf.width
	local width = opts.width or wrapper_conf.width
	local height = opts.height or CONTENT_HEIGHT[kind]

	local config = {
		relative = "win",
		width = width,
		height = height + PADDING[kind],
		col = col,
		row = row,
		anchor = "SE",
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)
	vim.api.nvim_win_set_var(win, "poppy_ui_window", true)
	return win
end

M.update = function(buf, keys, count, wrapper_width, kind, mode)
	if not keys then
		return
	end
	kind = kind or "menu"
	local sep = INDENT .. string.rep("─", math.max(0, wrapper_width - #INDENT - 1)) .. " "
	local spec = HINT_SPECS[kind == "landing" and "landing" or mode] or {}

	local line_specs = { { { text = sep, hl = nil } } }
	for _, kp in ipairs(spec) do
		table.insert(line_specs, { { text = fmt_hint(keys[kp[1]], kp[2]), hl = nil } })
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
	util.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)

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
