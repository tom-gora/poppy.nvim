require("poppy._types")

local M = {}
local shared = require("poppy.core.shared")

---@param buf integer
M.bind_poppy_action = function(buf)
	local keys = shared.keys()
	if not keys then
		return
	end
	local bound, _ = shared.resolve_key(keys.poppy_action)

	local function opts_for(desc)
		return { buffer = buf, desc = desc }
	end

	vim.keymap.set(shared.NORM_TERM_MODES, bound, function()
		local menu = require("poppy.core.session.menu")
		menu.toggle_menu()
	end, opts_for("Poppy: Toggle menu"))
end

return M
