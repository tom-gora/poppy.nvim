local M = {}
local session = require("poppy.core.session")
local util = require("poppy.core.util")

M.run = function(poppy_name, opts, parent_win)
	local poppy_opts = opts.poppies_resolved[poppy_name]
	if not poppy_opts or not parent_win then
		return
	end

	local p_state = session.poppies[poppy_name]
	local bufnr = util.term_get_or_create_buffer(poppy_name, opts, p_state)
	if not bufnr then
		return
	end

	if not p_state or (not p_state.active and not p_state.hidden) then
		vim.api.nvim_buf_call(bufnr, function()
			pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
			util.term_spawn(util.term_resolve_command(poppy_opts), {
				on_exit = function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						vim.api.nvim_buf_delete(bufnr, { force = true })
					end
					if util.session_is_open() and util.session_get_current_poppy_name() == poppy_name then
						session.kill_current()
					else
						session.poppies[poppy_name] = nil
					end
				end,
			})
		end)
	end

	vim.api.nvim_win_set_buf(parent_win, bufnr)

	session.poppies[poppy_name] =
		{ active = true, hidden = false, bufnr = bufnr, win = parent_win, title = poppy_opts.title }
end

return M