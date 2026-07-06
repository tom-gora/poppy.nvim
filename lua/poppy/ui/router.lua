local M = {}
local poppy = require("poppy")

-- Switch to the poppy at the given index
M.switch_to_poppy = function(index)
    local manager = require("poppy.ui.manager")
    local sorted = poppy.get_sorted_popups()
    local item = sorted[index]
    if item then
        manager.switch(item.name)
    end
end

-- Kill the current poppy
M.kill_current = function()
    local manager = require("poppy.ui.manager")
    local target_name = manager.current_popup_name
    if target_name then
        local mode = poppy._get_opts().popups[target_name].mode
        require("poppy.modes." .. mode).close_session(target_name)
        manager.refresh(poppy.get_sorted_popups())
    end
end

-- Dismiss the wrapper
M.dismiss = function()
    local manager = require("poppy.ui.manager")
    manager.cleanup()
    _G.poppy_prototyping_dirty_switch = nil
end

return M
