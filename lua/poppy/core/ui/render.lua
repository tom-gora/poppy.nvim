require("poppy._types")

local M = {}

local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

-- =====================================================================
-- Shared helpers
-- =====================================================================

-- Create a scratch buffer with modifiable=false. All three renderers
-- need this idiom; lifted from duplicated create() functions.
---@return integer
local function create_buf()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return buf
end

-- =====================================================================
-- Header panel
-- =====================================================================

local header_ns = vim.api.nvim_create_namespace("poppy_header_panel")
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
	local wc = vim.api.nvim_win_get_config(wrapper_win)
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

	local win = vim.api.nvim_open_win(buf, false, config)
	style.apply_panel_style(win)
	shared.apply_win_marker(win)

	local title = "P◉PPY.NVIM"
	local title_w = vim.fn.strdisplaywidth(title)
	local title_col = math.max(0, math.floor((width - title_w) / 2))
	local sep = " " .. string.rep("─", width - 2) .. " "
	local title_line = string.rep(" ", title_col) .. title

	shared.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", title_line, sep })
	end)

	-- The full title_line is highlighted as one block.
	---@type vim.api.keyset.extmark
	local title_extmark = { end_col = #title_line, hl_group = "NormalPoppyUIPanel" }
	vim.api.nvim_buf_set_extmark(buf, header_ns, 1, 0, title_extmark)
	-- The ◉ is at display column 2 within the title (after "P"). Resolve
	-- it to a byte offset that respects any future title-string change,
	-- since ◉ is a 3-byte UTF-8 sequence and any other glyph would shift
	-- the offsets.
	local dot_display_col = vim.fn.strdisplaywidth(title_col .. "P")
	local dot_byte_col = vim.fn.byteidx(title_line, dot_display_col)
	local dot_byte_end = vim.fn.byteidx(title_line, dot_display_col + 1)
	---@type vim.api.keyset.extmark
	local dot_extmark = {
		end_col = dot_byte_end,
		hl_group = "PoppyRed",
	}
	vim.api.nvim_buf_set_extmark(buf, header_ns, 1, dot_byte_col, dot_extmark)
	return win
end

M.header = header

-- =====================================================================
-- List panel
-- =====================================================================

local list_ns = vim.api.nvim_create_namespace("poppy_list_panel")
local sign_group = "poppy_list"
local list = {}

-- Cell 1 = dot, cells 2-3 = icon. Two signs per line at different priorities.
-- Higher priority renders leftmost, so dot (priority 10) wins cell 1 and
-- icon (priority 5) renders to the right of it.
local DOT_PRIORITY = 10
local ICON_PRIORITY = 5

---@param dot string
---@param cat "exec"|"file"|"shell"
---@param is_active boolean
---@param is_hidden boolean
---@return string
local pick_sign = function(dot, cat, is_active, is_hidden)
	if dot == " " then
		return "PoppyDotNone"
	end
	if is_active then
		local cap = cat:sub(1, 1):upper() .. cat:sub(2)
		return "PoppyDotCurrent" .. cap
	end
	local prefix = "PoppyDot" .. cat:sub(1, 1):upper() .. cat:sub(2)
	return prefix .. (is_hidden and "H" or "A")
end

---@param cat "exec"|"file"|"shell"
---@param is_active boolean
---@return string
local pick_icon_sign = function(cat, is_active)
	local cap = cat:sub(1, 1):upper() .. cat:sub(2)
	if is_active then
		return "PoppyIconCurrent" .. cap
	end
	return "PoppyIcon" .. cap
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
	---@type vim.api.keyset.create_autocmd
	local insert_enter_autocmd = {
		buffer = buf,
		callback = function()
			vim.cmd("stopinsert")
		end,
	}
	vim.api.nvim_create_autocmd("InsertEnter", insert_enter_autocmd)
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
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local hint_offset = hint_height and hint_height or 5
	local height = math.max(1, hint_offset and (wrapper_conf.height - hint_offset) or wrapper_conf.height)
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

	local win = vim.api.nvim_open_win(buf, false, config)
	vim.wo[win].signcolumn = "yes:3"
	style.apply_panel_style(win)
	shared.apply_win_marker(win)
	return win
end

local cat_hl = {
	file = "PoppyFile",
	exec = "PoppyExec",
	shell = "PoppyShell",
}

local cat_hl_hidden = {
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
	if vim.fn.strdisplaywidth(title) <= max_width then
		return title
	end
	local result = ""
	for word in title:gmatch("%S+") do
		local test = result == "" and word or (result .. " " .. word)
		if vim.fn.strdisplaywidth(test) > max_width then
			break
		end
		result = test
	end
	result = result:gsub("[%p]+%s*$", "")
	if vim.fn.strdisplaywidth(result .. "…") <= max_width then
		result = result .. "…"
	end
	return result
end

---@param buf integer
---@param poppies PoppySessionEntry[]
---@param icons? PoppyIcons
---@param menu_width integer
---@return void
list.update = function(buf, poppies, icons, menu_width)
	vim.api.nvim_buf_clear_namespace(buf, list_ns, 0, -1)

	local idx_width = max_index_width(#poppies)
	local entries = {}

	for display_idx, entry in ipairs(poppies) do
		local cat = shared.cat(entry.config)
		local icon = (icons and icons[cat]) or " "
		local raw_title = entry.config.title or entry.name
		local runtime = entry.runtime_state
		local is_hidden = runtime and runtime.hidden or false
		local is_active = runtime and runtime.active or false
		local title_max = menu_width - 1 - vim.fn.strdisplaywidth(icon) - 1 - idx_width - 1
		local hl
		if is_active then
			hl = "PoppyCurrentRow" .. cat:sub(1, 1):upper() .. cat:sub(2)
		elseif is_hidden then
			hl = cat_hl_hidden[cat]
		else
			hl = cat_hl[cat]
		end
		entries[display_idx] = {
			name = entry.name,
			cat = cat,
			icon = icon,
			title = trim_title(raw_title, title_max),
			is_active = is_active,
			is_hidden = is_hidden,
			hl = hl,
		}
	end

	if #entries == 0 then
		entries[1] = { cat = "", icon = " ", title = "", is_active = false, is_hidden = false, hl = nil }
	end

	local lines = {}
	---@type vim.api.keyset.sign_placelist[]
	local placelist = {}
	for display_idx, e in ipairs(entries) do
		lines[display_idx] = string.format("%" .. idx_width .. "d", display_idx) .. " " .. e.title
		-- Cell 1: dot sign (priority 5)
		---@type vim.api.keyset.sign_placelist
		local dot_placement = {
			buffer = buf,
			group = sign_group,
			id = display_idx * 10,
			lnum = display_idx,
			priority = DOT_PRIORITY,
			name = pick_sign((e.is_active or e.is_hidden) and "•" or " ", e.cat, e.is_active, e.is_hidden),
		}
		placelist[#placelist + 1] = dot_placement
		-- Cells 2-3: icon sign (priority 5). Skip for the empty-list placeholder.
		if e.cat ~= "" then
			---@type vim.api.keyset.sign_placelist
			local icon_placement = {
				buffer = buf,
				group = sign_group,
				id = display_idx * 10 + 1,
				lnum = display_idx,
				priority = ICON_PRIORITY,
				name = pick_icon_sign(e.cat, e.is_active),
			}
			placelist[#placelist + 1] = icon_placement
		end
	end

	shared.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)

	for display_idx, e in ipairs(entries) do
		if e.hl then
			---@type vim.api.keyset.extmark
			local hl_extmark = {
				end_row = display_idx - 1,
				line_hl_group = e.hl,
			}
			vim.api.nvim_buf_set_extmark(buf, list_ns, display_idx - 1, 0, hl_extmark)
		end
	end

	vim.fn.sign_placelist(placelist)
end

M.list = list

-- =====================================================================
-- Hints panel
-- =====================================================================

local hints_ns = vim.api.nvim_create_namespace("poppy_hints_bar")
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
-- source of truth for the window-height math in view.lua.
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
---@param keys PoppyKeys
---@return integer? win
---@return integer? buf
hints.create_bottom_right = function(parent_win, keys)
	local buf = create_buf()

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
hints.recreate = function(wrapper_win, buf, opts)
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
-- no runtime mutations. Called from view.lua at mount time only.
---@param buf integer
---@param keys PoppyKeys
---@param kind "landing"|"menu"
---@param wrapper_width integer
---@return void
hints.write_static = function(buf, keys, kind, wrapper_width)
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

	vim.api.nvim_buf_clear_namespace(buf, hints_ns, 0, -1)
	shared.with_modifiable(buf, function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)
end

M.hints = hints

return M