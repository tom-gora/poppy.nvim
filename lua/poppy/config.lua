require("poppy._types")

local M = {}

local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

local DEFAULT_KEYS = { "poppy_action", "select", "kill", "exit_menu" }
local DEFAULT_ICONS = { "exec", "shell", "file" }

-- Pick non-empty strings from `user` for each name in `keys`, falling
-- back to `defaults`. Used to validate config string fields typed by the
-- user (keybindings, icons). Empty strings, nil, and wrong types are
-- all replaced with the default. When `max_display_width` is set, the
-- value's display width must also fit (icons get 2 to allow a single
-- 2-cell nerdfont glyph; longer nerd-font glyphs would break layout).
-- When `reject_pct` is true, values containing `%` are rejected (icons
-- are concatenated into a `string.format` call downstream, so `%`
-- would be mis-interpreted as a conversion spec).
local sanitize_string_fields = function(defaults, user, keys, max_display_width, reject_pct)
	local out = {}
	for _, k in ipairs(keys) do
		local v = (type(user) == "table") and user[k] or nil
		local valid = type(v) == "string" and v ~= ""
		if valid and max_display_width then
			valid = vim.fn.strdisplaywidth(v) <= max_display_width
		end
		if valid and reject_pct then
			valid = not v:find("%%", 1, true)
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
local title_fallback = function(mode, value)
	if type(value) == "function" then
		value = value()
	end
	if mode == "file" then
		return vim.fs.basename(vim.fn.expand(value))
	end
	-- mode is "term" (the only other resolved mode; "exec" is mapped to it
	-- in config.resolve_poppy and so never reaches here).
	local first_arg = type(value) == "table" and value[1] or vim.split(value, " ")[1]
	return vim.fs.basename(first_arg)
end

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
		title = title_fallback(mode, poppy.exec or poppy.file or poppy.shell or os.getenv("SHELL") or "shell")
	end

	-- `cat` is derived at use sites via shared.cat(poppy).
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
---@param user_opts? PoppyConfig
---@return PoppyMergedConfig
M.merge = function(user_opts)
	local user = user_opts or {}
	-- Leading `{}` keeps default_opts and user untouched.
	local merged = vim.tbl_deep_extend("force", {}, default_opts, user)

	local keys = sanitize_string_fields(default_opts.keys, merged.keys, DEFAULT_KEYS)
	local icons = sanitize_string_fields(default_opts.icons, merged.icons, DEFAULT_ICONS, 2, true)

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
	local dropped_names = {}
	for name, poppy in pairs(poppies) do
		local resolved = resolve_poppy(name, poppy)
		if resolved then
			poppies_resolved[name] = resolved
		else
			table.insert(dropped_names, name)
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
		win_height = layout.normalize_dimension(merged.win_height, 0.75),
		win_width = layout.normalize_dimension(merged.win_width, 0.8),
		win_location = win_location,
		poppies = poppies,
		poppies_resolved = poppies_resolved,
		dropped_names = dropped_names,
	}
end

return M
