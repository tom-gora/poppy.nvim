local M = {}

---@param pos string
---@return string
M.get_position_flags = function(pos)
    local x_flags = {
        center = "-x C",
        left = "-x L",
        right = "-x R -t right"
    }
    local x_flag = x_flags[pos] or "-x C"
    return x_flag .. " -y C"
end

return M
