# poppy.nvim

A personal Neovim plugin for managing toggleable terminal and file popups in a floating-window manager UI.

## About

Poppy provides a declarative way to manage terminal TUIs, file buffers, and shell sessions. Configured poppies appear as a numbered list in a side panel and can be switched between with `<M-p>N` keybinds.

The general philosophy is simplicity and automation over plugins like toggleterm.nvim.

## Configuration

```lua
require("poppy").setup({
    prefix_bind = "<M-p>",     -- Prefix for all poppy keybinds. Default: "<M-p>"
    sidebar_width = 25,       -- Width of the side panels. Default: 25
    win_height = 0.75,         -- Height ratio of screen (0.2-1.0) or absolute pixels. Default: 0.75
    win_location = "center",   -- "center" | "top" | "bottom". Default: "center"
    whichkey_disable = false,  -- If true, set desc to "which_key_ignore" for WhichKey compat.

    poppies = {
        -- Executable TUI
        lazygit = {
            exec = "lazygit",
            title = "LazyGit",
        },
        -- File buffer
        todos = {
            file = "~/Documents/TODO.md",
            title = "Global Todos",
        },
        -- Dynamic file path (function)
        local_todos = {
            file = function()
                local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
                local git_root = vim.fs.find(".git", { path = dir, upward = true })[1]
                if git_root then
                    return vim.fs.dirname(git_root) .. "/TODO.md"
                end
                return "./TODO.md"
            end,
            title = "Project Todos",
        },
        -- Shell session ("default" resolves to $SHELL)
        terminal = {
            shell = "default",
            title = "Terminal",
        },
        -- Explicit shell
        bash = {
            shell = "/usr/bin/bash",
        },
    },
})
```

### Poppy modes

Each poppy must have exactly one of:

| Key | Type | Description |
|---|---|---|
| `exec` | `string\|string[]\|function` | Command to run in a terminal buffer |
| `file` | `string\|function` | File path to open |
| `shell` | `string\|function` | Shell binary path (or `"default"` for `$SHELL`) |

## Usage

| Action | Command | Keybind |
|---|---|---|
| Toggle manager | `:Poppy` | — |
| Open manager + switch | `:Poppy open <name>` | — |
| Close manager | `:Poppy close` | — |
| Switch to poppy N | — | `<M-p>1`–`<M-p>N` |
| Kill current poppy | — | `<M-p>k` |

The `:Poppy` command has tab-completion for all configured poppies.

## Structure

```
lua/poppy/
  init.lua              Thin public API: toggle, open, close, setup
  config.lua            Defaults, merge, validation
  core/
    session.lua         Engine: state, opts, window orchestration, mode dispatch
    input.lua           Keybind setup (prefix-driven switching)
    ui/
      wrapper.lua       Outer floating window
      content.lua       Inner content window
      hints_panel.lua   Keybinding hints panel
      list_panel.lua    Poppy list panel
      banner.lua        ASCII art banner (idle state)
      style.lua         Highlight groups
  modes/
    term.lua            Terminal mode (exec + shell configs)
    file.lua            File buffer mode
    utils.lua           Shared helpers (spawn_term, title_fallback)
```

## License

This is free and unencumbered software released into the public domain under [UNLICENSE](./UNLICENSE)

For more information, please refer to https://unlicense.org/

## AI Disclaimer

This project was created with assistance of Gemini 3.1 Flash and opencode, but not "vibecoded" fully. Used a mix of traditional coding and assist for exploring implementation options and general support, combined with manual debugging to avoid context drift and hallucination traps. This is a further exercise of building workflows for efficient and wise usage of both traditional and automated methods with preserving the knowledge about the codebase.