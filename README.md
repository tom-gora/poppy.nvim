# poppy.nvim

A floating-window manager for a small set of "poppies" (terminal TUIs,
file buffers, shell sessions) you reach for constantly. One binding,
one menu, no per-popup boilerplate.

## About

Built because plugins like toggleterm.nvim never quite fit how I work:
many TUIs and quick-access buffers, each independent, each needing its
own keymap, each silently piling up in the window list. Poppy inverts
that: declare your poppies once, get a single manager with a sidebar
list, a content pane, and one keybinding that cycles through
open/content/sidebar/closed.

Personal project, in no hurry to grow features. The shape may change
without a major-version bump.

## Installation

Drop it into your runtimepath:

```
git clone https://github.com/tomeczku/poppy.nvim ~/.config/nvim/pack/plugins/start/poppy.nvim
```

(or use your plugin manager of choice; no `lazy`/`packer`-specific
setup is required).

Then call `setup` somewhere in your config:

```lua
require("poppy").setup({
    poppies = {
        lazygit = { exec = "lazygit", title = "LazyGit" },
        todos   = { file = "~/Documents/TODO.md", title = "Todos" },
        term    = { shell = "default", title = "Terminal" },
    },
})
```

## Configuration

```lua
require("poppy").setup({
    keys = {
        poppy_action = "<C-_>",  -- open / toggle menu / toggle off
        select       = "<CR>",   -- in sidebar: switch to Nth / cursor-row poppy
        kill         = "d",      -- in sidebar: kill Nth / cursor-row poppy
        exit_menu    = "<Esc>",  -- in sidebar: return focus to the active poppy
    },
    icons = {
        -- sidebar gutter per poppy category; any single string works
        exec  = "X",
        shell = "$",
        file  = "F",
    },
    menu_autohide     = false, -- hide sidebar after selecting a poppy; show a tiny "Menu" hint in the corner
    title_header      = true,  -- show "POPPY" header above the sidebar
    autoclose         = true,  -- close the manager when focus leaves all poppy windows
    exclusive_float   = true,  -- when poppy opens, close any other floating windows
    menu_width        = 25,    -- width of the sidebar (cols)
    win_height        = 0.75,  -- UI height: ratio (0.2 to 1.0), absolute cells (>1), or function
    win_width         = 0.8,   -- same, for width
    win_location      = "center", -- "center" | "top" | "bottom"

    poppies = {
        -- TUI / command
        lazygit = { exec = "lazygit", title = "LazyGit" },

        -- File buffer; path is checked at setup
        todos = {
            file  = "~/Documents/TODO.md",
            title = "Todos",
        },

        -- Dynamic file path
        project_todos = {
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

        -- Shell session; "default" resolves to $SHELL
        scratch = { shell = "default", title = "Terminal" },
    },
})
```

If a `file` function returns `nil` or `""`, or the path expands to an
empty string, the poppy is dropped with a WARN.

### Poppy modes

Each poppy declares exactly one of:

| Key | Type | Notes |
| ------- | ------------------ | --------------------------------------------------------------------- |
| `exec` | `string\|string[]\|function` | Command run in a terminal buffer (TUIs, log tails, dev servers). The first token must be on `$PATH` at setup; otherwise the poppy is dropped. |
| `file` | `string\|function` | File to open. Not checked at setup. If the file is missing on first open, its parent directories are created and an empty file is written. |
| `shell` | `string\|function` | Shell binary path; `"default"` resolves to `$SHELL` (falls back to `bash`). Must be on `$PATH` at setup; otherwise the poppy is dropped. |

`exec` and `file`/`shell` may also be functions returning a string (or
list of strings for `exec`). Functions are called twice: once at setup
to validate the result, and again at the first open to resolve the
final value. This means the function must be safe to call at setup
time, and the result at setup is the snapshot used for the title. If
you need a different path at open time than at setup time, the
runtime check will catch it and drop the poppy with a WARN.

`title` is optional. For files, the basename is used; for exec/shell,
the first whitespace-delimited token.

### Unsaved edits and missing files

