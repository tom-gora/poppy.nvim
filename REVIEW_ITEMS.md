# Poppy.nvim — Code Review Items

Concrete problems and follow-ups spotted while reading the codebase. Grouped by
severity / area. No trivia — each item is something that can hurt users or
maintainers.

## Bugs / Correctness
Below I added the intended actions I decided need to be taken per item after reviewing the list. Each resolution is marked as "mock comment" using "//".

- **`actions.lua:97-98` — dead `vim.schedule(function() end)` call.** Inside
  `transition_to_content`, right after `panels.destroy()`, there's a no-op
  scheduled function. It looks like a leftover from debugging and serves no
  purpose; delete it.
  // Remove line

- **`manager.lua:123` — unguarded `opts.exclusive_float` dereference.**
  `if state.windows.opts.exclusive_float then` will crash with "attempt to
  index a nil value" if a user calls `require("poppy").open()` (or any other
  API) before `setup()`. The lazy-population block above it assumes `opts`
  is non-nil when it inspects `opts.poppies`, but `exclusive_float` is read
  from the same table without a nil check. Either guard it or document
  loudly that `setup()` must run first.
  // Add nil check to prevent even if calling Poppy open sould not be possible before calling setup as setup is registering these commands.
  // However I am not sure if this would not error if setup is called with config containing no defined "poppy" entries, thus better guard against nil
  // use vim.notify with vim.log.levels.WARN to explicitly but in a short message form inform about what has gone wrong.

- **`actions.lua:286-288` — `kill_active` focuses a likely-dead window.**
  `M.kill_active()` calls `M.recover()` (which schedules teardown and
  closes/destroys panels synchronously), then synchronously calls
  `focus(state.windows.content_win)`. After `recover()` returns, the
  content window may have been closed by the `WinClosed` watcher or by the
  `recover` fallback path. `focus` does check `nvim_win_is_valid` so it
  won't crash, but the user-visible behavior is a no-op focus flicker on
  the wrapper. Fix by either (a) reordering so focus happens inside the
  scheduled recover, or (b) re-resolving `content_win` after the call.
  // Haven't observed in manual testing. recover either returns to landing view of panels if last opened poppy have been killed/closed
  // OR it is supposed to recover to previously active poppy content window if more were opened. If there is a potential for racing to close a nilled win nr
  // prepare suspected scenarios, then write smoke test scripts at /tmp and see if in any of them attempt to focus a nilled win happens.
  // If you spot issues report first and we will think about it. If no issues can be caught then everything should be good.
  // Ultimately we might need a check around to call focus only if win is valid window, else I presume this call be skipped.

- **`actions.lua:171-175` — silent no-op on unknown poppy name.**
  `switch_by_name` returns silently if `poppies_resolved[poppy_name]` is
  nil. There's no `vim.notify`, so a typo in `:Poppy open lzygt` looks
  indistinguishable from success. Same applies to
  `setup_command` completion (it does show available names, but the
  runtime path is silent).
  // Yeah makes sense. Add notify with WARN log level. (Possibly connects to setup that should be checking if user declared any poppy keys in config.
  // If config is empty, should warn and invite to create a key in config table "poppies") via notify and bail on setup early completely
  //  as there is no poppy.nvim declarative tools, without tools declared. By this logic down the line completions will not be problematic if there is no faulty setup. 
  // Am I missing something?

- **`actions.lua:241-265` — `recover` "fallback or destroy" picks an
  arbitrary hidden poppy.** When the current poppy dies and there are
  multiple hidden poppies, the first one iterated (non-deterministic
  table order) is chosen as the fallback. Could surprise users; document
  the behavior or pick by last-active / last-opened.
  // There is already logic path to recover to last active in case of killing/closing internally process or file. Investigate if this could be pulled in and reused in this edge case.

- **`header_panel.lua:36-47` — byte-based centering of a multibyte title.**
  `title_col = math.ceil((width - #title) / 2)` uses byte length, but
  `"P◉PPY.NVIM"` contains the 3-byte glyph `◉`. The center dot and the
  extmark for `PoppyRed` are placed using the same byte offset, so on
  terminals with wide glyphs the dot can sit one cell off from where it
  looks centered. Use `vim.fn.strdisplaywidth` and `vim.fn.strchars`
  (or compute column from char offsets).
  // did not take into account weird nerdfont/unicode. Worth taking into account in case in the future I decide to maybe allow users define their own header string?
  // Not seeing need or value at the moment, but yeah, do implement a safer calc.

- **`list_panel.lua:138` — `string.format("%s %..."` with user-controlled
  icon.** If a user configures `icons.shell = "%"`, the format string
  interprets `%` as a conversion spec and throws. Default icons are safe
  but the surface is wide open. Either reject icon strings containing `%`
  in `sanitize_string_fields`, or use `string.format("%%s ...")` after
  percent-escaping the icon.
  // This is still prototype and naive impl. Yes it is worth sanitizing, maybe even inside existing config sanitisation routine.


