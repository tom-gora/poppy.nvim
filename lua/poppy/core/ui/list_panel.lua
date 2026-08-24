require("poppy._types")

local M = {}
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local namespace = vim.api.nvim_create_namespace("poppy_list_panel")

local sign_group = "poppy_list"

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

-- Cell 1 = dot, cells 2-3 = icon. Two signs per line at different priorities.
-- Higher priority renders leftmost, so dot (priority 10) wins cell 1 and
-- icon (priority 5) renders to the right of it.
local DOT_PRIORITY = 10
local ICON_PRIORITY = 5

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
M.create = function(wrapper_win, menu_width, focusable, hint_height, row_override)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	---@type vim.api.keyset.create_autocmd
	local insert_enter_autocmd = {
		buffer = buf,
		callback = function()
			vim.cmd("stopinsert")
		end,
	}
	vim.api.nvim_create_autocmd("InsertEnter", insert_enter_autocmd)
	return M.recreate(wrapper_win, buf, menu_width, focusable, hint_height, row_override), buf
end

---@param wrapper_win integer
---@param buf integer
---@param menu_width integer
---@param focusable boolean
---@param hint_height? integer
---@param row_override? integer
---@return integer? win
M.recreate = function(wrapper_win, buf, menu_width, focusable, hint_height, row_override)
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
M.update = function(buf, poppies, icons, menu_width)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

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
			vim.api.nvim_buf_set_extmark(buf, namespace, display_idx - 1, 0, hl_extmark)
		end
	end

	vim.fn.sign_placelist(placelist)
end

return M
