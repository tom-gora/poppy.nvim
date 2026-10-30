require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local render = require("poppy.core.ui.render")
local shared = require("poppy.core.shared")

---@param spec table
---@return PoppyMenuSpec
local normalize = function(spec)
	spec = spec or {}
	local known = {
		id = true,
		focusable = true,
		trap = true,
		items = true,
		rows = true,
		hints = true,
		keymaps = true,
		menu_header = true,
	}
	local out = {
		id = tostring(spec.id or "menu"),
		focusable = spec.focusable == true,
		trap = spec.trap == true,
		items = spec.items,
		menu_header = spec.menu_header,
		rows = spec.rows or {},
		hints = spec.hints or {},
		keymaps = spec.keymaps or {},
	}
	for k in pairs(spec) do
		if not known[k] then
			shared.notify_warn("menu '%s': ignoring unknown key '%s'", out.id, tostring(k))
		end
	end
	return out
end

---A dialog binds select and nothing else, so the other three are simply absent rather than
---bound to a no-op -- keeps get_keymap honest.
---@param buf integer
---@param keymaps PoppyMenuKeymap[]
---@return integer bound
M.bind = function(buf, keymaps)
	local keys = shared.keys()
	if not keys then
		return 0
	end
	local poppy_action_bound = (shared.resolve_key(keys.poppy_action))
	local configured_lhs = {}
	for _, km in ipairs(keymaps or {}) do
		local lhs = km[1] == "poppy_action" and poppy_action_bound or keys[km[1]]
		if lhs and lhs ~= "" then
			configured_lhs[lhs] = true
		end
	end
	-- vim.keymap.set replaces only on matching lhs; re-binding a narrower spec would leave the
	-- previous keys live and get_keymap would still report them as claimed.
	for _, field in ipairs({ "poppy_action", "select", "kill", "exit_menu" }) do
		local lhs = field == "poppy_action" and poppy_action_bound or keys[field]
		local permanent = shared.permanent_key(field)
		for _, candidate in ipairs({ lhs, permanent }) do
			if candidate and candidate ~= "" then
				pcall(vim.api.nvim_buf_del_keymap, buf, "n", candidate)
				pcall(vim.api.nvim_buf_del_keymap, buf, "t", candidate)
			end
		end
	end
	local bound = 0
	for _, km in ipairs(keymaps or {}) do
		local lhs = km[1] == "poppy_action" and poppy_action_bound or keys[km[1]]
		if type(km[3]) == "function" then
			for _, candidate in ipairs({ lhs, shared.permanent_key(km[1]) }) do
				-- A configured key owns its lhs outright: a permanent key standing on the same
				-- lhs would silently steal the action.
				if candidate and candidate ~= "" and not (candidate ~= lhs and configured_lhs[candidate]) then
					vim.keymap.set(shared.NORM_TERM_MODES, candidate, km[3], {
						buffer = buf,
						desc = "Poppy: " .. km[2],
					})
					bound = bound + 1
				end
			end
		end
	end
	return bound
end

---The panel's CursorMoved guard pins the column; this only chooses the row.
---@param win integer|nil
---@param row integer
---@return boolean moved
M.set_row = function(win, row)
	if not win or not api.nvim_win_is_valid(win) then
		return false
	end
	return pcall(api.nvim_win_set_cursor, win, { math.max(1, row), 0 }) == true
end

---@type PoppyHints
M.HINTS = {
	landing = {
		{ "select", "Select" },
		{ "poppy_action", "Toggle Off" },
	},
	body = {
		{ "select", "Select" },
		{ "kill", "Kill" },
		{ "exit_menu", "Exit menu" },
		{ "poppy_action", "Toggle off" },
	},
}

---`width_source` decides both body and legend width (same panel); view adds geometry.
---@type PoppyMenuLayout
M.LANDING = { width_source = "wrapper", focusable = true, hints = M.HINTS.landing }
---@type PoppyMenuLayout
M.SIDEBAR = { width_source = "menu", focusable = false, hints = M.HINTS.body }
-- The startup dialog owns a standalone narrow column, so it sizes to the wrapper
-- the way landing does. The sidebar dialog keeps the sidebar layout: it renders in
-- the sidebar column beside the content pane.
---@type PoppyMenuLayout
M.DIALOG = { width_source = "wrapper", focusable = true, hints = M.HINTS.landing }

