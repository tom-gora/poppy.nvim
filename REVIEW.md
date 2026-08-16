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
  _debug_helpers.lua commented-out manual layout-debug helpers
  core/
    shared.lua       cross-module helpers (hide/show_menu_hint/cat/keys/with_modifiable/sorted_poppies)
    session/
      state.lua      mutable runtime state (window/buffer IDs, current/last poppy, opts)
      setup.lua      setup entry, autocmd + user-command registration, public session API
      manager.lua    wrapper + content create/destroy, open/close/toggle
      actions.lua    transitions: switch, kill, recover, hide; owns WinClosed watcher
      menu.lua       list/content keymaps, menu focus toggle, exit_menu
    ui/
      wrapper.lua    outer floating window
      content.lua    inner content window (active poppy buffer)
      panels.lua     sidebar container; create/destroy/show/hide/focus
      list_panel.lua numbered poppy list with signs + extmark highlights
      hints_panel.lua keybinding hints + bottom-right menu indicator
      header_panel.lua "P◉PPY.NVIM" header
      layout.lua     dimensions, z-index, landing-view width helper
      style.lua      highlight groups + ColorScheme refresh + winhl assignments
    modes/
      term.lua       exec + shell lifecycle (jobstart, on_exit cleanup)
      file.lua       file lifecycle (create buf, load, var tag)
