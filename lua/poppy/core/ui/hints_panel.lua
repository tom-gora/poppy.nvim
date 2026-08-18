require("poppy._types")

local M = {}
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local namespace = vim.api.nvim_create_namespace("poppy_hints_bar")

local INDENT = "  "
local KEY_COL = 5
local COL_GAP = "  "

---@param key string
---@param label string
---@param indent string
local fmt_hint = function(key, label, indent)
	local padded = key .. string.rep(" ", math.max(0, KEY_COL - #key))
	return indent .. padded .. COL_GAP .. label .. " "
end

-- Each entry is `[config_key, label]`. `config_key` is looked up on `keys`
-- so all four keybindings stay in one place; `label` is the hint text.
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
	menu = ACTIVE,
}

-- Total rendered lines per kind = 1 separator + N hint entries. Single
-- source of truth for the window-height math in panels.lua.
M.HINT_LINES = {
	landing = #HINT_SPECS.landing,
	menu = #HINT_SPECS.menu,
}

---@param wrapper_win integer
---@param opts? PoppyHintOpts
---@return integer? win
---@return integer? buf
M.create = function(wrapper_win, opts)
	opts = opts or {}
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return M.recreate(wrapper_win, buf, opts), buf
end

---@param parent_win integer
---@param keys PoppyKeys
---@return integer? win
---@return integer? buf
M.create_bottom_right = function(parent_win, keys)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false

	local text = " " .. keys.poppy_action .. " Menu "
	local win_conf = vim.api.nvim_win_get_config(parent_win)
	-- Tucked into the bottom-right corner above the content border so it
	-- sits on top of the z stack without overlapping the TUI.
	local row = math.max(0, win_conf.height) + 1
	local col = math.max(0, win_conf.width) + 1

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = #text,
		height = 1,
		col = col,
		row = row,
		anchor = "SE",
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX + 1,
		focusable = false,
		win = parent_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)

	shared.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
	end)

	shared.apply_win_marker(win)

	return win, buf
end

---@param wrapper_win integer
---@param buf integer
---@param opts? PoppyHintOpts
---@return integer? win
M.recreate = function(wrapper_win, buf, opts)
	opts = opts or {}
	local kind = opts.kind or "menu"
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local col = opts.col or wrapper_conf.width
	local row = opts.row or wrapper_conf.height
	local width = opts.width or wrapper_conf.width
	local height = opts.height or M.HINT_LINES[kind]
	if kind == "menu" then
		row = row + 1
	end

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = width,
		height = height + 2,
		col = col,
		row = row,
		anchor = "SE",
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX + 1,
		focusable = false,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)
	shared.apply_win_marker(win)
	return win
end

-- Write the hint lines once. Hints are static (config keys + layout kind);
-- no runtime mutations. Called from panels.lua at mount time only.
---@param buf integer
---@param keys PoppyKeys
---@param kind "landing"|"menu"
---@param wrapper_width integer
---@return nil
M.write_static = function(buf, keys, kind, wrapper_width)
	if not keys then
		return
	end
	local sep = " " .. string.rep("─", math.max(0, wrapper_width - #INDENT - 1)) .. " "
	local spec = HINT_SPECS[kind] or {}

	local lines = { sep }
	local per_line_segments = { { { text = sep, hl = nil } } }

	for _, kp in ipairs(spec) do
		local hint_text = fmt_hint(keys[kp[1]], kp[2], INDENT)
		local left_len = #hint_text
		local padding = math.max(1, wrapper_width - left_len)
		local segments = { { text = hint_text, hl = nil }, { text = string.rep(" ", padding), hl = nil } }
		table.insert(per_line_segments, segments)
		table.insert(lines, hint_text .. string.rep(" ", padding))
	end

	-- Defensive: zero entries -> blank line.
	if #lines == 0 then
		table.insert(lines, "")
		table.insert(per_line_segments, {})
	end
	table.insert(lines, " ")

	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	shared.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)
end

return M
