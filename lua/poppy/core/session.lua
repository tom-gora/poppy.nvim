local M = {}

local wrapper = require("poppy.core.ui.wrapper")
local panels = require("poppy.core.ui.panels")
local hints_panel = require("poppy.core.ui.hints_panel")
local list_panel = require("poppy.core.ui.list_panel")
local header_panel = require("poppy.core.ui.header_panel")
local content = require("poppy.core.ui.content")
local input = require("poppy.core.input")

M.poppies = {}

local _suppress_watch = false
local opts = nil
local landing_view_width = nil
local is_landing = false
local menu_focused = false
local autohide_hint_win = nil
local autohide_hint_buf = nil
local wrapper_buf = nil
local wrapper_win = nil
local content_buf = nil
local content_win = nil
local current_poppy_name = nil

-- forward declarations for mutual references
local _recover
local _watch_content_window

local header_lines = function()
	return (opts and opts.title_header ~= false) and header_panel.HEIGHT or 0
end

M.set_opts = function(merged)
	opts = merged
end

M.get_opts = function()
	return opts
end

local get_sorted_poppies = function()
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

local compute_landing_view_width = function()
	local sorted = get_sorted_poppies()
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
	return wrapper_win ~= nil and vim.api.nvim_win_is_valid(wrapper_win)
end

_watch_content_window = function(win_id, sidebars_width)
	if not win_id then
		return
	end
	local sw = sidebars_width or 25
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		once = true,
		group = vim.api.nvim_create_augroup("poppy_ui", { clear = false }),
		callback = function()
			if not M.is_open() or _suppress_watch then
				return
			end
			local c_win, c_buf = content.create(wrapper_win, sw)
			content_win = c_win
			content_buf = c_buf
			_watch_content_window(c_win, sw)
			if current_poppy_name then
				M.kill_current()
			else
				_recover()
			end
		end,
	})
end

local refresh = function(sorted_poppies)
	if is_landing then
		list_panel.update(panels.get_list_buf(), sorted_poppies, M.poppies, opts and opts.icons)
		hints_panel.update(
			panels.get_hints_buf(),
			opts and opts.keys,
			#sorted_poppies,
			vim.api.nvim_win_get_width(wrapper_win),
			"landing",
			"landing"
		)
		return
	end
	if panels.is_autohidden() or panels.is_hidden() then
		return
	end
	local sw = (opts and opts.sidebar_width) or 25
	list_panel.update(panels.get_list_buf(), sorted_poppies, M.poppies, opts and opts.icons)
	local mode = menu_focused and "active_focused" or "active_sidebar"
		hints_panel.update(
			panels.get_hints_buf(),
			opts and opts.keys,
			#sorted_poppies,
			sw,
			"sidebar",
			mode
		)
end

local _active_width = function()
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
	if M.is_open() then
		if poppy_name then
			M.switch(poppy_name)
		end
		return wrapper_win
	end
	local sorted_poppies = get_sorted_poppies()
	local last_poppy = current_poppy_name

	if poppy_name or (last_poppy and M.poppies[last_poppy]) then
		local sw = (opts and opts.sidebar_width) or 25
		local hdr = header_lines()
		local win, wbuf
		if wrapper_buf and vim.api.nvim_buf_is_valid(wrapper_buf) then
			wbuf = wrapper_buf
			win = wrapper.recreate(wbuf, opts)
		else
			win, wbuf = wrapper.create(opts)
			wrapper_buf = wbuf
		end
		local c_win, c_buf = content.create(win, sw)
		panels.create(win, sw, 4, hdr)
		_watch_content_window(c_win, sw)

		wrapper_win = win
		content_win = c_win
		content_buf = c_buf
		current_poppy_name = nil
		is_landing = false

		if poppy_name then
			M.switch(poppy_name)
		else
			M.switch(last_poppy)
		end

		input.setup_sidebar(panels.get_list_buf(), opts and opts.keys)
	else
		if not landing_view_width then
			landing_view_width = compute_landing_view_width()
		end
		local win, wbuf
		if wrapper_buf and vim.api.nvim_buf_is_valid(wrapper_buf) then
			wbuf = wrapper_buf
			win = wrapper.recreate(wbuf, opts, landing_view_width)
		else
			win, wbuf = wrapper.create(opts, landing_view_width)
			wrapper_buf = wbuf
		end
		panels.create_landing(win, header_lines())
		wrapper_win = win
		content_win = nil
		content_buf = nil
		current_poppy_name = nil
		is_landing = true

		local list_buf = panels.get_list_buf()
		vim.bo[list_buf].filetype = "poppy_menu"
		input.setup_sidebar(list_buf, opts and opts.keys)
		local list_win = panels.get_list_win()
		if list_win and vim.api.nvim_win_is_valid(list_win) then
			vim.api.nvim_set_current_win(list_win)
		end
	end

	refresh(sorted_poppies)

	return wrapper_win
