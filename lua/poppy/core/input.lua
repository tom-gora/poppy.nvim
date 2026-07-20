local M = {}

M.setup_global = function(keys)
	vim.keymap.set({ "n", "t" }, keys.poppy_action, function()
		require("poppy.core.session").toggle()
	end, { desc = "Poppy: Toggle UI" })
end

M.setup_menu = function(buf, keys)
	vim.keymap.set({ "n", "t" }, keys.select, function()
		local session = require("poppy.core.session")
		if vim.v.count > 0 then
			session.switch_by_index(vim.v.count)
		else
			session.switch_by_cursor()
		end
	end, { buffer = buf, desc = "Poppy: Select" })

	vim.keymap.set({ "n", "t" }, keys.kill, function()
		local session = require("poppy.core.session")
		if vim.v.count > 0 then
			session.kill_by_index(vim.v.count)
		else
			session.kill_by_cursor()
		end
	end, { buffer = buf, desc = "Poppy: Kill" })

	vim.keymap.set({ "n", "t" }, keys.exit_menu, function()
		require("poppy.core.session").exit_menu()
	end, { buffer = buf, desc = "Poppy: Exit menu" })
end

M.setup_content = function(buf, keys)
	vim.keymap.set({ "n", "t" }, keys.poppy_action, function()
		require("poppy.core.session").toggle_menu()
	end, { buffer = buf, desc = "Poppy: Toggle menu" })
end

return M
