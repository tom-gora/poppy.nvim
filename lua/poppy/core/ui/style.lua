require("poppy._types")

local M = {}

local PANELS_BG_LIGHTEN_FACTOR = 0.03
local HIDDEN_LIST_ITEM_DARKEN_FACTOR = -0.4

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

-- pcall so an unrecognized highlight group in a misconfigured theme
-- doesn't abort the plugin. Re-defined on every M.setup so sign text
-- colors track the just-set highlight groups.
---@return nil
local define_poppy_signs = function()
	local signs = {
		{ name = "PoppyDotFileA", text = "•", hl = "PoppyFile" },
		{ name = "PoppyDotFileH", text = "•", hl = "PoppyFileHidden" },
		{ name = "PoppyDotExecA", text = "•", hl = "PoppyExec" },
		{ name = "PoppyDotExecH", text = "•", hl = "PoppyExecHidden" },
		{ name = "PoppyDotShellA", text = "•", hl = "PoppyShell" },
		{ name = "PoppyDotShellH", text = "•", hl = "PoppyShellHidden" },
		{ name = "PoppyDotCurrentFile", text = "•", hl = "PoppyCurrentRowFile" },
		{ name = "PoppyDotCurrentExec", text = "•", hl = "PoppyCurrentRowExec" },
		{ name = "PoppyDotCurrentShell", text = "•", hl = "PoppyCurrentRowShell" },
		{ name = "PoppyDotNone", text = " ", hl = "NormalPoppyUIPanel" },
	}
	---@param s { name: string, text: string, hl: string }
	---@return vim.api.keyset.sign_define
	local sign_def_for = function(s)
		return { text = s.text, texthl = s.hl }
	end
	for _, s in ipairs(signs) do
		pcall(vim.fn.sign_define, s.name, sign_def_for(s))
	end
end

-- Define the per-cat icon signs from the user's configured icons. Called
-- once at setup after config.merge so user overrides reach the signs.
-- Each icon is padded to 2 cells so the gutter stays the same width
-- regardless of glyph width.
---@param icons? PoppyIcons
M.define_icon_signs = function(icons)
	---@param icon string
	---@return string
	local pad_icon = function(icon)
		local w = vim.fn.strdisplaywidth(icon)
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
		pcall(vim.fn.sign_define, "PoppyIcon" .. cap, { text = padded, texthl = "Poppy" .. cap })
		pcall(vim.fn.sign_define, "PoppyIconCurrent" .. cap, { text = padded, texthl = "PoppyCurrentRow" .. cap })
	end
end

-- Validate-inside-schedule so we don't schedule work that would
-- no-op anyway. All panel/window winhl assignments use this.
---@param win integer
---@param mappings string
---@return nil
local set_winhl_deferred = function(win, mappings)
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		vim.api.nvim_set_option_value("winhl", mappings, { scope = "local", win = win })
	end)
end

