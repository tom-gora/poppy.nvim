---@diagnostic disable duplicate-doc-field
---@class PoppyConfig
---@field keys? table<string, string> # Keybindings: poppy_action, select, kill, exit_menu. Default: { poppy_action = "<C-_>", select = "<CR>", kill = "d", exit_menu = "<Esc>" }
---@field icons? table<string, string> # Icons per poppy type: exec, shell, file. Default: { exec = "🛠", shell = "$", file = "🗋" }
---@field menu_autohide? boolean # If true, hide sidebar style menu after selecting a poppy. Default: false
---@field title_header? boolean # Show "POPPY" header panel above list. Default: true
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

local geometry = require("poppy.core.ui.geometry")
local util = require("poppy.core.util")

local default_opts = {
	keys = { poppy_action = "<C-_>", select = "<CR>", kill = "d", exit_menu = "<Esc>" },
	icons = { exec = "🛠", shell = "$", file = "🗋" },
	menu_autohide = false,
	title_header = true,
	menu_width = 25,
	win_height = 0.75,
	win_width = 0.8,
	win_location = "center",
}

-- Build a fresh, sanitized record for a poppy. Reads from the user's raw
-- poppy config (which is left untouched); never mutates the user's input.
-- Returns nil on error (and emits a notify).
local function resolve_poppy(name, poppy)
	if not poppy then
		return nil
	end

	local cat, mode
	if poppy.exec then
		cat, mode = "exec", "term"
	elseif poppy.file then
		cat, mode = "file", "file"
	elseif poppy.shell then
		cat, mode = "shell", "term"
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

	-- Fresh record; the user's poppy config is NOT mutated.
	return {
		exec = poppy.exec,
		file = poppy.file,
		shell = poppy.shell,
		mode = mode,
		cat = cat,
		title = title,
	}
end

-- Build a fresh, fully sanitized opts table. The user's `user_opts` is
-- left untouched: keys/icons are copied into fresh tables, poppies is
-- referenced (not mutated), and a parallel `poppies_resolved` map holds
-- the engine-internal `mode` / `cat` / `title` fields.
M.merge = function(user_opts)
	local user = user_opts or {}
	-- First arg is `{}` so neither default_opts (module-local) nor user is mutated.
	local merged = vim.tbl_deep_extend("force", {}, default_opts, user)

	-- Sanitize keys: build a fresh table. Never mutate merged.keys in place.
	local merged_keys = merged.keys
	local keys = {}
	for _, k in ipairs({ "poppy_action", "select", "kill", "exit_menu" }) do
		if type(merged_keys) == "table" and type(merged_keys[k]) == "string" and merged_keys[k] ~= "" then
			keys[k] = merged_keys[k]
		else
			keys[k] = default_opts.keys[k]
		end
	end

	-- Sanitize icons: same pattern.
	local merged_icons = merged.icons
	local icons = {}
	for _, k in ipairs({ "exec", "shell", "file" }) do
		if type(merged_icons) == "table" and type(merged_icons[k]) == "string" then
			icons[k] = merged_icons[k]
		else
			icons[k] = default_opts.icons[k]
		end
	end

	-- Validate win_location.
	local valid_locations = { center = true, top = true, bottom = true }
	local win_location = merged.win_location
	if not valid_locations[win_location] then
		vim.notify(
			"Poppy: Invalid win_location '" .. tostring(win_location) .. "'. Falling back to 'center'.",
			vim.log.levels.WARN
		)
		win_location = default_opts.win_location
	end

	-- Build the resolved poppies map. The user's `merged.poppies` is left
	-- alone; a parallel `poppies_resolved` table holds the engine-internal
	-- `mode` / `cat` / `title` fields.
	local poppies = merged.poppies or {}
	local poppies_resolved = {}
	for name, poppy in pairs(poppies) do
		local resolved = resolve_poppy(name, poppy)
		if resolved then
			poppies_resolved[name] = resolved
		end
	end

	-- Final opts: completely fresh table; nothing aliased to user input.
	return {
		keys = keys,
		icons = icons,
		menu_autohide = merged.menu_autohide == true,
		title_header = merged.title_header ~= false,
		menu_width = merged.menu_width,
		win_height = geometry.normalize_ratio_or_pixels(merged.win_height, 0.75),
		win_width = geometry.normalize_ratio_or_pixels(merged.win_width, 0.8),
		win_location = win_location,
		poppies = poppies,
		poppies_resolved = poppies_resolved,
	}
end

return M
