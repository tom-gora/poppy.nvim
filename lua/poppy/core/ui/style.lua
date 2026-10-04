require("poppy._types")

local M = {}

local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")

-- ─── Cursor as the list's row marker ───────────────────────────────────────
-- The list reserves a leading cell on every row and the real cursor sits in
-- it, so the cursor is the row indicator rather than a drawn glyph.
--
-- 'guicursor' is the only lever for stopping it blinking, and it is a *global*
-- option: it cannot be set per window (nvim rejects { win = ... }, and
-- { scope = "local" } silently writes through to the global). So while the list
-- holds focus we swap it to a static block and put the user's own value back on
-- the way out. That window is the entire user-visible cost, and restoring it is
-- the entire safety obligation -- a missed restore would leave a static block
-- cursor in every window.
--
-- This lives with the rest of the cursor's appearance rather than with the
-- panels: the cursorline background (PoppyCursorLine, apply_list_style) and the
-- cursor's shape are the same concern, and only one module should own the
-- global-option save/restore dance.
local LIST_CURSOR = "a:block-blinkon0"

-- Module-level and never reinitialised. M.setup() re-runs on every ColorScheme
-- and on every setup() call; clearing `overridden` while vim.o.guicursor was
-- still our override would discard the user's saved value with no way back.
local cursor_mode = {
	-- The user's own value, captured once before we first touch it. Kept for the
	-- lifetime of the session so a re-enter cannot overwrite it with our own.
	saved = nil,
	-- Whether we currently have a value stashed, independent of what it is.
	overridden = false,
	-- The list window we last entered, so a WinLeave for some other window does
	-- not restore out from under us.
	list_win = nil,
}

-- The list window is recreated on every mount (its id changes; only its buffer
-- id is stable), so the window is always read fresh from state rather than
-- captured. Note that a WinEnter/WinLeave callback's args.buf is a *buffer* id,
-- not a window id -- and on WinLeave it is the outgoing window's buffer, which
-- is not the list's -- so identity has to come from state, never from args.
---@return integer|nil
local current_list_win = function()
	local win = state.windows.list_win
	if win and api.nvim_win_is_valid(win) then
		return win
	end
	return nil
end

---Put the user's own 'guicursor' back. Safe to call at any time and more than
---once: it is a no-op unless we are the ones who overrode it.
---@return nil
local restore_cursor_mode = function()
	if not cursor_mode.overridden then
		return
	end
	cursor_mode.overridden = false
	cursor_mode.list_win = nil
	if cursor_mode.saved == nil then
		return
	end
	local saved = cursor_mode.saved
	cursor_mode.saved = nil
	pcall(function()
		vim.o.guicursor = saved
	end)
end

---@param win integer
---@return nil
local apply_list_guicursor = function(win)
	if cursor_mode.list_win == win then
		return
	end
	-- Re-entered without leaving (window remounted under focus): keep the
	-- original cached value rather than capturing our own override.
	if not cursor_mode.overridden then
		local ok, current = pcall(function()
			return vim.o.guicursor
		end)
		if ok then
			cursor_mode.saved = current
			cursor_mode.overridden = true
		end
	end
	cursor_mode.list_win = win
	pcall(function()
		vim.o.guicursor = LIST_CURSOR
	end)
end

-- Exposed so session cleanup can restore explicitly: teardown closes windows in
-- ways that do not always produce a clean WinLeave, and a clobbered global
-- 'guicursor' outliving the session is not acceptable.
M.restore_cursor_mode = restore_cursor_mode

-- Registered from M.setup rather than at load, so a second setup() clears and
-- rebuilds them instead of stacking a duplicate WinEnter/WinLeave pair.
-- Recreating the group is safe: cursor_mode is module-level and survives
-- untouched, so a rebuild mid-override cannot lose the user's saved 'guicursor'.
local setup_cursor_autocmds = function()
	api.nvim_create_augroup("poppy_list_cursor_mode", { clear = true })
	api.nvim_create_autocmd("WinEnter", {
		group = "poppy_list_cursor_mode",
		callback = function()
			-- WinEnter: the new window is current, so compare against it.
			local list_win = current_list_win()
			if list_win and api.nvim_get_current_win() == list_win then
				apply_list_guicursor(list_win)
			end
		end,
	})
	api.nvim_create_autocmd("WinLeave", {
		group = "poppy_list_cursor_mode",
		callback = function()
			-- Restore on *every* leave once we hold an override, without trying to
			-- work out whether the window in question was the list. Any window-id
			-- test here is unreliable: WinLeave fires while the outgoing window is
			-- still current, so "is the list still current" is true even as focus
			-- leaves it, and killing a poppy from inside the list destroys and
			-- rebuilds the window mid-teardown so state can name the replacement.
			-- The paired WinEnter re-applies the override if focus lands back on the
			-- list, so over-restoring is self-correcting and leaking is not.
			restore_cursor_mode()
		end,
	})
	-- Teardown can close windows without a clean WinLeave, and leaving a global
	-- option clobbered is the worst thing this plugin could do.
	api.nvim_create_autocmd("VimLeavePre", {
		group = "poppy_list_cursor_mode",
		callback = restore_cursor_mode,
	})
