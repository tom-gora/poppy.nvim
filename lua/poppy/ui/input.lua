local M = {}
local router = require("poppy.ui.router")

M.setup = function(buf, sorted_popups, skip_kill)
	local map = vim.keymap.set
	
	-- Dismiss: <M-p><M-p>
	map({"n", "t"}, "<M-p><M-p>", router.dismiss, { buffer = buf, desc = "Poppy: Dismiss UI" })

	-- Switch tabs: <M-p>[1-9]
	for i = 1, #sorted_popups do
		local item = sorted_popups[i]
		local title = item.config.title or item.name
		map({"n", "t"}, "<M-p>" .. i, function()
			router.switch_to_poppy(i)
		end, { buffer = buf, desc = "Poppy: Switch to " .. title })
	end

	-- Kill tab: <M-p>k (skip when no popup is active, e.g. banner)
	if not skip_kill then
		map({"n", "t"}, "<M-p>k", router.kill_current, { buffer = buf, desc = "Poppy: Kill current popup" })
	end
end

return M
