local M = {}

local config = require("poppy.config")
local state = require("poppy.state")
local opts = nil

local is_nested = function()
	return os.getenv("NVIM") and true or false
end

M.get_state = function()
	return state
end

M.toggle = function()
	local manager = require("poppy.ui.manager")
	if manager.is_open() then
		require("poppy.ui.router").dismiss()
	else
		manager.open()
	end
end

M.open = function(poppy_name)
	local manager = require("poppy.ui.manager")
	if not manager.is_open() then
		manager.open(poppy_name)
	elseif poppy_name then
		manager.switch(poppy_name)
	end
end

M.close = function()
	require("poppy.ui.router").dismiss()
end

M.setup = function(user_opts)
	if is_nested() then
		return
	end
	require("poppy.ui.style").setup()
	opts = config.merge(user_opts)

	vim.api.nvim_create_augroup("poppy_group", { clear = true })
	vim.api.nvim_create_autocmd("BufUnload", {
		group = "poppy_group",
		callback = function(ctx)
			local ok, poppy_name = pcall(vim.api.nvim_buf_get_var, ctx.buf, "poppy_popup")
			if not ok or not poppy_name or not state.poppies[poppy_name] then
				return
			end

			local manager = require("poppy.ui.manager")
			state.poppies[poppy_name] = nil
			if manager.is_open() and manager.current_poppy_name == poppy_name then
				manager._recover()
			end
		end,
	})

	vim.api.nvim_create_user_command("Poppy", function(cmd_opts)
		local args = cmd_opts.args
		if args == "" or args == "toggle" then
			M.toggle()
		elseif args == "close" then
			M.close()
		elseif args:sub(1, 5) == "open " then
			M.open(args:sub(6))
		else
			M.toggle()
		end
	end, {
		nargs = "?",
		complete = function(_, _, _)
			local keys = { "toggle", "open ", "close" }
			if opts and opts.poppies then
				for k, _ in pairs(opts.poppies) do
					table.insert(keys, "open " .. k)
				end
			end
			return keys
		end,
	})
end

M._get_opts = function()
	return opts
end

M.get_sorted_poppies = function()
	local sorted = {}
	if opts and opts.poppies then
		for name, p_config in pairs(opts.poppies) do
			table.insert(sorted, { name = name, config = p_config })
		end
		local cat_order = { exec = 0, file = 1, shell = 2 }
		table.sort(sorted, function(a, b)
			local cat_a = cat_order[a.config.mode] or 99
			local cat_b = cat_order[b.config.mode] or 99
			if cat_a ~= cat_b then
				return cat_a < cat_b
			end
			return a.name < b.name
		end)
	end
	return sorted
end

return M
