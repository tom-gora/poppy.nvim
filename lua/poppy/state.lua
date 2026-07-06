local M = {}

-- Structure: { ["popup_name"] = { active = boolean, hidden = boolean, title = string } }
M.popups = {}

-- Helper to get active and background popups from global state
-- This is now the single source of truth for the UI state machine
M.get_poppy_states = function()
	local active = nil
	local background = {}
	if not M.popups then
		return active, background
	end
	for _, sp in pairs(M.popups) do
		if sp.active == true then
			active = sp
		elseif sp.hidden then
			table.insert(background, sp)
		end
	end
	return active, background
end

return M
