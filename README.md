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
    confirm_create_file = false, -- if true, prompt before creating a missing file path at setup
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

If a `file` function returns `nil` or `""` at setup, or the resolved
path doesn't exist, the poppy is dropped with a WARN. If
`confirm_create_file = true` is set, you are prompted per missing
path before dropping. See [Confirm file creation](#confirm-file-creation).

### Poppy modes

Each poppy declares exactly one of:

| Key | Type | Notes |
| ------- | ------------------ | --------------------------------------------------------------------- |
| `exec` | `string\|string[]` | Command run in a terminal buffer (TUIs, log tails, dev servers). The first token must be on `$PATH` at setup; otherwise the poppy is dropped. |
| `file` | `string\|function` | File to open. Must exist at setup; otherwise the poppy is dropped. With `confirm_create_file = true`, missing paths prompt for creation. |
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

### Confirm file creation

By default, a file poppy whose path doesn't exist at setup is dropped
with a WARN. Set `confirm_create_file = true` to be prompted per
missing path before dropping:

```lua
require("poppy").setup({
    confirm_create_file = true,
    poppies = {
        notes = { file = "~/TODO.md", title = "Notes" },
    },
})
```

The prompt is `vim.ui.select({"Create", "Skip"})` with a 20s
auto-skip timeout. If the user-installed picker is async, the default
synchronous impl runs and the timeout covers headless / picker-hung
cases. If the user picks Skip or the timer fires, the poppy is
dropped. If the user picks Create, the parent directories are
created with `mkdir -p` and an empty file is written to the resolved
path.

If a file disappears between setup and the first open, the runtime
check drops the poppy with a WARN. The buffer is preserved (because
`bufhidden = "hide"`); use `:write` to recreate the file at its
original path. Poppy does not synthesize a fallback location at
runtime — no clutter without confirmation.

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

Tab-completion knows your configured poppy names.

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

