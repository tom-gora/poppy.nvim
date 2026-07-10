local M = {}

local wrapper = require("poppy.core.ui.wrapper")
local panels = require("poppy.core.ui.panels")
local hints_panel = require("poppy.core.ui.hints_panel")
local list_panel = require("poppy.core.ui.list_panel")
local content = require("poppy.core.ui.content")
local input = require("poppy.core.input")

M.poppies = {}
M._suppress_watch = false

local opts = nil

M.landing_view_width = nil
M.is_landing = false
M.menu_focused = false

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

M.compute_landing_view_width = function()
	local sorted = M.get_sorted_poppies()
	local max_line = 0
	for i, item in ipairs(sorted) do
		local icon = (opts and opts.icons and opts.icons[item.config.cat]) or " "
		local title = item.config.title or item.name
		local line = string.format(" %s %s %d %s", " ", icon, i, title)
		max_line = math.max(max_line, #line)
	end
	local count = #sorted
	local keys = (opts and opts.keys) or { poppy_action = "<C-_>", select = "<CR>" }
	local hints_text = string.format(" %s Select   %s Toggle Off ", keys.select, keys.poppy_action)
	local hints_len = #hints_text
	return math.max(max_line, hints_len) + 4
end

M.is_open = function()
	return M.wrapper_win ~= nil and vim.api.nvim_win_is_valid(M.wrapper_win)
end

M._watch_content_window = function(win_id, sidebars_width)
	if not win_id then
		return
	end
	local sw = sidebars_width or 25
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = vim.api.nvim_create_augroup("poppy_ui", { clear = false }),
		callback = function()
			if not M.is_open() or M._suppress_watch then
				return
			end
			local c_win, c_buf = content.create(M.wrapper_win, sw)
			M.content_win = c_win
			M.content_buf = c_buf
			M._watch_content_window(c_win, sw)
			if M.current_poppy_name then
				M.kill_current()
			else
				M._recover()
			end
		end,
	})
end

M.refresh = function(sorted_poppies)
	if M.is_landing then
		list_panel.update(panels.get_list_buf(), sorted_poppies, M.poppies, opts and opts.icons)
		hints_panel.update(
			panels.get_hints_buf(),
			opts and opts.keys,
			#sorted_poppies,
			vim.api.nvim_win_get_width(M.wrapper_win),
			"landing"
		)
		return
	end
	if panels.is_autohidden() or panels.is_hidden() then
		return
	end
	local sw = (opts and opts.sidebar_width) or 25
	list_panel.update(panels.get_list_buf(), sorted_poppies, M.poppies, opts and opts.icons)
	local mode = M.menu_focused and "active_focused" or "active_sidebar"
	hints_panel.update(
		panels.get_hints_buf(),
		opts and opts.keys,
		#sorted_poppies,
		sw,
		mode
	)
end

M._active_width = function()
	local raw = opts and opts.win_width
	if type(raw) == "function" then
		raw = raw()
	end
	raw = raw or 0.8
	if raw > 1 then
		return math.floor(raw)
	end
	return math.floor(vim.o.columns * math.min(math.max(raw, 0.2), 1.0))
end

M.open = function(poppy_name)
	local sorted_poppies = M.get_sorted_poppies()
	local last_poppy = M.current_poppy_name

	if poppy_name or (last_poppy and M.poppies[last_poppy]) then
		local sw = (opts and opts.sidebar_width) or 25
		local win, wbuf = wrapper.create(opts)
		local c_win, c_buf = content.create(win, sw)
		panels.create(win, sw, 1)
		M._watch_content_window(c_win, sw)

		M.wrapper_win = win
		M.wrapper_buf = wbuf
		M.content_win = c_win
		M.content_buf = c_buf
		M.current_poppy_name = nil
		M.is_landing = false

		if poppy_name then
			M.switch(poppy_name)
		else
			M.switch(last_poppy)
		end
	else
		if not M.landing_view_width then
			M.landing_view_width = M.compute_landing_view_width()
		end
		local win, wbuf = wrapper.create(opts, M.landing_view_width)
		panels.create_landing(win)

		M.wrapper_win = win
		M.wrapper_buf = wbuf
		M.content_win = nil
		M.content_buf = nil
		M.current_poppy_name = nil
		M.is_landing = true

		local list_buf = panels.get_list_buf()
		vim.bo[list_buf].filetype = "poppy_menu"
		input.setup_sidebar(list_buf, opts and opts.keys)
		local list_win = panels.get_list_win()
		if list_win and vim.api.nvim_win_is_valid(list_win) then
			vim.api.nvim_set_current_win(list_win)
		end
	end

	M.refresh(sorted_poppies)

	return M.wrapper_win
end

M.toggle_menu = function()
	if M.is_landing or not M.is_open() then
		return
	end
	local sorted = M.get_sorted_poppies()

	if panels.is_autohidden() then
		panels.show_for_autohide(M.content_win)
		M.menu_focused = true
		local list_win = panels.get_list_win()
		if list_win and vim.api.nvim_win_is_valid(list_win) then
			vim.api.nvim_set_current_win(list_win)
		end
		M.refresh(sorted)
	elseif panels.is_hidden() then
		panels.show(M.content_win)
		M.menu_focused = false
		M.refresh(sorted)
		if M.content_win and vim.api.nvim_win_is_valid(M.content_win) then
			vim.api.nvim_set_current_win(M.content_win)
		end
	else
		M.menu_focused = not M.menu_focused
		if M.menu_focused then
			panels.focus_sidebar()
			local list_win = panels.get_list_win()
			if list_win and vim.api.nvim_win_is_valid(list_win) then
				vim.api.nvim_set_current_win(list_win)
			end
		else
			panels.unfocus_sidebar()
			if M.content_win and vim.api.nvim_win_is_valid(M.content_win) then
				vim.api.nvim_set_current_win(M.content_win)
			end
		end
		M.refresh(sorted)
	end
