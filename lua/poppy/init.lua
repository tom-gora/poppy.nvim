local M = {}

local config = require("poppy.config")
local state = require("poppy.state")
local opts = nil

local is_nested = function() return os.getenv("NVIM") and true or false end

M.get_state = function() return state end

local open_popup = function(popup_name)
	if is_nested() then return end
	if not opts then
		print("Poppy: Not initialized. Call setup() first.")
		return
	end

	-- Deactivate current active popup
	for name, p_state in pairs(state.popups) do
		if p_state.active then
			local mode = opts.popups[name].mode
			require("poppy.modes." .. mode).hide_session(name)
			p_state.active = false
			p_state.hidden = true
			vim.cmd("redrawstatus")
		end
	end

	local popup_opts = opts.popups[popup_name]
	require("poppy.modes." .. popup_opts.mode).run(popup_name, opts)
	vim.cmd("redrawstatus")
end

local setup_autocmds = function()
	local group = vim.api.nvim_create_augroup("poppy_group", { clear = true })
	vim.api.nvim_create_autocmd({ "WinLeave" }, {
		group = group,
		callback = function()
			local win = vim.api.nvim_get_current_win()
			local success, popup_name = pcall(vim.api.nvim_win_get_var, win, "poppy_win")
			if success and popup_name then
				local mode = opts.popups[popup_name].mode
				require("poppy.modes." .. mode).hide_session(popup_name)
			end
		end,
	})
end

local __temp_state_inspect = function()
	vim.keymap.set("n", "<F1>", function()
		print(vim.inspect(require("poppy").get_state()))
	end, { desc = "Poppy: Inspect state" })
end

M.setup = function(user_opts)
	if is_nested() then return end
	opts = config.merge(user_opts)
	setup_autocmds()
	__temp_state_inspect()

	vim.api.nvim_create_user_command("Poppy", function(cmd_opts)
		if cmd_opts.args == "" then
			print("Poppy: Please specify a popup name.")
			return
		end
		open_popup(cmd_opts.args)
	end, {
		nargs = 1,
		complete = function(_, _, _)
			local keys = {}
			if opts and opts.popups then
				for k, _ in pairs(opts.popups) do table.insert(keys, k) end
			end
			return keys
		end,
	})

	vim.api.nvim_create_user_command("PoppyClose", function(cmd_opts)
		local mode = opts.popups[cmd_opts.args].mode
		require("poppy.modes." .. mode).close_session(cmd_opts.args)
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("PoppyHide", function(cmd_opts)
		local mode = opts.popups[cmd_opts.args].mode
		require("poppy.modes." .. mode).hide_session(cmd_opts.args)
	end, { nargs = 1 })
end

return M
