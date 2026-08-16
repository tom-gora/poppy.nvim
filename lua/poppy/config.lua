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
-- would be mis-interpreted as a conversion spec). On rejection a WARN
-- is emitted so the user knows their override was ignored.
local sanitize_string_fields = function(defaults, user, keys, max_display_width, reject_pct)
	local out = {}
	for _, k in ipairs(keys) do
		local v = (type(user) == "table") and user[k] or nil
		local valid = type(v) == "string" and v ~= ""
		if valid and max_display_width then
			valid = vim.fn.strdisplaywidth(v) <= max_display_width
		end
		if valid and reject_pct then
			valid = not v:find("%", 1, true)
		end
		if not valid and v ~= nil then
			local reason
			if type(v) ~= "string" then
				reason = "value is " .. type(v) .. ", expected string"
			elseif v == "" then
				reason = "value is empty string"
			elseif max_display_width and vim.fn.strdisplaywidth(v) > max_display_width then
				reason = string.format(
					"display width %d exceeds max %d",
					vim.fn.strdisplaywidth(v),
					max_display_width
				)
			elseif reject_pct and v:find("%", 1, true) then
				reason = "value contains '%' which would break string.format downstream"
			else
				reason = "value failed validation"
			end
			vim.notify(
				string.format(
					"Poppy: ignoring invalid %s.%s (%s); falling back to default '%s'",
					"config",
					k,
					reason,
					tostring(defaults[k])
				),
				vim.log.levels.WARN
			)
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

	-- `vim.tbl_deep_extend` requires a table as its second positional
	-- argument and raises a hard error otherwise. Catch non-table
	-- `user_opts` before reaching it so we surface a WARN and fall back
	-- to defaults rather than crashing inside the merge.
	if type(user) ~= "table" then
		vim.notify(
			string.format(
				"Poppy: setup() expected a table of options, got %s. Using defaults.",
				type(user)
			),
			vim.log.levels.WARN
		)
		user = {}
	end

	-- Leading `{}` keeps default_opts and user untouched.
	local merged = vim.tbl_deep_extend("force", {}, default_opts, user)

	local known_top = {
		"keys",
		"icons",
		"poppies",
		"menu_autohide",
		"title_header",
		"autoclose",
		"exclusive_float",
		"menu_width",
		"win_height",
		"win_width",
		"win_location",
	}
	for k in pairs(user) do
		local is_known = false
		for _, name in ipairs(known_top) do
			if k == name then
				is_known = true
				break
			end
		end
		if not is_known then
			vim.notify(
				string.format(
					"Poppy: unknown config key '%s'. (Known keys: %s.)",
					tostring(k),
					table.concat(known_top, ", ")
				),
				vim.log.levels.WARN
			)
		end
	end

	-- Booleans: silent coercion. User typo like `autoclose = "true"` (truthy
	-- string) would otherwise pass `if autoclose then` and behave
	-- correctly today but break silently if the runtime check ever uses
	-- `type() == "boolean"`.
	local bool_keys = { "menu_autohide", "title_header", "autoclose", "exclusive_float" }
	for _, k in ipairs(bool_keys) do
		if merged[k] ~= nil and type(merged[k]) ~= "boolean" then
			vim.notify(
				string.format(
					"Poppy: config key '%s' expected boolean, got %s. Falling back to default %s.",
					k,
					type(merged[k]),
					tostring(default_opts[k])
				),
				vim.log.levels.WARN
			)
			merged[k] = default_opts[k]
		end
	end

	-- Numbers: silent coercion with WARN. Dimension handling is in
	-- layout.normalize_dimension; here we only catch obvious type
	-- mistakes (string/nil/bool passed for menu_width/win_height/win_width).
	local num_keys = { "menu_width" }
	for _, k in ipairs(num_keys) do
		if merged[k] ~= nil and type(merged[k]) ~= "number" and type(merged[k]) ~= "function" then
			vim.notify(
				string.format(
					"Poppy: config key '%s' expected number or function, got %s. Falling back to default %s.",
					k,
					type(merged[k]),
					tostring(default_opts[k])
				),
				vim.log.levels.WARN
			)
			merged[k] = default_opts[k]
		end
	end

	-- poppies: must be a table mapping name -> config table. If the user
	-- passed a string/list/function, every poppy would silently drop with
	-- the "must have exactly one of exec/file/shell" error during
	-- resolution — confusing. Catch it up front.
	if merged.poppies ~= nil and type(merged.poppies) ~= "table" then
		vim.notify(
			string.format(
				"Poppy: config key 'poppies' expected a table of name -> config, got %s. No poppies will be available.",
				type(merged.poppies)
			),
			vim.log.levels.WARN
		)
		merged.poppies = {}
	end

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
		if type(poppy) ~= "table" then
			vim.notify(
				string.format(
					"Poppy: poppy '%s' has non-table config (%s); dropping.",
					tostring(name),
					type(poppy)
				),
				vim.log.levels.WARN
			)
			table.insert(dropped_names, name)
		else
			local resolved = resolve_poppy(name, poppy)
			if resolved then
				poppies_resolved[name] = resolved
			else
				table.insert(dropped_names, name)
			end
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
