require("poppy._types")

local M = {}

local PANELS_BG_LIGHTEN_FACTOR = 0.03
local HIDDEN_LIST_ITEM_DARKEN_FACTOR = -0.4
-- 0 = full cat color, 1 = full Normal fg. Tuned so cat peeks through but row reads as "almost normal".
local NORMAL_LIST_ITEM_TINT_FACTOR = 0.7

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

---@param color integer
---@param target integer
---@param factor number
---@return integer
local blend_towards = function(color, target, factor)
	local r1 = math.floor(color / 65536)
	local g1 = math.floor((color % 65536) / 256)
	local b1 = color % 256
	local r2 = math.floor(target / 65536)
	local g2 = math.floor((target % 65536) / 256)
	local b2 = target % 256
	local r = math.max(0, math.min(255, math.floor(r1 + (r2 - r1) * factor)))
	local g = math.max(0, math.min(255, math.floor(g1 + (g2 - g1) * factor)))
	local b = math.max(0, math.min(255, math.floor(b1 + (b2 - b1) * factor)))
	return r * 65536 + g * 256 + b
end

-- pcall so an unrecognized hl in a misconfigured theme doesn't abort. Re-run on every setup so signs track the just-set groups.
local define_poppy_signs = function()
	local signs = {
		{ name = "PoppyDotFileA", text = "•", texthl = "PoppyFile" },
		{ name = "PoppyDotFileH", text = "•", texthl = "PoppyFileHidden" },
		{ name = "PoppyDotExecA", text = "•", texthl = "PoppyExec" },
		{ name = "PoppyDotExecH", text = "•", texthl = "PoppyExecHidden" },
		{ name = "PoppyDotShellA", text = "•", texthl = "PoppyShell" },
		{ name = "PoppyDotShellH", text = "•", texthl = "PoppyShellHidden" },
		{ name = "PoppyDotCurrentFile", text = "•", texthl = "PoppyCurrentRowFile" },
		{ name = "PoppyDotCurrentExec", text = "•", texthl = "PoppyCurrentRowExec" },
		{ name = "PoppyDotCurrentShell", text = "•", texthl = "PoppyCurrentRowShell" },
		{ name = "PoppyDotNone", text = " ", texthl = "NormalPoppyUIPanel" },
	}
	for _, s in ipairs(signs) do
		pcall(vim.fn.sign_define, s.name, s)
	end
end

---@param icons? PoppyIcons
---@return void
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

---@param win integer
---@param mappings string
local set_winhl_deferred = function(win, mappings)
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		vim.api.nvim_set_option_value("winhl", mappings, { scope = "local", win = win })
	end)
end

---@return void
M.setup = function()
	local nf = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
	if nf.bg then
		vim.api.nvim_set_hl(0, "NormalPoppyUIPanel", {
			bg = adjust_brightness(nf.bg, PANELS_BG_LIGHTEN_FACTOR),
			fg = nf.fg,
		})
		vim.api.nvim_set_hl(0, "NormalPoppyContent", { link = "NormalFloat" })
	else
		vim.api.nvim_set_hl(0, "NormalPoppyUIPanel", { link = "NormalFloat" })
		vim.api.nvim_set_hl(0, "NormalPoppyContent", { link = "NormalFloat" })
	end
	local panel_hl = vim.api.nvim_get_hl(0, { name = "NormalPoppyUIPanel" })
	local err = vim.api.nvim_get_hl(0, { name = "ErrorMsg" })
	vim.api.nvim_set_hl(0, "PoppyRed", { fg = err.fg, bg = panel_hl.bg })

	local str = vim.api.nvim_get_hl(0, { name = "Label" })
	vim.api.nvim_set_hl(0, "PoppyBorder", { fg = str.fg, bg = nf.bg })

	local comment = vim.api.nvim_get_hl(0, { name = "Comment" })
	vim.api.nvim_set_hl(0, "PoppyInactive", { fg = comment.fg, bg = nf.bg })
	vim.api.nvim_set_hl(0, "PoppyActive", { link = "IncSearch" })

	local type_hl = vim.api.nvim_get_hl(0, { name = "Type" })
	local string_hl = vim.api.nvim_get_hl(0, { name = "String" })
	local func_hl = vim.api.nvim_get_hl(0, { name = "Function" })
	local lnr = vim.api.nvim_get_hl(0, { name = "LineNr" })
	local clnr = vim.api.nvim_get_hl(0, { name = "CursorLineNr" })
	local lnra = vim.api.nvim_get_hl(0, { name = "LineNrAbove" })
	local lnrb = vim.api.nvim_get_hl(0, { name = "LineNrBelow" })

	-- White fallback defends against transparent Normals.
	local n = vim.api.nvim_get_hl(0, { name = "Normal" })
	local n_fg = n.fg or 0xFFFFFF

	local CATEGORY = { { "File", type_hl }, { "Exec", string_hl }, { "Shell", func_hl } }

	for _, entry in ipairs(CATEGORY) do
		local fg = entry[2].fg and blend_towards(entry[2].fg, n_fg, NORMAL_LIST_ITEM_TINT_FACTOR) or n_fg
		vim.api.nvim_set_hl(0, "Poppy" .. entry[1], { fg = fg })
	end

	for _, entry in ipairs({
		{ "PoppyLineNr", lnr },
		{ "PoppyCursorLineNr", clnr },
		{ "PoppyLineNrAbove", lnra },
		{ "PoppyLineNrBelow", lnrb },
	}) do
		vim.api.nvim_set_hl(0, entry[1], { fg = entry[2].fg, bg = nf.bg })
	end

	for _, entry in ipairs(CATEGORY) do
		local name, hl = entry[1], entry[2]
		if hl.fg then
			vim.api.nvim_set_hl(0, "Poppy" .. name .. "Hidden", {
				fg = adjust_brightness(hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR),
			})
		else
			vim.api.nvim_set_hl(0, "Poppy" .. name .. "Hidden", { link = "Comment" })
		end
	end

	for _, entry in ipairs(CATEGORY) do
		vim.api.nvim_set_hl(0, "PoppyCurrentRow" .. entry[1], { fg = entry[2].fg, bold = true })
	end

	vim.api.nvim_set_hl(0, "PoppyActiveDot", { link = "Normal" })

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
M.apply_hints_panel_style = function(win)
	set_winhl_deferred(win, "Normal:NormalPoppyUIPanel")
end

---@param win integer
M.apply_panel_style = function(win)
	set_winhl_deferred(win, "Normal:NormalPoppyUIPanel,SignColumn:NormalPoppyUIPanel")
end

---@param win integer
---@param ext_number boolean
---@param ext_relativenumber boolean
M.apply_content_style = function(win, ext_number, ext_relativenumber)
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		vim.api.nvim_set_option_value(
			"winhl",
			"Normal:NormalPoppyContent,SignColumn:NormalPoppyContent,LineNr:PoppyLineNr,LineNrAbove:PoppyLineNrAbove,LineNrBelow:PoppyLineNrBelow,CursorLineNr:PoppyCursorLineNr",
			{ scope = "local", win = win }
		)

		local buf = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "terminal" then
			return
		end
		local win_opts = { win = win }
		vim.api.nvim_set_option_value("cursorline", true, win_opts)
		vim.api.nvim_set_option_value("signcolumn", "yes", win_opts)
		vim.api.nvim_set_option_value("number", ext_number, win_opts)
		vim.api.nvim_set_option_value("relativenumber", ext_relativenumber, win_opts)
	end)
end

---@param win integer
M.apply_border_style = function(win)
	set_winhl_deferred(win, "FloatBorder:PoppyBorder")
end

return M
