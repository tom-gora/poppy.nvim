local M = {}
local router = require("poppy.ui.router")

M.setup = function(buf, sorted_poppies, skip_kill)
	local map = vim.keymap.set
	local opts = require("poppy")._get_opts()
	local prefix = (opts and opts.prefix_bind) or "<M-p>"
	local wk = (opts and opts.whichkey_disable) and "which_key_ignore" or nil

	local function desc(text)
		if wk then return wk end
		return "Poppy: " .. text
	end

	for i = 1, #sorted_poppies do
		local item = sorted_poppies[i]
		local title = item.config.title or item.name
		map({"n", "t"}, prefix .. i, function()
			router.switch_to_poppy(i)
		end, { buffer = buf, desc = desc("Switch to " .. title) })
	end

	if not skip_kill then
		map({"n", "t"}, prefix .. "k", router.kill_current, { buffer = buf, desc = desc("Kill current poppy") })
	end
end

return M
