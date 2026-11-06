require("poppy._types")

local M = {}

local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

-- 'guicursor' is global only; nvim rejects { win = ... }, and { scope = "local" } silently
-- writes through to the global. A missed restore would leave a static block cursor in every window.
local LIST_CURSOR = "a:block-blinkon0-PoppyCursor"

-- M.setup() re-runs on every ColorScheme and setup() call. Clearing `overridden` while still
-- owning the global would discard the user's saved value.
---@class CursorMode
---@field saved string?
---@field overridden boolean
---@field menu_win integer?
local cursor_mode = {
	saved = nil,
	overridden = false,
	menu_win = nil,
}

-- The list window is recreated on every mount (its id changes; only the buffer id is stable).
---@return integer|nil
local current_menu_win = function()
	local win = state.windows.menu_win
	if win and api.nvim_win_is_valid(win) then
		return win
	end
	return nil
end

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
		if ok and type(current) == "string" then
			cursor_mode.saved = current
			cursor_mode.overridden = true
		end
	end
	cursor_mode.menu_win = win
	pcall(function()
		vim.o.guicursor = LIST_CURSOR
	end)
end

-- Teardown can close windows without a clean WinLeave; a clobbered global 'guicursor' outliving
-- the session is unacceptable.
M.restore_cursor_mode = restore_cursor_mode

-- M.setup clears its own augroup, so an autocmd living there would be torn down mid-dispatch.
local reapply_menu_cursor = function()
	local menu_win = current_menu_win()
	if menu_win and api.nvim_get_current_win() == menu_win then
		apply_list_guicursor(menu_win)
	end
end

local setup_cursor_autocmds = function()
	api.nvim_create_augroup("poppy_body_cursor_mode", { clear = true })
	api.nvim_create_autocmd("WinEnter", {
		group = "poppy_body_cursor_mode",
		callback = reapply_menu_cursor,
	})
	api.nvim_create_autocmd("WinLeave", {
		group = "poppy_body_cursor_mode",
		callback = restore_cursor_mode,
	})
	api.nvim_create_autocmd("VimLeavePre", {
		group = "poppy_body_cursor_mode",
		callback = restore_cursor_mode,
	})
end

---@return "light"|"dark"
local get_bg_variant = function()
	local hl = vim.api.nvim_get_hl(0, { name = "Normal" })
	if not hl or not hl.bg then
		return vim.o.background
	end
	local bg_dec = hl.bg
	local r = math.floor(bg_dec / 65536) / 255
	local g = math.floor((bg_dec % 65536) / 256) / 255
	local b = (bg_dec % 256) / 255
	local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
	return luminance > 0.5 and "light" or "dark"
end

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

-- pcall so an unrecognized hl in a misconfigured theme doesn't abort. Re-run on every setup so
-- signs track the just-set groups.
local define_poppy_signs = function()
	local signs = {
		{ name = "PoppyDotActive", text = "◉", texthl = "PoppyRed" },
		{ name = "PoppyDotFileH", text = "•", texthl = "PoppyFileHidden" },
		{ name = "PoppyDotExecH", text = "•", texthl = "PoppyExecHidden" },
		{ name = "PoppyDotShellH", text = "•", texthl = "PoppyShellHidden" },
		{ name = "PoppyDotNone", text = " ", texthl = "PoppyNormalPanel" },
	}
	for _, s in ipairs(signs) do
		pcall(fn.sign_define, s.name, s)
	end
end

-- Padded to 2 cells like the category icons so two stacked signs keep signcolumn=SIGN_COL.
local ANSWER_SIGNS = {
	{ name = "PoppyAnswerYes", text = "Y" },
	{ name = "PoppyAnswerNo", text = "N" },
	{ name = "PoppyAnswerSave", text = "S" },
	{ name = "PoppyAnswerDiscard", text = "D" },
	{ name = "PoppyAnswerCancel", text = "X" },
}

