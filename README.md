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
        poppy_action = "<C-/>",  -- remap if it doesn't fire (see "Key bindings" below)
        select       = "<CR>",
        kill         = "d",
        exit_menu    = "<Esc>",
    },
    icons                  = { exec = "🛠", shell = "$", file = "🗋" },
    autohide_menu          = false,   -- hide sidebar after selecting; corner hint shows the binding
    title_header           = true,
    hints_footer           = true,
    close_on_focus_lost    = true,    -- close when focus returns to a normal editor window
                                       -- (cmdline, loclist, quickfix, preview, and transient
                                       --  nofile popups such as hovers and diagnostic floats
                                       --  do not trigger it)
    close_other_floats_on_open = true, -- close other floating windows when poppy opens
    assume_multiplexer     = false,   -- set true inside tmux/screen when <C-/> never reaches nvim
    border                 = "rounded", -- "none" | "single" | "double" | "rounded" | "shadow" | border spec
    menu_width             = 25,
    win_height             = 0.75,    -- ratio (0.2..1.0), absolute cells (>1), or function
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
| `file` | `string\|function` | Opens the path. A missing file is offered for creation before the UI appears. |
| `shell` | `string\|function` | Spawns a terminal buffer with the shell. `"default"` resolves to `$SHELL`. |

`exec`/`file`/`shell` functions are called at setup (validation + title) and at first open. They must be safe to call at setup time. `title` is optional; the default is the file basename or the first whitespace-delimited token.

### Borders

`border` takes `"none"`, `"single"`, `"double"`, `"rounded"`, `"shadow"`, or an
`nvim_open_win` border spec table. `"none"` (and `"solid"`) means borderless. Leave it
out and poppy follows your global `winborder`, falling back to borderless.

### Key bindings

`keys.poppy_action` is the one binding you press constantly, so it deserves a moment
of attention. Inside tmux or screen, some terminals drop `<C-/>` (or any Ctrl
combination whose underlying byte is consumed by the multiplexer) before it reaches
nvim — the keymap is then bound but never fires. If that happens to you, either:

- bind a key your terminal forwards cleanly (`<C-_>`, `<C-\>`, etc.), or
- set `assume_multiplexer = true` and poppy will rebind `<C-/>` to `<C-_>` automatically when `$TMUX`/`$STY` are set.

On modern terminals (kitty/wezterm/foot with `extkeys`, ghostty) inside tmux, `<C-/>`
usually works as-is — `assume_multiplexer` is only needed when it doesn't.

### Dialogs

Two questions can interrupt an open. Both are answered before the UI settles, and
several missing files are resolved one after another:

- **Missing file** — a `file` poppy points at a path that does not exist. `Yes` creates
  it along with its parent directories, `No` drops that poppy.
- **Unsaved changes** — you kill a poppy whose buffer is modified. `Save` writes it,
  `Discard` drops the changes, `Go back` cancels the kill. Terminals are exempt: their
  `modified` flag never flips.

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

Poppy refuses to open in a terminal smaller than 57x10 and says so; resize and toggle
it back on.

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

-- Less commonly needed
require("poppy").recover()             -- re-pick a fallback poppy or land on the picker
require("poppy").transition_to_content() -- grow the wrapper from landing to sidebar+content
```

`setup` may be re-called; a second call tears down any live session before re-initializing.

`kill_by_name` / `kill_by_index` act on a poppy that has been opened. A configured but
never-opened poppy has no session to kill and is left alone.

## How it works

`lua/poppy/core/session/state.lua` holds the mutable state. `session/manager.lua` is the orchestrator (open/close/toggle, switch/kill, recovery); `session/init.lua` is the public API entry that wires the `:Poppy` command, global keymap, and re-exports the manager's API. `session/{menu,dialog,keymaps,autocommands}.lua` own the user-facing surface. `ui/{layout,render,view,style}.lua` own the windows and chrome. `modes/{term,file}.lua` are the per-poppy backends. `_types.lua` holds the LuaCATS annotations.

## License

Public domain; see [UNLICENSE](./UNLICENSE).
