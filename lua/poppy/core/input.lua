local M = {}

M.setup = function(buf, sorted_poppies, prefix, whichkey_disable, skip_kill, skip_hide)
	local map = vim.keymap.set
	local wk = whichkey_disable and "which_key_ignore" or nil

	local function desc(text)
		if wk then
			return wk
		end
		return "Poppy: " .. text
	end

	for i = 1, #sorted_poppies do
		local item = sorted_poppies[i]
		local title = item.config.title or item.name
		map({ "n", "t" }, prefix .. i, function()
			require("poppy.core.session").switch_by_index(i)
		end, { buffer = buf, desc = desc("Switch to " .. title) })
	end

	if not skip_kill then
		map({ "n", "t" }, prefix .. "k", function()
			require("poppy.core.session").kill_current()
		end, { buffer = buf, desc = desc("Kill current poppy") })
	end

	if not skip_hide then
		map({ "n", "t" }, prefix .. "h", function()
			require("poppy.core.session").toggle_panels()
		end, { buffer = buf, desc = desc("Toggle panels") })
	end
end

return M