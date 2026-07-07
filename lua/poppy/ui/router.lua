local M = {}

-- Switch to the poppy at the given index
M.switch_to_poppy = function(index)
    local manager = require("poppy.ui.manager")
    local sorted = require("poppy").get_sorted_poppies()
    local item = sorted[index]
    if item then
        manager.switch(item.name)
    end
end

-- Kill the current poppy
M.kill_current = function()
    require("poppy.ui.manager").kill_current()
end

-- Dismiss the wrapper
M.dismiss = function()
    require("poppy.ui.manager").cleanup()
end

return M
