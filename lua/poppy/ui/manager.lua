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
        input.setup(M.content_buf, sorted_popups)
    end
	
	M.refresh(sorted_popups)
	
	return M.wrapper_win, M.sidebar_right_win, M.sidebar_left_win, M.content_win
end

M.switch = function(popup_name)
    M.current_popup_name = popup_name
    local opts = poppy._get_opts()
    local popup_opts = opts.popups[popup_name]
    local sorted_popups = poppy.get_sorted_popups()
    
    -- Set buffer to modifiable to clear/set content
    vim.api.nvim_set_option_value("modifiable", true, { buf = M.content_buf })
    vim.api.nvim_buf_set_lines(M.content_buf, 0, -1, false, {})
    
    -- Renderer logic
    if popup_opts.exec then
        require("poppy.__modes.exec").init_buffer(M.content_win, popup_name, popup_opts, opts, sorted_popups)
    end
    
    -- Setup input AFTER mode might have replaced the buffer
    input.setup(vim.api.nvim_win_get_buf(M.content_win), sorted_popups)
    
    M.refresh(sorted_popups)
end

M.refresh = function(sorted_popups)
	sidebar_right.update(vim.api.nvim_win_get_buf(M.sidebar_right_win), sorted_popups)
	sidebar_left.update(vim.api.nvim_win_get_buf(M.sidebar_left_win))
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
