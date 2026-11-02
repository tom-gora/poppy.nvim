require("poppy._types")

local M = {}
local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")

local INDENT = "   "
local KEY_COL = 5
local COL_GAP = "  "

local SIGN_COL = 4

local header_ns = api.nvim_create_namespace("poppy_header_panel")
local TITLE_MARK = 1
local DOT_MARK = 2
local SEP_MARK = 3

---Paint the header text + extmarks into an already-open header window.
---@param _win integer
---@param buf integer
---@param width integer
M.header_paint = function(_win, buf, width)
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
end

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

---Attach CursorMoved/CursorHold guards to a body buffer. Idempotent on repeat
---calls because the augroup is `clear = false` and the autocmds are buffer-scoped.
---@param buf integer
M.body_attach_guards = function(buf)
	api.nvim_clear_autocmds({ group = body_autocmd_group, buffer = buf })
	shared.guard_insert_mode(buf)
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
	if shared.opts_field("autohide_menu") then
		api.nvim_create_autocmd("CursorHold", {
			group = body_autocmd_group,
			buffer = buf,
			callback = function()
				require("poppy.core.session.menu").exit_menu()
			end,
		})
	end
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

---`wrap`/`linebreak` window options are display-only and do not affect the returned count.
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

M.body = body

local hints_ns = api.nvim_create_namespace("poppy_hints_panel")
local hints = {}

---@param parent_win integer
---@param keys PoppyKeys?
---@return integer? win
---@return integer? buf
hints.create_bottom_right = function(parent_win, keys)
	if not keys then
		local buf = api.nvim_create_buf(false, true)
		return nil, buf
	end

	local text = " " .. keys.poppy_action .. " Menu "
	local desc = layout.menu_hint_badge_config(parent_win, text)
	local win, buf = layout.open_scratch(desc, "hints")
	shared.with_modifiable(buf, function()
		api.nvim_buf_set_lines(buf, 0, -1, false, { text })
	end)
	return win, buf
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
