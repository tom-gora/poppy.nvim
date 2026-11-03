local M = {}

local api = vim.api
local fn = vim.fn
local uv = vim.uv or vim.loop

local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

---@type table<string, uv.fs_event_t>
M._watchers = {}

---Names whose files vanished while the editor was unfocused; drained on the next FocusGained.
---@type string[]
M._pending_notifications = {}

local FOCUS_GROUP = "poppy_watch_focus"
local REPLAY_GROUP = "poppy_watch_replay"
local replay_armed = false

local drop_buffer = function(name)
	local rt = state.runtime(name)
	if not (rt and rt.bufnr and api.nvim_buf_is_valid(rt.bufnr)) then
		return
	end
	pcall(api.nvim_buf_delete, rt.bufnr, { force = true })
end

local drain = function()
	if #M._pending_notifications == 0 then
		replay_armed = false
		return
	end
	local names = table.concat(M._pending_notifications, ", ")
	M._pending_notifications = {}
	replay_armed = false
	shared.notify_warn("poppy file(s) removed externally: %s", names)
end

local setup_replay = function()
	if replay_armed then
		return
	end
	replay_armed = true
	api.nvim_create_augroup(REPLAY_GROUP, { clear = true })
	api.nvim_create_autocmd("FocusGained", {
		group = REPLAY_GROUP,
		once = true,
		callback = drain,
	})
end

local handle_vanished = function(name, path)
	if not state.poppy_configured(name) then
		return
	end
	drop_buffer(name)
	local was_active = shared.drop_poppy(name, nil)
	if state.windows.editor_focused then
		shared.notify_warn("poppy '%s' dropped: file removed externally", name)
	else
		table.insert(M._pending_notifications, name)
		setup_replay()
	end
	if was_active and shared.session_is_open() then
		require("poppy.core.session.manager").recover()
	end
end

local handle_changed = function(name, path)
	local rt = state.runtime(name)
	if not (rt and rt.bufnr and api.nvim_buf_is_valid(rt.bufnr)) then
		return
	end
	if vim.bo[rt.bufnr].modified then
		return
	end
	local ok, lines = pcall(fn.readfile, path)
	if ok then
		pcall(api.nvim_buf_set_lines, rt.bufnr, 0, -1, false, lines)
		api.nvim_set_option_value("modified", false, { buf = rt.bufnr })
	end
end

local on_event = function(name, path)
	return function(err, filename, events)
		if err then
			return
		end
		vim.schedule(function()
			if not state.poppy_configured(name) then
				return
			end
			local basename = vim.fs.basename(path)
			if filename ~= basename then
				return
			end
			local ev = events or {}
			local renamed = ev.rename == true
			if renamed and fn.filereadable(path) ~= 1 then
				handle_vanished(name, path)
			elseif ev.change == true or renamed then
				handle_changed(name, path)
			end
		end)
	end
end

---@param name string
---@param path string Absolute path.
---@return boolean ok
M.add = function(name, path)
	if M._watchers[name] then
		return true
	end
	local dir = vim.fs.dirname(path)
	if dir == "" or fn.isdirectory(dir) ~= 1 then
		return false
	end
	local watcher, werr = uv.new_fs_event()
	if not watcher then
		return false
	end
	watcher:start(dir, {}, vim.schedule_wrap(on_event(name, path)))
	if werr then
		watcher:stop()
		watcher:close()
		return false
	end
	M._watchers[name] = watcher
	return true
end

---@param name string
---@return nil
M.remove = function(name)
	local w = M._watchers[name]
	if w then
		pcall(function()
			w:stop()
		end)
		pcall(function()
			w:close()
		end)
		M._watchers[name] = nil
	end
end

---Stop and close every watcher. Called on re-setup and VimLeavePre.
---@return nil
M.close_all = function()
	for name, _ in pairs(M._watchers) do
		M.remove(name)
	end
	M._pending_notifications = {}
	replay_armed = false
end

---Long-lived focus tracking. Sets `state.windows.editor_focused` and clears it on
---re-setup via the augroup's `clear = true`. Lives for the whole session.
---@return nil
M.setup_focus_tracking = function()
	state.windows.editor_focused = true
	api.nvim_create_augroup(FOCUS_GROUP, { clear = true })
	api.nvim_create_autocmd("FocusLost", {
		group = FOCUS_GROUP,
		callback = function()
			state.windows.editor_focused = false
		end,
	})
	api.nvim_create_autocmd("FocusGained", {
		group = FOCUS_GROUP,
		callback = function()
			state.windows.editor_focused = true
		end,
	})
end

return M
