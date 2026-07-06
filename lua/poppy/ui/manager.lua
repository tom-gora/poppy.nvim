local M = {}
local wrapper = require("poppy.ui.wrapper")
local sidebar_right = require("poppy.ui.sidebar_right")
local sidebar_left = require("poppy.ui.sidebar_left")
local content = require("poppy.ui.content")
local input = require("poppy.ui.input")
local poppy = require("poppy")
local banner = require("poppy.ui.banner")

M.open = function(popup_name)
	local sorted_popups = poppy.get_sorted_popups()
	
	local win, wbuf = wrapper.create({})
	local s_left_win, s_left_buf = sidebar_left.create(win)
	local s_right_win, s_right_buf = sidebar_right.create(win)
    local c_win, c_buf = content.create(win, 22, 22)
	
	-- Store references
	M.wrapper_win = win
    M.wrapper_buf = wbuf
	M.sidebar_right_win = s_right_win
    M.sidebar_right_buf = s_right_buf
	M.sidebar_left_win = s_left_win
    M.sidebar_left_buf = s_left_buf
    M.content_win = c_win
    M.content_buf = c_buf
    M.current_popup_name = nil
    
    if popup_name then
        M.switch(popup_name)
    else
        banner.render(M.content_buf, M.content_win)
        input.setup(M.content_buf, sorted_popups, true)
    end
	
	M.refresh(sorted_popups)
	
	return M.wrapper_win, M.sidebar_right_win, M.sidebar_left_win, M.content_win
end

M.switch = function(popup_name)
    local opts = poppy._get_opts()
    if not opts or not opts.popups or not opts.popups[popup_name] then
        return
    end

    -- Mark current popup as hidden in state (don't close window, it's the shared content window)
    if M.current_popup_name then
        local cur_state = poppy.get_state().popups[M.current_popup_name]
        if cur_state then
            cur_state.active = false
            cur_state.hidden = true
        end
    end

    local popup_opts = opts.popups[popup_name]
    M.current_popup_name = popup_name
    local sorted_popups = poppy.get_sorted_popups()

    -- Render the new popup into the content window
    local mode = popup_opts.mode
    require("poppy.modes." .. mode).run(popup_name, opts, M.content_win)

    -- Re-bind prefix keys on whatever buffer is now in the content window
    input.setup(vim.api.nvim_win_get_buf(M.content_win), sorted_popups)

    M.refresh(sorted_popups)
    vim.api.nvim_set_current_win(M.content_win)
end

M.refresh = function(sorted_popups)
	sidebar_right.update(vim.api.nvim_win_get_buf(M.sidebar_right_win), sorted_popups)
	sidebar_left.update(vim.api.nvim_win_get_buf(M.sidebar_left_win))
end

M.kill_current = function()
    if not M.current_popup_name then return end
    local target = M.current_popup_name
    local state = poppy.get_state()
    local p_state = state.popups[target]
    local target_bufnr = p_state and p_state.bufnr

    -- Clear state first
    state.popups[target] = nil
    M.current_popup_name = nil

    -- Find fallback: any remaining hidden popup
    local fallback_name = nil
    for name, ps in pairs(state.popups) do
        if ps.hidden then
            fallback_name = name
            break
        end
    end

    local sorted = poppy.get_sorted_popups()

    if fallback_name then
        M.switch(fallback_name)
    else
        -- Show banner (replaces buffer in content_win first)
        vim.api.nvim_win_set_buf(M.content_win, M.content_buf)
        banner.render(M.content_buf, M.content_win)
        input.setup(M.content_buf, sorted, true)
        M.refresh(sorted)
    end

    -- Now safe to delete the killed buffer (no longer displayed in content_win)
    if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
        vim.api.nvim_buf_delete(target_bufnr, { force = true })
    end

    pcall(vim.api.nvim_set_current_win, M.content_win)
end


M.cleanup = function()
    local buffers = {M.wrapper_buf, M.sidebar_right_buf, M.sidebar_left_buf, M.content_buf}
    local windows = {M.wrapper_win, M.sidebar_right_win, M.sidebar_left_win, M.content_win}
    
    for _, win in ipairs(windows) do
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    for _, buf in ipairs(buffers) do
        if buf and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end

return M
