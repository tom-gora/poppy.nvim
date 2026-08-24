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

- `state.poppies` is now a sorted array of `{name, config,
  runtime_state}` entries, populated once at setup from
  `opts.poppies_resolved`. The array index IS the display order
  (category → alphabetical). `state.poppy(name)` and
  `state.poppy_index(name)` do linear scans (~5–30 entries typical).
  Name lookup is O(n), irrelevant for the scale. `shared.get_sorted_poppies`
  was inlined into the two setup-time callers (`setup.lua` canonical loop
  and `manager.lua` lazy-pop fallback) and deleted from `shared.lua`.

- `list_panel.update(buf, poppies, icons, menu_width)` — single sorted
  array arg. Iterates directly with `for display_idx, entry in ipairs(poppies) do`,
  no `poppies[item.name]` lookup, no separate runtime-map arg.

- `actions.kill_active` (`actions.lua:272`): `focus(state.windows.content_win)`
  ran synchronously after `M.recover()` defers via `vim.schedule`.
  Recover's deferred callback correctly focuses whatever the new content
  window is — the synchronous focus was dead work and got overwritten.
  Removed the line. Recover's fallback path is now the sole focus path
  after a kill.

- `actions.switch_by_name` (`actions.lua:140`) hid the current poppy
  then re-opened it even when `poppy_name == state.windows.current_poppy_name`.
  Added early-return guard at top of function: `if poppy_name == state.windows.current_poppy_name then return end`.
  Re-selecting the current poppy is now a no-op.

- `header_panel.lua` (bottom): hardcoded UTF-8 byte offsets of "◉"
  inside "P◉PPY.NVIM" to compute the colored-dot extmark range. Replaced
  with `vim.fn.byteidx(title_line, vim.fn.strdisplaywidth(title_col .. "P"))` —
  derives byte offsets from display column position, so any future
  title-text change still resolves correctly.

- `style.apply_list_panel_style(win)` was being called from both
  `list_panel.lua` and `header_panel.lua` — the function existed to style
  the list panel specifically but the header happened to want the same
  winhl. Renamed to `style.apply_panel_style(win)`. Two callers updated,
  behavior unchanged.

- `manager.open` had a lazy-population block that re-populated
  `state.poppies` from sorted config if the array happened to be empty.
  Dead code: `M.open` already has `ensure_setup()` guard at top, so
  `state.windows.opts` is guaranteed populated when the block could run.
  Block removed along with the local `sort_config` and `CAT_ORDER`
  helpers it was the only caller of.

- `state.windows.opts.X` chains scattered across `actions.lua`,
  `manager.lua`, `menu.lua`. Added `shared.opts_field(name)` accessor
  that returns the named field or nil. Six call sites updated:
  - `actions.lua`: `opts_field("icons")`, `opts_field("poppies_resolved")`,
    `opts_field("menu_autohide")`
  - `manager.lua`: `opts_field("exclusive_float")`
  - `menu.lua`: `opts_field("menu_autohide")` (×2)
  - `panels.lua`: `opts_field("menu_width") or 25`
  Other sites that pass the whole `state.windows.opts` table as a function
  argument (layout.compute_wrapper_dimensions, wrapper.create/recreate,
  modes.X.run) left as-is — the function signatures accept the full
  config table directly.

- Commented-out debug blocks deleted from `list_panel.lua` and
  `hints_panel.lua`. The `_debug_helpers.lua` file (the only thing
  they referenced) was unused elsewhere and is gone too.
