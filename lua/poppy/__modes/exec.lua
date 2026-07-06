local M = {}
local input = require("poppy.ui.input")

M.init_buffer = function(win, popup_name, popup_opts, opts, sorted_popups)
    local hide_map = popup_opts.hide_keymap or opts.hide_keymap
	local close_map = popup_opts.close_keymap or opts.close_keymap

    -- Create a fresh, pristine buffer for terminal
    local term_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(win, term_buf)
    
    -- Setup keybinds on the new buffer
    input.setup(term_buf, sorted_popups)

    -- Spawn terminal using buf_call to execute in the fresh buffer context
    vim.api.nvim_buf_call(term_buf, function()
        vim.fn.termopen(popup_opts.exec, {
            on_exit = function()
                -- Handle cleanup
            end,
        })
    end)

    vim.api.nvim_buf_set_name(term_buf, " Poppy: " .. popup_name .. " ")
    vim.cmd("startinsert")
end

return M

