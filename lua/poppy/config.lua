require("poppy._types")

local M = {}

local fn = vim.fn
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

local DEFAULT_KEYS = { "poppy_action", "select", "kill", "exit_menu" }
local DEFAULT_ICONS = { "exec", "shell", "file" }

---@param v any
---@param max_display_width? integer Fits one 2-cell nerdfont glyph.
---@param reject_pct? boolean Blocks '%' which would break string.format downstream.
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

local sanitize_string_fields = function(defaults, user, keys, max_display_width, reject_pct, warns)
	local out = {}
	for _, k in ipairs(keys) do
		local v = (type(user) == "table") and user[k] or nil
		local ok, reason = validate_string_field(v, max_display_width, reject_pct)
		if not ok and v ~= nil then
			warns[#warns + 1] = string.format("%s.%s: %s; falling back to default '%s'", "config", k, reason, tostring(defaults[k]))
		end
		out[k] = ok and v or defaults[k]
	end
	return out
end

local default_opts = {
	keys = { poppy_action = "<C-/>", select = "<CR>", kill = "d", exit_menu = "<Esc>" },
	icons = { exec = "🛠", shell = "$", file = "🗋" },
	autohide_menu = false,
	title_header = true,
	hints_footer = true,
	close_on_focus_lost = true,
	close_other_floats_on_open = true,
	assume_multiplexer = false,
	menu_width = layout.DEFAULT_MENU_WIDTH,
	win_height = 0.75,
	win_width = 0.8,
	win_location = "center",
}

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
		shared.notify_warn("poppy '%s' resolved to %s, expected string or list of strings", tostring(name), type(value))
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

	local declared_modes = {}
	if poppy.exec then declared_modes[#declared_modes + 1] = "exec" end
	if poppy.file then declared_modes[#declared_modes + 1] = "file" end
	if poppy.shell then declared_modes[#declared_modes + 1] = "shell" end

	if #declared_modes == 0 then
		shared.notify_error("poppy '%s' must have exactly one of 'exec', 'file', or 'shell'", tostring(name))
		return nil
	end

	if #declared_modes > 1 then
		shared.notify_warn(
			"poppy '%s' declares multiple modes (%s); using '%s'. Remove the others.",
			tostring(name),
			table.concat(declared_modes, ", "),
			declared_modes[1]
		)
	end

	local mode, declared = declared_modes[1], poppy[declared_modes[1]]

	local resolved, ok, err = resolve_and_validate_value(name, declared)
	if not ok then
		shared.notify_warn("poppy '%s' dropped at setup: %s", tostring(name), err)
		return nil
	end

	if mode == "file" then
		-- A list is not a path. Rejecting it here keeps fn.expand from raising E730.
		if type(resolved) ~= "string" then
			shared.notify_warn("poppy '%s' file value must be a string, got %s", tostring(name), type(resolved))
			return nil
		end
		local expanded = fn.expand(resolved)
		if expanded == "" then
			shared.notify_warn("poppy '%s' file path resolved to empty: %s", tostring(name), tostring(resolved))
			return nil
		end
		return { mode = "file", value = declared, title = poppy.title or vim.fs.basename(expanded) }
	end

	local check = mode == "shell" and resolved == "default" and shared.default_shell() or resolved
	local argv = shared.argv0(check)
	if argv and argv ~= "" and fn.executable(argv) == 0 then
		shared.notify_warn("poppy '%s' binary '%s' not found on $PATH", tostring(name), argv)
		return nil
	end

	local title = poppy.title
	if title == nil then
		title = vim.fs.basename(shared.argv0(resolved) or name)
	end

	-- `value` keeps the declared form so a function is re-resolved at open, as documented.
	return { mode = mode, value = declared, title = title }
end

local classify_border = function(v, borderless_style)
	if type(v) == "string" then
		if v == "none" or v == "solid" then
			return false, borderless_style
		end
		if v == "single" or v == "double" or v == "rounded" or v == "shadow" then
			return true, v
		end
		return nil, nil
	end
	if type(v) == "table" and #v >= 1 and type(v[1]) == "string" then
		local head = v[1]
		if head == "none" or head == "solid" then
			return false, borderless_style
		end
		if head == "single" or head == "double" or head == "rounded" or head == "shadow" then
			return true, head
		end
		return true, v
	end
	return nil, nil
end

local resolve_border = function(user_border, borderless_style, fallback_warn)
	if user_border ~= nil then
		local use, style = classify_border(user_border, borderless_style)
		if use ~= nil then
			return use, style
		end
		shared.notify_warn("invalid border %s; falling back to winborder", vim.inspect(user_border))
	end

	local ok, wb = pcall(function()
		return vim.opt.winborder:get()
	end)
	if ok and type(wb) == "table" and #wb > 0 then
		local use, style = classify_border(wb, borderless_style)
		if use ~= nil then
			return use, style
		end
		shared.notify_warn("invalid winborder %s; %s", vim.inspect(wb), fallback_warn)
	end

	return false, borderless_style
end

---@param user_opts? PoppyConfig
---@return PoppyMergedConfig
M.merge = function(user_opts)
	local user = user_opts or {}

	if type(user) ~= "table" then
		shared.notify_warn("setup() expected a table of options, got %s. Using defaults.", type(user))
		user = {}
	end

	-- Batched: every "fall back to default" reason collected here, emitted as
	-- a single warning at the end of merge so a misconfigured setup() produces
	-- one notification rather than a flood.
	---@type string[]
	local warns = {}

	-- Leading {} keeps default_opts and user untouched (deep_extend mutates its first arg).
	local merged = vim.tbl_deep_extend("force", {}, default_opts, user)

	local known_top = {
		"keys",
		"icons",
		"poppies",
		"autohide_menu",
		"title_header",
		"hints_footer",
		"close_on_focus_lost",
		"close_other_floats_on_open",
		"assume_multiplexer",
		"menu_width",
		"win_height",
		"win_width",
		"win_location",
		"border",
	}
	local known_set = {}
	for _, name in ipairs(known_top) do
		known_set[name] = true
	end
	for k in pairs(user) do
		if not known_set[k] then
			shared.notify_warn("unknown config key '%s'. (Known keys: %s.)", tostring(k), table.concat(known_top, ", "))
		end
	end

	local bool_keys = { "autohide_menu", "title_header", "hints_footer", "close_on_focus_lost", "close_other_floats_on_open", "assume_multiplexer" }
	for _, k in ipairs(bool_keys) do
		if merged[k] ~= nil and type(merged[k]) ~= "boolean" then
			warns[#warns + 1] = string.format("'%s' expected boolean, got %s; falling back to %s", k, type(merged[k]), tostring(default_opts[k]))
			merged[k] = default_opts[k]
		end
	end

	if merged.menu_width ~= nil and type(merged.menu_width) ~= "number" and type(merged.menu_width) ~= "function" then
		warns[#warns + 1] = string.format("'menu_width' expected number or function, got %s; falling back to %s", type(merged.menu_width), tostring(default_opts.menu_width))
		merged.menu_width = default_opts.menu_width
	end

	if merged.poppies ~= nil and type(merged.poppies) ~= "table" then
		shared.notify_warn(
			"config key 'poppies' expected a table of name -> config, got %s. No poppies will be available.",
			type(merged.poppies)
		)
		merged.poppies = {}
	end

	local keys = sanitize_string_fields(default_opts.keys, merged.keys, DEFAULT_KEYS, nil, nil, warns)
	for field, value in pairs(keys) do
		local alias = shared.key_alias(value)
		if alias then
			warns[#warns + 1] = string.format("bind '%s' for keys.%s conflicts with %s; falling back to '%s'", value, field, alias, tostring(default_opts.keys[field]))
			keys[field] = default_opts.keys[field]
		end
	end
	local icons = sanitize_string_fields(default_opts.icons, merged.icons, DEFAULT_ICONS, 2, true, warns)

	local valid_locations = { center = true, top = true, bottom = true }
	local win_location = merged.win_location
	if not valid_locations[win_location] then
		warns[#warns + 1] = string.format("invalid win_location '%s'; falling back to 'center'", tostring(win_location))
		win_location = default_opts.win_location
	end

	local poppies = merged.poppies or {}
	local poppies_resolved = {}
	local dropped_names = {}
	for name, poppy in pairs(poppies) do
		if type(poppy) ~= "table" then
			shared.notify_warn("poppy '%s' has non-table config (%s); dropping.", tostring(name), type(poppy))
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

	local use_borders, border_style = resolve_border(merged.border, "none", "using borderless")

	if #warns > 0 then
		shared.notify_warn(
			"the following config entries were misconfigured; defaults applied:\n  - %s",
			table.concat(warns, "\n  - ")
		)
	end

	return {
		keys = keys,
		icons = icons,
		autohide_menu = merged.autohide_menu,
		title_header = merged.title_header,
		hints_footer = merged.hints_footer,
		close_on_focus_lost = merged.close_on_focus_lost,
		close_other_floats_on_open = merged.close_other_floats_on_open,
		assume_multiplexer = merged.assume_multiplexer,
		menu_width = merged.menu_width,
		win_height = layout.normalize_dimension(merged.win_height, 0.75),
		win_width = layout.normalize_dimension(merged.win_width, 0.8),
		win_location = win_location,
		poppies = poppies,
		poppies_resolved = poppies_resolved,
		dropped_names = dropped_names,
		use_borders = use_borders,
		border_style = border_style,
	}
end

return M
