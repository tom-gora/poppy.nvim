local M = {}
local session = require("poppy.core.session")

M.toggle = function()
	session.toggle()
end

M.open = function(poppy_name)
	session.open(poppy_name)
end

M.close = function()
	session.close()
end

M.setup = function(user_opts)
	session.setup(user_opts)
end

-- Picker integration: select / kill a poppy by name or by index in the
-- sorted list. Use get_poppies() to map UI rows to indices.
M.switch_by_name = function(poppy_name)
	session.switch_by_name(poppy_name)
end

M.switch_by_index = function(index)
	session.switch_by_index(index)
end

M.kill_by_name = function(poppy_name)
	session.kill_by_name(poppy_name)
end

M.kill_by_index = function(index)
	session.kill_by_index(index)
end

-- Kills the poppy currently displayed in the content window and runs the
-- recovery flow (falls back to a hidden poppy or transitions to landing).
M.kill_active = function()
	session.kill_active()
end

-- Read-only data getters for users building custom pickers / statuslines /
-- whatever they want on top of poppy's native menu.
M.get_poppies = session.get_poppies
M.get_poppy_by_name = session.get_poppy_by_name
M.get_poppy_by_index = session.get_poppy_by_index
M.get_current_poppy = session.get_current_poppy
M.get_current_poppy_name = session.get_current_poppy_name
M.is_open = session.is_open

return M