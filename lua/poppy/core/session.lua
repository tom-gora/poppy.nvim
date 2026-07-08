local M = {}

local wrapper = require("poppy.core.ui.wrapper")
local panels = require("poppy.core.ui.panels")
local hints_panel = require("poppy.core.ui.hints_panel")
local list_panel = require("poppy.core.ui.list_panel")
local content = require("poppy.core.ui.content")
local input = require("poppy.core.input")
local banner = require("poppy.core.ui.banner")

M.poppies = {}

local opts = nil

M.set_opts = function(merged)
	opts = merged
end

M.get_opts = function()
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
			local cat_a = cat_order[a.config.cat] or 99
			local cat_b = cat_order[b.config.cat] or 99
			if cat_a ~= cat_b then
				return cat_a < cat_b
			end
			return a.name < b.name
		end)
	end
	return sorted
end

M.is_open = function()
	return M.wrapper_win ~= nil and vim.api.nvim_win_is_valid(M.wrapper_win)
end

M._watch_content_window = function(win_id, sidebars_width)
	local sw = sidebars_width or 25
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = vim.api.nvim_create_augroup("poppy_ui", { clear = false }),
		callback = function()
			if not M.is_open() then
				return
			end
			local c_win, c_buf = content.create(M.wrapper_win, sw)
			M.content_win = c_win
			M.content_buf = c_buf
			M._watch_content_window(c_win, sw)
			if M.current_poppy_name then
				M.kill_current()
			else
				local sorted = M.get_sorted_poppies()
				vim.api.nvim_win_set_buf(M.content_win, M.content_buf)
				banner.render(M.content_buf, M.content_win)
				input.setup(M.content_buf, sorted, M._prefix(), M._wk(), true)
				M.refresh(sorted)
			end
		end,
	})
end

