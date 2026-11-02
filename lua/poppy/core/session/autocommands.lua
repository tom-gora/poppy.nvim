require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local layout = require("poppy.core.ui.layout")
local shared = require("poppy.core.shared")
local dialog = require("poppy.core.session.dialog")

---@return table session
local session = function()
	local mod = require("poppy.core.session")
	return mod
end

---@param opts PoppyMergedConfig
---@return nil
M.setup = function(opts)
	api.nvim_create_augroup("poppy_group", { clear = true })

	-- Re-resolve poppy_action on every content-window focus so a tmux state change
	-- doesn't strand the buffer with a stale <C-/> vs <C-_> binding.
	api.nvim_create_autocmd("BufEnter", {
		group = "poppy_group",
		callback = function()
			if not shared.session_is_open() then
				return
			end
			local cb = state.windows.content_buf
			if cb and api.nvim_buf_is_valid(cb) then
				require("poppy.core.session.keymaps").bind_poppy_action(cb)
			end
		end,
	})

	api.nvim_create_autocmd("BufUnload", {
		group = "poppy_group",
		callback = function(e)
			if not shared.session_is_open() then
				return
			end
			local ok, poppy_name = pcall(api.nvim_buf_get_var, e.buf, "poppy_popup")
			if not ok or not poppy_name or not state.poppy_configured(poppy_name) then
				return
			end

			state.clear_runtime(poppy_name)
			if state.windows.current_poppy_name == poppy_name then
				session().recover()
			end
		end,
	})

	if opts and opts.close_on_focus_lost then
		api.nvim_create_autocmd({ "WinLeave", "TermEnter" }, {
			group = "poppy_group",
			callback = function()
				if not shared.session_is_open() then
					return
				end
				-- Defer so nvim_get_current_win() reports the new window.
				vim.schedule(function()
					if not shared.session_is_open() then
						return
					end
					-- A recovery in flight owns the session: its own window churn must
					-- not be mistaken for the user leaving poppy for good.
					if state.windows.recovering then
						return
					end
					local win = api.nvim_get_current_win()
					if not api.nvim_win_is_valid(win) then
						return
					end
					if shared.is_poppy_window(win) then
						return
					end
					-- A live question blocks the session being closed out from under it.
					if dialog.trapped() then
						return
					end
					-- Cmdline, loclist, quickfix, preview are Neovim-owned; closing on any of them
					-- yanks the session mid-flow.
					local kind = vim.fn.win_gettype(win)
					if kind == "command" or kind == "loclist" or kind == "quickfix" or kind == "preview" then
						return
					end
					-- User floats (terminal, picker) own real buffers; transient floats (pum,
					-- hover, notification) live on `nofile` — close only the latter.
					if kind == "popup" then
						local buftype = vim.bo[vim.api.nvim_win_get_buf(win)].buftype
						if buftype == "nofile" then
							return
						end
					end
					session().toggle()
				end)
			end,
		})
	end

	-- Toggle rather than close: a live session keeps its poppy buffers, so widening the
	-- window and toggling again lands straight back on the same poppy.
	api.nvim_create_autocmd("VimResized", {
		group = "poppy_group",
		callback = function()
			if not shared.session_is_open() or not layout.below_floor() then
				return
			end
			session().toggle()
			shared.notify_warn(
				"terminal too small (%dx%d); toggle poppy back on at %dx%d or wider",
				vim.o.columns,
				vim.o.lines,
				layout.MIN_COLS,
				layout.MIN_LINES
			)
		end,
	})
end

---@return nil
M.setup_float_sweep = function()
	api.nvim_create_autocmd("WinEnter", {
		group = "poppy_group",
		once = true,
		callback = function()
			vim.schedule(function()
				for _, w in ipairs(api.nvim_list_wins()) do
					if
						api.nvim_win_is_valid(w)
						and not shared.is_poppy_window(w)
						and api.nvim_win_get_config(w).relative ~= ""
					then
						api.nvim_win_close(w, true)
					end
				end
			end)
		end,
	})
end

---@param win_id integer|nil
---@param menu_w? integer
---@return nil
M.watch_content_window = function(win_id, menu_w)
	if not win_id then
		return
	end
	local w = menu_w or layout.DEFAULT_MENU_WIDTH
	api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = "poppy_ui",
		callback = function()
			if state.windows.recovering then
				return
			end
			-- Stay out of the way while a question is up.
			if dialog.trapped() then
				return
			end
			if not shared.session_is_open() then
				return
			end
			shared.drop_scratch_buffer(state.windows.content_buf)
			local c_win, c_buf = view.content.create(state.windows.wrapper_win, w)
			state.windows.content_win = c_win
			state.windows.content_buf = c_buf
			M.watch_content_window(c_win, w)
			if state.windows.current_poppy_name then
				session().kill_active()
			else
				session().recover()
			end
		end,
	})
end

return M