Buffers are kept (`bufhidden = "hide"`) between switches, so unsaved
edits survive switching away and back. On re-open:

- a **clean** buffer is re-read, so edits made outside nvim show up
- a **modified** buffer is reattached untouched — your work is never
  overwritten. Use `:write` to save it, or `:edit!` to discard it
- if the file was **deleted** while it was closed, a clean buffer keeps
  its contents and `:write` recreates the file at the same path; a
  modified buffer is left alone entirely

If the `file` value is a function and resolves to a *different* path
than last time, the old buffer is discarded and the new file is loaded.

## Usage

Hit `keys.poppy_action` (`<C->_` by default) to open the manager:

- **First open**, or after `:Poppy close`: lands on a centered popup
  with just the sidebar and hints.
- **Re-open** with poppies alive: the previous one's buffer is back in
  the content pane, sidebar visible.

From the sidebar, `select` swaps the content pane to a different
poppy; `kill` removes one (so it has to be re-opened next time);
`exit_menu` returns focus to the content pane.

Hitting `keys.poppy_action` twice in succession closes the manager. If
the only open poppy was current, killing it lands you back in the
landing view automatically.

### :Poppy command

```vim
:Poppy            " toggle
:Poppy close      " close
:Poppy menu       " toggle just the sidebar
:Poppy open [<name>]   " open (or switch to <name> if already open)
```

Tab-completion knows your configured poppy names. A name that was never
configured is refused with a warning: nothing opens, and a manager that is
already up is left as it is.

## Lua API

```lua
require("poppy").setup({ ... })          -- required, once
require("poppy").open(name?)             -- open manager (or switch to name)
require("poppy").close()
require("poppy").toggle()                -- toggle whole manager
require("poppy").switch_by_name(name)
require("poppy").switch_by_index(1..N)
require("poppy").switch_by_cursor()      -- whatever the cursor row points at
require("poppy").kill_active()
require("poppy").kill_by_name(name)
require("poppy").kill_by_index(1..N)
require("poppy").kill_by_cursor()

require("poppy").get_poppies()           -- list of {name, config, runtime_state?} entries
require("poppy").get_poppy_by_name(name)  -- {name, config, runtime_state?} or nil
require("poppy").get_poppy_by_index(1..N) -- {name, config, runtime_state?} or nil
require("poppy").get_current_poppy()      -- {name, config, runtime_state?} or nil
require("poppy").get_current_poppy_name() -- string?
require("poppy").is_open()               -- boolean
```

`setup` is meant to be called once, but re-sourcing your config calls it
again. A second call tears down a live session first, exactly as
`:Poppy close` does, so a config reload cannot leave the previous floats on
screen. It is a full reset: in-flight poppy buffers are not preserved, so a
modified file buffer with unsaved edits is discarded.

## How it works

There is one mutable state table in `lua/poppy/core/session/state.lua`
window IDs, buffer IDs, the poppy registry, the merged config, and a
couple of booleans. Everything else reads through it.

`lua/poppy/core/session/init.lua` is the public orchestrator: setup,
open/close/toggle, switch/kill, the `:Poppy` command, and the
recovery routine that re-arms the manager after a buffer gets `:bd`'d
out from under it. Mode plugins (`modes/term.lua`, `modes/file.lua`)
just receive `(name, config, parent_win)` and own their own
buffer/job lifecycle.

UI lives under `lua/poppy/core/ui/`:

- `layout.lua` pure dimension math (`win_width`/`win_height`
  resolution, ratio vs absolute, `z-index` constant).
- `render.lua` panel renderers (header / list / hints) plus extmark +
  sign placement.
- `style.lua` highlight setup; re-runs on `ColorScheme`.
- `view.lua` the shell windows (wrapper + content), sidebar mount
  lifecycle, autohide show/hide, list refresh.

Type annotations live in `lua/poppy/_types.lua` (LuaCATS) and the
project bundles a `.luarc.json` pointing at the `$VIMRUNTIME` meta
files so editors/lsp pick them up.

## License

Public domain; see [UNLICENSE](./UNLICENSE).

