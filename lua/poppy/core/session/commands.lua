local M = {}

M.setup = function(opts, callbacks)
	local sub_handlers = {
		toggle = function() callbacks.toggle() end,
		close = function() callbacks.close() end,
		menu = function() callbacks.toggle_menu() end,
		open = function(name) callbacks.open(name ~= "" and name or nil) end,
	}
	vim.api.nvim_create_user_command("Poppy", function(cmd_opts)
		local sub = cmd_opts.fargs[1]
		local handler = sub_handlers[sub or "toggle"]
		if not handler then
			vim.notify(
				string.format(
					"Poppy: unknown subcommand '%s' (valid: toggle, close, menu, open [<name>])",
					tostring(sub)
				),
				vim.log.levels.WARN
			)
			return
		end
		handler(table.concat(cmd_opts.fargs, " ", 2))
	end, {
		nargs = "*",
		complete = function(arg_lead, cmd_line)
			local body = cmd_line:gsub("^%s*:?[Pp]oppy%s+", "")
			local cmd, rest = body:match("^(%S+)%s*(.*)")
			if cmd == "open" and rest ~= "" then
				local names = {}
				if opts and opts.poppies then
					for k, _ in pairs(opts.poppies) do
						if k:sub(1, #arg_lead) == arg_lead then
							table.insert(names, k)
						end
					end
				end
				return names
			elseif cmd == nil or rest == "" then
				local subs = { "toggle", "close", "menu", "open" }
				local out = {}
				for _, s in ipairs(subs) do
					if s:sub(1, #arg_lead) == arg_lead then
						table.insert(out, s)
					end
				end
				return out
			end
			return {}
		end,
	})
end

return M