require("poppy._types")

local M = {}

local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

local function create_buf()
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return buf
end

local header_ns = api.nvim_create_namespace("poppy_header_panel")
local header = {}

---@param wrapper_win integer
---@param width_override? integer
---@param col_override? integer
---@return integer? win
---@return integer? buf
header.create = function(wrapper_win, width_override, col_override)
	local buf = create_buf()
	return header.recreate(wrapper_win, buf, width_override, col_override), buf
end

---@param wrapper_win integer
---@param buf integer
---@param width_override? integer
---@param col_override? integer
---@return integer? win
header.recreate = function(wrapper_win, buf, width_override, col_override)
	local wc = api.nvim_win_get_config(wrapper_win)
	local width = width_override or wc.width
	local col = col_override or 0

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = width,
		height = 3,
		col = col,
		row = 0,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
		win = wrapper_win,
	}

	local win = api.nvim_open_win(buf, false, config)
	style.apply_panel_style(win)
	shared.apply_win_marker(win)

	local title = "P◉PPY.NVIM"
	local title_w = fn.strdisplaywidth(title)
	local title_col = math.max(0, math.floor((width - title_w) / 2))
	local sep = " " .. string.rep("─", width - 2) .. " "
	local title_line = string.rep(" ", title_col) .. title

	shared.with_modifiable(buf, function()
		api.nvim_buf_set_lines(buf, 0, -1, false, { "", title_line, sep })
	end)

	---@type vim.api.keyset.set_extmark
	local title_extmark = { end_col = #title_line, hl_group = "NormalPoppyUIPanel" }
	api.nvim_buf_set_extmark(buf, header_ns, 1, 0, title_extmark)

	-- Resolve display col to byte offset so any glyph swap (◉ is 3-byte UTF-8) just works.
	local dot_display_col = fn.strdisplaywidth(title_col .. "P")
	local dot_byte_col = fn.byteidx(title_line, dot_display_col)
	local dot_byte_end = fn.byteidx(title_line, dot_display_col + 1)
	---@type vim.api.keyset.set_extmark
	local dot_extmark = {
		end_col = dot_byte_end,
		hl_group = "PoppyRed",
	}
	api.nvim_buf_set_extmark(buf, header_ns, 1, dot_byte_col, dot_extmark)
	return win
end

M.header = header

local list_ns = api.nvim_create_namespace("poppy_list_panel")
-- Own group, not poppy_ui: that one is cleared on every mount, which would drop the guard.
local list_autocmd_group = api.nvim_create_augroup("poppy_list_buffer", { clear = false })
local sign_group = "poppy_list"
local list = {}

local DOT_PRIORITY = 10
local ICON_PRIORITY = 5

---@param category "exec"|"file"|"shell"
---@return string  Titlecased category, e.g. "exec" -> "Exec"
local cap_category = function(category)
	return category:sub(1, 1):upper() .. category:sub(2)
end

---@param dot string
---@param category "exec"|"file"|"shell"
---@param is_active boolean
---@param is_hidden boolean
---@return string
local pick_sign = function(dot, category, is_active, is_hidden)
	if dot == " " then
		return "PoppyDotNone"
	end
	if is_active then
		return "PoppyDotCurrent" .. cap_category(category)
	end
	return "PoppyDot" .. cap_category(category) .. (is_hidden and "H" or "A")
end

---@param category "exec"|"file"|"shell"
---@param is_active boolean
---@return string
local pick_icon_sign = function(category, is_active)
	local prefix = is_active and "PoppyIconCurrent" or "PoppyIcon"
	return prefix .. cap_category(category)
end

---@param wrapper_win integer
---@param menu_width integer
---@param focusable boolean
---@param hint_height? integer
---@param row_override? integer
---@return integer? win
---@return integer? buf
list.create = function(wrapper_win, menu_width, focusable, hint_height, row_override)
	local buf = create_buf()
	-- The list is a read-only panel; refuse insert mode. Buffer-local, so it dies with the buffer.
	api.nvim_clear_autocmds({ group = list_autocmd_group, buffer = buf })
	api.nvim_create_autocmd("InsertEnter", {
		group = list_autocmd_group,
		buffer = buf,
		callback = function()
			vim.cmd("stopinsert")
		end,
	})
	return list.recreate(wrapper_win, buf, menu_width, focusable, hint_height, row_override), buf
end

---@param wrapper_win integer
---@param buf integer
---@param menu_width integer
---@param focusable boolean
---@param hint_height? integer
---@param row_override? integer
---@return integer? win
list.recreate = function(wrapper_win, buf, menu_width, focusable, hint_height, row_override)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local hint_offset = hint_height or 5
	local height = math.max(1, wrapper_conf.height - hint_offset)
	local row = wrapper_conf.height - hint_offset
	if row_override then
		height = math.max(1, height - row_override)
	end

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = menu_width,
		height = height,
		anchor = "SE",
		col = wrapper_conf.width,
		row = row,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = focusable == true,
		win = wrapper_win,
	}

	local win = api.nvim_open_win(buf, false, config)
	vim.wo[win].signcolumn = "yes:3"
	style.apply_panel_style(win)
	shared.apply_win_marker(win)
	return win
end

local category_hl = {
	file = "PoppyFile",
	exec = "PoppyExec",
	shell = "PoppyShell",
}

local category_hl_hidden = {
	file = "PoppyFileHidden",
	exec = "PoppyExecHidden",
	shell = "PoppyShellHidden",
}

---@param count integer
---@return integer
local max_index_width = function(count)
	return #tostring(count)