---@return nil
M.setup = function()
	local nf = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
	if nf.bg then
		---@type vim.api.keyset.highlight
		local normal_poppy_ui_panel_hl = {
			bg = adjust_brightness(nf.bg, PANELS_BG_LIGHTEN_FACTOR),
			fg = nf.fg,
		}
		vim.api.nvim_set_hl(0, "NormalPoppyUIPanel", normal_poppy_ui_panel_hl)
		---@type vim.api.keyset.highlight
		local normal_poppy_content_hl = { link = "NormalFloat" }
		vim.api.nvim_set_hl(0, "NormalPoppyContent", normal_poppy_content_hl)
	else
		---@type vim.api.keyset.highlight
		local normal_poppy_ui_panel_hl = { link = "NormalFloat" }
		vim.api.nvim_set_hl(0, "NormalPoppyUIPanel", normal_poppy_ui_panel_hl)
		---@type vim.api.keyset.highlight
		local normal_poppy_content_hl = { link = "NormalFloat" }
		vim.api.nvim_set_hl(0, "NormalPoppyContent", normal_poppy_content_hl)
	end
	local panel_hl = vim.api.nvim_get_hl(0, { name = "NormalPoppyUIPanel" })
	local err = vim.api.nvim_get_hl(0, { name = "ErrorMsg" })
	---@type vim.api.keyset.highlight
	local poppy_red_hl = { fg = err.fg, bg = panel_hl.bg }
	vim.api.nvim_set_hl(0, "PoppyRed", poppy_red_hl)

	local str = vim.api.nvim_get_hl(0, { name = "Label" })
	---@type vim.api.keyset.highlight
	local poppy_border_hl = { fg = str.fg, bg = nf.bg }
	vim.api.nvim_set_hl(0, "PoppyBorder", poppy_border_hl)

	local comment = vim.api.nvim_get_hl(0, { name = "Comment" })
	---@type vim.api.keyset.highlight
	local poppy_inactive_hl = { fg = comment.fg, bg = nf.bg }
	vim.api.nvim_set_hl(0, "PoppyInactive", poppy_inactive_hl)
	---@type vim.api.keyset.highlight
	local poppy_active_hl = { link = "IncSearch" }
	vim.api.nvim_set_hl(0, "PoppyActive", poppy_active_hl)

	local type_hl = vim.api.nvim_get_hl(0, { name = "Type" })
	local string_hl = vim.api.nvim_get_hl(0, { name = "String" })
	local func_hl = vim.api.nvim_get_hl(0, { name = "Function" })
	local lnr = vim.api.nvim_get_hl(0, { name = "LineNr" })
	local clnr = vim.api.nvim_get_hl(0, { name = "CursorLineNr" })
	local lnra = vim.api.nvim_get_hl(0, { name = "LineNrAbove" })
	local lnrb = vim.api.nvim_get_hl(0, { name = "LineNrBelow" })

	local CATEGORY = { { "File", type_hl }, { "Exec", string_hl }, { "Shell", func_hl } }

	for _, entry in ipairs(CATEGORY) do
		---@type vim.api.keyset.highlight
		local poppy_cat_hl = { fg = entry[2].fg }
		vim.api.nvim_set_hl(0, "Poppy" .. entry[1], poppy_cat_hl)
	end

	for _, entry in ipairs({
		{ "PoppyLineNr", lnr },
		{ "PoppyCursorLineNr", clnr },
		{ "PoppyLineNrAbove", lnra },
		{ "PoppyLineNrBelow", lnrb },
	}) do
		---@type vim.api.keyset.highlight
		local poppy_lnr_hl = { fg = entry[2].fg, bg = nf.bg }
		vim.api.nvim_set_hl(0, entry[1], poppy_lnr_hl)
	end

	for _, entry in ipairs(CATEGORY) do
		local name, hl = entry[1], entry[2]
		if hl.fg then
			---@type vim.api.keyset.highlight
			local poppy_cat_hidden_hl = {
				fg = adjust_brightness(hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR),
			}
			vim.api.nvim_set_hl(0, "Poppy" .. name .. "Hidden", poppy_cat_hidden_hl)
		else
			---@type vim.api.keyset.highlight
			local poppy_cat_hidden_hl = { link = "Comment" }
			vim.api.nvim_set_hl(0, "Poppy" .. name .. "Hidden", poppy_cat_hidden_hl)
		end
	end

	for _, entry in ipairs(CATEGORY) do
		---@type vim.api.keyset.highlight
		local poppy_cat_current_hl = { fg = entry[2].fg, bold = true }
		vim.api.nvim_set_hl(0, "PoppyCurrentRow" .. entry[1], poppy_cat_current_hl)
	end

	---@type vim.api.keyset.highlight
	local poppy_active_dot_hl = { link = "Normal" }
	vim.api.nvim_set_hl(0, "PoppyActiveDot", poppy_active_dot_hl)

	define_poppy_signs()

	vim.api.nvim_create_augroup("poppy_style", { clear = true })
	---@type vim.api.keyset.create_autocmd
	local colorscheme_autocmd = {
		group = "poppy_style",
		callback = function()
			M.setup()
		end,
	}
	vim.api.nvim_create_autocmd("ColorScheme", colorscheme_autocmd)
end

---@param win integer
---@return nil
M.apply_hints_panel_style = function(win)
	set_winhl_deferred(win, "Normal:NormalPoppyUIPanel")
end

---@param win integer
---@return nil
M.apply_list_panel_style = function(win)
	set_winhl_deferred(win, "Normal:NormalPoppyUIPanel,SignColumn:NormalPoppyUIPanel")
end

---@param win integer
---@param ext_number boolean
---@param ext_relativenumber boolean
---@return nil
M.apply_content_style = function(win, ext_number, ext_relativenumber)
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		---@type vim.api.keyset.set_option_value
		local winhl_opts = { scope = "local", win = win }
		vim.api.nvim_set_option_value(
			"winhl",
			"Normal:NormalPoppyContent,SignColumn:NormalPoppyContent,LineNr:PoppyLineNr,LineNrAbove:PoppyLineNrAbove,LineNrBelow:PoppyLineNrBelow,CursorLineNr:PoppyCursorLineNr",
			winhl_opts
		)

		local buf = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "terminal" then
			return
		end
		---@type vim.api.keyset.set_option_value
		local win_opts = { win = win }
		vim.api.nvim_set_option_value("cursorline", true, win_opts)
		vim.api.nvim_set_option_value("signcolumn", "yes", win_opts)
		vim.api.nvim_set_option_value("number", ext_number, win_opts)
		vim.api.nvim_set_option_value("relativenumber", ext_relativenumber, win_opts)
	end)
end

---@param win integer
---@return nil
M.apply_border_style = function(win)
	set_winhl_deferred(win, "FloatBorder:PoppyBorder")
end

return M
