local M = {}

---@param hl_group string
---@param force_bg_from_normal boolean
---@return string
M.get_tmux_style_format = function(hl_group, force_bg_from_normal)
	local hl = vim.api.nvim_get_hl(0, { name = hl_group, link = true })

	if force_bg_from_normal then
		local normal_hl = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = true })
		if normal_hl and normal_hl.bg then
			hl.fg = normal_hl.bg
			hl.bg = normal_hl.bg
		end
	end

	local parts = {}
	if hl.fg then
		table.insert(parts, string.format("fg=#%06x", hl.fg))
	end
	if hl.bg then
		table.insert(parts, string.format("bg=#%06x", hl.bg))
	end

	if #parts == 0 then
		return ""
	end

	return table.concat(parts, ",")
end

---@param popup_opts PoppyPopupConfig
---@param opts PoppyConfig
---@return string[]
M.prepare_popup_styles = function(popup_opts, opts)
	local args = {}

	local border = popup_opts.border or opts.border

	if border == "none" then
		table.insert(args, "-B")
	else
		-- border type (characters)
		table.insert(args, "-b")
		table.insert(args, (border == "solid" and "rounded") or border)

		-- border style (colors)
		local border_style = M.get_tmux_style_format("FloatBorder", border == "solid")
		if border_style ~= "" then
			table.insert(args, "-S")
			table.insert(args, border_style)
		end
	end

	-- popup content style
	local normal_style = M.get_tmux_style_format("NormalFloat", false)
	if normal_style ~= "" then
		table.insert(args, "-s")
		table.insert(args, normal_style)
	end

	return args
end

return M
