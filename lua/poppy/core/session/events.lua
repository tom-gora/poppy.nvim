local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local killing = require("poppy.core.session.killing")
local switching = require("poppy.core.session.switching")
local panels = require("poppy.core.ui.panels")
local util = require("poppy.core.util")

M.setup_exclusive_float = function()
	vim.api.nvim_create_autocmd("WinEnter", {
		group = "poppy_group",
		once = true,
		callback = function()
			vim.schedule(function()
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if not vim.api.nvim_win_is_valid(w) or panels.is_poppy_window(w) then
						goto continue
					end
					if vim.api.nvim_win_get_config(w).relative ~= "" then
						vim.api.nvim_win_close(w, true)
					end
					::continue::
				end
			end)
		end,
	})
end

M.setup = function(opts, callbacks)
	vim.api.nvim_create_augroup("poppy_group", { clear = true })

	vim.api.nvim_create_autocmd("BufUnload", {
		group = "poppy_group",
		callback = function(ctx)
			if not util.session_is_open() then
				return
			end
			local ok, poppy_name = pcall(vim.api.nvim_buf_get_var, ctx.buf, "poppy_popup")
			if not ok or not poppy_name or not poppy_state.runtime_get(poppy_name) then
				return
			end

			poppy_state.runtime_remove(poppy_name)
			if util.session_is_open() and state.current_poppy_name == poppy_name then
				killing.recover()
			end
		end,
	})

	if opts and opts.menu_autohide then
		vim.api.nvim_create_autocmd("CursorHold", {
			group = "poppy_group",
			callback = function()
				if vim.bo.filetype == "poppy_menu" then
					switching.exit_menu()
				end
			end,
		})
	end

	if opts and opts.autoclose then
		vim.api.nvim_create_autocmd({ "WinLeave", "TermEnter" }, {
			group = "poppy_group",
			callback = function()
				if not util.session_is_open() then
					return
				end
				-- Defer so nvim_get_current_win() reports the new window.
				vim.schedule(function()
					if not util.session_is_open() then
						return
					end
					local cur = vim.api.nvim_get_current_win()
					if not vim.api.nvim_win_is_valid(cur) then
						return
					end
					-- Internal hop: destination is a poppy window, stay open.
					if panels.is_poppy_window(cur) then
						return
					end
					-- Cmdline is exempt: user may be typing :Poppy or any command.
					if vim.fn.win_gettype(cur) == "command" then
						return
					end
					callbacks.toggle()
				end)
			end,
		})
	end
end

return M
