local M = {}

M.SOCKET_NAME = "poppy_" .. vim.fn.getpid()
M.SOCKET_PATH = "/tmp/tmux-" .. vim.loop.getuid() .. "/" .. M.SOCKET_NAME

---@param cmd string[]
---@return string
M.run = function(cmd)
	-- Add -f /dev/null to force ignoring the main tmux.conf
	local full_cmd = { "tmux", "-L", M.SOCKET_NAME, "-f", "/dev/null" }
	for _, part in ipairs(cmd) do
		table.insert(full_cmd, part)
	end

	-- Using vim.fn.system directly avoids shell pipe interpretation
	return vim.fn.system(full_cmd)
end

---@param session_id string
---@return boolean
M.has_session = function(session_id)
	local result = M.run({ "has-session", "-t", session_id })
	return result == ""
end

---@param session_id string
---@param format string
---@param alignment string
M.configure_session = function(session_id, format, alignment)
	-- Ensure status bar is on, pane border is off
	M.run({ "set-option", "-t", session_id, "status", "on" })
	M.run({ "set-option", "-t", session_id, "pane-border-status", "off" })

	-- Clear and set format
	M.run({ "set-option", "-t", session_id, "status-left", "" })
	M.run({ "set-option", "-t", session_id, "status-right", "" })
	M.run({ "set-option", "-t", session_id, "status-justify", "centre" })
	M.run({ "set-option", "-t", session_id, "status-format[0]", "#[align=" .. alignment .. " bold]" .. format })
	M.run({ "set-option", "-t", session_id, "status-style", "bg=default,fg=white" })
end

M.new_session = function(session_id, path, exec)
	M.run({ "start-server" })
	M.run({ "new-session", "-d", "-s", session_id, "-c", path, exec })
	M.run({ "set-option", "-t", session_id, "exit-empty", "on" })
end

---@param format string
---@param session_id string
M.set_border_format = function(format, session_id)
	-- pane-border-format is a window option
	M.run({ "set-option", "-w", "-t", session_id, "pane-border-format", format })
end

---@param key string
---@param cmd string
M.bind_key = function(key, cmd)
	M.run({ "bind-key", "-n", key, cmd })
end

M.set_hook = function(hook_name, cmd)
	M.run({ "set-hook", "-g", hook_name, cmd })
end

M.kill_session = function(session_id)
	M.run({ "kill-session", "-t", session_id })
end

M.detach_session = function(session_id)
	M.run({ "detach-client", "-s", session_id })
end

M.kill_server = function()
	M.run({ "kill-server" })
end

return M
