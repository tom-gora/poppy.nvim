local M = {}
local executor = require("poppy.executor")
local shared_state = require("poppy.shared.state")
local utils = require("poppy.backends.term.utils")
local style = require("poppy.backends.term.style")

local active_wins = {}

---@param popup_name string
---@param opts PoppyConfig
M.run = function(popup_name, opts)
	local popup_opts = opts.popups[popup_name]
	if not popup_opts then
		return
	end

	local exec = executor.prepare(popup_opts.exec)
	local hide_map = popup_opts.hide_keymap or opts.hide_keymap
	local close_map = popup_opts.close_keymap or opts.close_keymap

	local width, height, row, col, align = style.calculate_layout(popup_opts, opts)

	local bufnr = nil
	local win = nil

	-- Check if we have an existing hidden session for this popup
	local p_state = shared_state.popups[popup_name]
	if p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
		bufnr = p_state.bufnr
	else
		bufnr = vim.api.nvim_create_buf(false, true)
	end

	local win_opts = style.get_win_opts(width, height, row, col, popup_opts, opts, align, hide_map, close_map)

	win = vim.api.nvim_open_win(bufnr, true, win_opts)
	vim.api.nvim_win_set_var(win, "poppy_popup_name", popup_name)
	active_wins[popup_name] = win

	-- Apply minimal UI settings
	vim.opt_local.number = false
	vim.opt_local.relativenumber = false
	vim.opt_local.cursorline = false
	-- Hide statusline by matching it to the background
	vim.opt_local.winhighlight =
		"Normal:NormalFloat,FloatBorder:NormalFloat,StatusLine:NormalFloat,StatusLineNC:NormalFloat"

	vim.cmd("startinsert")

	-- Set local keymaps

	vim.keymap.set("t", hide_map, function()
		utils.send_ipc(popup_name, "hide")
		M.hide_session(popup_name)
	end, { buffer = bufnr, noremap = true, silent = true })

	vim.keymap.set("t", close_map, function()
		utils.send_ipc(popup_name, "close")
		M.close_session(popup_name)
	end, { buffer = bufnr, noremap = true, silent = true })

	if not p_state or not p_state.hidden then
		utils.spawn_term(exec, {
			on_exit = function()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end
				utils.send_ipc(popup_name, "close")
				shared_state.popups[popup_name] = nil
				active_wins[popup_name] = nil
				vim.cmd("redrawstatus")
			end,
		})
	end

	vim.api.nvim_buf_set_name(bufnr, " Poppy: " .. popup_name .. " ")

	shared_state.popups[popup_name] = { active = true, hidden = false, bufnr = bufnr, win = win }
end

M.close_session = function(popup_name)
	local win = active_wins[popup_name]
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end

	local p_state = shared_state.popups[popup_name]
	if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
		vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
	end

	shared_state.popups[popup_name] = nil
	active_wins[popup_name] = nil
	vim.cmd("redrawstatus")
end

M.hide_session = function(popup_name)
	local win = active_wins[popup_name]
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end

	if shared_state.popups[popup_name] then
		shared_state.popups[popup_name].active = false
		shared_state.popups[popup_name].hidden = true
	end
	active_wins[popup_name] = nil
	vim.cmd("redrawstatus")
end

return M
