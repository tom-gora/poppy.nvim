local M = {}

local state = require("poppy.core.session.state")
local poppy_state = require("poppy.core.session.poppy_state")
local switching = require("poppy.core.session.switching")
local panels = require("poppy.core.ui.panels")
local input = require("poppy.core.input")
local layout = require("poppy.core.ui.layout")
local util = require("poppy.core.util")

M.recover = function()
	state.current_poppy_name = nil
	vim.schedule(function()
		if not util.is_open(state.wrapper_win) or state.is_landing or state.current_poppy_name then
			return
		end

		local fallback_name = nil
		for name, ps in poppy_state.runtime_iter() do
			if ps.hidden then
				fallback_name = name
				break
			end
		end

		if fallback_name then
			switching.switch_by_name(fallback_name)
		else
			panels.destroy()
			if state.menu_hint_win then
				vim.api.nvim_win_close(state.menu_hint_win, true)
			end
			state.menu_hint_win = nil
			state.menu_hint_buf = nil

			vim.api.nvim_create_augroup("poppy_ui", { clear = true })

			if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
				vim.api.nvim_win_close(state.content_win, true)
			end
			state.content_win = nil
			state.content_buf = nil

			local landing_width = poppy_state.landing_view_width()
			local wc = vim.api.nvim_win_get_config(state.wrapper_win)
			vim.api.nvim_win_set_config(state.wrapper_win, {
				relative = wc.relative,
				width = landing_width,
				height = wc.height,
				col = math.floor((vim.o.columns - landing_width) / 2),
				row = wc.row,
			})
			panels.create_landing(state.wrapper_win, layout.get_header_height(state.opts))
			state.is_landing = true

			local list_buf = panels.get_list_buf()
			vim.bo[list_buf].filetype = "poppy_menu"
			input.setup_menu(list_buf, util.keys())
			switching.refresh_panels(poppy_state.entries())

			local list_win = panels.get_list_win()
			if list_win and vim.api.nvim_win_is_valid(list_win) then
				pcall(vim.api.nvim_set_current_win, list_win)
			end
		end
	end)
end

M.kill_active = function()
	if not state.current_poppy_name then
		return
	end
	local target = state.current_poppy_name
	local p_state = poppy_state.runtime_get(target)
	local target_bufnr = p_state and p_state.bufnr

	poppy_state.runtime_remove(target)
	state.current_poppy_name = nil
	M.recover()

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if state.content_win and vim.api.nvim_win_is_valid(state.content_win) then
		pcall(vim.api.nvim_set_current_win, state.content_win)
	end
end

local _kill = function(resolved)
	if not resolved then
		return
	end
	if resolved.name == state.current_poppy_name then
		return M.kill_active()
	end
	if not resolved.runtime then
		return
	end

	local target_bufnr = resolved.runtime.bufnr
	poppy_state.runtime_remove(resolved.name)

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if util.is_open(state.wrapper_win) and not state.is_landing then
		switching.refresh_panels(poppy_state.entries())
	end
end

M.kill_by_name = function(name)
	return _kill(poppy_state.resolve(name))
end

M.kill_by_index = function(index)
	return _kill(poppy_state.resolve(index))
end

M.kill_by_cursor = function()
	local idx = util.cursor_to_poppy_index(poppy_state.entries())
	if idx then
		M.kill_by_index(idx)
	end
end

return M