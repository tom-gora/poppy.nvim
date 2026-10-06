require("poppy._types")

local M = {}

local fn = vim.fn
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

local DEFAULT_KEYS = { "poppy_action", "select", "kill", "exit_menu" }
local DEFAULT_ICONS = { "exec", "shell", "file" }

-- max_display_width fits one 2-cell nerdfont glyph; reject_pct blocks '%' which would break string.format downstream.
---@param v any
---@param max_display_width? integer
---@param reject_pct? boolean
---@return boolean ok
---@return string? reason
local validate_string_field = function(v, max_display_width, reject_pct)
	if type(v) ~= "string" then
		return false, "value is " .. type(v) .. ", expected string"
	end
	if v == "" then
		return false, "value is empty string"
	end
	if max_display_width then
		local w = fn.strdisplaywidth(v)
		if w > max_display_width then
			return false, string.format("display width %d exceeds max %d", w, max_display_width)
		end
	end
	if reject_pct and v:find("%", 1, true) then
		return false, "value contains '%' which would break string.format downstream"
	end
	return true, nil
end

local sanitize_string_fields = function(defaults, user, keys, max_display_width, reject_pct)
	local out = {}
	for _, k in ipairs(keys) do
		local v = (type(user) == "table") and user[k] or nil
		local ok, reason = validate_string_field(v, max_display_width, reject_pct)
		if not ok and v ~= nil then
			shared.notify_warn(
				"ignoring invalid %s.%s (%s); falling back to default '%s'",
				"config", k, reason, tostring(defaults[k])
			)
		end
		out[k] = ok and v or defaults[k]
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
	menu_width = layout.DEFAULT_MENU_WIDTH,
	win_height = 0.75,
	win_width = 0.8,
	win_location = "center",
}

-- First whitespace-delimited token of a string command, or first element of a list command.
---@param command string|string[]|function|nil
---@return string|nil
local argv0 = function(command)
	if type(command) == "string" then
		return (command:gsub("%s.*", ""))
	elseif type(command) == "table" and #command > 0 and type(command[1]) == "string" then
		return command[1]
	end
	return nil
end

---Evaluate a user function (or pass through a string/list) and validate the result against
---the type the field requires. On `not ok` the caller drops the poppy.
---@param name string
---@param raw string|string[]|function|nil
---@return string|string[]|nil value
---@return boolean ok
---@return string? err
local resolve_and_validate_value = function(name, raw)
	if raw == nil then
		return nil, false, "value is nil"
	end
	local value = raw
	if type(value) == "function" then
		local ok, result = pcall(value)
		if not ok then
			shared.notify_warn("poppy '%s' function errored at setup: %s", tostring(name), tostring(result))
			return nil, false, "function errored"
		end
		value = result
	end
	if value == nil or value == "" then
		return nil, false, "value is empty"
	end
	if type(value) ~= "string" and type(value) ~= "table" then
		shared.notify_warn(
			"poppy '%s' resolved to %s, expected string or list of strings",
			tostring(name),
			type(value)
		)
		return nil, false, "type mismatch"
	end
	return value, true, nil
end

---@param name string
---@param poppy PoppyItemConfig?
---@return PoppyResolvedConfig?
local resolve_poppy = function(name, poppy)
	if not poppy then
		return nil
	end

	local mode
	local raw
	if poppy.exec then
		mode = "term"
		raw = poppy.exec
	elseif poppy.file then
		mode = "file"
		raw = poppy.file
	elseif poppy.shell then
		mode = "term"
		raw = poppy.shell
	else
		shared.notify_error("poppy '%s' must have exactly one of 'exec', 'file', or 'shell'", tostring(name))
		return nil
	end

	local value, ok, err = resolve_and_validate_value(name, raw)
	if not ok then
		shared.notify_warn("poppy '%s' dropped at setup: %s", tostring(name), err)
		return nil
	end

	if mode == "file" then
		local expanded = fn.expand(value)
		if expanded == "" then
			shared.notify_warn("poppy '%s' file path resolved to empty: %s", tostring(name), tostring(value))
			return nil
		end
		value = expanded
	else
		local check = value
		if poppy.shell and value == "default" then
			check = os.getenv("SHELL") or "bash"
		end
		local argv = argv0(check)
		if argv and argv ~= "" and fn.executable(argv) == 0 then
			shared.notify_warn("poppy '%s' binary '%s' not found on $PATH", tostring(name), argv)
			return nil
		end
	end

	local title = poppy.title
	if title == nil then
		if mode == "file" then
			title = vim.fs.basename(value)
		elseif type(value) == "table" then
			title = vim.fs.basename(value[1] or name)
		else
			title = vim.fs.basename(vim.split(value, " ")[1] or name)
		end
	end

	return {
		exec = poppy.exec,
		file = poppy.file,
		shell = poppy.shell,
		mode = mode,
		title = title,
	}
end

---@param user_opts? PoppyConfig
---@return PoppyMergedConfig
M.merge = function(user_opts)
	local user = user_opts or {}

	-- vim.tbl_deep_extend errors on non-table; catch up front.
	if type(user) ~= "table" then
		shared.notify_warn("setup() expected a table of options, got %s. Using defaults.", type(user))
		user = {}
	end

	-- Leading {} keeps default_opts and user untouched (deep_extend mutates its first arg).
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
	local known_set = {}
	for _, name in ipairs(known_top) do
		known_set[name] = true
	end
	for k in pairs(user) do
		if not known_set[k] then
			shared.notify_warn(
				"unknown config key '%s'. (Known keys: %s.)",
				tostring(k), table.concat(known_top, ", ")
			)
		end
	end

	local bool_keys = { "menu_autohide", "title_header", "autoclose", "exclusive_float" }
	for _, k in ipairs(bool_keys) do
		if merged[k] ~= nil and type(merged[k]) ~= "boolean" then
			shared.notify_warn(
				"config key '%s' expected boolean, got %s. Falling back to default %s.",
				k, type(merged[k]), tostring(default_opts[k])
			)
			merged[k] = default_opts[k]
		end
	end

	local num_keys = { "menu_width" }
	for _, k in ipairs(num_keys) do
		if merged[k] ~= nil and type(merged[k]) ~= "number" and type(merged[k]) ~= "function" then
			shared.notify_warn(
				"config key '%s' expected number or function, got %s. Falling back to default %s.",
				k, type(merged[k]), tostring(default_opts[k])
			)
			merged[k] = default_opts[k]
		end
	end

	if merged.poppies ~= nil and type(merged.poppies) ~= "table" then
		shared.notify_warn(
			"config key 'poppies' expected a table of name -> config, got %s. No poppies will be available.",
			type(merged.poppies)
		)
		merged.poppies = {}
	end

	local keys = sanitize_string_fields(default_opts.keys, merged.keys, DEFAULT_KEYS)
	local icons = sanitize_string_fields(default_opts.icons, merged.icons, DEFAULT_ICONS, 2, true)

	local valid_locations = { center = true, top = true, bottom = true }
	local win_location = merged.win_location
	if not valid_locations[win_location] then
		shared.notify_warn(
			"invalid win_location '%s'. Falling back to 'center'.",
			tostring(win_location)
		)
		win_location = default_opts.win_location
	end

	local poppies = merged.poppies or {}
	local poppies_resolved = {}
	local dropped_names = {}
	for name, poppy in pairs(poppies) do
		if type(poppy) ~= "table" then
			shared.notify_warn(
				"poppy '%s' has non-table config (%s); dropping.",
				tostring(name), type(poppy)
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