end

---@param title string
---@param max_width integer
---@return string
local trim_title = function(title, max_width)
	if fn.strdisplaywidth(title) <= max_width then
		return title
	end
	local result = ""
	for word in title:gmatch("%S+") do
		local test = result == "" and word or (result .. " " .. word)
		if fn.strdisplaywidth(test) > max_width then
			break
		end
		result = test
	end
	result = result:gsub("[%p]+%s*$", "")
	if fn.strdisplaywidth(result .. "…") <= max_width then
		result = result .. "…"
	end
	return result
end

---@param buf integer
---@param poppies {name: string, config: PoppyResolvedConfig}[]
---@param icons? PoppyIcons
---@param menu_width integer
---@return void
list.update = function(buf, poppies, icons, menu_width)
	api.nvim_buf_clear_namespace(buf, list_ns, 0, -1)

	local idx_width = max_index_width(#poppies)
	local entries = {}

	for display_idx, configured in ipairs(poppies) do
		local category = shared.category_from_resolved(configured.config)
		local icon = (icons and icons[category]) or " "
		local raw_title = configured.config.title or configured.name
		local runtime = state.runtime(configured.name)
		local is_hidden = runtime and runtime.hidden or false
		local is_active = runtime and runtime.active or false
		local title_max = menu_width - 1 - fn.strdisplaywidth(icon) - 1 - idx_width - 1
		local hl = is_active and ("PoppyCurrentRow" .. cap_category(category))
			or (is_hidden and category_hl_hidden[category])
			or category_hl[category]
		entries[display_idx] = {
			name = configured.name,
			category = category,
			icon = icon,
			title = trim_title(raw_title, title_max),
			is_active = is_active,
			is_hidden = is_hidden,
			hl = hl,
		}
	end

	if #entries == 0 then
		entries[1] = { category = "", icon = " ", title = "", is_active = false, is_hidden = false, hl = nil }
	end

	local lines = {}
	---@type fn.sign_placelist.list.item[]
	local placelist = {}
	for display_idx, e in ipairs(entries) do
		lines[display_idx] = string.format("%" .. idx_width .. "d", display_idx) .. " " .. e.title
		---@type fn.sign_placelist.list.item
		local dot_placement = {
			buffer = buf,
			group = sign_group,
			id = display_idx * 10,
			lnum = display_idx,
			priority = DOT_PRIORITY,
			name = pick_sign((e.is_active or e.is_hidden) and "•" or " ", e.category, e.is_active, e.is_hidden),
		}
		placelist[#placelist + 1] = dot_placement
		if e.category ~= "" then
			---@type fn.sign_placelist.list.item
			local icon_placement = {
				buffer = buf,
				group = sign_group,
				id = display_idx * 10 + 1,
				lnum = display_idx,
				priority = ICON_PRIORITY,
				name = pick_icon_sign(e.category, e.is_active),
			}
			placelist[#placelist + 1] = icon_placement
		end
	end

	shared.with_modifiable(buf, function()
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)

	for display_idx, e in ipairs(entries) do
		if e.hl then
			---@type vim.api.keyset.set_extmark
			local hl_extmark = {
				end_row = display_idx - 1,
				line_hl_group = e.hl,
			}
			api.nvim_buf_set_extmark(buf, list_ns, display_idx - 1, 0, hl_extmark)
		end
	end

	fn.sign_placelist(placelist)
end

M.list = list

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

M.HINT_LINES = {
	landing = #HINT_SPECS.landing,
	menu = #HINT_SPECS.menu,
}

local hints = {}

---@param wrapper_win integer
---@param opts? PoppyHintOpts
---@return integer? win
---@return integer? buf
hints.create = function(wrapper_win, opts)
	opts = opts or {}
	local buf = create_buf()
	return hints.recreate(wrapper_win, buf, opts), buf
end

---@param parent_win integer
---@param keys PoppyKeys?
---@return integer? win
---@return integer? buf
hints.create_bottom_right = function(parent_win, keys)
	local buf = create_buf()
	if not keys then
		return nil, buf
	end

	local text = " " .. keys.poppy_action .. " Menu "
	local win_conf = api.nvim_win_get_config(parent_win)
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

	local win = api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)

	shared.with_modifiable(buf, function()
		api.nvim_buf_set_lines(buf, 0, -1, false, { text })
	end)

	shared.apply_win_marker(win)

	return win, buf
end

---@param wrapper_win integer
---@param buf integer
---@param opts? PoppyHintOpts
---@return integer? win
hints.recreate = function(wrapper_win, buf, opts)
	opts = opts or {}
	local kind = opts.kind or "menu"
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
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

	local win = api.nvim_open_win(buf, false, config)
	style.apply_hints_panel_style(win)
	shared.apply_win_marker(win)
	return win
end

---@param buf integer
---@param keys PoppyKeys?
---@param kind "landing"|"menu"
---@param wrapper_width integer
---@return void
hints.write_static = function(buf, keys, kind, wrapper_width)
	if not keys then
		return
	end
	local sep = " " .. string.rep("─", math.max(0, wrapper_width - #INDENT - 1)) .. " "
	local lines = { sep }

	for _, kp in ipairs(HINT_SPECS[kind] or {}) do
		local hint_text = fmt_hint(keys[kp[1]], kp[2], INDENT)
		table.insert(lines, hint_text .. string.rep(" ", math.max(1, wrapper_width - #hint_text)))
	end

	table.insert(lines, " ")

	shared.with_modifiable(buf, function()
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)
end

M.hints = hints

return M
