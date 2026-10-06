require("poppy._types")

local M = {}

local shared = require("poppy.core.shared")

---Bind poppy_action on a content buffer (normal + terminal-job modes). The content pane is a
---TUI/file buffer the user is actively working in, so only the key that summons the menu belongs
---here -- select/kill/exit_menu live on the menu body and would conflict with the content.
---@param buf integer
M.bind_poppy_action = function(buf)
	local keys = shared.keys()
	if not keys then
		return
	end

	local function opts_for(desc)
		return { buffer = buf, desc = desc }
	end

	vim.keymap.set(shared.NORM_TERM_MODES, keys.poppy_action, function()
		local menu = require("poppy.core.session.menu")
		menu.toggle_menu()
	end, opts_for("Poppy: Toggle menu"))
end

return M
