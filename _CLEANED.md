# _CLEANED

Resolved items moved out of `REVIEW.md`.

- `panels.lua:99` `rebuild` references `state.windows.menu_width` and
  `state.windows.header_height` which are local state — but the panel
  width is also passed in as `menu_width` and silently ignored in
  favor of the state field. Either remove the parameter or use it.

- `focus()` helper is duplicated verbatim in `actions.lua:9–15` and
  `menu.lua:7–13`. Identical five-line body in both. Should live in
  `shared.lua`.

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

- `hints_panel.update` still has a `mode` parameter (`:149`) but the
  only caller passes `"active_menu"` after the recent simplification of
  `actions.refresh_panels`. The `active_focused` entry in `HINT_SPECS`
  (`hints_panel.lua:44`) is unreachable dead data.

- `actions.lua:110` has `local panel_width = state.windows.opts and state.windows.opts.menu_width or 25` while a few lines above
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

- The lazy require inside `refresh()` at `menu.lua:35–37` is the only
  reason `menu.lua` doesn't require `actions` at module top — but
  `menu.lua:88` does `local actions = require(...)` at module scope
  anyway, making the inner lazy require useless.

- `setup.lua` exposes internal functions (`setup_command`,
  `setup_autocmds`, `setup_exclusive_float`) on `M` but only `setup`
  is public. Marking them module-local would prevent accidental
  external call.