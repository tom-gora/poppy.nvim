---@diagnostic disable: duplicate-doc-field
---@class PoppyConfig
---@field width? number # Popup width as a ratio of terminal width (0.2 - 1.0). Default: 0.8
---@field height? number # Popup height as a ratio of terminal height (0.2 - 1.0). Default: 0.8
---@field position? "center"|"left"|"right" # Popup position. Default: "center"
---@field border? "rounded"|"single"|"double"|"solid"|"none" # Border style. Default: "rounded"
---@field title? string # Popup title. Default: ""
---@field align_on_border? "left"|"center"|"right" # Title/Footer alignment. Default: "center"
---@field close_keymap? string # Keymap to close the popup. Default: "<C-q>"
---@field hide_keymap? string # Keymap to hide the popup. Default: "<C-d>"
---@field popups? table<string, PoppyPopupConfig>
---
---@class PoppyPopupConfig
---@field exec? string|string[]
---@field file? string
---@field shell? boolean
---@field width? number
---@field height? number
---@field position? "left" | "right" | "center"
---@field border? string
---@field hide_keymap? string # Default hide keymap. Default: "<C-d>"
---@field close_keymap? string # Default close keymap. Default: "<C-q>"
---@field title? string
---@field align_on_border? "left" | "center" | "right"
---
local default_opts = {
	width = 0.8,
	height = 0.8,
	position = "center",
	border = "rounded",
	close_keymap = "<C-q>",
	hide_keymap = "<C-d>",
	title = "",
	align_on_border = "center",
}

local M = {}

local clamp = function(val, min, max, default, key)
	if val == nil then return default end
	if type(val) ~= "number" or val < min or val > max then
		vim.notify("Poppy: Invalid " .. key .. " value '" .. tostring(val) .. "'. Falling back to default: " .. tostring(default), vim.log.levels.WARN)
		return default
	end
	return val
end

local sanitize = function(opts)
	opts.width = clamp(opts.width, 0.2, 1.0, default_opts.width, "width")
	opts.height = clamp(opts.height, 0.2, 1.0, default_opts.height, "height")

	if opts.popups then
		for name, popup in pairs(opts.popups) do
			local modes = 0
			if popup.exec then modes = modes + 1; popup.mode = "exec" end
			if popup.file then modes = modes + 1; popup.mode = "file" end
			if popup.shell then modes = modes + 1; popup.mode = "shell" end

			if modes ~= 1 then
				vim.notify("Poppy: Popup '" .. name .. "' must have exactly one of 'exec', 'file', or 'shell'.", vim.log.levels.ERROR)
				opts.popups[name] = nil
			else
				-- Add title fallback
				if not popup.title then
					popup.title = require("poppy.modes.utils").title_fallback(popup.mode, popup.exec or popup.file or "shell")
				end
				popup.width = clamp(popup.width, 0.2, 1.0, opts.width, name .. ".width")
				popup.height = clamp(popup.height, 0.2, 1.0, opts.height, name .. ".height")
			end
		end
	end
	return opts
end

M.merge = function(user_opts)
	local opts = vim.tbl_deep_extend("force", default_opts, user_opts or {})
	return sanitize(opts)
end

return M
