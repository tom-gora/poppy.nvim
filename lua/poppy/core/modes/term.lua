local M = {}
local actions = require("poppy.core.session.actions")
local poppy_state = require("poppy.core.session.poppy_state")
local shared = require("poppy.core.shared")

M.run = function(poppy_name, opts, parent_win)
	local poppy_opts = opts.poppies_resolved[poppy_name]
	if not poppy_opts or not parent_win then
		return
	end

	local p_state = poppy_state.runtime_get(poppy_name)
	local bufnr = shared.term_get_or_create_buffer(poppy_name, opts, p_state)
	if not bufnr then
		return
	end

	if not (p_state and (p_state.active or p_state.hidden)) then
		vim.api.nvim_buf_call(bufnr, function()
			vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
			shared.term_spawn(shared.term_resolve_command(poppy_opts), {
				on_exit = function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						vim.api.nvim_buf_delete(bufnr, { force = true })
					end
					if shared.session_is_open() and shared.session_get_current_poppy_name() == poppy_name then
						actions.kill_active()
					else
						poppy_state.runtime_remove(poppy_name)
					end
				end,
			})
		end)
	end

	vim.api.nvim_win_set_buf(parent_win, bufnr)

	poppy_state.runtime_set(
		poppy_name,
		{ active = true, hidden = false, bufnr = bufnr, win = parent_win, title = poppy_opts.title }
	)
end

return M