---
// REVIEWED UP UNTIL THIS POINT. DO NOT PROGRESS WITHOUT MY FURTHER MANUAL REVIEW INVOLVEMENT
---

- **`file.lua:32-34` — silently creates empty file when missing.**
  `if vim.fn.filereadable(file_path) ~= 1 then vim.fn.writefile({}, file_path) end`
  creates an empty file with no notification. For a "notes" poppy this is
  probably intended; for a "config dump" poppy pointed at a typo'd path
  it's a foot-gun. Add a notify, or only do it when the dir exists, or
  respect a `create_if_missing` flag.

- **`term.lua:30-31` — `term_spawn` passes `nil` into `jobstart` if
  `command` is a function that returns nil.** `jobstart(nil, {...})` errors
  with a cryptic message. Validate the resolved command and bail with a
  friendly `vim.notify` if nil.

- **`actions.lua:66` — module-load-time augroup creation.** The
  `poppy_ui` augroup is created with `clear = false` at module import
  time. If anything else (a theme plugin, a test harness, etc.) created
  an autocmd under that name before poppy was required, those autocmds
  will coexist with ours and `clear = true` calls inside `cleanup` /
  `recover` will wipe user autocmds. Move the augroup creation into
  `setup()` and own the namespace.

- **`term.lua:54-69` — `not (p_state and (p_state.active or p_state.hidden))`
  spawns only when no runtime exists.** But if a buffer survived a
  `kill_active` cycle while its `BufUnload` callback (setup.lua:81-97)
  raced in, you can get into a state where `state.poppies[name]` is nil
  but the buffer still exists (or vice versa). The condition doesn't
  defensively call `nvim_buf_is_valid` on `p_state.bufnr` before reusing.
  Add the validity check, mirroring `file.lua`'s `usable`.

## Code Quality / Maintainability

- **`setup.lua:163-186` duplicates the state schema from `state.lua:5-25`.**
  `init_or_reset_state` re-lists every key by hand. Two places to keep in
  sync; both will rot. Either expose `state.reset()` in `state.lua` and
  call it, or have `state.lua` export a single `default_state()` factory.

- **`hide_poppy` is duplicated** between `manager.lua:13-21` and
  `actions.lua:55-63` (the comment in manager.lua even calls this out).
  Move it to `shared.lua` and import from both.

- **`show_menu_hint` is duplicated** between `menu.lua:34-42` and
  `shared.lua:22-29`. `menu.lua`'s copy even calls `shared.close_menu_hint`
  first — same logic, one extra file. Just call `shared.show_menu_hint()`
  directly.

- **`menu.lua:100` comment lies about lazy-loading.**
  ```lua
  -- ...actions <-> menu cycle).
  local actions = require("poppy.core.session.actions")
  ```
  The require is at module top-level, not lazy. Either move it inside
  `setup_list_keys` / `setup_content_keys` (which is what the comment
  describes) or update the comment.

- **`actions.lua:9,156` — odd forward-declaration pattern.**
  ```lua
  local list_panel_update
  -- ...
  list_panel_update = function(...) ... end
  ```
  The `local list_panel_update` on its own line is redundant; the second
  statement is already a local assignment. Pick one form.

- **`config.lua:70-73` comment is misleading.** "exec is mapped to term in
  config.resolve_poppy and so never reaches here" — exec DOES reach the
  term branch of `title_fallback`, with `value` being the exec string.
  The comment makes it sound like exec is special-cased out.

- **`panels.lua:131-159` `create_landing` overwrites `state.windows.menu_width`
  with the wrapper width**, while `create` uses the caller-supplied
  `menu_width`. Two functions, two ways to set the same field. The
  inconsistency makes it harder to reason about panel widths during a
  landing→content transition.

## Documentation

- **`README.md` Structure section is out of date** — references files that
  don't exist:
  - `core/session/init.lua` (actual: `state.lua`, `setup.lua`,
    `manager.lua`, `actions.lua`, `menu.lua`)
  - `core/input.lua` (actual: keymaps live in `session/menu.lua`)
  - `core/util.lua` (actual: `core/shared.lua`)
  
  Either rewrite to match reality or fold the split files back together.

- **No public API documentation in README.** `poppy.get_poppies`,
  `get_poppy_by_name`, `get_poppy_by_index`, `get_current_poppy`,
  `get_current_poppy_name`, `is_open`, `switch_by_cursor`,
  `kill_by_cursor` are all exported but never mentioned. Users have to
  read `init.lua` to discover them.

- **No `:checkhealth poppy` integration.** For a plugin that runs many
  autocmds, schedules callbacks, and depends on highlight groups from
  other plugins' themes, a health check is the cheapest UX win you can
  ship.

