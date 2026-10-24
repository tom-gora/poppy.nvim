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

---Setup already validated; nil means the caller should drop the poppy.
---@param poppy_opts PoppyResolvedConfig
---@return string|string[]|nil
local term_resolve_command = function(poppy_opts)
	local raw = poppy_opts.value
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
	if poppy_opts.mode == "shell" and raw == "default" then
		return shared.default_shell()
	end
	return raw
end

---@param command string|string[]
---@param opts table
---@return integer|nil job_id
---@return boolean ok  false when jobstart refused; command was resolvable but failed to spawn
local term_spawn = function(command, opts)
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
---@return boolean ok
M.run = function(poppy_name, poppy_opts, parent_win)
	if not poppy_opts or not parent_win then
		return false
	end
	if poppy_opts.mode == "file" then
		return false
	end

	-- Pre-check $PATH synchronously: jobstart/termopen return a job id even for missing binaries
	-- (fork succeeds, exec fails async), so without this the drop only happens after typing.
	local command = term_resolve_command(poppy_opts)
	if not command then
		shared.drop_poppy(poppy_name, string.format("command resolved to nil for poppy '%s'", poppy_name))
		return false
	end
	local argv = shared.argv0(command)
	if argv and fn.executable(argv) == 0 then
		shared.drop_poppy(poppy_name, string.format("binary '%s' not found on $PATH", argv))
		return false
	end

	local bufnr, reused = term_get_or_create_buffer(poppy_name)
	if not bufnr then
		return false
	end

	if not reused then
		-- Scopes the active buffer to bufnr so the terminal attaches even though parent_win shows another.
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
				end,
			}
			local _, ok = term_spawn(command, spawn_opts)
			spawn_ok = ok
		end)

		if not spawn_ok then
			-- jobstart can still fail for other reasons (malformed argv).
			shared.drop_poppy(poppy_name, string.format("jobstart returned no id for %s", vim.inspect(command)))
			pcall(api.nvim_buf_delete, bufnr, { force = true })
			return false
		end
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