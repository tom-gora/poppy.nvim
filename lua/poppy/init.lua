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

return M
