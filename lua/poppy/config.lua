---@class PoppyConfig
---@field prefix_bind? string # Prefix for all poppy keybinds. Default: "<M-p>"
---@field sidebar_width? number # Width of side panels. Default: 25
---@field win_height? number|function # Height ratio of screen (0.2-1.0), or function returning same. Default: 0.75
---@field win_location? "center"|"top"|"bottom" # Vertical position of the wrapper. Default: "center"
---@field whichkey_disable? boolean # If true, set desc to "which_key_ignore". Default: false
---@field poppies? table<string, PoppyItemConfig>
---
---@class PoppyItemConfig
---@field exec? string|string[]
---@field file? string
---@field shell? string|function
---@field title? string
---
local default_opts = {
	prefix_bind = "<M-p>",
	sidebar_width = 25,
	win_height = 0.75,
	win_location = "center",
	whichkey_disable = false,
}

local M = {}

local sanitize_win_height = function(val)
	if val == nil then
		return 0.75
	end
	if type(val) == "function" then
		return val
	end
	if type(val) == "number" then
		if val > 1 then
			return val
		end
		return math.min(math.max(val, 0.2), 1.0)
	end
	return 0.75
end

local sanitize = function(opts)
	opts.win_height = sanitize_win_height(opts.win_height)

	local valid_locations = { center = true, top = true, bottom = true }
	if not valid_locations[opts.win_location] then
		vim.notify(
			"Poppy: Invalid win_location '" .. tostring(opts.win_location) .. "'. Falling back to 'center'.",
			vim.log.levels.WARN
		)
		opts.win_location = default_opts.win_location
	end

	if opts.poppies then
		for name, poppy in pairs(opts.poppies) do
			local modes = 0
			if poppy.exec then
				modes = modes + 1
				poppy.mode = "term"
				poppy.cat = "exec"
			end
			if poppy.file then
				modes = modes + 1
				poppy.mode = "file"
				poppy.cat = "file"
			end
			if poppy.shell then
				modes = modes + 1
				poppy.mode = "term"
				poppy.cat = "shell"
			end

			if modes ~= 1 then
				vim.notify(
					"Poppy: Poppy '" .. name .. "' must have exactly one of 'exec', 'file', or 'shell'.",
					vim.log.levels.ERROR
				)
				opts.poppies[name] = nil
			else
				if not poppy.title then
					poppy.title = require("poppy.modes.utils").title_fallback(
						poppy.mode,
						poppy.exec or poppy.file or poppy.shell or os.getenv("SHELL") or "shell"
					)
				end
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

