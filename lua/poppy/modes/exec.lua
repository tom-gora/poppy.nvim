local M = {}
local state = require("poppy.state")
local utils = require("poppy.modes.utils")
local style = require("poppy.style")

local active_wins = {}

M._prototype_run = function(popup_name, opts)
	local popup_opts = opts.popups[popup_name]
	if not popup_opts then
		return
	end

	local hide_map = popup_opts.hide_keymap or opts.hide_keymap
	local close_map = popup_opts.close_keymap or opts.close_keymap
	local width, height, row, col, align = style.calculate_layout(popup_opts, opts)

	local p_state = state.popups[popup_name]
	local bufnr = (p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr))
			and p_state.bufnr
		or vim.api.nvim_create_buf(false, false)

	local win_opts = style.get_win_opts(width, height, row, col, popup_opts, opts, align, hide_map, close_map)
	local win = vim.api.nvim_open_win(bufnr, true, win_opts)
	vim.api.nvim_win_set_var(win, "poppy_win", popup_name)
	active_wins[popup_name] = win

	vim.opt_local.winhighlight =
		"Normal:NormalFloat,FloatBorder:NormalFloat,StatusLine:NormalFloat,StatusLineNC:NormalFloat"
	vim.cmd("startinsert")

	vim.keymap.set("t", hide_map, function()
		M.hide_session(popup_name)
	end, { buffer = bufnr, noremap = true, silent = true })
	vim.keymap.set("t", close_map, function()
		M.close_session(popup_name)
	end, { buffer = bufnr, noremap = true, silent = true })

	if not p_state or not p_state.hidden then
		utils.spawn_term(popup_opts.exec, {
			on_exit = function()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end
				state.popups[popup_name] = nil
				active_wins[popup_name] = nil
				vim.cmd("redrawstatus")
			end,
		})
	end

	pcall(vim.api.nvim_buf_set_name, bufnr, " Poppy: " .. popup_name .. " ")
	state.popups[popup_name] = { active = true, hidden = false, bufnr = bufnr, win = win, title = popup_opts.title }
end

M.get_or_create_buffer = function(popup_name, opts)
	local popup_opts = opts.popups[popup_name]
	local p_state = state.popups[popup_name]
	local bufnr = (p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr))
			and p_state.bufnr
		or vim.api.nvim_create_buf(false, false)
	
	-- Setup for first time
	if not p_state or (not p_state.active and not p_state.hidden) then
        vim.api.nvim_buf_call(bufnr, function()
            pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
            utils.spawn_term(popup_opts.exec, {
                on_exit = function()
                    state.popups[popup_name] = nil
                    vim.cmd("redrawstatus")
                end,
            })
        end)
    end
    
	pcall(vim.api.nvim_buf_set_name, bufnr, " Poppy: " .. popup_name .. " ")
	return bufnr
end

M.run = function(popup_name, opts, parent_win)
	local popup_opts = opts.popups[popup_name]
	if not popup_opts then
		return
	end

	local bufnr = M.get_or_create_buffer(popup_name, opts)
    
    local hide_map = popup_opts.hide_keymap or opts.hide_keymap
    local close_map = popup_opts.close_keymap or opts.close_keymap
	
	if parent_win then
	    vim.api.nvim_win_set_buf(parent_win, bufnr)
	    active_wins[popup_name] = parent_win
	else
	    -- Fallback to old behavior
	    local width, height, row, col, align = style.calculate_layout(popup_opts, opts)
	    local win_opts = style.get_win_opts(width, height, row, col, popup_opts, opts, align, hide_map, close_map)
	    local win = vim.api.nvim_open_win(bufnr, true, win_opts)
	    vim.api.nvim_win_set_var(win, "poppy_win", popup_name)
	    active_wins[popup_name] = win
        vim.opt_local.winhighlight = "Normal:NormalFloat,FloatBorder:NormalFloat,StatusLine:NormalFloat,StatusLineNC:NormalFloat"
        vim.cmd("startinsert")
	end
    
	-- Setup keymaps
	vim.keymap.set("t", hide_map, function()
		M.hide_session(popup_name)
	end, { buffer = bufnr, noremap = true, silent = true })
	vim.keymap.set("t", close_map, function()
		M.close_session(popup_name)
	end, { buffer = bufnr, noremap = true, silent = true })

	state.popups[popup_name] = { active = true, hidden = false, bufnr = bufnr, win = active_wins[popup_name], title = popup_opts.title }
end


M.close_session = function(popup_name)
	local win = active_wins[popup_name]
	if win and vim.api.nvim_win_is_valid(win) then
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
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	if state.popups[popup_name] then
		state.popups[popup_name].active = false
		state.popups[popup_name].hidden = true
	end
	active_wins[popup_name] = nil
	vim.cmd("redrawstatus")
end

return M