---@return PoppyMenuLayout
M.current_cfg = function()
	local dialog = state.windows.dialog
	if dialog and dialog.kind == "missing_file" then
		return M.DIALOG
	end
	return state.windows.is_landing and M.LANDING or M.SIDEBAR
end

---@param menu PoppyMenuSpec
---@param panel_width integer
---@return string[] lines
---@return integer height
M.menu_header_lines = function(menu, panel_width)
	local src = menu.menu_header
	if not src or #src == 0 then
		return {}, 0
	end
	local text_width = math.max(1, panel_width - render.measure_item(1, ""))
	local joined = table.concat(src, "\n")
	local lines = render.wrap_text(joined, text_width)
	return lines, #lines
end

---Legend lines a menu renders, including the separator and trailing blank.
---@param hints PoppyHint[]
---@return integer
M.legend_height = function(hints)
	local is_missing_file_dialog = state.windows.dialog and state.windows.dialog.kind == "missing_file"
	local offset = is_missing_file_dialog and 3 or 2
	return #hints + offset
end

---Session required lazily at call time to keep the cycle open.
---@type table
local session = nil

---@param cfg PoppyMenuLayout One of M.LANDING / M.SIDEBAR.
---@return PoppyMenuSpec
M.spec_poppy_list = function(cfg)
	session = session or require("poppy.core.session")
	return normalize({
		id = "poppy_list",
		focusable = cfg.focusable == true,
		items = function(panel_width)
			return render.items_for_poppies(state.poppies_configured, shared.opts_field("icons"), panel_width)
		end,
		hints = cfg.hints or M.HINTS.body,
		keymaps = {
			{
				"select",
				"Select",
				function()
					if vim.v.count > 0 then
						session.switch_by_index(vim.v.count)
					else
						session.switch_by_cursor()
					end
				end,
			},
			{
				"kill",
				"Kill",
				function()
					if vim.v.count > 0 then
						session.kill_by_index(vim.v.count)
					else
						session.kill_by_cursor()
					end
				end,
			},
			{
				"exit_menu",
				"Exit menu",
				function()
					M.exit_menu()
				end,
			},
		},
	})
end

---The spec for whichever presentation is showing. view picks the presentation; focus_body binds.
---@return PoppyMenuSpec
M.current_spec = function()
	return M.spec_override or M.spec_poppy_list(M.current_cfg())
end

---@param spec table|nil
M.set_override = function(spec)
	M.spec_override = spec and normalize(spec) or nil
end

M.clear_override = function()
	M.spec_override = nil
end

---Bind here rather than at mount: focusability is dynamic (sidebar mounts `focusable = false`
---and only becomes focusable on toggle).
---@return boolean focused
M.focus_body = function()
	M.bind(state.windows.menu_buf, M.current_spec().keymaps)
	shared.close_menu_hint()
	local win = state.windows.menu_win
	if not shared.try_focus_win(win) then
		return false
	end
	local name = state.windows.current_poppy_name
	if not name then
		return true
	end
	local idx = state.poppy_index(name)
	if idx then
		M.set_row(win, idx)
	end
	return true
end

M.toggle_menu = function()
	local view = require("poppy.core.ui.view")
	if state.windows.is_landing or not shared.session_is_open() then
		return
	end

	local want_focus = not view.is_menu_focused()

	if shared.opts_field("autohide_menu") then
		view.set_visible(want_focus, state.windows.content_win)
	end

	if want_focus then
		M.focus_body()
	end

	view.set_focused(want_focus)

	view.refresh_menu_when_visible()

	if not want_focus then
		shared.try_focus_win(state.windows.content_win)
	end
end

M.exit_menu = function()
	local view = require("poppy.core.ui.view")
	if not view.is_menu_focused() or state.windows.is_landing then
		return
	end
	-- A live question owns the menu: hiding it would close the question panel and
	-- resolve the dialog destructively (discarding unsaved changes).
	if require("poppy.core.session.dialog").trapped() then
		return
	end

	if shared.opts_field("autohide_menu") then
		view.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	else
		view.set_focused(false)
	end

	view.refresh_menu_when_visible()
	shared.focus_content_in_insert()
end

return M
