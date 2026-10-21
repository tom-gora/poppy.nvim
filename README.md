# poppy.nvim

A floating-window manager for a small set of named "poppies" (TUIs, files, shells) you reach for constantly. One binding, one menu.

## Installation

```
git clone https://github.com/tomeczku/poppy.nvim ~/.config/nvim/pack/plugins/start/poppy.nvim
```

```lua
require("poppy").setup({
    poppies = {
        lazygit = { exec = "lazygit", title = "LazyGit" },
        todos   = { file = "~/Documents/TODO.md", title = "Todos" },
        scratch = { shell = "default", title = "Terminal" },
    },
})
```

## Configuration

```lua
require("poppy").setup({
    keys = {
        poppy_action = "<C-/>",  -- default; remap if your terminal drops Ctrl+/
        select       = "<CR>",
        kill         = "d",
        exit_menu    = "<Esc>",
    },
    icons                  = { exec = "🛠", shell = "$", file = "🗋" },
    autohide_menu          = false, -- hide sidebar after selecting; corner hint shows the binding
    title_header           = true,
    hints_footer           = true,
    close_on_focus_lost    = true,  -- close when focus leaves all poppy windows
    close_other_floats_on_open = true, -- close other floating windows when poppy opens
    assume_multiplexer     = false, -- force the mux fallback when env detection misses
    menu_width             = 25,
    win_height             = 0.75, -- ratio (0.2..1.0), absolute cells (>1), or function
    win_width              = 0.8,
    win_location           = "center", -- "center" | "top" | "bottom"

    poppies = {
        lazygit = { exec = "lazygit", title = "LazyGit" },
        todos   = { file = "~/Documents/TODO.md", title = "Todos" },
        scratch = { shell = "default", title = "Terminal" },
    },
})
```

### Poppy modes

| Key | Type | Behavior |
| --- | --- | --- |
| `exec` | `string\|string[]\|function` | Spawns a terminal buffer running the command. First token must be on `$PATH` at setup. |
| `file` | `string\|function` | Opens the path. Missing parent directories are created on first open. |
| `shell` | `string\|function` | Spawns a terminal buffer with the shell. `"default"` resolves to `$SHELL`. |

`exec`/`file`/`shell` functions are called at setup (validation + title) and at first open. They must be safe to call at setup time. `title` is optional; the default is the file basename or the first whitespace-delimited token.

### Unsaved edits and missing files

Buffers stay loaded between switches (`bufhidden = "hide"`). On re-open: a clean buffer is re-read from disk; a modified buffer is reattached untouched; a vanished file keeps its contents and `:write` recreates it. If a `file` function resolves to a new path, the old buffer is discarded.

## Usage

`keys.poppy_action` opens the manager; press it again to close. From the sidebar: `select` switches the content pane, `kill` removes a poppy, `exit_menu` returns focus to the content pane.

```
:Poppy                 " toggle
:Poppy close           " close
:Poppy menu            " toggle the sidebar only
:Poppy open [<name>]   " open, or switch to <name> if already open
```

Tab-completion knows the configured poppy names.

## Lua API

```lua
require("poppy").setup({ ... })

require("poppy").open(name?)
require("poppy").close()
require("poppy").toggle()

require("poppy").switch_by_name(name)
require("poppy").switch_by_index(1..N)
require("poppy").switch_by_cursor()

require("poppy").kill_active()
require("poppy").kill_by_name(name)
require("poppy").kill_by_index(1..N)
require("poppy").kill_by_cursor()

require("poppy").get_poppies()
require("poppy").get_poppy_by_name(name)
require("poppy").get_poppy_by_index(1..N)
require("poppy").get_current_poppy()
require("poppy").get_current_poppy_name()
require("poppy").is_open()
```

`setup` may be re-called; a second call tears down any live session before re-initializing.

## How it works

`lua/poppy/core/session/state.lua` holds the mutable state. `session/init.lua` is the orchestrator (setup, open/close/toggle, switch/kill, `:Poppy` command, recovery). `session/{menu,dialog,keymaps,autocommands}.lua` own the user-facing surface. `ui/{layout,render,view,style}.lua` own the windows and chrome. `modes/{term,file}.lua` are the per-poppy backends. `_types.lua` holds the LuaCATS annotations.

## License

Public domain; see [UNLICENSE](./UNLICENSE).