local define_answer_signs = function()
	for _, s in ipairs(ANSWER_SIGNS) do
		local w = fn.strdisplaywidth(s.text)
		pcall(fn.sign_define, s.name, {
			text = w >= 2 and s.text or s.text .. string.rep(" ", 2 - w),
			texthl = "PoppyCurrentRowFile",
		})
	end
end

---@param icons? PoppyIcons
---@return nil
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

---@return nil
M.setup = function()
	restore_cursor_mode()

	-- normalize and guard bg even if theme does not set vim.o.background
	local lum = get_bg_variant()
	local content_adjust_factor = (lum == "dark") and 0.05 or -0.05
	local panel_adjust_factor = (lum == "dark") and -0.05 or 0.1

	local nf = api.nvim_get_hl(0, { name = "NormalFloat", link = false })
	local fb = api.nvim_get_hl(0, { name = "FloatBorder", link = false })
	local str = api.nvim_get_hl(0, { name = "Label", link = false })
	local use_borders = shared.use_borders()
	-- skip shading if using borders as surface dlimiting
	if use_borders then
		goto continue
	end
	-- Shading is computed here, not above: adjust_brightness needs a real bg, and the
	-- fallback branch below handles the case where NormalFloat carries none.
	if nf.bg then
		local bg_content = adjust_brightness(nf.bg, content_adjust_factor)
		local multiply_factor = (lum == "dark") and 3.5 or 5.5
		local bg_panel = adjust_brightness(nf.bg, panel_adjust_factor * multiply_factor)

		api.nvim_set_hl(0, "PoppyNormalContent", {
			bg = bg_content,
			fg = nf.fg,
		})
		api.nvim_set_hl(0, "PoppyBorderContent", { fg = fb.fg or str.fg, bg = bg_content })

		api.nvim_set_hl(0, "PoppyNormalPanel", {
			fg = nf.fg,
			bg = bg_panel,
		})
		api.nvim_set_hl(0, "PoppyBorderPanel", { fg = fb.fg, bg = bg_panel })
	else -- fallback
		api.nvim_set_hl(0, "PoppyNormalPanel", { link = "NormalFloat", force = true })
		api.nvim_set_hl(0, "PoppyNormalContent", { link = "NormalFloat", force = true })
		api.nvim_set_hl(0, "PoppyBorderPanel", { link = "FloatBorder", force = true })
		api.nvim_set_hl(0, "PoppyBorderContent", { link = "FloatBorder", force = true })
	end
	::continue::
	api.nvim_set_hl(0, "PoppyCursor", { link = "Cursor", force = true })
	api.nvim_set_hl(0, "PoppyCursorLine", { link = "CursorLine", force = true })
	local err = api.nvim_get_hl(0, { name = "DiagnosticError", link = false })
	api.nvim_set_hl(0, "PoppyRed", { fg = err.fg, bg = "none" })
	api.nvim_set_hl(0, "PoppySeparator", { fg = fb.fg, bg = "none" })
	api.nvim_set_hl(0, "SignColumn", { bg = "none" })

	local comment = api.nvim_get_hl(0, { name = "Comment", link = false })
	api.nvim_set_hl(0, "PoppyInactive", { fg = comment.fg, bg = "none" })

	local type_hl = api.nvim_get_hl(0, { name = "Constant", link = false })
	local string_hl = api.nvim_get_hl(0, { name = "String", link = false })
	local func_hl = api.nvim_get_hl(0, { name = "Function", link = false })
	local lnr = api.nvim_get_hl(0, { name = "LineNr", link = false })
	local clnr = api.nvim_get_hl(0, { name = "CursorLineNr", link = false })
	local lnra = api.nvim_get_hl(0, { name = "LineNrAbove", link = false })
	local lnrb = api.nvim_get_hl(0, { name = "LineNrBelow", link = false })

	-- Rows use the raw category colour; state lives in the signcolumn, not the text.
	local CATEGORY = { { "File", type_hl }, { "Exec", string_hl }, { "Shell", func_hl } }

	for _, entry in ipairs(CATEGORY) do
		local cat, hl = entry[1], entry[2]
		api.nvim_set_hl(0, "Poppy" .. cat, { fg = hl.fg })
		api.nvim_set_hl(0, "PoppyCurrentRow" .. cat, { fg = hl.fg, bold = true })
		if hl.fg then
			api.nvim_set_hl(0, "Poppy" .. cat .. "Hidden", { fg = hl.fg, bold = false, force = true })
		else
			api.nvim_set_hl(0, "Poppy" .. cat .. "Hidden", { link = "Comment" }) -- fallback
		end
	end

	for _, entry in ipairs({
		{ "PoppyLineNr", lnr },
		{ "PoppyCursorLineNr", clnr },
		{ "PoppyLineNrAbove", lnra },
		{ "PoppyLineNrBelow", lnrb },
	}) do
		api.nvim_set_hl(0, entry[1], { fg = entry[2].fg, bg = "none" })
	end

	define_poppy_signs()
	define_answer_signs()
	M.define_icon_signs(state.windows.opts and state.windows.opts.icons)

	api.nvim_create_augroup("poppy_style", { clear = true })
	api.nvim_create_autocmd("ColorScheme", {
		group = api.nvim_create_augroup("poppy_style", { clear = true }),
		callback = function()
			M.setup()
		end,
	})

	setup_cursor_autocmds()

	reapply_menu_cursor()
