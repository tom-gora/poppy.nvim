local M = {}

---@param exec string|string[]
---@return string
M.prepare = function(exec)
    local cmd
    if type(exec) == "table" then
        cmd = exec[1]
    else
        cmd = vim.split(exec, " ")[1]
    end

    -- If it's an executable, return as-is
    if vim.fn.executable(cmd) == 1 then
        return type(exec) == "table" and table.concat(exec, " ") or exec
    end

    -- Otherwise, treat as file and wrap in nvim with styling
    local file_path = vim.fn.expand(cmd)
    local nvim_opts = {
        'vim.api.nvim_set_hl(0, "Normal", {link="NormalFloat", force=true})',
        'vim.api.nvim_set_hl(0, "SignColumn", {link="NormalFloat", force=true})',
        'vim.opt_local.number = false',
        'vim.opt_local.relativenumber = false',
        'vim.opt_local.laststatus = 0',
        'vim.cmd("set winhighlight=Normal:NormalFloat")',
        'vim.opt.shadafile = "NONE"',
        'vim.opt.swapfile = false',
    }
    
    -- We use a single quote for the -c argument and escape single quotes inside it
    local nvim_cmd = string.format("nvim %s -c 'lua %s'", file_path, table.concat(nvim_opts, "; "))
    return nvim_cmd
end

return M
