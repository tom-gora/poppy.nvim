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
---@field exec string|string[]
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

---@param val any
---@param min number
---@param max number
---@param default number
---@param key string
---@return number
local clamp = function(val, min, max, default, key)
	if val == nil then
		return default
	end
	if type(val) ~= "number" or val < min or val > max then
		vim.notify(
			"Poppy: Invalid "
				.. key
				.. " value '"
				.. tostring(val)
				.. "'. Falling back to default: "
				.. tostring(default),
			vim.log.levels.WARN
		)
		return default
	end
	return val
end

---@param exec string|string[]|function
---@return boolean
local check_exec = function(exec)
	if type(exec) == "function" then
		return true
	end
	local cmd
	if type(exec) == "table" then
		cmd = exec[1]
	else
		cmd = vim.split(exec, " ")[1]
	end
	local expanded = vim.fn.expand(cmd)
	return vim.fn.executable(cmd) == 1 or vim.fn.filereadable(expanded) == 1
end

---@param opts PoppyConfig
---@return PoppyConfig
local sanitize = function(opts)
	opts.width = clamp(opts.width, 0.2, 1.0, default_opts.width, "width")
	opts.height = clamp(opts.height, 0.2, 1.0, default_opts.height, "height")

	if opts.popups then
		for name, popup in pairs(opts.popups) do
			-- Check if exec is valid
			if not check_exec(popup.exec) then
				vim.notify(
					"Poppy: Popup '" .. name .. "' exec '" .. tostring(popup.exec) .. "' is not executable. Ignoring.",
					vim.log.levels.ERROR
				)
				opts.popups[name] = nil
			else
				popup.width = clamp(popup.width, 0.2, 1.0, opts.width, name .. ".width")
				popup.height = clamp(popup.height, 0.2, 1.0, opts.height, name .. ".height")
			end
		end
	end
	return opts
end

---@param user_opts? PoppyConfig
---@return PoppyConfig
M.merge = function(user_opts)
	local opts = vim.tbl_deep_extend("force", default_opts, user_opts or {})
	return sanitize(opts)
end

return M