end

---@param win integer
M.apply_hints_panel_style = function(win)
	local use_borders = shared.use_borders()
	if use_borders then
		return
	end
	set_winhl_deferred(
		win,
		"Normal:PoppyNormalPanel,EndOfBuffer:PoppyNormalPanel,NonText:PoppyNormalPanel,Whitespace:PoppyNormalPanel"
	)
end

---@param win integer
M.apply_panel_style = function(win)
	local use_borders = shared.use_borders()
	if use_borders then
		return
	end
	set_winhl_deferred(
		win,
		"NormalNC:PoppyNormalPanel,Normal:PoppyNormalPanel,EndOfBuffer:PoppyNormalPanel,NonText:PoppyNormalPanel,Whitespace:PoppyNormalPanel,FloatBorder:PoppyBorderPanel"
	)
end

---@param win integer
---@return nil
M.apply_body_style = function(win)
	vim.schedule(function()
		if not api.nvim_win_is_valid(win) then
			return
		end
		local use_borders = shared.use_borders()
		if use_borders then
			goto continue
		end
		api.nvim_set_option_value(
			"winhl",
			"Normal:PoppyNormalPanel,EndOfBuffer:PoppyNormalPanel,NonText:PoppyNormalPanel,Whitespace:PoppyNormalPanel,CursorLine:PoppyCursorLine",
			{ scope = "local", win = win }
		)
		::continue::
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
		local buf = api.nvim_win_get_buf(win)
		local use_borders = shared.use_borders()
		if use_borders then
			goto continue
		end
		api.nvim_set_option_value(
			"winhl",
			"Normal:PoppyNormalContent,EndOfBuffer:PoppyNormalContent,NonText:PoppyNormalContent,Whitespace:PoppyNormalContent,FloatBorder:PoppyBorderContent,LineNr:PoppyLineNr,LineNrAbove:PoppyLineNrAbove,LineNrBelow:PoppyLineNrBelow,CursorLineNr:PoppyCursorLineNr",
			{ scope = "local", win = win }
		)
		::continue::
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
	local use_borders = shared.use_borders()
	if use_borders then
		return
	end
	set_winhl_deferred(
		win,
		"Normal:PoppyNormalPanel,EndOfBuffer:PoppyNormalPanel,NonText:PoppyNormalPanel,Whitespace:PoppyNormalPanel,FloatBorder:PoppyBorder"
	)
end

return M
