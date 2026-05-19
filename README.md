# poppy.nvim

A personal neovim plugin for managing toggleable terminal popups.

## About

This plugin provides a declarative way to use and manage terminal popups. Can use tmux popups (dedicated session) or the native neovim terminal as a backend, makes sure these popups behave consistently and remain isolated instances, no matter where they are triggered.

The project is currently in an early stage with no clear further goals yet.
The general philosophy is a focus on being simpler and more automated compared to plugins like toggleterm.nvim.

## Configuration Example

```lua
require("poppy").setup({
popups_backend = "tmux",
popups = {
git = {
exec = "lazygit",
width = 0.9,
height = 0.9,
}
}
})
```

## Features

- Declarative configuration for terminal popups.
- Support for both tmux and native neovim terminal backends. Unless declared will spawn tmux popups, if not in multiplexer will fallback to native term. However if tmux is configured but we happen to be in a regular non-multiplexed terminal a native backend will be used as fallback seamlessly so the plugin does not break with no tmux. It just orefers it (result of my preference).
- If used for file editing neovimn instances are nested and separate even inside of native term to improve isolation and reduce noise by disabling shada file for them. This prevents from cluttering :oldfiles, history and such with files that are intended for quick "scratchpad" access frequently but be disposable in nature (like various TODO files).
- If setting popup to a file location can be a path but also can be dynamically scripted and buffer will open for that location if file does not exist ready to be saved. Example:

```lua
			local_todos = {
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
				title = "GLOBAL TODOS",
				align_on_border = "centre",
			},

```

- Persistent state via simple file based IPC.
- Exposed a simple getter for this state so the popups in use or minimized can be displayed anywhere (I.E. in the statusline) easier.

## License

This is free and unencumbered software released into the public domain under [UNLICENSE](./UNLICENSE)

For more information, please refer to https://unlicense.org/

## AI DISCLAIMER

This project was created with assitance of Gemini 3.1 Flash and opencode, but not "vibecoded" fully. Used a mix of traditional coding and assist for exploring implementation options and general support in integrating with tmux logic through research, frequent state wipes and small guided and targetted sessions combined with manual debuggind to avoid the "context drift" or "hallucination traps". This is a further exercise of building workflows for efficient and wise usage of both traditional and automated methods with preserving the knowledge about the codebase without giving up too much control to the clanker.
