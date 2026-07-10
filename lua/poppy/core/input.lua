local M = {}

M.setup_global = function(keys)
	vim.keymap.set({ "n", "t" }, keys.poppy_action, function()
		require("poppy.core.session").toggle()
	end, { desc = "Poppy: Toggle UI" })
end

M.setup_sidebar = function(buf, keys)
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

	vim.keymap.set({ "n", "t" }, keys.dismiss_menu, function()
		require("poppy.core.session").dismiss_menu()
	end, { buffer = buf, desc = "Poppy: Dismiss menu" })
end

M.setup_content = function(buf, keys)
	vim.keymap.set({ "n", "t" }, keys.poppy_action, function()
		require("poppy.core.session").toggle_menu()
	end, { buffer = buf, desc = "Poppy: Toggle menu" })
end

M.teardown = function(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	for _, mode in ipairs({ "n", "t" }) do
		local maps = vim.api.nvim_buf_get_keymap(buf, mode)
		for _, m in ipairs(maps) do
			if m.desc and m.desc:sub(1, 7) == "Poppy: " then
				pcall(vim.api.nvim_buf_del_keymap, buf, m.mode, m.lhs)
			end
		end
	end
end

return M