local M = {}
local session = require("poppy.core.session")

M.toggle = session.toggle
M.open = session.open
M.close = session.close
M.setup = session.setup
M.switch_by_name = session.switch_by_name
M.switch_by_index = session.switch_by_index
M.kill_by_name = session.kill_by_name
M.kill_by_index = session.kill_by_index
M.kill_active = session.kill_active

M.get_poppies = session.get_poppies
M.get_poppy_by_name = session.get_poppy_by_name
M.get_poppy_by_index = session.get_poppy_by_index
M.get_current_poppy = session.get_current_poppy
M.get_current_poppy_name = session.get_current_poppy_name
M.is_open = session.is_open

return M
