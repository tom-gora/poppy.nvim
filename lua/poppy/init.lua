local M = {}
local setup = require("poppy.core.session.setup")

M.toggle = setup.toggle
M.open = setup.open
M.close = setup.close
M.setup = setup.setup
M.switch_by_name = setup.switch_by_name
M.switch_by_index = setup.switch_by_index
M.switch_by_cursor = setup.switch_by_cursor
M.kill_by_name = setup.kill_by_name
M.kill_by_index = setup.kill_by_index
M.kill_by_cursor = setup.kill_by_cursor
M.kill_active = setup.kill_active

M.get_poppies = setup.get_poppies
M.get_poppy_by_name = setup.get_poppy_by_name
M.get_poppy_by_index = setup.get_poppy_by_index
M.get_current_poppy = setup.get_current_poppy
M.get_current_poppy_name = setup.get_current_poppy_name
M.is_open = setup.is_open

return M
