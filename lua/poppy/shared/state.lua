local M = {}

-- Structure: { ["popup_name"] = { active = boolean, hidden = boolean } }
M.popups = {}
M.STATE_DIR = vim.fn.stdpath("state") .. "/poppy"
M.STATE_FILE = M.STATE_DIR .. "/" .. vim.fn.getpid() .. ".json"

return M
