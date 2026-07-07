local M = {}

local banner_art = {
	"███████████     ███████    ███████████  ███████████  █████ █████    ██████   █████ █████   █████ █████ ██████   ██████",
	"▒▒███▒▒▒▒▒███  ███▒▒▒▒▒███ ▒▒███▒▒▒▒▒███▒▒███▒▒▒▒▒███▒▒███ ▒▒███    ▒▒██████ ▒▒███ ▒▒███   ▒▒███ ▒▒███ ▒▒██████ ██████",
	" ▒███    ▒███ ███     ▒▒███ ▒███    ▒███ ▒███    ▒███ ▒▒███ ███      ▒███▒███ ▒███  ▒███    ▒███  ▒███  ▒███▒█████▒███",
	" ▒██████████ ▒███      ▒███ ▒██████████  ▒██████████   ▒▒█████       ▒███▒▒███▒███  ▒███    ▒███  ▒███  ▒███▒▒███ ▒███",
	" ▒███▒▒▒▒▒▒  ▒███      ▒███ ▒███▒▒▒▒▒    ▒███▒▒▒▒▒      ▒▒███        ▒███ ▒▒██████  ▒▒███   ███   ▒███  ▒███ ▒▒▒  ▒███",
	" ▒███        ▒▒███     ███  ▒███         ▒███            ▒███        ▒███  ▒▒█████   ▒▒▒█████▒    ▒███  ▒███      ▒███",
	" █████        ▒▒▒███████▒   █████        █████           ████    ██ █████  ▒▒█████    ▒▒███      █████ █████     █████",
	"▒▒▒▒▒           ▒▒▒▒▒▒▒    ▒▒▒▒▒        ▒▒▒▒▒           ▒▒▒▒▒    ▒▒ ▒▒▒▒▒    ▒▒▒▒▒      ▒▒▒      ▒▒▒▒▒ ▒▒▒▒▒     ▒▒▒▒▒",
}

M.render = function(bufnr, win)
	local win_width = vim.api.nvim_win_get_width(win)
	local win_height = vim.api.nvim_win_get_height(win)
	local lines = {}

	local v_padding = math.floor((win_height - #banner_art) / 2)
	for i = 1, v_padding do
		table.insert(lines, "")
	end

	for _, line in ipairs(banner_art) do
		local line_width = vim.api.nvim_strwidth(line)
		local h_padding = math.max(0, math.floor((win_width - line_width) / 2))
		table.insert(lines, string.rep(" ", h_padding) .. line)
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

return M