end

M.dismiss_menu = function()
	if not M.menu_focused or M.is_landing then
		return
	end
	M.menu_focused = false
	if opts and opts.menu_autohide then
		panels.hide_for_autohide(M.content_win)
	else
		panels.unfocus_sidebar()
	end
	M.refresh(M.get_sorted_poppies())
	if M.content_win and vim.api.nvim_win_is_valid(M.content_win) then
		vim.api.nvim_set_current_win(M.content_win)
	end
end

M.switch = function(poppy_name)
	if not M.is_open() or not opts or not opts.poppies or not opts.poppies[poppy_name] then
		return
	end

	if M.current_poppy_name then
		local cur_state = M.poppies[M.current_poppy_name]
		if cur_state then
			cur_state.active = false
			cur_state.hidden = true
		end
	end

	if M.is_landing then
		panels.destroy()
		local sw = (opts and opts.sidebar_width) or 25
		local wc = vim.api.nvim_win_get_config(M.wrapper_win)
		local full_width = M._active_width()
		vim.api.nvim_win_set_config(M.wrapper_win, {
			relative = wc.relative,
			width = full_width,
			height = wc.height,
			col = math.floor((vim.o.columns - full_width) / 2),
			row = wc.row,
		})
		local c_win, c_buf = content.create(M.wrapper_win, sw)
		panels.create(M.wrapper_win, sw, 1)
		M._watch_content_window(c_win, sw)
		M.content_win = c_win
		M.content_buf = c_buf
		M.is_landing = false
		input.setup_sidebar(panels.get_list_buf(), opts and opts.keys)
	end

	local poppy_opts = opts.poppies[poppy_name]
	M.current_poppy_name = poppy_name
	local sorted_poppies = M.get_sorted_poppies()

	local mode = poppy_opts.mode
	require("poppy.modes." .. mode).run(poppy_name, opts, M.content_win)

	input.setup_content(vim.api.nvim_win_get_buf(M.content_win), opts and opts.keys)

	M.menu_focused = false
	if opts.menu_autohide then
		panels.hide_for_autohide(M.content_win)
	else
		panels.unfocus_sidebar()
	end

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

M.switch_by_cursor = function()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
	if not line then
		return
	end
	local idx = line:match("%s+(%d+)%s")
	if idx then
		M.switch_by_index(tonumber(idx))
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

	if M.content_win and vim.api.nvim_win_is_valid(M.content_win) then
		pcall(vim.api.nvim_set_current_win, M.content_win)
	end
end

M.kill_by_index = function(index)
	local sorted = M.get_sorted_poppies()
	local item = sorted[index]
	if not item then
		return
	end
	local name = item.name

	if name == M.current_poppy_name then
		M.kill_current()
		return
	end

	local p_state = M.poppies[name]
	if not p_state then
		return
	end

	local target_bufnr = p_state.bufnr
	M.poppies[name] = nil

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if M.is_open() and not M.is_landing then
		M.refresh(M.get_sorted_poppies())
	end
end

M.kill_by_cursor = function()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
	if not line then
		return
	end
	local idx = line:match("%s+(%d+)%s")
	if idx then
		M.kill_by_index(tonumber(idx))
	end
end

M._recover = function()
	M.current_poppy_name = nil
	vim.schedule(function()
		if not M.is_open() or M.is_landing or M.current_poppy_name then
			return
		end

		local fallback_name = nil
		for name, ps in pairs(M.poppies) do
			if ps.hidden then
				fallback_name = name
				break
			end
		end

		if fallback_name then
			M.switch(fallback_name)
		else
			panels.destroy()
			M._suppress_watch = true
			if M.content_win and vim.api.nvim_win_is_valid(M.content_win) then
				vim.api.nvim_win_close(M.content_win, true)
			end
			M.content_win = nil
			M.content_buf = nil
			M._suppress_watch = false

			if not M.landing_view_width then
				M.landing_view_width = M.compute_landing_view_width()
			end
			local wc = vim.api.nvim_win_get_config(M.wrapper_win)
			vim.api.nvim_win_set_config(M.wrapper_win, {
				relative = wc.relative,
				width = M.landing_view_width,
				height = wc.height,
				col = math.floor((vim.o.columns - M.landing_view_width) / 2),
				row = wc.row,
			})
			panels.create_landing(M.wrapper_win)
			M.is_landing = true

			local sorted = M.get_sorted_poppies()
			local list_buf = panels.get_list_buf()
			vim.bo[list_buf].filetype = "poppy_menu"
			input.setup_sidebar(list_buf, opts and opts.keys)
			M.refresh(sorted)

			local list_win = panels.get_list_win()
			if list_win and vim.api.nvim_win_is_valid(list_win) then
				pcall(vim.api.nvim_set_current_win, list_win)
			end
		end
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

	M.wrapper_win = nil
	M.wrapper_buf = nil
	M.content_win = nil
	M.content_buf = nil
	M.is_landing = false
	M.menu_focused = false
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
	M.poppies = {}
	M.landing_view_width = nil
	M.is_landing = false
	M.menu_focused = false
	M.current_poppy_name = nil
	M.wrapper_win = nil

	require("poppy.core.ui.style").setup()
	M.set_opts(require("poppy.config").merge(user_opts))

	input.setup_global(opts and opts.keys)

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
		elseif args == "menu" then
			M.toggle_menu()
		elseif args:sub(1, 5) == "open " then
			M.open(args:sub(6))
		else
			M.toggle()
		end
	end, {
		nargs = "?",
		complete = function(_, _, _)
			local keys = { "toggle", "open ", "close", "menu" }
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