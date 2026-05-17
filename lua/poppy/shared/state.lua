local M = {}

-- Structure: { ["popup_name"] = { active = boolean, hidden = boolean } }
M.popups = {}
M.STATE_FILE = vim.fn.stdpath("state") .. "/poppy.json"

return M