end

M.toggle_menu = function()
	if is_landing or not M.is_open() then
		return
	end
	local sorted = get_sorted_poppies()

	if panels.is_autohidden() then
		if autohide_hint_win and vim.api.nvim_win_is_valid(autohide_hint_win) then
			vim.api.nvim_win_close(autohide_hint_win, true)
		end
		autohide_hint_win = nil
		autohide_hint_buf = nil
		panels.show_for_autohide(content_win)
		menu_focused = true
		local list_win = panels.get_list_win()
		if list_win and vim.api.nvim_win_is_valid(list_win) then
			vim.api.nvim_set_current_win(list_win)
		end
		refresh(sorted)
	elseif panels.is_hidden() then
		panels.show(content_win)
		menu_focused = false
		refresh(sorted)
		if content_win and vim.api.nvim_win_is_valid(content_win) then
			vim.api.nvim_set_current_win(content_win)
		end
	else
		menu_focused = not menu_focused
		if menu_focused then
			panels.focus_sidebar()
			local list_win = panels.get_list_win()
			if list_win and vim.api.nvim_win_is_valid(list_win) then
				vim.api.nvim_set_current_win(list_win)
			end
		else
			panels.unfocus_sidebar()
			if content_win and vim.api.nvim_win_is_valid(content_win) then
				vim.api.nvim_set_current_win(content_win)
			end
		end
		refresh(sorted)
	end
end

M.exit_menu = function()
	if not menu_focused or is_landing then
		return
	end
	menu_focused = false
	if opts and opts.menu_autohide then
		panels.hide_for_autohide(content_win)
		if autohide_hint_win and vim.api.nvim_win_is_valid(autohide_hint_win) then
			vim.api.nvim_win_close(autohide_hint_win, true)
		end
		autohide_hint_win = nil
		autohide_hint_buf = nil
		if content_win and vim.api.nvim_win_is_valid(content_win) then
			autohide_hint_win, autohide_hint_buf = hints_panel.create_bottom_right(content_win, opts.keys)
		end
	else
		panels.unfocus_sidebar()
	end
	refresh(get_sorted_poppies())
	if content_win and vim.api.nvim_win_is_valid(content_win) then
		vim.api.nvim_set_current_win(content_win)
		local cbuf = vim.api.nvim_win_get_buf(content_win)
		if vim.bo[cbuf].buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end
end

M.switch = function(poppy_name)
	if not M.is_open() or not opts or not opts.poppies or not opts.poppies[poppy_name] then
		return
	end

	if current_poppy_name then
		local cur_state = M.poppies[current_poppy_name]
		if cur_state then
			cur_state.active = false
			cur_state.hidden = true
		end
	end

	if is_landing then
		panels.destroy()
		local sw = (opts and opts.sidebar_width) or 25
		local wc = vim.api.nvim_win_get_config(wrapper_win)
		local full_width = _active_width()
		vim.api.nvim_win_set_config(wrapper_win, {
			relative = wc.relative,
			width = full_width,
			height = wc.height,
			col = math.floor((vim.o.columns - full_width) / 2),
			row = wc.row,
		})
		local hdr = header_lines()
		local c_win, c_buf = content.create(wrapper_win, sw)
		panels.create(wrapper_win, sw, 4, hdr)
		_watch_content_window(c_win, sw)
		content_win = c_win
		content_buf = c_buf
		is_landing = false
		input.setup_sidebar(panels.get_list_buf(), opts and opts.keys)
	end

	local poppy_opts = opts.poppies[poppy_name]
	current_poppy_name = poppy_name
	local sorted_poppies = get_sorted_poppies()

	local mode = poppy_opts.mode
	require("poppy.modes." .. mode).run(poppy_name, opts, content_win)

	input.setup_content(vim.api.nvim_win_get_buf(content_win), opts and opts.keys)

	menu_focused = false
	if opts.menu_autohide then
		panels.hide_for_autohide(content_win)
		if autohide_hint_win and vim.api.nvim_win_is_valid(autohide_hint_win) then
			vim.api.nvim_win_close(autohide_hint_win, true)
		end
		autohide_hint_win = nil
		autohide_hint_buf = nil
		if content_win and vim.api.nvim_win_is_valid(content_win) then
			autohide_hint_win, autohide_hint_buf = hints_panel.create_bottom_right(content_win, opts.keys)
		end
	else
		panels.unfocus_sidebar()
	end

	refresh(sorted_poppies)
	vim.api.nvim_set_current_win(content_win)

	if vim.bo[vim.api.nvim_win_get_buf(content_win)].buftype == "terminal" then
		vim.cmd("startinsert")
	end
end

