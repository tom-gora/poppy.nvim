local M = {}

M.spawn_term = function(command, opts)
	if type(command) == "function" then
		command = command()
	end
	if vim.fn.has("nvim-0.11") == 1 then
		opts.term = true
		return vim.fn.jobstart(command, opts)
	else
		---@diagnostic disable-next-line: deprecated
		return vim.fn.termopen(command, opts)
	end
end

M.title_fallback = function(mode, value)
	if type(value) == "function" then
		value = value()
	end
	if mode == "file" then
		return vim.fs.basename(vim.fn.expand(value))
	elseif mode == "exec" then
		if type(value) == "table" then
			return vim.fs.basename(value[1])
		end
		return vim.fs.basename(vim.split(value, " ")[1])
	elseif mode == "term" then
		if type(value) == "table" then
			return vim.fs.basename(value[1])
		end
		return vim.fs.basename(vim.split(value, " ")[1])
	end
	return "POPPY"
end

return M
