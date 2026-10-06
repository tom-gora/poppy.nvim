require("poppy._types")

local M = {}

local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")

-- ─── Cursor as the list's row marker ───────────────────────────────────────
-- The list reserves a leading cell on every row and the real cursor sits in it,
-- so the cursor is the row indicator rather than a drawn glyph.
--
-- 'guicursor' is the only lever for stopping it blinking, and it is *global*: it cannot be set
-- per window (nvim rejects { win = ... }, and { scope = "local" } silently writes through to the
-- global). So while the list holds focus we swap it to a static block and put the user's value
-- back on the way out. A missed restore would leave a static block cursor in every window.
local LIST_CURSOR = "a:block-blinkon0"

-- Module-level and never reinitialised. M.setup() re-runs on every ColorScheme and setup()
-- call; clearing `overridden` while still owning the global would discard the user's saved value.
local cursor_mode = {
	-- The user's own value, captured once before we first touch it.
	saved = nil,
	-- Whether we currently have a value stashed, independent of what it is.
	overridden = false,
	-- The list window we last entered, so a WinLeave for some other window doesn't restore.
	menu_win = nil,
}

-- The list window is recreated on every mount (its id changes; only the buffer id is stable).
-- WinEnter/WinLeave callbacks pass a *buffer* id, not a window id -- identity has to come from state.
---@return integer|nil
local current_menu_win = function()
	local win = state.windows.menu_win
	if win and api.nvim_win_is_valid(win) then
		return win
	end
	return nil
end

---Put the user's own 'guicursor' back. Safe to call at any time and more than once: no-op unless
---we are the ones who overrode it.
---@return nil
local restore_cursor_mode = function()
	if not cursor_mode.overridden then
		return
	end
	cursor_mode.overridden = false
	cursor_mode.menu_win = nil
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
	if cursor_mode.menu_win == win then
		return
	end
	-- Re-entered without leaving (window remounted under focus): keep the original cached value.
	if not cursor_mode.overridden then
		local ok, current = pcall(function()
			return vim.o.guicursor
		end)
		if ok then
			cursor_mode.saved = current
			cursor_mode.overridden = true
		end
	end
	cursor_mode.menu_win = win
	pcall(function()
		vim.o.guicursor = LIST_CURSOR
	end)
end

-- Exposed so session cleanup can restore explicitly: teardown can close windows without a
-- clean WinLeave, and a clobbered global 'guicursor' outliving the session is unacceptable.
M.restore_cursor_mode = restore_cursor_mode

-- Registered from M.setup so a second setup() clears and rebuilds rather than stacking. cursor_mode
-- is module-level and survives a rebuild, so a mid-override re-register cannot lose the saved value.
local setup_cursor_autocmds = function()
	api.nvim_create_augroup("poppy_body_cursor_mode", { clear = true })
	api.nvim_create_autocmd("WinEnter", {
		group = "poppy_body_cursor_mode",
		callback = function()
			local menu_win = current_menu_win()
			if menu_win and api.nvim_get_current_win() == menu_win then
				apply_list_guicursor(menu_win)
			end
		end,
	})
	api.nvim_create_autocmd("WinLeave", {
		group = "poppy_body_cursor_mode",
		callback = function()
			-- Restore on every leave once we hold an override, without checking the window id.
			-- Any window-id test is unreliable here: WinLeave fires while the outgoing window is
			-- still current, so "is the list still current" is true even as focus leaves it; the
			-- paired WinEnter re-applies the override if focus returns. Over-restoring is self-correcting.
			restore_cursor_mode()
		end,
	})
	api.nvim_create_autocmd("VimLeavePre", {
		group = "poppy_body_cursor_mode",
		callback = restore_cursor_mode,
	})
end

-- Darken the sidebar/landing panel surface slightly so the float reads as its own surface
-- against NormalFloat. Only the panel surface is touched; fg and text colours are left to the theme.
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
	-- Three states, all from the signcolumn: active = red dot, hidden = small dot, never opened = nothing.
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

-- Dialog answer glyphs, padded to 2 cells like the category icons: two stacked signs must keep
-- the signcolumn at SIGN_COL, which measure_item budgets against.
local CONFIRM_SIGNS = {
	{ name = "PoppyConfirmYes", text = "\u{2714}" },
	{ name = "PoppyConfirmNo", text = "\u{2717}" },
	{ name = "PoppyConfirmCancel", text = "\u{25C0}" },
}

local define_confirm_signs = function()
	for _, s in ipairs(CONFIRM_SIGNS) do
		local w = fn.strdisplaywidth(s.text)
		pcall(fn.sign_define, s.name, {
			text = w >= 2 and s.text or s.text .. string.rep(" ", 2 - w),
			texthl = "PoppyCurrentRowFile",
		})
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
	-- A colorscheme change can land while the list holds focus, leaving our override installed.
	-- Handled here rather than as a fourth autocmd: this function re-runs on ColorScheme and
	-- clears its own augroup, so an autocmd living there would be torn down mid-dispatch.
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

	-- Cursorline sourced from the theme so it matches the terminal. nvim 0.13 has a native
	-- cursorlinehl option; on 0.12 this goes through winhl.
	local cline = api.nvim_get_hl(0, { name = "CursorLine" })
	api.nvim_set_hl(0, "PoppyCursorLine", { fg = cline.fg, bg = cline.bg })

	-- Rows use the raw category colour. State is carried by the signcolumn, not by the text.
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
	define_confirm_signs()

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

-- List imitates a selector: real cursor in the leading cell, cursorline background. SignColumn
-- is pinned to the panel background so cursorline never bleeds into it -- state lives there.
---@param win integer
M.apply_body_style = function(win)
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
