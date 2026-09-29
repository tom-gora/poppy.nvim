require("poppy._types")

local M = {}
local api = vim.api
local fn = vim.fn
local state = require("poppy.core.session.state")
local shared = require("poppy.core.shared")

---@param poppy_name string
---@return integer|nil bufnr
---@return boolean reused
local term_get_or_create_buffer = function(poppy_name)
	local rt = state.runtime(poppy_name)
	if rt and rt.hidden and rt.bufnr and api.nvim_buf_is_valid(rt.bufnr) then
		return rt.bufnr, true
	end
	local bufnr = api.nvim_create_buf(false, false)
	pcall(api.nvim_buf_set_name, bufnr, " Poppy: " .. poppy_name .. " ")
	return bufnr, false
end

---@param poppy_opts PoppyResolvedConfig
-- Defense-in-depth: setup already validated this. Re-evaluates the function
-- only if the cached value is a function (e.g. someone mutated state manually).
-- Returns nil when the resolved value is unusable; the caller drops the poppy.
---@return string|string[]|nil
local term_resolve_command = function(poppy_opts)
	local raw
	if poppy_opts.shell ~= nil then
		raw = poppy_opts.shell
	else
		raw = poppy_opts.exec
	end
	if type(raw) == "function" then
		local ok, result = pcall(raw)
		if not ok then
			return nil
		end
		raw = result
	end
	if raw == nil or raw == "" then
		return nil
	end
	if poppy_opts.shell ~= nil and raw == "default" then
		return os.getenv("SHELL") or "bash"
	end
	return raw
end

---Returns the argv[0] of a command (string or table form) for executable() lookup.
---@param command string|string[]|function|nil
---@return string|nil
local argv0 = function(command)
	if type(command) == "string" then
		return (command:gsub("%s.*", "")) -- first whitespace-delimited token
	elseif type(command) == "table" and #command > 0 and type(command[1]) == "string" then
		return command[1]
	end
	return nil
end

---@param command string|string[]|function|nil
---@param opts table
---@return integer|nil job_id
---@return boolean ok  false when jobstart refused; command was resolvable but failed to spawn
local term_spawn = function(command, opts)
	if type(command) == "function" then
		command = command()
	end
	if not command then
		return nil, false
	end
	if fn.has("nvim-0.11") == 1 then
		opts.term = true
		return fn.jobstart(command, opts), true
	else
		---@diagnostic disable-next-line: deprecated
		return fn.termopen(command, opts), true
	end
end

---@param poppy_name string
---@param poppy_opts PoppyResolvedConfig
---@param parent_win integer
---@param on_die? fun(poppy_name: string)  -- called when the spawned job exits; mode does not decide what happens next
---@return boolean ok
M.run = function(poppy_name, poppy_opts, parent_win, on_die)
	if not poppy_opts or not parent_win then
		return false
	end

	-- Pre-check the binary on $PATH synchronously, before creating a buffer.
	-- jobstart/termopen return a job id even for missing binaries (fork
	-- succeeds, exec fails async inside the shell). Doing this here means the
	-- drop happens at open time, not after the user has started typing into a
	-- dead terminal.
	local command = term_resolve_command(poppy_opts)
	if type(command) == "function" then
		command = command()
	end
	if not command then
		shared.drop_poppy(poppy_name, string.format("command resolved to nil for poppy '%s'", poppy_name))
		return false
	end
	local argv = argv0(command)
	if argv and fn.executable(argv) == 0 then
		shared.drop_poppy(poppy_name, string.format("binary '%s' not found on $PATH", argv))
		return false
	end

	local bufnr, reused = term_get_or_create_buffer(poppy_name)
	if not bufnr then
		return false
	end

	if reused then
		api.nvim_win_set_buf(parent_win, bufnr)
		state.poppies_runtime[poppy_name] = {
			active = true,
			hidden = false,
			bufnr = bufnr,
			win = parent_win,
			title = poppy_opts.title,
		}
		return true
	end

	-- jobstart({ term = true }) attaches the terminal to the active buffer;
	-- nvim_buf_call scopes the active buffer to bufnr for that call.
	local spawn_ok = false
	api.nvim_buf_call(bufnr, function()
		api.nvim_set_option_value("modified", false, { buf = bufnr })
		---@type table
		local spawn_opts = {
			on_exit = function()
				if api.nvim_buf_is_valid(bufnr) then
					pcall(api.nvim_buf_delete, bufnr, { force = true })
				end
				state.clear_runtime(poppy_name)
				if on_die then
					on_die(poppy_name)
				end
			end,
		}
		local _, ok = term_spawn(command, spawn_opts)
		spawn_ok = ok
	end)

	if not spawn_ok then
		-- Shouldn't happen given the pre-check, but jobstart can still
		-- fail for other reasons (e.g. malformed argv). Defensive drop.
		shared.drop_poppy(poppy_name, string.format("jobstart returned no id for %s", vim.inspect(command)))
		pcall(api.nvim_buf_delete, bufnr, { force = true })
		return false
	end

	api.nvim_win_set_buf(parent_win, bufnr)
	state.poppies_runtime[poppy_name] = {
		active = true,
		hidden = false,
		bufnr = bufnr,
		win = parent_win,
		title = poppy_opts.title,
	}
	return true
end

return M