end

-- Darken the sidebar/landing panel background slightly so the float reads as its
-- own surface against the editor's NormalFloat. Only the panel surface is
-- touched -- fg and every text colour are left to the theme.
--
-- Increase the magnitude to make the panel more distinct; move it toward 0 to
-- flatten the panel back into the surrounding background. Positive values
-- lighten instead, which is how this used to work before it was dropped.
local PANEL_BG_DARKEN_FACTOR = -0.3

---@param color integer
---@param factor number
---@return integer
local adjust_brightness = function(color, factor)
	local target = factor >= 0 and 255 or 0
	local f = math.abs(factor)
	local r = math.floor(color / 65536)
	local g = math.floor((color % 65536) / 256)
	local b = color % 256
	r = math.max(0, math.min(255, math.floor(r + (target - r) * f)))
	g = math.max(0, math.min(255, math.floor(g + (target - g) * f)))
	b = math.max(0, math.min(255, math.floor(b + (target - b) * f)))
	return r * 65536 + g * 256 + b
end

-- pcall so an unrecognized hl in a misconfigured theme doesn't abort. Re-run on every setup so signs track the just-set groups.
local define_poppy_signs = function()
	-- Three states, read purely from the signcolumn: the active poppy gets the
	-- red logo circle, anything running in the background gets a small dot, and
	-- never-opened poppies get nothing.
	local signs = {
		{ name = "PoppyDotActive", text = "◉", texthl = "PoppyRed" },
		{ name = "PoppyDotFileH", text = "•", texthl = "PoppyFileHidden" },
		{ name = "PoppyDotExecH", text = "•", texthl = "PoppyExecHidden" },
		{ name = "PoppyDotShellH", text = "•", texthl = "PoppyShellHidden" },
		{ name = "PoppyDotNone", text = " ", texthl = "NormalPoppyUIPanel" },
	}
	for _, s in ipairs(signs) do
		pcall(fn.sign_define, s.name, s)
	end
end

---@param icons? PoppyIcons
---@return void
M.define_icon_signs = function(icons)
	---@param icon string
	---@return string
	local pad_icon = function(icon)
		local w = fn.strdisplaywidth(icon)
		if w >= 2 then
			return icon
		end
		return icon .. string.rep(" ", 2 - w)
	end

	local map = {
		{ "File", icons and icons.file or " " },
		{ "Exec", icons and icons.exec or " " },
		{ "Shell", icons and icons.shell or " " },
	}
	for _, e in ipairs(map) do
		local cap, icon_text = e[1], e[2]
		local padded = pad_icon(icon_text)
		pcall(fn.sign_define, "PoppyIcon" .. cap, { text = padded, texthl = "Poppy" .. cap })
		pcall(fn.sign_define, "PoppyIconCurrent" .. cap, { text = padded, texthl = "PoppyCurrentRow" .. cap })
	end
end

---@param win integer
---@param mappings string
local set_winhl_deferred = function(win, mappings)
	vim.schedule(function()
		if not api.nvim_win_is_valid(win) then
			return
		end
		api.nvim_set_option_value("winhl", mappings, { scope = "local", win = win })
	end)
end

