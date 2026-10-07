require("poppy._types")

local M = {}

local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

-- Hint line geometry, shared with layout.lua's width measurements.
local INDENT = "  "
local KEY_COL = 5
local COL_GAP = "  "

local function create_buf()
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	return buf
end

local header_ns = api.nvim_create_namespace("poppy_header_panel")
-- Stable extmark ids so re-renders replace rather than accumulate.
local TITLE_MARK = 1
local DOT_MARK = 2
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
		api.nvim_buf_clear_namespace(buf, header_ns, 0, -1)
		api.nvim_buf_set_lines(buf, 0, -1, false, { "", title_line, sep })
	end)

	---@type vim.api.keyset.set_extmark
	local title_extmark = { end_col = #title_line, hl_group = "NormalPoppyUIPanel" }
	api.nvim_buf_set_extmark(buf, header_ns, 1, 0, vim.tbl_extend("force", title_extmark, { id = TITLE_MARK }))

	-- ◉ is 3-byte UTF-8, so resolve display col to byte offset before setting the extmark.
	-- title_col is a number; "5P" would concatenate to "5P" and resolve to col 2.
	local dot_display_col = title_col + fn.strdisplaywidth("P")
	local dot_byte_col = fn.byteidx(title_line, dot_display_col)
	local dot_byte_end = fn.byteidx(title_line, dot_display_col + 1)
	---@type vim.api.keyset.set_extmark
	local dot_extmark = {
		end_col = dot_byte_end,
		hl_group = "PoppyRed",
	}
	api.nvim_buf_set_extmark(buf, header_ns, 1, dot_byte_col, vim.tbl_extend("force", dot_extmark, { id = DOT_MARK }))
	return win
end

M.header = header

local body_ns = api.nvim_create_namespace("poppy_body_panel")
-- Own augroup, not poppy_ui: that one is cleared on every mount and would drop the cursor guard.
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

-- Active poppy: red dot. Hidden (running in background): small dot. Never opened: nothing.
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
---@return integer? win
---@return integer? buf
body.create = function(wrapper_win, menu_width, focusable, hint_height, row_override)
	local buf = create_buf()
	-- Refuse insert: body is a read-only panel.
	api.nvim_clear_autocmds({ group = body_autocmd_group, buffer = buf })
	api.nvim_create_autocmd("InsertEnter", {
		group = body_autocmd_group,
		buffer = buf,
		callback = function()
			vim.cmd("stopinsert")
		end,
	})
	-- Pin cursor to column 0 (the row marker). Window re-read because body is recreated on every mount.
	api.nvim_create_autocmd("CursorMoved", {
		group = body_autocmd_group,
		buffer = buf,
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
	return body.recreate(wrapper_win, buf, menu_width, focusable, hint_height, row_override), buf
end

---@param wrapper_win integer
---@param buf integer
---@param menu_width integer
---@param focusable boolean
---@param hint_height? integer
---@param row_override? integer
---@return integer? win
body.recreate = function(wrapper_win, buf, menu_width, focusable, hint_height, row_override)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local hint_offset = hint_height or 5
	local height = math.max(1, wrapper_conf.height - hint_offset)
	-- When the title header is absent, anchor the body to the top of the wrapper so the
	-- poppies list sits at the top (legend still at the bottom). When the header is present,
	-- the body anchors below it. `row_override` is the dialog question panel: it sits
	-- above the body (SE anchor, just above the legend) regardless of header state.
	local header_h = layout.get_header_height(state.windows.opts)
	local anchor, row
	if row_override and row_override > 0 then
		anchor = "SE"
		row = wrapper_conf.height - hint_offset
		height = math.max(1, height - row_override)
	elseif header_h == 0 then
		anchor = "NW"
		row = 0
	else
		anchor = "SE"
		row = wrapper_conf.height - hint_offset
	end

	---@type vim.api.keyset.win_config
	local config = {
		relative = "win",
		width = menu_width,
		height = height,
		anchor = anchor,
		col = wrapper_conf.width,
		row = row,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = focusable == true,
		win = wrapper_win,
	}

	local win = api.nvim_open_win(buf, false, config)
	vim.wo[win].signcolumn = "yes:2"
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

-- Cell width reserved for signs in each body row. Two signs (state dot + category icon)
-- at signcolumn="yes:2" = 2 cells per sign = 4. Must match body.recreate's signcolumn.
-- Exported so layout.lua can size panels from the same arithmetic.
M.SIGN_COL = 4

---@param idx_width integer
---@param title string
---@return integer
M.measure_item = function(idx_width, label)
	return M.SIGN_COL + 2 + idx_width + 1 + fn.strdisplaywidth(label)
end

-- One hint line: indent + key padded to KEY_COL + gap + label + trailing space.
local hint_line = function(key, label, indent)
	local padded = key .. string.rep(" ", math.max(0, KEY_COL - #key))
	return indent .. padded .. COL_GAP .. label .. " "
end

---@param key string
---@param label string
---@return integer
M.measure_hint_line = function(key, label)
	return fn.strdisplaywidth(hint_line(key, label, INDENT))
end

---Hard-cut `s` so the result fits `width`. If `s` already fits, returns it unchanged.
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

---@param title string
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
	-- Single overlong token, no whitespace: hard-cut rather than degrade to a lone ellipsis.
	if result == "" then
		return hard_cut_to_width(label, max_width) .. "…"
	end
	result = result:gsub("[%p]+%s*$", "")
	return fn.strdisplaywidth(result .. "…") <= max_width and (result .. "…") or result
end

-- Exported so a menu can budget a title against the panel width with the painter's own arithmetic.
M.fit_text = fit_text

---Wrap text to `width` on word boundaries. Differs from 'wrap'/'linebreak' (display-only,
---no height back) so the caller knows the line count *before* the window exists, enabling
---a one-pass measure-and-size. A word longer than `width` is hard-cut; the remainder is
---carried forward and never silently dropped.
---@param text string
---@param width integer
---@return string[]
M.wrap_text = function(text, width)
	width = math.max(1, width)
	local out = {}

	---Wrap a single paragraph to `width`. A word longer than `width` is hard-cut; the
	---remainder is fed back into the word loop on subsequent iterations.
	---@param paragraph string
	---@return string[]
	local function wrap_paragraph(paragraph)
		if paragraph == "" then
			return { "" }
		end
		local lines = {}
		local line = ""
	-- Words list built up front so a hard-cut's remainder can be appended as the
	-- next "word" and re-enter the normal break logic on the next pass.
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
				-- Remainder is what didn't fit; char-indexed because cut is in chars not bytes.
				local cut_chars = fn.strchars(cut)
				local remainder = fn.strcharpart(word, cut_chars)
				if remainder ~= "" then
					-- Feed the remainder back as the next word.
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
	if type(menu.items) == "function" then
		---@type MenuItem[]
		rows = menu.items(panel_width) or { { label = "", marks = { "PoppyDotNone" }, hl = nil } }
	end
	local set = {
		idx_width = #tostring(math.max(#rows, 1)),
		rows = rows,
	}
	-- Reserve a one-cell trailing margin so a truncated label never runs flush to the edge.
	local budget = panel_width - M.measure_item(set.idx_width, "") - 1
	for i, row in ipairs(set.rows) do
		set.rows[i] = {
			label = M.fit_text(row.label, budget),
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
		local category = shared.category_from_resolved(configured.config)
		local raw_title = configured.config.title or configured.name
		local runtime = state.runtime(configured.name)
		local is_hidden = runtime and runtime.hidden or false
		local is_active = runtime and runtime.active or false
		-- Reserve a one-cell trailing margin so a truncated label never runs flush to the edge.
		local label_max = menu_width - M.measure_item(idx_width, "") - 1
		local hl = is_active and ("PoppyCurrentRow" .. cap_category(category))
			or (is_hidden and category_hl_hidden[category])
			or category_hl[category]

		-- State dot always; category icon only when there's a category (placeholder items get neither).
		local marks = { pick_sign(category, is_active, is_hidden) }
		if category ~= "" then
			marks[#marks + 1] = pick_icon_sign(category, is_active)
		end

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

---Paint an item set into a body buffer. Sign ids are row-derived, so a repaint replaces rather than accumulates.
M.items_for_poppies = poppy_items

---@param buf integer
---@param spec MenuItems
---@return void
body.paint_items = function(buf, spec)
	api.nvim_buf_clear_namespace(buf, body_ns, 0, -1)

	local idx_width = spec.idx_width
	local lines = {}
	---@type fn.sign_placelist.list.item[]
	local placelist = {}

	for display_idx, e in ipairs(spec.rows) do
		-- Leading cell holds the cursor (pinned to col 0); every row needs it to keep the text column fixed.
		lines[display_idx] = "  " .. string.format("%" .. idx_width .. "d", display_idx) .. " " .. e.label
		for mark_idx, name in ipairs(e.marks or {}) do
			-- Sign id = row*10 + (mark_idx-1). Stable per row, so repaints replace, not accumulate.
			local sign_id = mark_idx == 1 and display_idx * 10 or (display_idx * 10 + mark_idx - 1)
			---@type fn.sign_placelist.list.item
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

---Plain stacked panel for a menu's question text. Anchored "SE" to the wrapper's right edge
---so it sits in the sidebar; "row" is the TOP offset (bottom = row + height). Keeps the body's
---signcolumn width so the question's left edge lines up with the items below.
---@param wrapper_win integer
---@param buf integer
---@param width integer
---@param height integer
---@param row integer
---@return integer? win
body.recreate_plain = function(wrapper_win, buf, width, height, row)
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local h = math.max(1, height)
	local config = {
		relative = "win",
		win = wrapper_win,
		anchor = "SE",
		row = row + h,
		col = wrapper_conf.width,
		width = width,
		height = h,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = false,
	}
	local win = api.nvim_open_win(buf, false, config)
	-- Match body's signcolumn so question and item text share a left edge.
	vim.wo[win].signcolumn = "yes:2"
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
	local buf = create_buf()
	return body.recreate_plain(wrapper_win, buf, width, height, row), buf
end

M.body = body

---@param key string
---@param label string
---@param indent string
---@return string
local fmt_hint = function(key, label, indent)
	return hint_line(key, label, indent)
end

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
	local wrapper_conf = api.nvim_win_get_config(wrapper_win)
	local col = opts.col or wrapper_conf.width
	local row = (opts.row or wrapper_conf.height) + (opts.row_offset or 0)
	local width = opts.width or wrapper_conf.width
	-- Legend lines only; the separator and trailing blank are added to `height` below.
	-- Derived from the caller's hint list when not given, so there's no line-count table
	-- keyed by legend name to keep in step with the content.
	local height = opts.height or #(opts.hints or {})

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
---@param keys PoppyKeys
---@param spec {string, string}[]|nil Explicit hint rows: PoppyKeys field name, label.
---@param wrapper_width integer
---@return void
hints.write_spec = function(buf, keys, spec, wrapper_width)
	if not keys or not spec then
		return
	end
	local sep = " " .. string.rep("─", math.max(0, wrapper_width - #INDENT)) .. " "
	local lines = { sep }

	for _, kp in ipairs(spec) do
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
