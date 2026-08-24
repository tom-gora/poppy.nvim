# poppy.nvim

One popup to rule them all...

A personal Neovim plugin for managing toggleable terminal and file popups in a floating-window manager UI.

## About

Poppy provides a declarative way to manage terminal TUIs, file buffers, and shell sessions. Configured buffers, named "poppies", appear in a unified UI, managed from a list in a menu panel and can be switched between or killed from inside this manager. Oil-style "select" on the list or operator pending mode based on list index are both provided as a way to interact with the list.

The general philosophy is simplicity and automation over plugins like toggleterm.nvim.The problem with such plugins I had was that user declares many TUIs/quick access buffers. Each is independent, requires setting and customizing own bindings etc. Here I wanted to provide a single popup-style interface and a simple to use native-feel menu to access, open, kill and switch between them. Just one binding "poppy_action" circles though main states:

    1. toggle on + content window focused
        >>> 2.  focus the menu (optionally manage from here)
            >>> 3. toggle off (double-hit on "poppy action" closes the whole thing)

## Configuration

```lua
-- default opts:
require("poppy").setup({
    keys = {
        poppy_action = "<C-_>", -- Toggle on / toggle the menu while inside / toggle off
        select       = "<CR>",  -- In the sidebar: switch to the count-th or cursor-row poppy
        kill         = "d",     -- In the sidebar: kill the count-th or cursor-row poppy
        exit_menu    = "<Esc>", -- In the sidebar: return focus to the active poppy
    },
    icons = {                   -- Icon shown in the sidebar per poppy category
        exec  = "🛠",
        shell = "$",
        file  = "🗋",
    },
    menu_autohide  = false,     -- On true, the menu auto-hides after selecting a poppy or after the "updatetime" passed via "CursorHold" aurocmd. Else, sidebar is always visible
    title_header   = true,      -- On false, the "P◉PPY.NVIM" header above the list isn't rendered
    autoclose      = true,      -- Close the manager when focus leaves all poppy windows (WinLeave + TermEnter; fzf-lua, external terminals, `<C-w>w`, tmux nav). The `:` cmdline is exempted so `:Poppy` subcommands still work.
    exclusive_float = true,     -- When poppy opens, close all other floating windows (Telescope, snacks, LSP hovers, notifications, etc.)
    menu_width     = 25,        -- Width of the side menu panel
    win_height     = 0.75,      -- Entire UI height: ratio (0.2–1.0), absolute columns/lines (>1), or function
    win_width      = 0.8,       -- Same but witdth
    win_location   = "center",  -- Vertical offset: "center" | "top" | "bottom".

    poppies = {
        -- Executable TUI
        lazygit = {
            exec  = "lazygit",
            title = "LazyGit",
        },
        -- File buffer
        todos = {
            file  = "~/Documents/TODO.md",
            title = "Global Todos",
        },
        -- Dynamic file path (function)
        local_todos = {
            file  = function()
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
        scratch_terminal = {
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

| Key     | Type               | Description                                                                 |
| ------- | ------------------ | --------------------------------------------------------------------------- |
| `exec`  | `string`           | Command to run in a terminal buffer. TUIs, log tails, dev servers, repls... |
| `file`  | `string\|function` | File to open (Path string or 0-arg function returning one).                 |
| `shell` | `string\|function` | Shell binary path, or `"default"` for `$SHELL`.                             |

A title is generated automatically if `title` is omitted. For files, the
basename is used; for exec/shell, the first whitespace-delimited token is
basenamed.

## Usage

Poppies are switched from inside the menu.

1. Press `keys.poppy_action` (`<C-_>` by default) to toggle the plugin ui.
   - If no poppy has been opened in this session, it opens in
     **landing** mode: a centered popup with just the list and hints.
   - Otherwise, the manager reopens with the previously active poppy's
     buffer in the content area and the sidebar visible.
2. With the cursor in the sidebar, press a digit (or move the cursor) and
   then `keys.select` (`<CR>`) to switch to that poppy. With no digit, the
   cursor row is used.
3. From the sidebar, `keys.kill` (`d`) closes and deletes the buffer of
   the count-th / cursor-row poppy.
4. `keys.exit_menu` (`<Esc>`) returns focus to the active poppy.
5. Inside a poppy's content window, `keys.poppy_action` toggles the
   sidebar / focus.

### `:Poppy` user command

| Subcommand                 | Effect                                             |
| -------------------------- | -------------------------------------------------- |
| `:Poppy` / `:Poppy toggle` | Toggle the manager.                                |
| `:Poppy menu`              | Toggle the sidebar/menu while the manager is open. |
| `:Poppy open <name>`       | Open the manager and switch to `<name>`.           |
| `:Poppy close`             | Close the manager and all live poppies.            |

`:Poppy open` has tab-completion for all configured poppy names.

### Public Lua API

`require("poppy")` returns a table; everything below is on it.

| Function                       | Purpose                                                 |
| ------------------------------ | ------------------------------------------------------- |
| `poppy.setup({...})`           | Configure the plugin. Call once at startup.             |
| `poppy.toggle()`               | Open the manager if closed, close if open.              |
| `poppy.open([name])`           | Open the manager; optionally switch to `<name>`.         |
| `poppy.close()`                | Close the manager and all live poppies.                 |
| `poppy.switch_by_name(name)`   | Switch to the named poppy (must be opened).             |
| `poppy.switch_by_index(index)` | Switch by 1-based index in the registered poppy list.   |
| `poppy.kill_by_name(name)`     | Kill the named poppy and delete its buffer.             |
| `poppy.kill_by_index(index)`   | Kill by 1-based index.                                  |
| `poppy.kill_active()`          | Kill whichever poppy is currently active.               |
| `poppy.get_poppies()`          | List of all configured poppies (open + never-opened).   |
| `poppy.get_poppy_by_name(n)`   | Lookup a single poppy by name (or `nil`).               |
| `poppy.get_poppy_by_index(i)`  | Lookup by 1-based index (or `nil`).                     |
| `poppy.get_current_poppy()`    | The currently focused poppy, or `nil`.                 |
| `poppy.get_current_poppy_name()` | Name of the currently focused poppy, or `nil`.        |
| `poppy.is_open()`              | `true` while the manager UI is on screen.               |

## Structure

```
lua/poppy/
  init.lua              Thin public API (re-exports from core.session.setup)
  config.lua            Defaults, merge, shape validation, WARN on bad input
  _types.lua            LuaCATS class definitions (PoppyConfig, PoppyKeys, ...)

  core/
    shared.lua            Cross-module helpers (session_is_open, hide_poppy,
                          show_menu_hint, get_sorted_poppies, cat, keys, ...)
    session/
      state.lua             Runtime window/buffer IDs, current/last poppy,
                             menu state. Single mutable instance via default_state().
      setup.lua             Entry point: setup, open, close, toggle,
                             switch_*, kill_*, state getters (get_poppies, ...).
      manager.lua           Outer wrapper + content window create/destroy.
      actions.lua           State transitions: switch, kill, recover, hide.
                             Owns the WinClosed watcher for content windows.
      menu.lua              Buffer-local keymaps, focus/unfocus, exit_menu.

    ui/
      wrapper.lua           Outer floating window (relative='editor').
      content.lua           Inner content window (the active poppy's buffer).
      panels.lua            Sidebar container; create/destroy/hide/show/focus.
      list_panel.lua        Numbered poppy list with sign + extmark highlights.
      hints_panel.lua       Keybinding hints panel + bottom-right menu hint.
      header_panel.lua      "P◉PPY.NVIM" header (shown when title_header = true).
      layout.lua            Dimensions, z-index, landing-view width helpers.
      style.lua             Highlight group definitions + ColorScheme refresh.

  modes/
    term.lua              Terminal mode (handles `exec` and `shell` poppies).
    file.lua              File-buffer mode (handles `file` poppies).
```

## License

This is free and unencumbered software released into the public domain under [UNLICENSE](./UNLICENSE)

For more information, please refer to https://unlicense.org/

## AI Disclaimer

This project was created with assistance of Gemini 3.1 Flash, and MiniMax3 models via opencode, but not "vibecoded". Used a mix of traditional coding , degining flow and wireframes from excalidraw and assist for exploring implementation options and general support, combined with manual debugging to avoid hallucination traps. This is an exercise in building workflows for efficient, reasonable usage of both traditional and automated methods with preserving the knowledge about the codebase.