M.switch_by_index = function(index)
	local sorted = get_sorted_poppies()
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
	if not current_poppy_name then
		return
	end
	local target = current_poppy_name
	local p_state = M.poppies[target]
	local target_bufnr = p_state and p_state.bufnr

	M.poppies[target] = nil
	current_poppy_name = nil
	_recover()

	if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
		vim.api.nvim_buf_delete(target_bufnr, { force = true })
	end

	if content_win and vim.api.nvim_win_is_valid(content_win) then
		pcall(vim.api.nvim_set_current_win, content_win)
	end
end

M.kill_by_index = function(index)
	local sorted = get_sorted_poppies()
	local item = sorted[index]
	if not item then
		return
	end
	local name = item.name

	if name == current_poppy_name then
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

	if M.is_open() and not is_landing then
		refresh(get_sorted_poppies())
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

_recover = function()
	current_poppy_name = nil
	vim.schedule(function()
		if not M.is_open() or is_landing or current_poppy_name then
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
			if autohide_hint_win then
				vim.api.nvim_win_close(autohide_hint_win, true)
			end
			autohide_hint_win = nil
			autohide_hint_buf = nil
			_suppress_watch = true
			if content_win and vim.api.nvim_win_is_valid(content_win) then
				vim.api.nvim_win_close(content_win, true)
			end
			content_win = nil
			content_buf = nil
			_suppress_watch = false

			if not landing_view_width then
				landing_view_width = compute_landing_view_width()
			end
			local wc = vim.api.nvim_win_get_config(wrapper_win)
			vim.api.nvim_win_set_config(wrapper_win, {
				relative = wc.relative,
				width = landing_view_width,
				height = wc.height,
				col = math.floor((vim.o.columns - landing_view_width) / 2),
				row = wc.row,
			})
			panels.create_landing(wrapper_win, header_lines())
			is_landing = true

			local sorted = get_sorted_poppies()
			local list_buf = panels.get_list_buf()
			vim.bo[list_buf].filetype = "poppy_menu"
			input.setup_sidebar(list_buf, opts and opts.keys)
			refresh(sorted)

			local list_win = panels.get_list_win()
			if list_win and vim.api.nvim_win_is_valid(list_win) then
				pcall(vim.api.nvim_set_current_win, list_win)
			end
		end
	end)
end

local cleanup = function()
	if current_poppy_name then
		local ps = M.poppies[current_poppy_name]
		if ps then
			ps.active = false
			ps.hidden = true
			ps.win = nil
		end
	end

	if autohide_hint_win and vim.api.nvim_win_is_valid(autohide_hint_win) then
		vim.api.nvim_win_close(autohide_hint_win, true)
	end
	autohide_hint_win = nil
	autohide_hint_buf = nil

	panels.destroy()

	_suppress_watch = true
	for _, win in ipairs({ wrapper_win, content_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	_suppress_watch = false

	local has_running_popies = next(M.poppies) ~= nil
	local buffers = { content_buf }
	if not has_running_popies then
		table.insert(buffers, wrapper_buf)
		table.insert(buffers, panels.get_hints_buf())
		table.insert(buffers, panels.get_list_buf())
		local hbuf = panels.get_header_buf()
		if hbuf then
			table.insert(buffers, hbuf)
		end
	end

	for _, buf in ipairs(buffers) do
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	wrapper_win = nil
	content_win = nil
	content_buf = nil
	is_landing = false
	menu_focused = false
end

local hard_cleanup = function()
	for _, p_state in pairs(M.poppies) do
		if p_state and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then
			vim.api.nvim_buf_delete(p_state.bufnr, { force = true })
		end
	end
	M.poppies = {}
	current_poppy_name = nil
	cleanup()
end

M.close = function()
	hard_cleanup()
end

M.toggle = function()
	if M.is_open() then
		cleanup()
	else
		M.open()
	end
end

M.setup = function(user_opts)
	M.poppies = {}
	landing_view_width = nil
	is_landing = false
	menu_focused = false
	current_poppy_name = nil
	wrapper_win = nil
	autohide_hint_win = nil
	autohide_hint_buf = nil

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
			if M.is_open() and current_poppy_name == poppy_name then
				_recover()
			end
		end,
	})

	if opts.menu_autohide then
		vim.api.nvim_create_autocmd("CursorHold", {
			group = "poppy_group",
			callback = function()
				if vim.bo.filetype == "poppy_menu" then
					M.exit_menu()
				end
			end,
		})
	end

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

M.current_poppy_name = nil
M.poppies = {}

setmetatable(M, {
	__index = function(_, k)
		if k == "current_poppy_name" then
			return current_poppy_name
		end
		return nil
	end,
	__newindex = function(_, k, v)
		if k == "current_poppy_name" then
			current_poppy_name = v
			return
		end
		rawset(M, k, v)
	end,
})

return M