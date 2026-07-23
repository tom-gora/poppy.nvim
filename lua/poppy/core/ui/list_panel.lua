local M = {}
local style = require("poppy.core.ui.style")
local namespace = vim.api.nvim_create_namespace("poppy_list_panel")
local mv = 25

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

M.create = function(wrapper_win, width, focusable, hint_height, row_override)
	if width then
		mv = width
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	vim.api.nvim_create_autocmd("InsertEnter", {
		buffer = buf,
		callback = function()
			vim.cmd("stopinsert")
		end,
	})
	return M.recreate(wrapper_win, buf, width, focusable, hint_height, row_override), buf
end

M.recreate = function(wrapper_win, buf, width, focusable, hint_height, row_override)
	if width then
		mv = width
	end
	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local h = math.max(1, (hint_height and (wrapper_conf.height - hint_height) or (wrapper_conf.height - 1)))
	if row_override then
		h = math.max(1, h - row_override)
	end

	local config = {
		relative = "win",
		width = mv,
		height = h,
		col = wrapper_conf.width - mv,
		row = row_override or 0,
		style = "minimal",
		border = "none",
		zindex = 201,
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

M.update = function(buf, sorted_poppies, poppies, icons)
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

	local lines = {}
	local rows = {}
	local placelist = {}
	local idx_width = max_index_width(#sorted_poppies)

	for display_idx, item in ipairs(sorted_poppies) do
		local icon = (icons and icons[item.config.cat]) or " "
		local cat = item.config.cat or item.config.mode
		local raw_title = item.config.title or item.name
		local ps = poppies[item.name]
		local is_hidden = ps and ps.hidden
		local is_active = ps and ps.active
		local dot = (is_active or is_hidden) and "•" or " "
		local icon_w = vim.fn.strdisplaywidth(icon)
		local title_max = mv - 1 - icon_w - 1 - idx_width - 1
		local title = trim_title(raw_title, title_max)
		local line = string.format("%s %" .. idx_width .. "d %s", icon, display_idx, title)
		table.insert(lines, line)

		local hl = nil
		if is_active then
			local cap = cat:sub(1, 1):upper() .. cat:sub(2)
			hl = "PoppyCurrentRow" .. cap
		elseif is_hidden then
			hl = cat_hl_hidden[cat]
		else
			hl = cat_hl[cat]
		end
		table.insert(rows, { row = #lines - 1, hl = hl, name = item.name })

		table.insert(placelist, {
			buffer = buf,
			group = sign_group,
			id = display_idx,
			lnum = display_idx,
			name = pick_sign(dot, cat, is_active, is_hidden),
		})
	end

	if #lines == 0 then
		table.insert(lines, "")
		table.insert(placelist, {
			buffer = buf,
			group = sign_group,
			id = 1,
			lnum = 1,
			name = "PoppyDotNone",
		})
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	for _, entry in ipairs(rows) do
		if entry.hl then
			vim.api.nvim_buf_set_extmark(buf, namespace, entry.row, 0, {
				end_row = entry.row,
				line_hl_group = entry.hl,
			})
		end
	end

	vim.fn.sign_placelist(placelist)
end

return M