```

Architectural notes:

- A single mutable state module (`state.lua`) is imported by everyone; no
  encapsulation of mutation. Defensive nil-checks throughout. Reasonable
  for an MVP, fits the plugin's small scope.
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

- `state.poppies` is dual-purpose: it's both an array of `{name, config}`
  entries (set during setup, used to drive display order) AND a map of
  `name → {active, hidden, bufnr, win, title}` runtime entries (set by
  modes/term.lua and modes/file.lua). They coexist by accident of Lua
  table semantics (string keys don't disturb the array length). Every
  iteration site has to know which one it's reading, and three places
  iterate via `pairs(state.poppies)` and have to guard with
  `if p_state and p_state.bufnr` to avoid confusing the two. Splitting
  into `state.poppies_config` (array) and `state.poppies_runtime` (map)
  would make every call site read clearly.
- `actions.refresh_panels` parameter is named `sorted_poppies` but is
  always called with `state.poppies`. The two are not the same thing
  downstream (one feeds `list_panel.update`'s `sorted_poppies`, the
  other feeds its `poppies` runtime map), so the parameter is actually
  load-bearing — but the name lies. Either pass the sorted array or
  rename for honesty.
- `manager.open` lines 114–118: a "lazy first-time population" block
  re-populates `state.poppies` from sorted config. Without `setup()`,
  `state.windows.opts` is nil and this would crash on the access; with
  `setup()`, this block is dead because setup already populated it.
- `state.windows.opts.X` chains appear all over the code for everything
  except `keys`. There's a `shared.keys()` helper but no
  `shared.opts_or_empty()`-style accessor, so the rest of the chain is
  inconsistent.

## Ugly

- `focus()` helper is duplicated verbatim in `actions.lua:9–15` and
  `menu.lua:7–13`. Identical five-line body in both. Should live in
  `shared.lua`.
- `panels.mark_poppy_window` exists in `panels.lua:243` but is never
  called; instead every panel wrapper file (`wrapper.lua:27`,
  `content.lua:36`, `list_panel.lua:97`, `hints_panel.lua:101`/`:142`,
  `header_panel.lua:46`) inlines
  `vim.api.nvim_win_set_var(win, "poppy_ui_window", true)`. Six copies
  of the same one-liner, with a wrapper function defined but unused.
- `panels.create` and `panels.create_landing` are declared to return
  `PoppyPanelHandles` but every caller discards the return value
  (`actions.lua:113`, `actions.lua:121`). The returned tables are dead.
- `panels.rebuild` is invoked with magic numbers `3` and `4` for hint
  line height (`panels.lua:195`, `:203`, `:224`). No symbolic constant
  exists; the meaning is "3 when menu focused, 4 when unfocused" and
  you have to count rows in the hints panel to verify.
- `header_panel.lua:45` calls `style.apply_list_panel_style(win)` for
  the header window — the function exists to style the list panel. The
  header just happens to want the same winhl. Either rename the helper
  to something panel-agnostic or split it.
- `hints_panel.update` still has a `mode` parameter (`:149`) but the
  only caller passes `"active_menu"` after the recent simplification of
  `actions.refresh_panels`. The `active_focused` entry in `HINT_SPECS`
  (`hints_panel.lua:44`) is unreachable dead data.
- `actions.kill_active` line 282: `focus(state.windows.content_win)`
  runs synchronously right after `M.recover()`, which defers via
  `vim.schedule`. By the time recover's callback runs, content_win
  may have been rebuilt; the immediate focus call lands on a stale or
  invalid window and is overridden anyway. The line is misleading
  (looks intentional, has no effect).
- `actions.switch_by_name` hides the current poppy then re-opens it
  even when `poppy_name == state.windows.current_poppy_name`. Cheap
  but pure waste; an early-return guard would remove it.
- `header_panel.lua:64–65` hardcodes UTF-8 byte offsets of "◉" inside
  "P◉PPY.NVIM" to compute the colored-dot extmark range. If the title
  string ever changes, this silently mis-highlights. Should use
  `vim.str_utfindex` / `vim.fn.strdisplaywidth` to find the char
  position.
- `actions.lua:110` has `local panel_width = state.windows.opts and
  state.windows.opts.menu_width or 25` while a few lines above
  `local menu_width = function() return ... end` does the same with a
  default fallback. The hardcoded `25` is also the default already
  defined in `state.lua:46`; triple-defined magic number.
- `manager.open` calls `actions.refresh_panels(state.poppies)` at line
  140 after `actions.switch_by_name` already did at line 188 inside
  itself. Double render on every `has_content` open. The landing path
  needs the outer call (since `enter_landing` doesn't refresh), so the
  fix is to move refresh into `enter_landing` and drop the outer call.
- `state.poppies` cleanup iterates `pairs(state.poppies)` in
  `manager.lua:clear_poppies` — same iteration/dual-purpose friction
  noted above, masked by the `p_state.bufnr` guard. Would dissolve
  naturally if the table were split.
- `panels.create` and `panels.create_landing` share a parallel
  structure (three `ensure_panel` calls each) with subtly different
  parameters. The `panels.rebuild` path duplicates the same
  close-three-and-recreate logic a third time. One entry point keyed
  on a layout argument would consolidate them.
- Commented-out debug blocks left in production files:
  `list_panel.lua:9–13` and `:91–94`, `hints_panel.lua:10–13`,
  `:91–93`, `:136–139`. They reference
  `poppy._debug_helpers.layout__hightlight_window_visually` (note the
  typo) which would color panels red if uncommented. Either ship the
  debug mode behind a config flag or delete them.
- Module split between `actions.lua` and `menu.lua` forces three
  `require("poppy.core.session.actions")` sites to be lazy (one inside
  `setup_list_keys`, one inside `refresh`, one in `menu.lua:88` at
  module scope anyway). The mutual dependency is real but the cure
  is either to keep `actions` as the only state-transition module
  and shrink `menu` to a keymap-only module, or move the few shared
  functions into `shared.lua` so neither has to require the other.
- The lazy require inside `refresh()` at `menu.lua:35–37` is the only
  reason `menu.lua` doesn't require `actions` at module top — but
  `menu.lua:88` does `local actions = require(...)` at module scope
  anyway, making the inner lazy require useless.
- `setup.lua` exposes internal functions (`setup_command`,
  `setup_autocmds`, `setup_exclusive_float`) on `M` but only `setup`
  is public. Marking them module-local would prevent accidental
  external call.
- `state.windows.opts.poppies_resolved` is one of two parallel poppy
  tables in `opts` (the other being `poppies`, the user's raw input).
  Only used in `switch_by_name`. The `poppies_resolved` naming is
  redundant — it's resolved at config-time, not at use-time — but
  it's load-bearing so leave it.

## Real bugs

- **`actions.kill_active` line 282**: `focus(state.windows.content_win)`
  fires synchronously after `M.recover()` defers via `vim.schedule`.
  At the moment of the focus call, `state.windows.content_win` still
  points at the content window of the just-killed poppy (its buffer
  was deleted in the line above), and the scheduled recover will
  replace or close it shortly after. The focus call either lands on
  a bufferless window (Neovim ignores it silently) or races with the
  scheduled close. Recover's fallback path correctly focuses whatever
  the new content window is — the line is dead and misleading. Remove
  it.
