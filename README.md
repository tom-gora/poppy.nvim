# poppy.nvim

A personal neovim plugin for managing toggleable popups.

## About

This plugin provides a declarative way to manage terminal and file popups. It uses native Neovim floating windows (`float` backend) for files and terminal buffers (`term` backend), ensuring popups remain isolated and consistent.

The project is currently in an early stage with no clear further goals yet.
The general philosophy is a focus on being simpler and more automated compared to plugins like toggleterm.nvim.

## Configuration Example

```lua
require("poppy").setup({
    -- Gobally configured preferences
	popups_backend = "float", -- "float" | "term" # Choose backend: "float" for files, "term" for commands
    -- If preferred multiplexer but in non-multiplexed terminal will automatically fallback to term.
    width = 0.45, -- Popup width as a ratio of terminal width (0.2 - 1.0). Default: 0.8
    height = 0.9, -- Popup height as a ratio of terminal height (0.2 - 1.0). Default: 0.8
    position = "right", -- "center"|"left"|"right" # Popup position. Default: "center"
    border = "solid", -- "rounded"|"single"|"double"|"solid"|"none" # Border style. Default: "rounded"
    close_keymap = "<C-q>", -- Keymap to close the popup. Default: "<C-q>"
    hide_keymap = "<C-d>", -- Keymap to hide the popup. Default: "<C-d>"
    title = "POPPY", -- Popup title. Default: ""
    align_on_border = "right", -- Title/Footer alignment. Default: "center"
    -- Declare popups/Override any of the above by popup
	popups = {
        -- Executable tui example
		lazygit = {
            exec = "lazygit", -- "string|function" # Provide executable that's in $PATH
            width = 0.45,
            height = 0.9,
            position = "right",
            border = "solid",
			close_keymap = "<C-q>",
			hide_keymap = "<C-x>",
			title = "LazyGit",
			align_on_border = "right",
		},
        -- File path example
		todos = {
			exec = "~/Documents/TODO.md", -- "string|function" # Provide fixed path to file on the system. If file then will be created/opened
			width = 0.8,
			height = 0.8,
			border = "solid",
			position = "center",
			close_keymap = "<C-q>",
			hide_keymap = "<C-x>",
			title = "GLOBAL TODOS",
			align_on_border = "center",
		},
        -- Dynamic file path example
		local_todos = {
            -- "string|function" # Return path based of you chosen logic
            -- Example: find Git root upwards and place the file there, otherwise at current location
			exec = function()
				local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
				local git_root = vim.fs.find(".git", {
					path = dir,
					upward = true,
				})[1]
				if git_root then
					return vim.fs.dirname(git_root) .. "/TODO.md"
				else
					return "./TODO.md"
				end
			end,
			width = 0.8,
			height = 0.8,
			border = "solid",
			position = "center",
			close_keymap = "<C-q>",
			hide_keymap = "<C-x>",
			title = "PROJECT TODOS",
			align_on_border = "center",
		},
	},
})
```

## Features

- Declarative configuration for terminal and file popups.
- Uses a hybrid backend: native Neovim floating windows (`float`) for files, and terminal buffers (`term`) for executable commands.
- File popups use isolated buffers (`buflisted = false`) to keep them clean and avoid cluttering `:oldfiles` or history, making them ideal for quick scratchpads.
- Persistent state via simple file based IPC.
- Exposed a simple getter for this state so the popups in use or minimized can be displayed anywhere (I.E. in the statusline) easier.

## License

This is free and unencumbered software released into the public domain under [UNLICENSE](./UNLICENSE)

For more information, please refer to https://unlicense.org/

## AI DISCLAIMER

This project was created with assitance of Gemini 3.1 Flash and opencode, but not "vibecoded" fully. Used a mix of traditional coding and assist for exploring implementation options and general support in integrating with tmux logic through research, frequent state wipes and small guided and targetted sessions combined with manual debuggind to avoid the "context drift" or "hallucination traps". This is a further exercise of building workflows for efficient and wise usage of both traditional and automated methods with preserving the knowledge about the codebase without giving up too much control to the clanker.
