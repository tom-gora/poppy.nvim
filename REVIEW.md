# REVIEW

## What it is

`poppy.nvim` is a single floating-window manager for a user-declared set of
"poppies". Each poppy is one of: an executable TUI (`exec`), a file buffer
(`file`, may be a function returning a path), or a shell (`shell`, may be
`"default"` for `$SHELL`). The whole feature surface is declarative: users
register them in `setup({poppies = {...}})` and the manager renders a
unified UI — sidebar list, content window for the active poppy, header,
hints panel, optional bottom-right menu indicator.

The core interaction is one binding (`poppy_action`) that cycles through
landing (empty manager, list only) → focused content → sidebar focused →
closed (double-hit). `:Poppy` user command exposes the same plus
`:Poppy open <name>` and `:Poppy close`. A public Lua API mirrors it.

## How it's built

```
lua/poppy/
  init.lua           thin public API re-export
  config.lua         defaults + merge + per-key type validation (WARNs on bad input)
  _types.lua         LuaCATS class definitions
  core/
    shared.lua       cross-module helpers (ensure_setup, opts_field, keys,
                      cat, with_modifiable, try_focus_win, apply_win_marker,
                      is_poppy_window, hide_poppy, show_menu_hint, ...)
    session/
      state.lua      runtime state (sorted poppy registry, current/last
                      poppy, window/buffer IDs, opts). Single mutable
                      instance via default_state().
      setup.lua      setup entry, autocmd + user-command registration,
                      public session API
      manager.lua    wrapper + content create/destroy, open/close/toggle
      actions.lua    state transitions: switch, kill, recover, hide.
                      Owns the WinClosed watcher for content windows.
                      Per-function setup guard via shared.ensure_setup().
      menu.lua       list/content buffer keymaps, focus/unfocus,
                      exit_menu. Per-function setup guard.
    ui/
      wrapper.lua    outer floating window
      content.lua    inner content window (the active poppy's buffer)
      panels.lua     sidebar container; create/destroy/show/hide/focus
      list_panel.lua numbered poppy list with sign + extmark highlights
      hints_panel.lua keybinding hints panel + bottom-right menu hint
      header_panel.lua "P◉PPY.NVIM" header
      layout.lua     dimensions, z-index, landing-view width helper
      style.lua      highlight groups + ColorScheme refresh
    modes/
      term.lua      exec + shell lifecycle (jobstart, on_exit cleanup)
      file.lua      file-buffer mode (handles file poppies)
```

Architectural notes:

- Mode plugins (`modes/term.lua`, `modes/file.lua`) both implement
  `M.run(name, opts, parent_win)` and own their buffer/job lifecycle.
  The session layer never touches terminal job or file load directly.
- UI is rendered with extmarks + `sign_placelist` over scratch buffers.
  No terminal/TUI app code lives in the UI layer.
- Z-index strategy: `POPPY_Z_INDEX = 48`, just under Neovim's default 50
  so completion pum / hovers / notifications / `:help` stay on top.
- Autocmd ownership is split across three augroups: `poppy_group`
  (BufUnload, CursorHold, WinLeave/TermEnter), `poppy_ui` (WinClosed
  watcher), `poppy_style` (ColorScheme). Each is `clear = true` on
  re-setup.
- Config validation is strict and emits `vim.notify(..., WARN)` for
  every offending key/field, with the default used as fallback. Recent
  diff added unknown-key detection, boolean/number coercion checks,
  and per-poppy non-table detection.
- `state.poppies` is a sorted array of `{fixed_index, config,
  runtime_state?}` populated once at setup. Array index = display order
  (category → name). `runtime_state` toggles per entry as poppies
  open/close; the array itself never reshuffles.
- Each state-touching module guards via `shared.ensure_setup()` (called
  per function, not per module-load) so direct `require()` of an
  internal module before `setup()` runs yields a working warning rather
  than a half-state crash.

## Good

- Clear module split by responsibility; `modes/` decoupled from `ui/`
  cleanly.
- Config validation is comprehensive and the WARN-on-bad-input pattern
  is consistent.
- LuaCATS annotations on every public surface.
- Each panel's content is built off scratch buffers with extmarks, so
  rerenders don't churn the actual user buffers.
- `exclusive_float` is opt-in and correctly avoids touching other
  plugin floats.
- Sidebar list panel uses signs + extmark line highlights, which keeps
  icon + dot + number + title cleanly aligned.
- Hint rendering and bottom-right "Menu" hint reuse the same
  `hints_panel` module.
- Mode plugins are tiny and orthogonal.
- `default_opts` is immutable (deep-extended into a fresh `{}`) — the
  user table is never mutated.
- `poppy_popup` buf-var ties `BufUnload` back to a name for cleanup.

## Bad

_(none)_

## Ugly

- Module split between `actions.lua` and `menu.lua` forces three
  `require("poppy.core.session.actions")` sites to be lazy (one inside
  `setup_list_keys`, one inside `refresh`, one in `menu.lua` at
  module scope anyway). The mutual dependency is real but the cure
  is either to keep `actions` as the only state-transition module
  and shrink `menu` to a keymap-only module, or move the few shared
  functions into `shared.lua` so neither has to require the other.

## Real bugs

_(none)_