M.refresh = function(sorted_poppies)
	local sw = (opts and opts.sidebar_width) or 25
	local wrapper_width = vim.o.columns - 2
	if not panels.is_hidden() then
		list_panel.update(panels.get_list_buf(), sorted_poppies, M.poppies)
		hints_panel.update(panels.get_hints_buf(), M._prefix(), #sorted_poppies, wrapper_width - sw, wrapper_width)
	end
end

M._prefix = function()
	return (opts and opts.prefix_bind) or "<M-p>"
end

M._wk = function()
	return opts and opts.whichkey_disable
end

M.open = function(poppy_name)
	local sorted_poppies = M.get_sorted_poppies()
	local sw = (opts and opts.sidebar_width) or 25
	local last_poppy = M.current_poppy_name

	local win, wbuf = wrapper.create(opts)
	local c_win, c_buf = content.create(win, sw)
	panels.create(win, sw)

	M._watch_content_window(c_win, sw)

	M.wrapper_win = win
	M.wrapper_buf = wbuf
	M.content_win = c_win
	M.content_buf = c_buf
	M.current_poppy_name = nil

	if poppy_name then
		M.switch(poppy_name)
	elseif last_poppy and M.poppies[last_poppy] then
		M.switch(last_poppy)
	else
		banner.render(M.content_buf, M.content_win)
		input.setup(M.content_buf, sorted_poppies, M._prefix(), M._wk(), true)
	end

	M.refresh(sorted_poppies)

	return M.wrapper_win, M.content_win
end

M.toggle_panels = function()
	panels.toggle(M.content_win)
	local sorted = M.get_sorted_poppies()
	if not panels.is_hidden() then
		M.refresh(sorted)
	end
end

M.switch = function(poppy_name)
	if not opts or not opts.poppies or not opts.poppies[poppy_name] then
		return
	end

	if M.current_poppy_name then
		local cur_state = M.poppies[M.current_poppy_name]
		if cur_state then
			cur_state.active = false
			cur_state.hidden = true
		end
	end

	local poppy_opts = opts.poppies[poppy_name]
	M.current_poppy_name = poppy_name
	local sorted_poppies = M.get_sorted_poppies()

	local mode = poppy_opts.mode
	require("poppy.modes." .. mode).run(poppy_name, opts, M.content_win)

	input.setup(vim.api.nvim_win_get_buf(M.content_win), sorted_poppies, M._prefix(), M._wk())

	M.refresh(sorted_poppies)
	vim.api.nvim_set_current_win(M.content_win)

	if vim.bo[vim.api.nvim_win_get_buf(M.content_win)].buftype == "terminal" then
		vim.cmd("startinsert")
	end
end

M.switch_by_index = function(index)
	local sorted = M.get_sorted_poppies()
	local item = sorted[index]
	if item then
		M.switch(item.name)
	end
end

M.kill_current = function()
	if not M.current_poppy_name then
		return
	end
	local target = M.current_poppy_name
	local p_state = M.poppies[target]
	local target_bufnr = p_state and p_state.bufnr

	M.poppies[target] = nil
	M.current_poppy_name = nil
	M._recover()

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	pcall(vim.api.nvim_set_current_win, M.content_win)
end

M._recover = function()
	M.current_poppy_name = nil
	vim.schedule(function()
		if not M.is_open() or not vim.api.nvim_win_is_valid(M.content_win) then
			return
		end
		pcall(vim.api.nvim_win_set_buf, M.content_win, M.content_buf)

		local fallback_name = nil
		for name, ps in pairs(M.poppies) do
			if ps.hidden then
				fallback_name = name
				break
			end
		end

		local sorted = M.get_sorted_poppies()
		if fallback_name then
			M.switch(fallback_name)
		else
			banner.render(M.content_buf, M.content_win)
			input.setup(M.content_buf, sorted, M._prefix(), M._wk(), true)
			M.refresh(sorted)
		end
		pcall(vim.api.nvim_set_current_win, M.content_win)
	end)
end

M.cleanup = function()
	if M.current_poppy_name then
		local ps = M.poppies[M.current_poppy_name]
		if ps then
			ps.active = false
			ps.hidden = true
			ps.win = nil
		end
	end

	panels.destroy()

	for _, win in ipairs({ M.wrapper_win, M.content_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local buffers = { M.wrapper_buf, panels.get_hints_buf(), panels.get_list_buf(), M.content_buf }
	for _, buf in ipairs(buffers) do
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
end

M.toggle = function()
	if M.is_open() then
		M.cleanup()
	else
		M.open()
	end
end

M.close = function()
	M.cleanup()
end

M.setup = function(user_opts)
	require("poppy.core.ui.style").setup()
	M.set_opts(require("poppy.config").merge(user_opts))

	vim.api.nvim_create_augroup("poppy_group", { clear = true })
	vim.api.nvim_create_autocmd("BufUnload", {
		group = "poppy_group",
		callback = function(ctx)
			local ok, poppy_name = pcall(vim.api.nvim_buf_get_var, ctx.buf, "poppy_popup")
			if not ok or not poppy_name or not M.poppies[poppy_name] then
				return
			end

			M.poppies[poppy_name] = nil
			if M.is_open() and M.current_poppy_name == poppy_name then
				M._recover()
			end
		end,
	})

	vim.api.nvim_create_user_command("Poppy", function(cmd_opts)
		local args = cmd_opts.args
		if args == "" or args == "toggle" then
			M.toggle()
		elseif args == "close" then
			M.close()
		elseif args == "panels" then
			M.toggle_panels()
		elseif args:sub(1, 5) == "open " then
			M.open(args:sub(6))
		else
			M.toggle()
		end
	end, {
		nargs = "?",
		complete = function(_, _, _)
			local keys = { "toggle", "open ", "close", "panels" }
			if opts and opts.poppies then
				for k, _ in pairs(opts.poppies) do
					table.insert(keys, "open " .. k)
				end
			end
			return keys
		end,
	})
end

return M