- **No version constant / plugin version.** There's no `lua/poppy/_version.lua`
  or `package.json`-equivalent. Tagging releases and providing
  `:Poppy version` would help users file reproducible bug reports.

- **TODO.md mentions an "IN PROGRESS" task (`Code style and optimisations`)**
  but lists no concrete items, so it's not actionable from a triage
  standpoint. Either break it into subtasks or close it.

## Config Validation / UX

- **`config.lua:117` — `vim.tbl_deep_extend("force", {}, default_opts, user)`
  lets unknown keys through.** A user typo like `autoclose = treu` (truthy
  string, not boolean) becomes part of `merged` and silently changes
  behavior. Even a single `vim.log.levels.WARN` for unknown top-level
  keys would help.

- **`config.lua:132-139` — invalid poppies are dropped silently.** No
  summary of how many were dropped or which. A single `vim.notify` at the
  end of merge listing dropped names would turn silent breakage into
  observable breakage.

- **`config.lua:34-47` — `sanitize_string_fields` only checks display width
  ≤ 2.** Two cells is fine for one 2-wide nerdfont glyph but not for any
  custom 3+ wide glyph. Either drop the upper bound or document it.

- **`config.lua:55` — `exclusive_float = true` is a surprising default.**
  Closing every other floating window (LSP hovers, snacks,
  notifications) when the user opens their terminal picker is aggressive.
  Default to `false` and let opt-in users flip it.

- **`setup.lua:11-15` — global `poppy_action` is mapped at `setup()` but
  never unmapped.** Calling `setup()` twice creates two keymaps pointing
  to the same callback, and `nvim_del_keymap` is never called. For a
  plugin loaded by `lazy.nvim` with multiple specs this can leak across
  reloads.

## Robustness

- **`setup.lua:144-158` — `setup_exclusive_float` re-registers on every
  open.** Each `poppy.open()` adds another `WinEnter` autocmd under
  `poppy_group`; `once = true` ensures each fires exactly once, but the
  pile-up is harmless only because the first fire closes the windows that
  the subsequent ones would target. Still — register once at `setup()`.

- **`actions.lua:152` — `mode = state.windows.menu_focused and "active_focused" or "active_menu"`**
  drives hint text, but `HINT_SPECS.active_focused == ACTIVE == HINT_SPECS.active_menu`.
  So the mode selector exists, the spec table treats them identically,
  and the only difference is dead dispatch. Either make the hints differ
  (e.g., show "Switch to content" when content-focused) or collapse the
  branch.

- **`panels.lua:48-63` `ensure_panel` doesn't validate that `recreate`
  returns a win of the expected config.** If a downstream panel module
  raises inside `recreate`, the state has stale `*_buf` but nil `*_win`.
  Wrap with `pcall` or assert.

- **`panels.lua:216-227` getter functions return raw `state.windows.*`
  fields without validation.** Callers (e.g., `manager.lua:62-67`) check
  validity, but exposing raw fields from a "module" looks intentional and
  invites misuse. Either return `nil` when invalid or rename to
  `*_buf_unchecked` so the unsafe intent is loud.

## Tests / CI

- **No test suite.** A plugin with this much stateful UI machinery (window
  orchestration, autocmds, terminal spawn, file-edit side effects,
  config validation) is the exact thing that benefits from `busted` /
  `mini.test` even at low coverage. Start with `config.merge` and
  `shared.get_sorted_poppies` — pure functions, easy wins.

- **No CI.** No `.github/workflows`, no `Makefile`, no `stylua.toml`. Pick
  at minimum a `stylua --check` step so formatting doesn't drift.

## Minor / Style

- `hl` in `hints_panel.lua:13-16` and `panels.lua:65-91` is overloaded
  (hint height vs highlight); rename to `hint_height` / `highlight`.
- `CAT_ORDER` in `shared.lua:9` and the category list in `style.lua:83`
  are duplicated knowledge — keep one as the source of truth.
- `actions.lua:225-266` `recover` is a 40-line function with three
  branches (fallback, no-fallback, current still set). Worth splitting
  into `pick_fallback_poppy`, `destroy_content_to_landing`, etc.
- `manager.lua:25-34` `clear_poppies` reads `state.poppies` with
  `pairs`, then `for k in pairs(state.poppies) state.poppies[k] = nil`
  inside the same loop body... wait, no, the loop is over `pairs` and
  the inner mutation is `state.poppies[k] = nil`. Lua's `pairs` may
  visit the entry being mutated, so deleting during iteration can be
  undefined behavior. Capture keys first:
  ```lua
  for k in pairs(state.poppies) do keys[k] = true end
  for k in pairs(keys) do state.poppies[k] = nil end
  ```
  (In practice Lua handles this, but it's the kind of thing that bites
  when the table is later swapped for a userdata-like structure.)
