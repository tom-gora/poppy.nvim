local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local killing = require("poppy.core.session.killing")
local switching = require("poppy.core.session.switching")
local util = require("poppy.core.util")

M.setup_exclusive_float = function()
	vim.api.nvim_create_autocmd("WinEnter", {
		group = "poppy_group",
		once = true,
		callback = function()
			vim.schedule(function()
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					local _, val = pcall(vim.api.nvim_win_get_var, w, "poppy_ui_window")
					if not vim.api.nvim_win_is_valid(w) or val == true then
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
			if not util.is_open(state.wrapper_win) then
				return
			end
			local ok, poppy_name = pcall(vim.api.nvim_buf_get_var, ctx.buf, "poppy_popup")
			if not ok or not poppy_name or not poppy_state.runtime_get(poppy_name) then
				return
			end

			poppy_state.runtime_remove(poppy_name)
			if util.is_open(state.wrapper_win) and state.current_poppy_name == poppy_name then
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
				if not util.is_open(state.wrapper_win) then
					return
				end
				-- Defer until after the focus transition completes; without
				-- this, nvim_get_current_win() can still report the old window.
				vim.schedule(function()
					if not util.is_open(state.wrapper_win) then
						return
					end
					local cur = vim.api.nvim_get_current_win()
					if not vim.api.nvim_win_is_valid(cur) then
						return
					end
					-- Internal hop (content <-> list, etc.): destination is
					-- still tagged as a poppy window. Stay open.
					local ok, val = pcall(vim.api.nvim_win_get_var, cur, "poppy_ui_window")
					if ok and val == true then
						return
					end
					-- Cmdline (`:`) is exempt: the user may be typing a
					-- `:Poppy` subcommand or any ordinary command while
					-- still wanting the UI to survive.
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
