local M = {}

local PANELS_BG_LIGHTEN_FACTOR = 0.04
local HIDDEN_LIST_ITEM_DARKEN_FACTOR = -0.4

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
	for _, s in ipairs(signs) do
		pcall(vim.fn.sign_define, s.name, { text = s.text, texthl = s.hl })
	end
end

-- Validate-inside-schedule so we don't schedule work that would
-- no-op anyway. All panel/window winhl assignments use this.
local set_winhl_deferred = function(win, mappings)
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		vim.api.nvim_set_option_value("winhl", mappings, { scope = "local", win = win })
	end)
end

M.setup = function()
	local nf = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
	if nf.bg then
		vim.api.nvim_set_hl(
			0,
			"NormalPoppyUIPanel",
			{ bg = adjust_brightness(nf.bg, PANELS_BG_LIGHTEN_FACTOR), fg = nf.fg }
		)
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

	local CATEGORY = { { "File", type_hl }, { "Exec", string_hl }, { "Shell", func_hl } }

	for _, entry in ipairs(CATEGORY) do
		vim.api.nvim_set_hl(0, "Poppy" .. entry[1], { fg = entry[2].fg })
	end

	for _, entry in ipairs({
		{ "PoppyLineNr",       lnr },
		{ "PoppyCursorLineNr", clnr },
		{ "PoppyLineNrAbove",  lnra },
		{ "PoppyLineNrBelow",  lnrb },
	}) do
		vim.api.nvim_set_hl(0, entry[1], { fg = entry[2].fg, bg = nf.bg })
	end

	for _, entry in ipairs(CATEGORY) do
		local name, hl = entry[1], entry[2]
		if hl.fg then
			vim.api.nvim_set_hl(0, "Poppy" .. name .. "Hidden", {
				fg = adjust_brightness(hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR),
				bold = true,
			})
		else
			vim.api.nvim_set_hl(0, "Poppy" .. name .. "Hidden", { link = "Comment", bold = true })
		end
	end

	for _, entry in ipairs(CATEGORY) do
		vim.api.nvim_set_hl(0, "PoppyCurrentRow" .. entry[1], { bg = entry[2].fg, fg = nf.bg })
	end

	vim.api.nvim_set_hl(0, "PoppyActiveDot", { link = "Normal" })

	define_poppy_signs()

	vim.api.nvim_create_augroup("poppy_style", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = "poppy_style",
		callback = function()
			M.setup()
		end,
	})
end

M.apply_hints_panel_style = function(win)
	set_winhl_deferred(win, "Normal:NormalPoppyUIPanel")
end

M.apply_list_panel_style = function(win)
	set_winhl_deferred(win, "Normal:NormalPoppyUIPanel,SignColumn:NormalPoppyUIPanel")
end

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
		vim.api.nvim_set_option_value("cursorline", true, { win = win })
		vim.api.nvim_set_option_value("signcolumn", "yes", { win = win })
		vim.api.nvim_set_option_value("number", ext_number, { win = win })
		vim.api.nvim_set_option_value("relativenumber", ext_relativenumber, { win = win })
	end)
end

M.apply_border_style = function(win)
	set_winhl_deferred(win, "FloatBorder:PoppyBorder")
end

return M
