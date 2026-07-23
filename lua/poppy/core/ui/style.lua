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

-- Sign definitions. Defined at module scope (above M.setup) so the
-- M.setup closure can call it. `pcall` wraps each `sign_define` so a
-- misconfigured theme (an unrecognized highlight group name) doesn't
-- abort the plugin. The signs are re-defined on every call to M.setup
-- (initial setup + every ColorScheme event), so sign text colors stay
-- in sync with the just-redefined highlight groups.
local function define_poppy_signs()
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

	vim.api.nvim_set_hl(0, "PoppyFile", { fg = type_hl.fg })
	vim.api.nvim_set_hl(0, "PoppyExec", { fg = string_hl.fg })
	vim.api.nvim_set_hl(0, "PoppyShell", { fg = func_hl.fg })

	if type_hl.fg then
		vim.api.nvim_set_hl(
			0,
			"PoppyFileHidden",
			{ fg = adjust_brightness(type_hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR), bold = true }
		)
	else
		vim.api.nvim_set_hl(0, "PoppyFileHidden", { link = "Comment", bold = true })
	end
	if string_hl.fg then
		vim.api.nvim_set_hl(
			0,
			"PoppyExecHidden",
			{ fg = adjust_brightness(string_hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR), bold = true }
		)
	else
		vim.api.nvim_set_hl(0, "PoppyExecHidden", { link = "Comment", bold = true })
	end
	if func_hl.fg then
		vim.api.nvim_set_hl(
			0,
			"PoppyShellHidden",
			{ fg = adjust_brightness(func_hl.fg, HIDDEN_LIST_ITEM_DARKEN_FACTOR), bold = true }
		)
	else
		vim.api.nvim_set_hl(0, "PoppyShellHidden", { link = "Comment", bold = true })
	end

	vim.api.nvim_set_hl(0, "PoppyCurrentRowFile", { bg = type_hl.fg, fg = nf.bg })
	vim.api.nvim_set_hl(0, "PoppyCurrentRowExec", { bg = string_hl.fg, fg = nf.bg })
	vim.api.nvim_set_hl(0, "PoppyCurrentRowShell", { bg = func_hl.fg, fg = nf.bg })

	vim.api.nvim_set_hl(0, "PoppyActiveDot", { link = "Normal" })

	-- Re-define signs so they pick up the just-set highlight groups.
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
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		vim.api.nvim_set_option_value("winhl", "Normal:NormalPoppyUIPanel", { scope = "local", win = win })
	end)
end

M.apply_list_panel_style = function(win)
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		vim.api.nvim_set_option_value(
			"winhl",
			"Normal:NormalPoppyUIPanel,SignColumn:NormalPoppyUIPanel",
			{ scope = "local", win = win }
		)
	end)
end

M.apply_content_style = function(win, ext_config_opts)
	vim.schedule(function()
		vim.api.nvim_set_option_value(
			"winhl",
			"Normal:NormalPoppyContent,SignColumn:NormalPoppyContent",
			{ scope = "local", win = win }
		)

		vim.api.nvim_set_option_value("signcolumn", "yes", { win = win })
		vim.api.nvim_set_option_value("number", ext_config_opts.number, { win = win })
		vim.api.nvim_set_option_value("relativenumber", ext_config_opts.relativenumber, { win = win })
	end)
end

M.apply_border_style = function(win)
	vim.schedule(function()
		vim.api.nvim_set_option_value("winhl", "FloatBorder:PoppyBorder", { scope = "local", win = win })
	end)
end

return M
