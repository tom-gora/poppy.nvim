local M = {}
local state = require("poppy.state")
local style = require("poppy.style")

local active_wins = {}

M.run = function(popup_name, opts)
	local popup_opts = opts.popups[popup_name]
	if not popup_opts then return end

	local width, height, row, col, align = style.calculate_layout(popup_opts, opts)

	-- Check if we have an existing hidden session
	local p_state = state.popups[popup_name]
	local bufnr
	if p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
		bufnr = p_state.bufnr
	else
		bufnr = vim.api.nvim_create_buf(false, false)
		local file_val = popup_opts.file
		if type(file_val) == "function" then
			file_val = file_val()
		end
		local file_path = vim.fn.expand(file_val)
		if vim.fn.filereadable(file_path) == 1 then
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("edit " .. vim.fn.fnameescape(file_path))
			end)
		end
		vim.bo[bufnr].buflisted = false
		vim.bo[bufnr].bufhidden = "hide"
		vim.bo[bufnr].swapfile = false
	end

	local win_opts = style.get_win_opts(
		width, height, row, col, popup_opts, opts, align,
		popup_opts.close_keymap or opts.close_keymap,
		popup_opts.hide_keymap or opts.hide_keymap
	)

	local win = vim.api.nvim_open_win(bufnr, true, win_opts)
	vim.api.nvim_win_set_var(win, "poppy_win", popup_name)
	active_wins[popup_name] = win

	vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:NormalFloat,SignColumn:NormalFloat"

	local hide_map = popup_opts.hide_keymap or opts.hide_keymap
	local close_map = popup_opts.close_keymap or opts.close_keymap

	vim.keymap.set("n", hide_map, function() M.hide_session(popup_name) end, { buffer = bufnr, noremap = true, silent = true })
	vim.keymap.set("n", close_map, function() M.close_session(popup_name) end, { buffer = bufnr, noremap = true, silent = true })

	state.popups[popup_name] = { active = true, hidden = false, bufnr = bufnr, win = win, title = popup_opts.title }
	vim.cmd("redrawstatus")
end

M.close_session = function(popup_name)
	local win = active_wins[popup_name]
	if win and vim.api.nvim_win_is_valid(win) then
		if #vim.api.nvim_list_wins() == 1 then vim.cmd("enew") end
		vim.api.nvim_win_close(win, true)
	end
	local p_state = state.popups[popup_name]
	if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
		vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
	end
	state.popups[popup_name] = nil
	active_wins[popup_name] = nil
	vim.cmd("redrawstatus")
end

M.hide_session = function(popup_name)
	local win = active_wins[popup_name]
	if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	if state.popups[popup_name] then
		state.popups[popup_name].active = false
		state.popups[popup_name].hidden = true
	end
	active_wins[popup_name] = nil
	vim.cmd("redrawstatus")
end

return M
