local M = {}
local wrapper = require("poppy.ui.wrapper")
local sidebar_right = require("poppy.ui.sidebar_right")
local sidebar_left = require("poppy.ui.sidebar_left")
local content = require("poppy.ui.content")
local input = require("poppy.ui.input")
local poppy = require("poppy")
local banner = require("poppy.ui.banner")

M.open = function(poppy_name)
	local sorted_poppies = poppy.get_sorted_poppies()
	local opts = poppy._get_opts()
	local sw = (opts and opts.sidebars_width) or 25
	local last_poppy = M.current_poppy_name

	local win, wbuf = wrapper.create(opts)
	local s_left_win, s_left_buf = sidebar_left.create(win, sw)
	local s_right_win, s_right_buf = sidebar_right.create(win, sw)
    local c_win, c_buf = content.create(win, sw, sw)

    M._watch_content_window(c_win, sw)
	
	-- Store references
	M.wrapper_win = win
    M.wrapper_buf = wbuf
	M.sidebar_right_win = s_right_win
    M.sidebar_right_buf = s_right_buf
	M.sidebar_left_win = s_left_win
    M.sidebar_left_buf = s_left_buf
    M.content_win = c_win
    M.content_buf = c_buf
    M.current_poppy_name = nil
    
    if poppy_name then
        M.switch(poppy_name)
    elseif last_poppy and poppy.get_state().poppies[last_poppy] then
        M.switch(last_poppy)
    else
        banner.render(M.content_buf, M.content_win)
        input.setup(M.content_buf, sorted_poppies, true)
    end
	
	M.refresh(sorted_poppies)
	
	return M.wrapper_win, M.sidebar_right_win, M.sidebar_left_win, M.content_win
end

M.switch = function(poppy_name)
    local opts = poppy._get_opts()
    if not opts or not opts.poppies or not opts.poppies[poppy_name] then
        return
    end

    -- Mark current popup as hidden in state (don't close window, it's the shared content window)
    if M.current_poppy_name then
        local cur_state = poppy.get_state().poppies[M.current_poppy_name]
        if cur_state then
            cur_state.active = false
            cur_state.hidden = true
        end
    end

    local poppy_opts = opts.poppies[poppy_name]
    M.current_poppy_name = poppy_name
    local sorted_poppies = poppy.get_sorted_poppies()

    -- Render the new popup into the content window
    local mode = poppy_opts.mode
    require("poppy.modes." .. mode).run(poppy_name, opts, M.content_win)

    -- Re-bind prefix keys on whatever buffer is now in the content window
    input.setup(vim.api.nvim_win_get_buf(M.content_win), sorted_poppies)

    M.refresh(sorted_poppies)
    vim.api.nvim_set_current_win(M.content_win)

    if vim.bo[vim.api.nvim_win_get_buf(M.content_win)].buftype == "terminal" then
        vim.cmd("startinsert")
    end
end

M.refresh = function(sorted_poppies)
	sidebar_right.update(vim.api.nvim_win_get_buf(M.sidebar_right_win), sorted_poppies)
	sidebar_left.update(vim.api.nvim_win_get_buf(M.sidebar_left_win))
end

M.kill_current = function()
    if not M.current_poppy_name then return end
    local target = M.current_poppy_name
    local state = poppy.get_state()
    local p_state = state.poppies[target]
    local target_bufnr = p_state and p_state.bufnr

    state.poppies[target] = nil
    M.current_poppy_name = nil
    M._recover()

    if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
        vim.api.nvim_buf_delete(target_bufnr, { force = true })
    end

    pcall(vim.api.nvim_set_current_win, M.content_win)
end

M._recover = function()
    M.current_poppy_name = nil
    vim.schedule(function()
        if not M.is_open() or not vim.api.nvim_win_is_valid(M.content_win) then return end
        pcall(vim.api.nvim_win_set_buf, M.content_win, M.content_buf)

        local fallback_name = nil
        for name, ps in pairs(poppy.get_state().poppies) do
            if ps.hidden then
                fallback_name = name
                break
            end
        end

        local sorted = poppy.get_sorted_poppies()
        if fallback_name then
            M.switch(fallback_name)
        else
            banner.render(M.content_buf, M.content_win)
            input.setup(M.content_buf, sorted, true)
            M.refresh(sorted)
        end
        pcall(vim.api.nvim_set_current_win, M.content_win)
    end)
end


M.cleanup = function()
    if M.current_poppy_name then
        local ps = poppy.get_state().poppies[M.current_poppy_name]
        if ps then
            ps.active = false
            ps.hidden = true
            ps.win = nil
        end
    end

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

M.is_open = function()
    return M.wrapper_win ~= nil and vim.api.nvim_win_is_valid(M.wrapper_win)
end

M._watch_content_window = function(win_id, sidebars_width)
    local sw = sidebars_width or 25
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(win_id),
        once = true,
        group = vim.api.nvim_create_augroup("poppy_ui", { clear = false }),
        callback = function()
            if not M.is_open() then return end
            local c_win, c_buf = content.create(M.wrapper_win, sw, sw)
            M.content_win = c_win
            M.content_buf = c_buf
            M._watch_content_window(c_win, sw)
            if M.current_poppy_name then
                M.kill_current()
            else
                local sorted = poppy.get_sorted_poppies()
                vim.api.nvim_win_set_buf(M.content_win, M.content_buf)
                banner.render(M.content_buf, M.content_win)
                input.setup(M.content_buf, sorted, true)
                M.refresh(sorted)
            end
        end,
    })
end

return M
