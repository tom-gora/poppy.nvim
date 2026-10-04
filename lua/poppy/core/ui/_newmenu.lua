require("poppy._types")

-- Menu backend. Eventually the renderer behind *every* menu in the plugin; today
-- it owns the row/hint/keymap/focus layer and nothing else. The wrapper float, the
-- header panel and all geometry stay in view.lua, which is deliberate: this module
-- takes buffers and widths, not window management, so the first slices cannot
-- regress panel mounting.
--
-- A menu is a spec:
--
--   id        string          identity, for diagnostics
--   width     "declared"|"content"   sidebar honours menu_width, dialog sizes to content
--   focusable boolean         may the body panel take focus
--   trap      boolean         block every exit route while up (dialog only)
--   rows      PoppyRow[]      what to draw; see render.list.paint
--   hints     {field,label}[] legend subset -- a dialog declares only what it binds
--   keymaps   {field,desc,fn}[] likewise; nothing is bound implicitly
--
-- The spec is normalised on the way in so consumers never re-check defaults, and so
-- a malformed spec fails once at the boundary rather than halfway through a paint.

local M = {}

local api = vim.api
local render = require("poppy.core.ui.render")
local shared = require("poppy.core.shared")

---@alias PoppyMenuWidth "declared"|"content"
---@alias PoppyMenuKeymap { field: string, desc: string, fn: function }

---@class PoppyMenuSpec
---@field id string
---@field width PoppyMenuWidth
---@field focusable boolean
---@field trap boolean
---@field rows PoppyRow[]
---@field hints {string, string}[]
---@field keymaps PoppyMenuKeymap[]

---@class PoppyMenuTarget
---@field list_buf integer Buffer painted with the row set.
---@field hints_buf integer? Buffer painted with the legend; skipped when nil.
---@field list_width integer Width the rows were trimmed against.
---@field hints_width integer Width the legend rule spans.

local function warn_unknown(id, key)
	shared.notify_warn("menu '%s': ignoring unknown key '%s'", tostring(id), tostring(key))
end

---Fill in defaults and drop unknown keys. Only `rows` and `id` are required; a
---menu with no keymaps simply renders and cannot be acted on, which is a legitimate
---state (the landing's body before a poppy is picked).
---@param spec table
---@return PoppyMenuSpec
M.normalize = function(spec)
	spec = spec or {}
	local out = {
		id = tostring(spec.id or "menu"),
		width = spec.width == "content" and "content" or "declared",
		focusable = spec.focusable == true,
		trap = spec.trap == true,
		rows = spec.rows or {},
		hints = spec.hints or {},
		keymaps = spec.keymaps or {},
	}
	for k in pairs(spec) do
		if k ~= "id" and k ~= "width" and k ~= "focusable" and k ~= "trap"
			and k ~= "rows" and k ~= "hints" and k ~= "keymaps" then
			warn_unknown(out.id, k)
		end
	end
	return out
end

---@param rows PoppyRow[]
---@param panel_width integer
---@return PoppyRowSet
local function rowset(rows, panel_width)
	local set = {
		idx_width = #tostring(math.max(#rows, 1)),
		rows = rows,
	}
	-- Trim here rather than at the call site: every consumer would otherwise have to
	-- remember, and a title that overruns is what crops a row against the panel edge.
	local budget = panel_width - render.measure_list_row(set.idx_width, "") - 1
	for i, row in ipairs(set.rows) do
		set.rows[i] = {
			title = render.trim_title(row.title, budget),
			marks = row.marks,
			hl = row.hl,
		}
	end
	if #set.rows == 0 then
		set.rows = { { title = "", marks = { "PoppyDotNone" }, hl = nil } }
	end
	return set
end

---Paint the body and legend into the given buffers. Safe to call repeatedly: the
---painters clear their namespaces first, and sign ids are row-derived, so a repaint
---replaces rather than accumulates.
---@param target PoppyMenuTarget
---@param spec table
---@return PoppyMenuSpec normalised
M.render = function(target, spec)
	local menu = M.normalize(spec)
	render.list.paint(target.list_buf, rowset(menu.rows, target.list_width))
	if target.hints_buf then
		render.hints.write_spec(target.hints_buf, shared.keys(), menu.hints, target.hints_width)
	end
	return menu
end

---Bind exactly the keymaps a spec declares -- no more. A dialog binds select and
---nothing else, so kill / exit_menu / poppy_action are simply absent rather than
---bound to a no-op, which keeps them visible in `get_keymap` as unclaimed.
---@param buf integer
---@param keymaps {string, string, function}[]
---@return integer bound number of mappings installed
M.bind = function(buf, keymaps)
	local keys = shared.keys()
	if not keys then
		return 0
	end
	local bound = 0
	for _, km in ipairs(keymaps or {}) do
		local lhs = keys[km[1]]
		if lhs and lhs ~= "" and type(km[3]) == "function" then
			vim.keymap.set(shared.NORM_TERM_MODES, lhs, km[3], {
				buffer = buf,
				desc = "Poppy: " .. km[2],
			})
			bound = bound + 1
		end
	end
	return bound
end

---Bind from a normalised spec. Separate from M.bind so a caller can repaint without
---rebinding, which matters for the popup that updates while the user is looking at it.
---@param buf integer
---@param menu PoppyMenuSpec
---@return integer bound
M.bind_spec = function(buf, menu)
	return M.bind(buf, menu.keymaps)
end

---Move the cursor onto a specific row, clamped. The body panel's own CursorMoved
---guard already pins the column; this only chooses the row, so a dialog can preselect
---the safer answer (see the "No" row preselected in the mock).
---@param win integer|nil
---@param row integer
---@return boolean moved
M.set_row = function(win, row)
	if not win or not api.nvim_win_is_valid(win) then
		return false
	end
	local ok = pcall(api.nvim_win_set_cursor, win, { math.max(1, row), 0 })
	return ok == true
end

return M