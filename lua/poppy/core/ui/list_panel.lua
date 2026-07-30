local M = {}
local style = require("poppy.core.ui.style")
local layout = require("poppy.core.ui.layout")
local util = require("poppy.core.util")
local namespace = vim.api.nvim_create_namespace("poppy_list_panel")

local sign_group = "poppy_list"

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

M.create = function(wrapper_win, menu_width, focusable, hint_height, row_override)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	vim.api.nvim_create_autocmd("InsertEnter", {
		buffer = buf,
		callback = function()
			vim.cmd("stopinsert")
		end,
	})
	return M.recreate(wrapper_win, buf, menu_width, focusable, hint_height, row_override), buf
end

M.recreate = function(wrapper_win, buf, menu_width, focusable, hint_height, row_override)
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local padding_offset = 2
	local hint_offset = hint_height and hint_height + padding_offset
	local h = math.max(1, (hint_height and (wrapper_conf.height - hint_offset) or (wrapper_conf.height - 3)))
	if row_override then
		h = math.max(1, h - row_override)
	end

	local config = {
		relative = "win",
		width = menu_width,
		height = h,
		col = wrapper_conf.width - menu_width,
		row = row_override or 0,
		style = "minimal",
		border = "none",
		zindex = layout.POPPY_Z_INDEX,
		focusable = focusable == true,
		win = wrapper_win,
	}

	local win = vim.api.nvim_open_win(buf, false, config)
	vim.wo[win].signcolumn = "yes:1"
	vim.api.nvim_set_option_value("statuscolumn", "%s", { win = win })
	style.apply_list_panel_style(win)
	vim.api.nvim_win_set_var(win, "poppy_ui_window", true)
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

local max_index_width = function(count)
	return #tostring(count)
end

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

M.update = function(buf, sorted_poppies, poppies, icons, menu_width)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

	local idx_width = max_index_width(#sorted_poppies)
	local entries = {}

	for display_idx, item in ipairs(sorted_poppies) do
		local cat = util.cat(item.config)
		local icon = (icons and icons[cat]) or " "
		local raw_title = item.config.title or item.name
		local ps = poppies[item.name]
		local is_hidden = ps and ps.hidden or false
		local is_active = ps and ps.active or false
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
			name = item.name,
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
	local placelist = {}
	for display_idx, e in ipairs(entries) do
		lines[display_idx] = string.format("%s %" .. idx_width .. "d %s", e.icon, display_idx, e.title)
		placelist[display_idx] = {
			buffer = buf,
			group = sign_group,
			id = display_idx,
			lnum = display_idx,
			name = pick_sign((e.is_active or e.is_hidden) and "•" or " ", e.cat, e.is_active, e.is_hidden),
		}
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	for display_idx, e in ipairs(entries) do
		if e.hl then
			vim.api.nvim_buf_set_extmark(buf, namespace, display_idx - 1, 0, {
				end_row = display_idx - 1,
				line_hl_group = e.hl,
			})
		end
	end

	vim.fn.sign_placelist(placelist)
end

return M
