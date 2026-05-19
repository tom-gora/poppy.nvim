local M = {}
local shared_state = require("poppy.shared.state")

M.send_ipc = function(popup_name, action)
	local f = io.open(shared_state.STATE_FILE, "w")
	if f then
		f:write(string.format('{"action": "%s", "popup": "%s"}', action, popup_name))
		f:close()
	end
end

M.spawn_term = function(command, opts)
	if vim.fn.has("nvim-0.11") == 1 then
		opts.term = true
		return vim.fn.jobstart(command, opts)
	else
		---@diagnostic disable-next-line: deprecated
		return vim.fn.termopen(command, opts)
	end
end

return M
