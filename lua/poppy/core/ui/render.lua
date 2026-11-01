require("poppy._types")

local M = {}
local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

local INDENT = "   "
local KEY_COL = 5
local COL_GAP = "  "

local SIGN_COL = 4
local SIGN_COL_OPT = "yes:2"

local create_unmodifiable_buf = function()
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return buf
end

local header_ns = api.nvim_create_namespace("poppy_header_panel")
-- Stable ids so re-renders replace rather than accumulate.
local TITLE_MARK = 1
local DOT_MARK = 2
local SEP_MARK = 3
local header = {}

---@param menu_wrapper_win integer
---@return integer? win
---@return integer? buf
header.create = function(menu_wrapper_win)
	local buf = create_unmodifiable_buf()
	return header.recreate(menu_wrapper_win, buf), buf
end

---@param menu_wrapper_win integer
---@param buf integer
---@return integer? win
header.recreate = function(menu_wrapper_win, buf)
	local wrapper_config = api.nvim_win_get_config(menu_wrapper_win)
	local insets = shared.get_insets()
	local inset, inset_inv = insets.inset, insets.inset_inv
	--  -2 if borders to account for borders columns
	local width = wrapper_config.width - (2 * inset)
	local col = inset
	-- if no borders leave 1 line on top of visual offset
	local row = inset_inv

	-- Header: title bar above the sidebar; zindex +1 above menu_wrapper so it draws over the border.
	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = width,
		height = 2,
		col = col,
		row = row,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
		win = menu_wrapper_win,
	}

	local win = api.nvim_open_win(buf, false, config)
	style.apply_panel_style(win)
	shared.apply_win_marker(win)

	local title = layout.HEADER_TITLE
	local title_w = fn.strdisplaywidth(title)
	local title_col = math.max(0, math.floor((width - title_w) / 2))
	local sep = "  " .. string.rep("─", width - 4) .. "  "
	local title_line = string.rep(" ", title_col) .. title

	shared.with_modifiable(buf, function()
		api.nvim_buf_clear_namespace(buf, header_ns, 0, -1)
		api.nvim_buf_set_lines(buf, 0, -1, false, { title_line, sep })
	end)

	---@type vim.api.keyset.set_extmark
	local title_extmark = { end_col = #title_line, hl_group = "NormalPoppyUIPanel" }
	api.nvim_buf_set_extmark(buf, header_ns, 1, 0, vim.tbl_extend("force", title_extmark, { id = TITLE_MARK }))

	---@type vim.api.keyset.set_extmark
	local sep_extmark = { end_col = #sep, hl_group = "PoppySeparator" }
	api.nvim_buf_set_extmark(buf, header_ns, 1, 0, vim.tbl_extend("force", sep_extmark, { id = SEP_MARK }))

	-- ◉ is 3-byte UTF-8; resolve display col to byte offset before setting the extmark.
	local dot_display_col = title_col + fn.strdisplaywidth("P")
	local dot_byte_col = fn.byteidx(title_line, dot_display_col)
	local dot_byte_end = fn.byteidx(title_line, dot_display_col + 1)
	---@type vim.api.keyset.set_extmark
	local dot_extmark = {
		end_col = dot_byte_end,
		hl_group = "PoppyRed",
	}
	api.nvim_buf_set_extmark(buf, header_ns, 0, dot_byte_col, vim.tbl_extend("force", dot_extmark, { id = DOT_MARK }))
	return win
end

M.header = header

local body_ns = api.nvim_create_namespace("poppy_body_panel")
-- Own augroup: poppy_ui is cleared on every mount and would drop the cursor guard.
local body_autocmd_group = api.nvim_create_augroup("poppy_body_buffer", { clear = false })
local sign_group = "poppy_body"
local body = {}

local DOT_PRIORITY = 10
local ICON_PRIORITY = 5

---@param category "exec"|"file"|"shell"
---@return string  Titlecased category, e.g. "exec" -> "Exec"
local cap_category = function(category)
	return category:sub(1, 1):upper() .. category:sub(2)
end

-- Active: red dot. Hidden: small dot. Never opened: nothing.
local pick_sign = function(category, is_active, is_hidden)
	if is_active then
		return "PoppyDotActive"
	end
	if is_hidden then
		return "PoppyDot" .. cap_category(category) .. "H"
	end
	return "PoppyDotNone"
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
---@param height_override? integer Explicit body height; the dialog owns its own geometry.
---@return integer? win
---@return integer? buf
body.create = function(
	wrapper_win,
	menu_width,
	focusable,
	hint_height,
	row_override,
	body_rows,
	hints_on,
	height_override
)
	local buf = create_unmodifiable_buf()
	api.nvim_clear_autocmds({ group = body_autocmd_group, buffer = buf })
	shared.guard_insert_mode(buf)
	-- Window re-read because body is recreated on every mount.
	api.nvim_create_autocmd("CursorMoved", {
		buffer = buf,
		group = body_autocmd_group,
		callback = function()
			local win = api.nvim_get_current_win()
			if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf then
				return
			end
			local ok, cursor = pcall(api.nvim_win_get_cursor, win)
			if ok and cursor and cursor[1] and cursor[2] ~= 0 then
				pcall(api.nvim_win_set_cursor, win, { cursor[1], 0 })
			end
		end,
	})
	-- Buffer-scoped to menu only
	if shared.opts_field("autohide_menu") then
		api.nvim_create_autocmd("CursorHold", {
			group = body_autocmd_group,
			buffer = buf,
			callback = function()
				-- Lazy require: session.menu requires this module at load time.
				require("poppy.core.session.menu").exit_menu()
			end,
		})
	end
	return body.recreate(
		wrapper_win,
		buf,
		menu_width,
		focusable,
		hint_height,
		row_override,
		body_rows,
		hints_on,
		height_override
	),
		buf
end

---@param wrapper_win integer
---@param buf integer
---@param menu_width integer
---@param focusable boolean
---@param hint_height? integer
---@param row_override? integer
---@param body_rows? integer Row count of the spec; lets the body size to content when no header and no hints.
---@param hints_on? boolean When true, body adds 2 rows of breathing above the hints panel.
---@param height_override? integer Explicit body height. Callers that own their own geometry (the dialog) pass it in.
---@return integer? win
body.recreate = function(
	wrapper_win,
	buf,
	menu_width,
	focusable,
	hint_height,
	row_override,
	body_rows,
	hints_on,
	height_override
)
	local wrapper_config = api.nvim_win_get_config(wrapper_win)
	local insets = shared.get_insets()
	local inset, inset_inv = insets.inset, insets.inset_inv
	local hint_offset = (hint_height and hint_height or 0)
	local header_offset = layout.get_header_height(state.windows.opts)
	local has_question = (state.windows.dialog and state.windows.dialog.body_buf ~= nil) and true or false
	local has_header = shared.opts_field("title_header") == true
	local has_hints = shared.opts_field("hints_footer") == true

	-- When the spec has no header and no hints, size the body to actual content rows so
	-- the panel doesn't render blank rows below the list.
	local row
	local available = wrapper_config.height - hint_offset
	row = not has_header and inset_inv or header_offset - inset
	local height = available - header_offset
	if not has_header then
		height = height - 1
	end
	-- if not has_hints and has_header then
	-- 	height = heightdd
	-- end
	-- use overrides from dialog path plus adjust for border with inset
	if has_question then
		height = body_rows
		row = row_override - inset
	end
	local width = menu_width
	local col = wrapper_config.width

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = width,
		height = height,
		anchor = "NE",
		col = col,
		row = row,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = focusable == true,
		win = wrapper_win,
	}

	local win = api.nvim_open_win(buf, false, config)
	vim.wo[win].signcolumn = SIGN_COL_OPT
	style.apply_body_style(win)
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

---@param idx_width integer
---@param label string
---@return integer
M.measure_item = function(idx_width, label)
	return SIGN_COL + 2 + idx_width + 1 + fn.strdisplaywidth(label)
end

local fmt_hint = function(key, label)
	local padded = key .. string.rep(" ", math.max(0, KEY_COL - #key))
	return INDENT .. padded .. COL_GAP .. label .. " "
end

---@param key string
---@param label string
---@return integer
M.measure_hint_line = function(key, label)
	return fn.strdisplaywidth(fmt_hint(key, label))
end

---Used by fit_text and wrap_text for the single-overlong-token case.
---@param s string
---@param width integer
---@return string
local hard_cut_to_width = function(s, width)
	if fn.strdisplaywidth(s) <= width then
		return s
	end
	local cut = math.max(0, width - 1)
	if cut < 1 then
		return fn.strcharpart(s, 0, math.max(0, width))
	end
	local kept = fn.strcharpart(s, 0, cut)
	while kept ~= "" and fn.strdisplaywidth(kept) > cut do
		kept = kept:sub(1, -2)
	end
	return kept
end

---@param label string
---@param max_width integer
---@return string
local fit_text = function(label, max_width)
	if fn.strdisplaywidth(label) <= max_width then
		return label
	end
	local result = ""
	for word in label:gmatch("%S+") do
		local test = result == "" and word or (result .. " " .. word)
		if fn.strdisplaywidth(test) > max_width then
			break
		end
		result = test
	end
	-- Single overlong token: hard-cut rather than degrade to a lone ellipsis.
	if result == "" then
		return hard_cut_to_width(label, max_width) .. "…"
	end
	result = result:gsub("[%p]+%s*$", "")
	return fn.strdisplaywidth(result .. "…") <= max_width and (result .. "…") or result
end

---Wrap text to `width` on word boundaries. Returns line count (window options 'wrap'/'linebreak' are display-only).
---@param text string
---@param width integer
---@return string[]
M.wrap_text = function(text, width)
	width = math.max(1, width)
	local out = {}

	---@param paragraph string
	---@return string[]
	local wrap_paragraph = function(paragraph)
		if paragraph == "" then
			return { "" }
		end
		local lines = {}
		local line = ""
		-- Pre-tokenise so a hard-cut's remainder can re-enter the loop as a new word.
		local words = {}
		for word in paragraph:gmatch("%S+") do
			words[#words + 1] = word
		end
		local i = 1
		while i <= #words do
			local word = words[i]
			if fn.strdisplaywidth(word) > width then
				-- Hard-cut: drop trailing chars until it fits. Remainder is the next word.
				local cut = word
				while cut ~= "" and fn.strdisplaywidth(cut) > width do
					cut = fn.strcharpart(cut, 0, #cut - 1)
				end
				if line ~= "" then
					lines[#lines + 1] = line
					line = ""
				end
				if cut ~= "" then
					lines[#lines + 1] = cut
				end
				-- Char-indexed because cut is in chars, not bytes.
				local cut_chars = fn.strchars(cut)
				local remainder = fn.strcharpart(word, cut_chars)
				if remainder ~= "" then
					table.insert(words, i + 1, remainder)
				end
				i = i + 1
			else
				local candidate = line == "" and word or (line .. " " .. word)
				if fn.strdisplaywidth(candidate) <= width then
					line = candidate
				else
					if line ~= "" then
						lines[#lines + 1] = line
					end
					line = word
				end
				i = i + 1
			end
		end
		if line ~= "" then
			lines[#lines + 1] = line
		end
		return lines
	end

	for _, paragraph in ipairs(vim.split(text, "\n", { plain = true })) do
		for _, l in ipairs(wrap_paragraph(paragraph)) do
			out[#out + 1] = l
		end
	end

	if #out == 0 then
		out[1] = ""
	end
	return out
end

-- Below: pure painter. Given an item set, write bytes into a buffer.

---Resolve a spec to a fitted row set.
---@param menu PoppyMenuSpec
---@param panel_width integer
---@return MenuItems
M.rowset = function(menu, panel_width)
	local rows = menu.rows
	local numbered = false
	if type(menu.items) == "function" then
		---@type MenuItem[]
		rows = menu.items(panel_width) or { { label = "", marks = { "PoppyDotNone" }, hl = nil } }
		numbered = true
	end
	local set = {
		idx_width = #tostring(math.max(#rows, 1)),
		numbered = numbered,
		rows = rows,
	}
	-- Landing leaves an extra cell of right padding so the longest row doesn't kiss the edge.
	local trailing_reserve = state.windows.is_landing and 2 or 1
	local budget = panel_width - M.measure_item(set.idx_width, "") - trailing_reserve
	for i, row in ipairs(set.rows) do
		set.rows[i] = {
			label = fit_text(row.label, budget),
			marks = row.marks,
			hl = row.hl,
		}
	end
	if #set.rows == 0 then
		set.rows = { { label = "", marks = { "PoppyDotNone" }, hl = nil } }
	end
	return set
end

---@param poppies {name: string, config: PoppyResolvedConfig}[]
---@param icons? PoppyIcons
---@param menu_width integer
---@return MenuItem[]
local poppy_items = function(poppies, icons, menu_width)
	local idx_width = max_index_width(#poppies)
	local items = {}

	for display_idx, configured in ipairs(poppies) do
		local category = configured.config.mode
		local raw_title = configured.config.title or configured.name
		local runtime = state.runtime(configured.name)
		local is_hidden = runtime and runtime.hidden or false
		local is_active = runtime and runtime.active or false
		-- -1 reserves a one-cell trailing margin so a truncated label never runs flush to the edge.
		local label_max = menu_width - M.measure_item(idx_width, "") - 1
		local hl = is_active and ("PoppyCurrentRow" .. cap_category(category))
			or (is_hidden and category_hl_hidden[category])
			or category_hl[category]

		-- State dot always; category icon only when there's a category.
		local marks = { pick_sign(category, is_active, is_hidden) }
		marks[#marks + 1] = pick_icon_sign(category, is_active)

		items[display_idx] = {
			label = fit_text(raw_title, label_max),
			marks = marks,
			hl = hl,
		}
	end

	if #items == 0 then
		items[1] = { label = "", marks = { pick_sign("", false, false) }, hl = nil }
	end

	return items
end

-- Sign ids are row-derived, so a repaint replaces rather than accumulates.
M.items_for_poppies = poppy_items

---@param buf integer
---@param spec MenuItems
---@return nil
body.paint_items = function(buf, spec)
	api.nvim_buf_clear_namespace(buf, body_ns, 0, -1)

	local idx_width = spec.idx_width
	local lines = {}
	---@type vim.fn.sign_placelist.list.item[]
	local placelist = {}

	for display_idx, e in ipairs(spec.rows) do
		-- Every row needs the leading cell so the text column stays fixed.
		local num = spec.numbered and string.format("%" .. idx_width .. "d", display_idx) or ""
		lines[display_idx] = "  " .. num .. (spec.numbered and " " or "") .. e.label
		for mark_idx, name in ipairs(e.marks or {}) do
			-- Sign id = row*10 + (mark_idx-1). Stable per row, so repaints replace, not accumulate.
			local sign_id = mark_idx == 1 and display_idx * 10 or (display_idx * 10 + mark_idx - 1)
			---@type vim.fn.sign_placelist.list.item
			placelist[#placelist + 1] = {
				buffer = buf,
				group = sign_group,
				id = sign_id,
				lnum = display_idx,
				priority = mark_idx == 1 and DOT_PRIORITY or ICON_PRIORITY,
				name = name,
			}
		end
	end

	shared.with_modifiable(buf, function()
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)

	for display_idx, e in ipairs(spec.rows) do
		if e.hl then
			---@type vim.api.keyset.set_extmark
			local hl_extmark = {
				end_row = display_idx - 1,
				line_hl_group = e.hl,
			}
			api.nvim_buf_set_extmark(buf, body_ns, display_idx - 1, 0, hl_extmark)
		end
	end

	fn.sign_placelist(placelist)
end

---@param wrapper_win integer
---@param buf integer
---@param width integer
---@param height integer
---@param row integer
---@return integer? win
body.recreate_plain = function(wrapper_win, buf, width, height, row)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local insets = shared.get_insets()
	local inset = insets.inset
	local h = math.max(1, height)
	local header_offset = layout.get_header_height(state.windows.opts)
	header_offset = header_offset == 0 and 0 or 1
	local row_adjusted = row + h + 1 - header_offset
	local config = {
		relative = "win",
		win = wrapper_win,
		anchor = "SE",
		row = row_adjusted,
		col = wrapper_conf.width - inset,
		width = width - inset,
		height = h,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_QUESTION_Z_INDEX,
		focusable = false,
	}
	local win = api.nvim_open_win(buf, false, config)
	vim.wo[win].signcolumn = SIGN_COL_OPT
	vim.wo[win].cursorline = false
	style.apply_panel_style(win)
	shared.apply_win_marker(win)
	return win
end

---@param wrapper_win integer
---@param width integer
---@param height integer
---@param row integer
---@return integer? win
---@return integer buf
body.create_plain = function(wrapper_win, width, height, row)
	local buf = create_unmodifiable_buf()
	return body.recreate_plain(wrapper_win, buf, width, height, row), buf
end

M.body = body

local hints_ns = api.nvim_create_namespace("poppy_hints_panel")
local hints = {}

---@param wrapper_win integer
---@param opts? PoppyHintOpts
---@return integer? win
---@return integer? buf
hints.create = function(wrapper_win, opts)
	opts = opts or {}
	local buf = create_unmodifiable_buf()
	return hints.recreate(wrapper_win, buf, opts), buf
end

---@param parent_win integer
---@param keys PoppyKeys?
---@return integer? win
---@return integer? buf
hints.create_bottom_right = function(parent_win, keys)
	local buf = create_unmodifiable_buf()
	if not keys then
		return nil, buf
	end

	local text = " " .. keys.poppy_action .. " Menu "
	local win_conf = api.nvim_win_get_config(parent_win)
	local row = math.max(0, win_conf.height) + 1
	local col = math.max(0, win_conf.width) + 1

	-- corner hint window: 1-line "<C-/> Menu" badge shown by autohide_menu.
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
	local wrapper_config = api.nvim_win_get_config(wrapper_win)
	local insets = shared.get_insets()
	local inset, inset_inv = insets.inset, insets.inset_inv
	local row = wrapper_config.height
	local col = 0
	local width = (opts.width or wrapper_config.width) - 2 * inset
	local height = opts.height - inset

	-- hints panel: key-binding legend below the sidebar body (or below landing body). SW anchor pins to parent's bottom row.
	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = width,
		height = height,
		col = col,
		row = row,
		anchor = "SW",
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
		win = wrapper_win,
	}

	local win = api.nvim_open_win(buf, false, config)
	-- Soft-wrap would duplicate the trailing cell onto a second visual row.
	vim.wo[win].wrap = false
	vim.wo[win].linebreak = false
	style.apply_hints_panel_style(win)
	shared.apply_win_marker(win)
	return win
end

---@param buf integer
---@param keys PoppyKeys? Nil when setup has not run; nothing is written.
---@param spec PoppyHint[]|nil Explicit hint rows: PoppyKeys field name, label.
---@param wrapper_width integer
---@return nil
hints.write_spec = function(buf, keys, spec, wrapper_width)
	if not keys or not spec then
		return
	end
	local inset = shared.get_insets().inset
	local sep = "  " .. string.rep("─", math.max(0, wrapper_width - (4 - inset))) .. "  "

	local lines = { sep }

	for _, kp in ipairs(spec) do
		-- A hint may name a config field or carry a literal lhs (dialog letters).
		local hint_key = keys[kp[1]] or shared.permanent_key(kp[1]) or kp[1]
		local hint_text = fmt_hint(hint_key, kp[2])
		table.insert(lines, hint_text)
	end

	shared.with_modifiable(buf, function()
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)

	api.nvim_buf_clear_namespace(buf, hints_ns, 0, -1)
	---@type vim.api.keyset.set_extmark
	local sep_extmark = { end_row = 1, hl_group = "PoppySeparator" }
	api.nvim_buf_set_extmark(buf, hints_ns, 0, 0, sep_extmark)
end

M.hints = hints

return M