---@return void
M.setup = function()
	-- A colorscheme change can land while the list holds focus, leaving our
	-- override installed. Handled here rather than as a fourth autocmd: this
	-- function re-runs on ColorScheme and clears its own augroup, so an
	-- autocmd living in that group would be torn down mid-dispatch. Calling it
	-- directly is the same reaction with a deterministic order.
	restore_cursor_mode()

	local nf = api.nvim_get_hl(0, { name = "NormalFloat" })
	if nf.bg then
		api.nvim_set_hl(0, "NormalPoppyUIPanel", {
			bg = adjust_brightness(nf.bg, PANEL_BG_DARKEN_FACTOR),
			fg = nf.fg,
		})
		api.nvim_set_hl(0, "NormalPoppyContent", { link = "NormalFloat" })
	else
		api.nvim_set_hl(0, "NormalPoppyUIPanel", { link = "NormalFloat" })
		api.nvim_set_hl(0, "NormalPoppyContent", { link = "NormalFloat" })
	end
	local panel_hl = api.nvim_get_hl(0, { name = "NormalPoppyUIPanel" })
	local err = api.nvim_get_hl(0, { name = "ErrorMsg" })
	api.nvim_set_hl(0, "PoppyRed", { fg = err.fg, bg = panel_hl.bg })

	local str = api.nvim_get_hl(0, { name = "Label" })
	api.nvim_set_hl(0, "PoppyBorder", { fg = str.fg, bg = nf.bg })

	local comment = api.nvim_get_hl(0, { name = "Comment" })
	api.nvim_set_hl(0, "PoppyInactive", { fg = comment.fg, bg = nf.bg })
	api.nvim_set_hl(0, "PoppyActive", { link = "IncSearch" })

	local type_hl = api.nvim_get_hl(0, { name = "Type" })
	local string_hl = api.nvim_get_hl(0, { name = "String" })
	local func_hl = api.nvim_get_hl(0, { name = "Function" })
	local lnr = api.nvim_get_hl(0, { name = "LineNr" })
	local clnr = api.nvim_get_hl(0, { name = "CursorLineNr" })
	local lnra = api.nvim_get_hl(0, { name = "LineNrAbove" })
	local lnrb = api.nvim_get_hl(0, { name = "LineNrBelow" })

	-- The list imitates a selector: the cursor row is marked by a cursorline
	-- background, and the real cursor acts as the row marker. Sourced from the
	-- theme so it matches the terminal rather than imposing a colour. nvim 0.13
	-- has a native cursorlinehl option; on 0.12 this goes through winhl.
	local cline = api.nvim_get_hl(0, { name = "CursorLine" })
	api.nvim_set_hl(0, "PoppyCursorLine", { fg = cline.fg, bg = cline.bg })

	-- Rows use the raw category colour. No tinting toward Normal and no dimming
	-- for hidden rows: state is carried by the signcolumn, not by the text.
	local CATEGORY = { { "File", type_hl }, { "Exec", string_hl }, { "Shell", func_hl } }

	for _, entry in ipairs(CATEGORY) do
		local cap, hl = entry[1], entry[2]
		api.nvim_set_hl(0, "Poppy" .. cap, { fg = hl.fg })
		api.nvim_set_hl(0, "PoppyCurrentRow" .. cap, { fg = hl.fg })
		if hl.fg then
			api.nvim_set_hl(0, "Poppy" .. cap .. "Hidden", { fg = hl.fg })
		else
			api.nvim_set_hl(0, "Poppy" .. cap .. "Hidden", { link = "Comment" })
		end
	end

	for _, entry in ipairs({
		{ "PoppyLineNr", lnr },
		{ "PoppyCursorLineNr", clnr },
		{ "PoppyLineNrAbove", lnra },
		{ "PoppyLineNrBelow", lnrb },
	}) do
		api.nvim_set_hl(0, entry[1], { fg = entry[2].fg, bg = nf.bg })
	end

	api.nvim_set_hl(0, "PoppyActiveDot", { link = "Normal" })

	define_poppy_signs()

	api.nvim_create_augroup("poppy_style", { clear = true })
	---@type vim.api.keyset.create_autocmd
	local colorscheme_autocmd = {
		group = "poppy_style",
		callback = function()
			M.setup()
		end,
	}
	api.nvim_create_autocmd("ColorScheme", colorscheme_autocmd)

	setup_cursor_autocmds()
end

---@param win integer
M.apply_hints_panel_style = function(win)
	set_winhl_deferred(win, "Normal:NormalPoppyUIPanel")
end

---@param win integer
M.apply_panel_style = function(win)
	set_winhl_deferred(win, "Normal:NormalPoppyUIPanel,SignColumn:NormalPoppyUIPanel")
end

-- The list imitates a selector. The real cursor is the row marker, sitting in
-- the leading cell each row reserves, over a cursorline background.
-- SignColumn is pinned to the panel background so cursorline never bleeds into
-- it -- state lives there, and it must stay static.
---@param win integer
M.apply_list_style = function(win)
	vim.schedule(function()
		if not api.nvim_win_is_valid(win) then
			return
		end
		api.nvim_set_option_value(
			"winhl",
			"Normal:NormalPoppyUIPanel,SignColumn:NormalPoppyUIPanel,CursorLine:PoppyCursorLine",
			{ scope = "local", win = win }
		)
		api.nvim_set_option_value("cursorline", true, { win = win })
	end)
end

---@param win integer
---@param ext_number boolean
---@param ext_relativenumber boolean
M.apply_content_style = function(win, ext_number, ext_relativenumber)
	vim.schedule(function()
		if not api.nvim_win_is_valid(win) then
			return
		end
		api.nvim_set_option_value(
			"winhl",
			"Normal:NormalPoppyContent,SignColumn:NormalPoppyContent,LineNr:PoppyLineNr,LineNrAbove:PoppyLineNrAbove,LineNrBelow:PoppyLineNrBelow,CursorLineNr:PoppyCursorLineNr",
			{ scope = "local", win = win }
		)

		local buf = api.nvim_win_get_buf(win)
		if api.nvim_get_option_value("buftype", { buf = buf }) == "terminal" then
			return
		end
		local win_opts = { win = win }
		api.nvim_set_option_value("cursorline", true, win_opts)
		api.nvim_set_option_value("signcolumn", "yes", win_opts)
		api.nvim_set_option_value("number", ext_number, win_opts)
		api.nvim_set_option_value("relativenumber", ext_relativenumber, win_opts)
	end)
end

---@param win integer
M.apply_border_style = function(win)
	set_winhl_deferred(win, "FloatBorder:PoppyBorder")
end

return M
