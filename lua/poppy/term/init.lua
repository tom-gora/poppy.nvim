local M = {}
local executor = require("poppy.executor")
local shared_state = require("poppy.shared.state")

local active_wins = {}

local function send_ipc(popup_name, action)
	local f = io.open(shared_state.STATE_FILE, "w")
	if f then
		f:write(string.format('{"action": "%s", "popup": "%s"}', action, popup_name))
		f:close()
	end
end

---@param popup_name string
---@param opts PoppyConfig
M.run = function(popup_name, opts)
	local popup_opts = opts.popups[popup_name]
	if not popup_opts then
		return
	end

	local exec = executor.prepare(popup_opts.exec)
	local width = math.floor(vim.o.columns * (popup_opts.width or opts.width))
	local height = math.floor(vim.o.lines * (popup_opts.height or opts.height))
	local position = popup_opts.position or opts.position or "center"
	local align = popup_opts.align_on_border or opts.align_on_border or "centre"
	local hide_map = popup_opts.hide_keymap or opts.hide_keymap
	local close_map = popup_opts.close_keymap or opts.close_keymap

	local col = 0
	if position == "left" then
		col = 0
	elseif position == "right" then
		col = vim.o.columns - width
	else -- center
		col = math.floor((vim.o.columns - width) / 2)
	end

	local row = math.floor((vim.o.lines - height) / 2)

	local bufnr = nil
	local win = nil

	-- Check if we have an existing hidden session for this popup
	local p_state = shared_state.popups[popup_name]
	if p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
		bufnr = p_state.bufnr
	else
		bufnr = vim.api.nvim_create_buf(false, true)
	end

	win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = popup_opts.border or opts.border,
		title = " " .. (popup_opts.title or opts.title) .. " ",
		title_pos = align == "centre" and "center" or align,
		footer = " " .. string.format("Hide: %s | Close: %s", hide_map, close_map) .. " ",
		footer_pos = align == "centre" and "center" or align,
	})
	active_wins[popup_name] = win

	-- Apply minimal UI settings
	vim.opt_local.number = false
	vim.opt_local.relativenumber = false
	vim.opt_local.cursorline = false
	-- Hide statusline by matching it to the background
	vim.opt_local.winhighlight = "Normal:NormalFloat,FloatBorder:NormalFloat,StatusLine:NormalFloat,StatusLineNC:NormalFloat"

	vim.cmd("startinsert")

	-- Set local keymaps

	vim.keymap.set("t", hide_map, function()
		send_ipc(popup_name, "hide")
		M.hide_session(popup_name)
	end, { buffer = bufnr, noremap = true, silent = true })

	vim.keymap.set("t", close_map, function()
		send_ipc(popup_name, "close")
		M.close_session(popup_name)
	end, { buffer = bufnr, noremap = true, silent = true })

	if not p_state or not p_state.hidden then
		vim.fn.termopen(exec, {
			on_exit = function()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end
				send_ipc(popup_name, "close")
				shared_state.popups[popup_name] = nil
				active_wins[popup_name] = nil
				vim.cmd("redrawstatus")
			end,
		})
	end

	vim.api.nvim_buf_set_name(bufnr, "Poppy: " .. popup_name)

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
