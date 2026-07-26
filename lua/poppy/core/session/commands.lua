local M = {}

M.setup = function(opts, callbacks)
	vim.api.nvim_create_user_command("Poppy", function(cmd_opts)
		local fargs = cmd_opts.fargs
		local sub = fargs[1]
		if sub == nil or sub == "toggle" then
			callbacks.toggle()
		elseif sub == "close" then
			callbacks.close()
		elseif sub == "menu" then
			callbacks.toggle_menu()
		elseif sub == "open" then
			local name = table.concat(fargs, " ", 2)
			callbacks.open(name ~= "" and name or nil)
		else
			vim.notify(
				string.format(
					"Poppy: unknown subcommand '%s' (valid: toggle, close, menu, open [<name>])",
					tostring(sub)
				),
				vim.log.levels.WARN
			)
		end
	end, {
		nargs = "*",
		complete = function(arg_lead, cmd_line)
			local body = cmd_line:gsub("^%s*:?[Pp]oppy%s+", "")
			local first_word = body:match("^(%S+)")
			if first_word == "open" and body:find("%s") then
				local names = {}
				if opts and opts.poppies then
					for k, _ in pairs(opts.poppies) do
						if k:sub(1, #arg_lead) == arg_lead then
							table.insert(names, k)
						end
					end
				end
				return names
			elseif first_word == nil or body:find("%s") == nil then
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