# poppy.nvim

A neovim popup scratchpad manager. Declare a small set of named "poppies" (TUIs, files, shells) once in `setup`; one binding (`<C-/>` by default) toggles a sidebar+content UI. The sidebar lists configured poppies with category icons, state dots, and numeric indices; the content pane shows the active one. A centred landing picker appears when no poppy is active. Two dialogs interrupt the flow: kill-confirm on unsaved edits, missing-file prompt on non-existent file poppies. Buffers are kept alive between switches for fast re-open.

## Installation

```lua
-- Neovim 0.12+ (built-in vim.pack)
vim.pack.add({ "https://git.tomgora.online/tomeczku/poppy.nvim" })
require("poppy").setup({
    poppies = {
        lazygit = { exec = "lazygit",  title = "LazyGit" },
        todos   = { file = "~/Documents/TODO.md", title = "Todos" },
        scratch = { shell = "default", title = "Terminal" },
    },
})

-- lazy.nvim
{
    "https://git.tomgora.online/tomeczku/poppy.nvim",
    lazy = false,
    priority = 1000,
    opts = {
        poppies = {
            lazygit = { exec = "lazygit",  title = "LazyGit" },
            todos   = { file = "~/Documents/TODO.md", title = "Todos" },
            scratch = { shell = "default", title = "Terminal" },
        },
    },
},
```

`vim.pack.add` is the built-in option since Neovim 0.12. `lazy.nvim` users can drop the `require("poppy").setup(...)` line — lazy calls it for you via `opts`.

## Configuration

```lua
require("poppy").setup({
    keys = {
        poppy_action = "<C-/>",  -- remap if it doesn't work in your terminal (see "Key bindings" below)
        select       = "<CR>",
        kill         = "d",
        exit_menu    = "h",
    },
    icons                     = { exec = "🛠", shell = "$", file = "🗋" },
    autohide_menu             = false,   -- hide sidebar after selecting; corner hint shows the binding
    title_header              = true,
    hints_footer              = true,
    close_on_focus_lost       = true,    -- close when focus returns to a normal editor window
                                           -- (cmdline, loclist, quickfix, preview, and transient
                                           --  nofile popups such as hovers and diagnostic floats
                                           --  do not trigger it)
    close_other_floats_on_open = true,   -- close other floating windows when poppy opens
    assume_multiplexer        = false,   -- set true inside tmux/screen when <C-/> never reaches nvim
    border                    = "rounded", -- "none" | "single" | "double" | "rounded" | "shadow" | border spec
    menu_width                = 25,
    win_height                = 0.75,    -- ratio (0.2..1.0), absolute cells (>1), or function
    win_width                 = 0.8,
    win_location              = "center", -- "center" | "top" | "bottom"

    poppies = {
        lazygit = { exec = "lazygit",  title = "LazyGit" },
        todos   = { file = "~/Documents/TODO.md", title = "Todos" },
        scratch = { shell = "default", title = "Terminal" },
    },
})
```

### Poppy modes

| Key | Type | Behavior |
| --- | --- | --- |
| `exec` | `string\|string[]\|function` | Spawns a terminal buffer running the command. Command must be on `$PATH`. |
| `file` | `string\|function` | Opens the file at the given path. If the path does not exist when opening, a dialog asks whether to create it (and its parent directories) or drop that poppy. |
| `shell` | `string\|function` | Spawns a terminal buffer with the shell. Set to `"default"` to use `$SHELL`. |

`exec`/`file`/`shell` are validated at setup and must be declared exactly once per poppy. `title` is optional and defaults to the file basename or command name.

### Borders

`border` takes `"none"`, `"single"`, `"double"`, `"rounded"`, `"shadow"`, or a border table of chars. `"none"` (and `"solid"`) use poppy's borderless design. If `border` is not set, poppy falls back to `vim.opt.winborder`; if that is empty or invalid, it uses borderless.

### Key bindings

`keys.poppy_action` is the one binding you press constantly, so it deserves a moment of attention. Inside tmux or screen, some terminals drop `<C-/>` (or any Ctrl combination whose underlying byte is consumed by the multiplexer) before it reaches nvim — the keymap is bound but never fires. If that happens to you, either:

- bind a key your terminal forwards cleanly (`<C-_>`, `<C-\>`, etc.), or
- set `assume_multiplexer = true` and poppy will rebind `<C-/>` to `<C-_>` automatically when `$TMUX`/`$STY` are set.

On modern terminals (kitty, wezterm, foot with `extkeys`, ghostty) inside tmux, `<C-/>` usually works as-is — `assume_multiplexer` is only needed when it doesn't.

### Dialogs

Two questions can interrupt an open. Both are answered before the UI settles, and several missing files are resolved one after another:

- **Missing file** — a `file` poppy points at a path that does not exist. `Yes` creates it along with its parent directories, `No` drops that poppy.
- **Unsaved changes** — you kill a poppy whose buffer is modified. `Save` writes it, `Discard` drops the changes, `Go back` cancels the kill. Terminals are exempt: their `modified` flag never flips.

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

`open` with no name reopens the last poppy (if its runtime is still alive) or lands on the picker. With a name, it switches directly.

Poppy refuses to open in a terminal smaller than 57×5 cells and says so; resize and toggle it back on.

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

`kill_by_name` / `kill_by_index` act on a poppy that has been opened. A configured but never-opened poppy has no session to kill and is left alone.

## How it works

`lua/poppy/core/session/state.lua` holds the mutable state. `session/manager.lua` is the orchestrator (open/close/toggle, switch/kill, recovery); `session/init.lua` is the public API entry that wires the `:Poppy` command, global keymap, and re-exports the manager's API. `session/{menu,dialog,keymaps,autocommands,watch}.lua` own the user-facing surface. `ui/{layout,mount,render,style}.lua` own the windows and chrome. `modes/{term,file}.lua` are the per-poppy backends. `_types.lua` holds the LuaCATS annotations.

## License

Public domain; see [UNLICENSE](./UNLICENSE).