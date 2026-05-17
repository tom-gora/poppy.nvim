local M = {}

local style = require("poppy.tmux.style")
local utils = require("poppy.tmux.utils")
local registry = require("poppy.tmux.registry")
local state = require("poppy.tmux.state")
local shared_state = require("poppy.shared.state")
local executor = require("poppy.executor")

---@param popup_name string
---@param opts PoppyConfig
M.run = function(popup_name, opts)
	local popup_opts = opts.popups[popup_name]
	if not popup_opts then
		print("Poppy: Popup '" .. popup_name .. "' not found.")
		return
	end

    local session_id = registry.get_session_name(popup_name)
    local width = popup_opts.width or opts.width
    local height = popup_opts.height or opts.height
    local title = popup_opts.title or opts.title
    local align = popup_opts.align_on_border or opts.align_on_border
    local position = popup_opts.position or opts.position
    
    local exec = executor.prepare(popup_opts.exec)

    -- Convert vim keys to tmux keys
    local to_tmux_key = function(vim_key)
        local key = vim_key:gsub("<", ""):gsub(">", "")
        key = key:gsub("C%-", "C-"):gsub("Esc", "Escape")
        return key
    end

    local hide_map = popup_opts.hide_keymap or opts.hide_keymap
    local close_map = popup_opts.close_keymap or opts.close_keymap
    
    local hide = to_tmux_key(hide_map)
    local close = (close_map == "<Esc><Esc>") and "Escape" or to_tmux_key(close_map)
    
    -- Ensure session exists
    if not state.has_session(session_id) then
        state.new_session(session_id, vim.loop.cwd(), exec)
    end
    
    -- Apply bindings and status hints
    -- Simplified command construction using file-based IPC:
    local hide_cmd = string.format("run-shell 'echo \"{\\\"action\\\": \\\"hide\\\", \\\"popup\\\": \\\"%s\\\"}\" > %s && tmux detach-client'", popup_name, shared_state.STATE_FILE)
    local close_cmd = string.format("run-shell 'echo \"{\\\"action\\\": \\\"close\\\", \\\"popup\\\": \\\"%s\\\"}\" > %s && tmux kill-window'", popup_name, shared_state.STATE_FILE)
    
    state.bind_key(hide, hide_cmd)
    state.bind_key(close, close_cmd)
    
    local raw_style = style.get_tmux_style_format("FloatTitle", false)
    local style_str = (raw_style ~= "") and ("#[" .. raw_style .. "]") or ""
    local status = string.format(" %sHide: %s | Close: %s ", style_str, hide_map, close_map)
    state.configure_session(session_id, status, align)

    -- Build display-popup command
    local cmd = { "tmux", "display-popup" }

    -- Size & Pos
    for _, flag in ipairs(vim.split(utils.get_position_flags(position), " ")) do
        table.insert(cmd, flag)
    end
    cmd[#cmd+1] = "-w"
    cmd[#cmd+1] = tostring(width * 100) .. "%"
    cmd[#cmd+1] = "-h"
    cmd[#cmd+1] = tostring(height * 100) .. "%"

    -- Title
    if title and title ~= "" then
        local raw_title_style = style.get_tmux_style_format("FloatTitle", false)
        local title_style = (raw_title_style ~= "") and ("#[" .. raw_title_style .. "]") or ""
        cmd[#cmd+1] = "-T"
        cmd[#cmd+1] = title_style .. "#[align=" .. align .. "]" .. title
    end

    -- Styles
    for _, arg in ipairs(style.prepare_popup_styles(popup_opts, opts)) do
        cmd[#cmd+1] = arg
    end

    -- Attach to persistent session on the poppy server
    cmd[#cmd+1] = "-E"
    cmd[#cmd+1] = string.format("tmux -L poppy -f /dev/null attach-session -t %s", session_id)

    -- Use jobstart to run display-popup asynchronously
    vim.fn.jobstart(cmd, {
        on_exit = function()
            -- If session is gone, it was a quit/close event.
            if not state.has_session(session_id) then
                -- Write 'close' action to IPC file
                local f = io.open(shared_state.STATE_FILE, "w")
                if f then
                    f:write(string.format('{"action": "close", "popup": "%s"}', popup_name))
                    f:close()
                end
            end
        end
    })
    
    shared_state.popups[popup_name] = { active = true, hidden = false }
    vim.cmd("redrawstatus")
end

M.kill_server = function()
    state.kill_server()
end

M.close_session = function(popup_name)
    local session_id = registry.get_session_name(popup_name)
    if state.has_session(session_id) then
        state.kill_session(session_id)
        shared_state.popups[popup_name] = nil
        vim.cmd("redrawstatus")
    end
end

M.hide_session = function(popup_name)
    local session_id = registry.get_session_name(popup_name)
    if state.has_session(session_id) then
        state.detach_session(session_id)
        if shared_state.popups[popup_name] then
            shared_state.popups[popup_name].active = false
            shared_state.popups[popup_name].hidden = true
        end
        vim.cmd("redrawstatus")
    end
end

return M
