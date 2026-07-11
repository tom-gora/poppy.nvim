---@class PoppyConfig
---@field keys? table<string, string> # Keybindings: poppy_action, select, kill, dismiss_menu. Default: { poppy_action = "<C-_>", select = "<CR>", kill = "d", dismiss_menu = "<Esc>" }
---@field icons? table<string, string> # Icons per poppy type: exec, shell, file. Default: { exec = "🛠", shell = "$", file = "🗋" }
---@field menu_autohide? boolean # If true, hide sidebar after selecting a poppy. Default: false
---@field title_header? boolean # Show "POPPY" header panel above list. Default: true
---@field sidebar_width? number # Width of side panels. Default: 25
---@field win_height? number|function # Height ratio of screen (0.2-1.0), or absolute pixels (>1), or function returning same. Default: 0.75
---@field win_width? number|function # Width ratio of screen (0.2-1.0), or absolute pixels (>1), or function returning same. Default: 0.8
---@field win_location? "center"|"top"|"bottom" # Vertical position of the wrapper. Default: "center"
---@field poppies? table<string, PoppyItemConfig>
---
---@class PoppyItemConfig
---@field exec? string|string[]
---@field file? string
---@field shell? string|function
---@field title? string
---
local default_opts = {
	keys = { poppy_action = "<C-_>", select = "<CR>", kill = "d", dismiss_menu = "<Esc>" },
	icons = { exec = "🛠", shell = "$", file = "🗋" },
	menu_autohide = false,
	title_header = true,
	sidebar_width = 25,
	win_height = 0.75,
	win_width = 0.8,
	win_location = "center",
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

local sanitize_win_width = function(val)
	if val == nil then
		return 0.8
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
	return 0.8
end

local sanitize = function(opts)
	opts.win_height = sanitize_win_height(opts.win_height)
	opts.win_width = sanitize_win_width(opts.win_width)

	local valid_locations = { center = true, top = true, bottom = true }
	if not valid_locations[opts.win_location] then
		vim.notify(
			"Poppy: Invalid win_location '" .. tostring(opts.win_location) .. "'. Falling back to 'center'.",
			vim.log.levels.WARN
		)
		opts.win_location = default_opts.win_location
	end

	if not opts.keys or type(opts.keys) ~= "table" then
		opts.keys = default_opts.keys
	else
		for _, k in ipairs({ "poppy_action", "select", "kill", "dismiss_menu" }) do
			if type(opts.keys[k]) ~= "string" or opts.keys[k] == "" then
				opts.keys[k] = default_opts.keys[k]
			end
		end
	end

	if not opts.icons or type(opts.icons) ~= "table" then
		opts.icons = default_opts.icons
	else
		for _, k in ipairs({ "exec", "shell", "file" }) do
			if type(opts.icons[k]) ~= "string" then
				opts.icons[k] = default_opts.icons[k]
			end
		end
	end

	if opts.menu_autohide ~= true then
		opts.menu_autohide = false
	end

	if opts.title_header ~= false then
		opts.title_header = true
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