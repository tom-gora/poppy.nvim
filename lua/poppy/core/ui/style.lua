require("poppy._types")

local M = {}

local api = vim.api
local fn = vim.fn

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
