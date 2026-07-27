---@diagnostic disable duplicate-doc-field
---@class PoppyConfig
---@field keys? table<string, string> # Keybindings: poppy_action, select, kill, exit_menu. Default: { poppy_action = "<C-_>", select = "<CR>", kill = "d", exit_menu = "<Esc>" }
---@field icons? table<string, string> # Icons per poppy type: exec, shell, file. Default: { exec = "🛠", shell = "$", file = "🗋" }
---@field menu_autohide? boolean # If true, hide sidebar style menu after selecting a poppy. Default: false
---@field title_header? boolean # Show "POPPY" header panel above list. Default: true
---@field autoclose? boolean # Close the manager when focus leaves all poppy windows. Default: true
---@field exclusive_float? boolean # When poppy opens close all other floating windows
---@field menu_width? number # Width of side panels. Default: 25
---@field win_height? number|function # Height ratio of screen (0.2-1.0), or absolute pixels (>1), or function returning same. Default: 0.75
---@field win_width? number|function # Width ratio of screen (0.2-1.0), or absolute pixels (>1), or function returning same. Default: 0.8
---@field win_location? "center"|"top"|"bottom" # Vertical position of the wrapper. Default: "center"
---@field poppies? table<string, PoppyItemConfig>
---
---@class PoppyItemConfig
---@field exec? string|string[]
---@field file? string
---@field shell? string|function
---@field title? string
---

local M = {}

local layout = require("poppy.core.ui.layout")
local util = require("poppy.core.util")

local DEFAULT_KEYS = { "poppy_action", "select", "kill", "exit_menu" }
local DEFAULT_ICONS = { "exec", "shell", "file" }

-- Pick non-empty strings from `user` for each name in `keys`, falling
-- back to `defaults`. Used to validate config string fields typed by the
-- user (keybindings, icons). Empty strings, nil, and wrong types are
-- all replaced with the default. When `max_display_width` is set, the
-- value's display width must also fit (icons get 2 to allow a single
-- 2-cell nerdfont glyph; longer nerd-font glyphs would break layout).
local sanitize_string_fields = function(defaults, user, keys, max_display_width)
	local out = {}
	for _, k in ipairs(keys) do
		local v = (type(user) == "table") and user[k] or nil
		local valid = type(v) == "string" and v ~= ""
		if valid and max_display_width then
			valid = vim.fn.strdisplaywidth(v) <= max_display_width
		end
		out[k] = valid and v or defaults[k]
	end
	return out
end

local default_opts = {
	keys = { poppy_action = "<C-_>", select = "<CR>", kill = "d", exit_menu = "<Esc>" },
	icons = { exec = "🛠", shell = "$", file = "🗋" },
	menu_autohide = false,
	title_header = true,
	autoclose = true,
	exclusive_float = true,
	menu_width = 25,
	win_height = 0.75,
	win_width = 0.8,
	win_location = "center",
}

-- Returns nil on validation error (and notifies). Never mutates the input.
local resolve_poppy = function(name, poppy)
	if not poppy then
		return nil
	end

	local mode
	if poppy.exec then
		mode = "term"
	elseif poppy.file then
		mode = "file"
	elseif poppy.shell then
		mode = "term"
	else
		vim.notify(
			"Poppy: Poppy '" .. name .. "' must have exactly one of 'exec', 'file', or 'shell'.",
			vim.log.levels.ERROR
		)
		return nil
	end

	local title = poppy.title
	if not title then
		title = util.title_fallback(mode, poppy.exec or poppy.file or poppy.shell or os.getenv("SHELL") or "shell")
	end

	-- `cat` is derived at use sites via util.cat(poppy).
	return {
		exec = poppy.exec,
		file = poppy.file,
		shell = poppy.shell,
		mode = mode,
		title = title,
	}
end

-- User input is never mutated: keys/icons are copied into fresh tables,
-- poppies is referenced, and a parallel `poppies_resolved` map carries
-- engine-internal mode/title.
M.merge = function(user_opts)
	local user = user_opts or {}
	-- Leading `{}` keeps default_opts and user untouched.
	local merged = vim.tbl_deep_extend("force", {}, default_opts, user)

	local keys = sanitize_string_fields(default_opts.keys, merged.keys, DEFAULT_KEYS)
	local icons = sanitize_string_fields(default_opts.icons, merged.icons, DEFAULT_ICONS, 2)

	local valid_locations = { center = true, top = true, bottom = true }
	local win_location = merged.win_location
	if not valid_locations[win_location] then
		vim.notify(
			"Poppy: Invalid win_location '" .. tostring(win_location) .. "'. Falling back to 'center'.",
			vim.log.levels.WARN
		)
		win_location = default_opts.win_location
	end

	local poppies = merged.poppies or {}
	local poppies_resolved = {}
	for name, poppy in pairs(poppies) do
		local resolved = resolve_poppy(name, poppy)
		if resolved then
			poppies_resolved[name] = resolved
		end
	end

	return {
		keys = keys,
		icons = icons,
		menu_autohide = merged.menu_autohide,
		title_header = merged.title_header,
		autoclose = merged.autoclose,
		exclusive_float = merged.exclusive_float,
		menu_width = merged.menu_width,
		win_height = layout.normalize_ratio_or_pixels(merged.win_height, 0.75),
		win_width = layout.normalize_ratio_or_pixels(merged.win_width, 0.8),
		win_location = win_location,
		poppies = poppies,
		poppies_resolved = poppies_resolved,
	}
end

return M
