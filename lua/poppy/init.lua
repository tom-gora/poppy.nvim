local M = {}

local config = require("poppy.config")
local state = require("poppy.shared.state")
local executor = require("poppy.executor")
local term = require("poppy.term")
local float = require("poppy.float")

---@type PoppyConfig?
local opts = nil

local is_nested = function()
	-- Check for nested Nvim
	if os.getenv("NVIM") then
		return true
	end
	return false
end

M.get_state = function()
	return state
end

local validate_ipc = function(data)
	return type(data) == "table" and type(data.action) == "string" and type(data.popup) == "string"
end

M._sync_state = function(raw_popup_name, action)
	-- Strip the 'poppy_' prefix if it exists
	local popup_name = raw_popup_name:gsub("^poppy_", "")

	if action == "hide" then
		-- Defensive check: only update if popup is registered
		if state.popups[popup_name] then
			state.popups[popup_name].active = false
			state.popups[popup_name].hidden = true
		end
	elseif action == "close" then
		state.popups[popup_name] = nil
	end
	vim.cmd("redrawstatus")
end

---@param popup_name string
local open_popup = function(popup_name)
	if is_nested() then
		return
	end

	if not opts then
		print("Poppy: Not initialized. Call setup() first.")
		return
	end

	-- Deactivate current active popup
	for name, p_state in pairs(state.popups) do
		if p_state.active then
			local is_term = executor.is_executable(opts.popups[name].exec)
			if is_term then
				term.hide_session(name)
			else
				float.hide_session(name)
			end
			p_state.active = false
			p_state.hidden = true
			vim.cmd("redrawstatus")
		end
	end

	local is_term = executor.is_executable(opts.popups[popup_name].exec)
	if is_term then
		term.run(popup_name, opts)
	else
		float.run(popup_name, opts)
	end

	if not state.popups[popup_name] then
		state.popups[popup_name] = { active = true, hidden = false }
	else
		state.popups[popup_name].active = true
		state.popups[popup_name].hidden = false
	end
	vim.cmd("redrawstatus")
end

---@param user_opts? PoppyConfig
M.setup = function(user_opts)
	if is_nested() then
		return
	end

	opts = config.merge(user_opts)

	-- Ensure state directory exists
	if vim.fn.isdirectory(state.STATE_DIR) == 0 then
		vim.fn.mkdir(state.STATE_DIR, "p")
	end

	-- Ensure state file exists for watcher
	local f = io.open(state.STATE_FILE, "a")
	if f then
		f:close()
	end

	-- File watcher for IPC
	local handle = vim.loop.new_fs_event()
	if not handle then
		return
	end
	handle:start(
		state.STATE_FILE,
		{},
		vim.schedule_wrap(function(err, _, _)
			if err then
				return
			end
			local file_handle = io.open(state.STATE_FILE, "r")
			if file_handle then
				local content = file_handle:read("*a")
				file_handle:close()

				local success, data = pcall(vim.json.decode, content)
				if success and validate_ipc(data) then
					M._sync_state(data.popup, data.action)
				else
					vim.notify("Poppy: Received malformed IPC data, ignoring update.", vim.log.levels.WARN)
				end
			end
		end)
	)

	vim.api.nvim_create_user_command("Poppy", function(cmd_opts)
		local popup_name = cmd_opts.args
		if popup_name == "" then
			print("Poppy: Please specify a popup name.")
			return
		end
		open_popup(popup_name)
	end, {
		nargs = 1,
		complete = function(_, _, _)
			local keys = {}
			if opts and opts.popups then
				for k, _ in pairs(opts.popups) do
					table.insert(keys, k)
				end
			end
			return keys
		end,
	})

	vim.api.nvim_create_user_command("PoppyClose", function(cmd_opts)
		local popup_name = cmd_opts.args
		if executor.is_executable(opts.popups[popup_name].exec) then
			term.close_session(popup_name)
		else
			float.close_session(popup_name)
		end
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("PoppyHide", function(cmd_opts)
		local popup_name = cmd_opts.args
		if executor.is_executable(opts.popups[popup_name].exec) then
			term.hide_session(popup_name)
		else
			float.hide_session(popup_name)
		end
	end, { nargs = 1 })

	vim.api.nvim_create_autocmd({ "WinLeave" }, {
		callback = function()
			local win = vim.api.nvim_get_current_win()
			local success, popup_name = pcall(vim.api.nvim_win_get_var, win, "poppy_win")
			if success and popup_name then
				if executor.is_executable(opts.popups[popup_name].exec) then
					term.hide_session(popup_name)
				else
					float.hide_session(popup_name)
				end
			end
		end,
	})
end

return M
