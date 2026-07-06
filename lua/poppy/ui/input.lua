local M = {}
local router = require("poppy.ui.router")

M.setup = function(buf, sorted_popups)
	local map = vim.keymap.set
	
	-- Dismiss: <M-p><M-p>
	map({"n", "t"}, "<M-p><M-p>", router.dismiss, { buffer = buf })
	
	-- Switch tabs: <M-p>[1-9]
	for i = 1, #sorted_popups do
		map({"n", "t"}, "<M-p>" .. i, function()
			router.switch_to_poppy(i)
		end, { buffer = buf })
	end
    
    -- Kill tab: <M-p>k
	map({"n", "t"}, "<M-p>k", router.kill_current, { buffer = buf })
end

return M
