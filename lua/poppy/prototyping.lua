local M = {}
local poppy_state = require("poppy.state")
local poppy_sidebar_ns = vim.api.nvim_create_namespace("poppy_sidebar_ns")

local create_sidebar_window = function(popups_titles, wrapper_win, state)
	local active_popup_focosed = ""
	local active_popups_background = {}

	-- Check for nil state or empty table properly
	if not state or not state.popups or vim.tbl_isempty(state.popups) then
		return nil
	end

	-- FIX 2: Added pairs() to prevent Lua syntax crash
	for _, sp in pairs(state.popups) do
		if sp.active == true then
			active_popup_focosed = sp.title
		end
		if sp.hidden then
			table.insert(active_popups_background, sp.title)
		end
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_clear_namespace(buf, poppy_sidebar_ns, 0, -1)

	local lines = {}
	local index = 1

	table.insert(lines, " Configured Popups:")
	table.insert(lines, "")

	-- Temporary storage to map highlight groups to their final buffer row
	local highlights_to_apply = {}

	for i, title in ipairs(popups_titles) do
		local hl_group = nil

		if string.find(title, active_popup_focosed) then
			hl_group = "Visual"
		elseif vim.tbl_contains(active_popups_background, title) then
			hl_group = "ErrorMsg"
		else
			hl_group = "Error"
		end

		local line = string.format(" [%d] %s", index, title or "Unknown")
		table.insert(lines, line)

		-- FIX 3: Calculate the precise 0-indexed row in the final buffer
		local current_buffer_row = #lines - 1

		if hl_group then
			table.insert(highlights_to_apply, { row = current_buffer_row, hl = hl_group })
		end

		index = index + 1
	end

	-- FIX 1: Set lines FIRST so the buffer has rows to highlight
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Apply extmarks NOW that the text exists in the buffer
	for _, hl_data in ipairs(highlights_to_apply) do
		vim.api.nvim_buf_set_extmark(buf, poppy_sidebar_ns, hl_data.row, 0, {
			end_row = hl_data.row,
			line_hl_group = hl_data.hl,
		})
	end

	local wrapper_conf = vim.api.nvim_win_get_config(wrapper_win)
	local width = math.ceil((vim.o.columns - wrapper_conf.width) / 2)
	local heigth = wrapper_conf.height

	local sidebar_win_config = {
		relative = "win",
		width = width,
		height = heigth + 2,
		col = vim.o.columns - 22,
		row = -1,
		style = "minimal",
		border = "none",
		zindex = 201,
		focusable = false,
		win = wrapper_win,
	}

	local sidebar_win = vim.api.nvim_open_win(buf, false, sidebar_win_config)
	vim.api.nvim_set_option_value("winhl", "NormalFloat:Visual", { win = sidebar_win })

	return sidebar_win
end

M.create_main_window = function(popup_titles)
	if not poppy_state or not poppy_state.popups or next(poppy_state.popups) == nil then
		vim.notify("debug tmp msg: no popups opened yet", vim.log.levels.WARN)
		return nil
	end

	local buf = vim.api.nvim_create_buf(false, false)
	local width = math.floor(vim.o.columns * 0.75)
	local height = math.floor(vim.o.lines * 0.75)
	local wrapper_win_config = {
		relative = "editor",
		width = width,
		height = height,
		col = (vim.o.columns - width) / 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = "solid",
		footer = " " .. string.format(" Close: %s | Hide: %s", "<CTRL+X>", "<CTRL+Y>") .. " ",
		footer_pos = "left",
		zindex = 200,
		focusable = false,
	}

	local wrapper_win = vim.api.nvim_open_win(buf, true, wrapper_win_config)
	-- vim.api.nvim_set_option_value("winhl", "NormalFloat:Normal", { win = wrapper_win })
	local sidebar_win = create_sidebar_window(popup_titles, wrapper_win, poppy_state)
	if not sidebar_win or sidebar_win == nil then
		_G.poppy_prototyping_dirty_switch = nil
		return nil
	end

	return wrapper_win, sidebar_win
end

return M
