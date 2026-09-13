# REVIEW

## What it is

`poppy.nvim` is a single floating-window manager for a user-declared set
of "poppies" (`exec` TUIs, `file` buffers, `shell` sessions). Users
register them in `setup({poppies = {...}})` and the plugin renders a
unified UI — wrapper, sidebar list, content window, optional header,
hints, and a corner "Menu" hint — all toggled by one keybinding
(`<C-_>` default) that cycles open → content → sidebar → closed, with a
`:Poppy` command and a Lua API on top.

## Pros

- **Config validation is strict and friendly.** Bad types / unknown
  keys / empty strings / `%` in icon strings all `vim.notify(WARN)`
  with a precise reason and fall back to defaults. The merged config
  also keeps `poppies` (user's raw form) and `poppies_resolved`
  (engine-internal `mode` + derived `title`) as parallel maps, so the
  runtime never has to re-derive mode on each switch.
- **Single mutable state module** (`session/state.lua`) with a
  `default_state()` factory. `state.windows.opts` is written exactly
  once at `setup`; everywhere else reads via `shared.opts_field()` /
  `shared.keys()`. No third module pokes state directly.
- **Modes are tiny and orthogonal.** `modes/term.lua` and
  `modes/file.lua` each implement `M.run(name, opts, parent_win)` and
  own their own buffer/job lifecycle. The session never touches a
  terminal job or file load directly. Easy to add a 4th mode later
  (LSP scratch buffer? dashboard?) by following the same shape.
- **Three "pure" UI modules** (`layout.lua`, `render.lua`, `style.lua`)
  take inputs (windows, bufs, dimensions, highlight ids) and return
  results without touching `state`. Easy to reason about in isolation.
- **ColorScheme refreshes highlights + signs together**, solving the
  "extmarks show stale colors after theme reload" problem cleanly via
  one `augroup poppy_style`.
- **Z-index is consistent** (48 wrapper/content, 49 hints), staying
  under Neovim's 50 default so completions/notifications render above.
- **Hints are written once at mount time**; only the list panel
  re-renders on state change. Cheap.
- **`shared.ensure_setup()`** guards every public function so direct
  calls before `setup()` warn instead of nil-derefing.
- **Recent changes (the working-tree diff)** added a `recovering` flag
  - `pcall` in `cleanup()` and `M.recover()` — both fix real race
    shapes (WinClosed watcher re-firing during teardown). The thinking
    is right; the diff just exposes that `recover` / `cleanup` are now
    even more entangled than before (see problems below).

## Cons

- **`session/init.lua` is ~710 lines doing 6 distinct jobs**:
  setup wiring, public getters, open/close/toggle lifecycle,
  switch\_/kill\_ actions, view-state transitions (landing ↔ content),
  and the recursive `watch_content_window` for `WinClosed`. Each is
  readable in isolation, but the file is at the size where adding a
  new lifecycle event means scrolling. Splitting actions out
  (`switch_*`/`kill_*` → `actions.lua`) and view transitions out
  (`transition_to_content`/`enter_landing`/`recover` →
  `view_transitions.lua`) would help. Not urgent; flagging for when
  shape stabilizes.
- **`state.poppies` is dual-purpose**: an array of `{name, config, runtime_state?}` where `runtime_state` is nil until the poppy is
  opened. Every reader has to remember which shape they're holding.
  The `poppies_runtime()` helper filters on `runtime_state ~= nil`
  but call sites still write `entry.runtime_state and entry.runtime_state.hidden` redundantly. A clean split into
  `state.poppies` (config) + `state.poppies_runtime` (map of name →
  runtime_state) would make every call site read honestly.
- **`menu_width` lies in the type system.** Type allows `number | function` (`_types.lua:29`) but `view.menu_width()` does
  `opts_field("menu_width") or 25` without resolving functions. If a
  user passes a function (legal per the type) it's silently ignored.
  Either narrow the type or resolve the function. Same asymmetry
  does not exist for `win_height`/`win_width`, which `layout.lua`
  resolves correctly — so this is a sharp inconsistency, not a
  feature.
- **Magic-number `25` for default `menu_width` lives in three places**:
  `config.lua:72` (defaults), `view.lua:184` (`or 25` fallback), and
  `session/init.lua:582` (`local w = menu_w or 25` inside
  `watch_content_window`). `view.menu_width()` is exported; the
  third site should use it.
- **`modes/term.lua` reaches into the session facade.** `on_exit`
  calls `session.kill_active()` when the dying job is the current
  poppy, else clears `state.poppy(name).runtime_state` inline. That's
  session policy (what to do when a job dies) living in the mode
  plugin. A `state.clear_runtime(name)` setter + a "this poppy died"
  callback the session passes in would invert this. Same shape, less
  coupling.
- **`M.open` and `M.switch_by_name` double-render the list.**
  `M.open` always calls `view.refresh_poppies()` (line ~400), but
  the content-branch via `switch_by_name` already refreshed (line
  ~476). Only the landing branch needs it (landing didn't refresh
  from `enter_landing`). Move the refresh into `enter_landing` and
  drop it from `M.open`.
- **`M.kill_active` and `_kill` overlap.** Both delete the buffer and
  clear `runtime_state`; only `kill_active` calls `recover()`. The
  cleanup logic is duplicated. Refactor to: `_kill(entry)` is the
  core; `kill_active` = `_kill(state.poppy(current_name))` then
  `recover()`. The current `_kill` checks for the active case and
  recurses one-deep, which is harder than necessary to read.
- **`watch_content_window` uses the forward-declare pattern**:
  ```lua
  local watch_content_window = nil
  watch_content_window = function(...)
      ...
      if type(watch_content_window) == "function" then
          watch_content_window(...)
      end
  end
  ```
  `local function watch_content_window(...)` would let Lua's hoisting
  handle it without the type-check guard and the mutable upvalue.

## Problems

### Bugs / latent bugs

- **`view.refresh_poppies` no-ops while sidebar is hidden, and
  `view.set_visible(true)` doesn't refresh after mount.** Sequence:
  open with `menu_autohide`, kill active poppy (sidebar stays hidden,
  refresh no-ops), toggle menu back on. `set_visible` → `mount_panels`
  → `render.list.create` is called (fresh buf, no `update`). List
  shows the *stale* state captured at the last refresh (i.e. before
  the kill). Fix: either force a refresh in `set_visible(true)` after
  `mount_panels`, or have `render.list.create` call `update`
  internally. Today it's a latent staleness.
- **`modes/file.lua` crashes if user function returns `nil`.** If
  `poppy_opts.file()` returns `nil` (e.g. the README's `git_root`
  example falls back to `"./TODO.md"`, but a user-supplied function
  could forget the fallback), `vim.fn.expand(nil)` errors in some
  Neovim versions. `vim.fn.filereadable(nil)` would also throw.
  README example is safe; user code is not.
- **`modes/term.lua` `on_exit` can double-fire.** If `M.kill_active`
  deletes the buffer (which closes the terminal job) and then clears
  `runtime_state`, the `on_exit` callback runs and calls
  `kill_active` again. With `current_poppy_name == nil` after the
  first kill, the second call no-ops today. Safe today; the path is
  fragile to any future change that makes `kill_active`
  idempotent-but-nontrivial.
- **`M.recover` iterates `pairs(state.poppies_runtime())` instead of
  `ipairs`.** It works (Lua array iteration is order-stable and
  `poppies_runtime` returns an array) but `ipairs` is more honest.
- **`cleanup()`'s `has_running_popies` variable lies.** It checks
  `next(state.poppies) ~= nil`, which is *always* true after `setup`
  (the array has entries even if none are open). The intent is "any
  poppy has a non-nil `runtime_state`". Currently the conditional
  *does* work — but only because `cleanup(true)` always calls
  `clear_poppies()` first, emptying the array. A `has_running_poppies`
  that actually checks `runtime_state` would read better.
- **`setup_exclusive_float` does O(n) walk over `nvim_list_wins()` on
  every WinEnter.** Fine in practice; flagging because if
  `exclusive_float` becomes true by default the close-on-other-float
  behavior could surprise users with many splits.
- **`term.lua` deletes buffer in `on_exit` unconditionally.** With
  `M.kill_active` already deleting the buffer first, this races.
  Idempotent because of the `nvim_buf_is_valid` guard, but the path
  is fragile.

### Type / API surface

- **`PoppyConfig.menu_width` is `number` only** (after narrowing
  intent), but the type still says `number` only — that's fine.
  Inconsistent with `win_height`/`win_width` (which genuinely accept
  functions). Either all three accept functions or none do.

### Maintainability

- **`config.merge` carries 8 `vim.notify(string.format(...))` calls**
  in a 290-line file, each 5 lines. A 3-line `notify_warn(template, ...)` helper would compress without losing detail.
- **`style.setup` is ~100 lines of hardcoded highlight math**, with
  the `CATEGORY = {File, Exec, Shell}` loop appearing 3-4 times. A
  shared subroutine per derivation (normal-tint, hidden-darken,
  current-bold) would cut it to ~40 lines.
- **`render.lua` packs three panel renderers in one file** with
  parallel `create`/`recreate`/`update` shapes. The namespace prefixes
  (`header_ns`, `list_ns`, `hints_ns`) keep it grep-able today; if
  panels grow, splitting per-panel files would help.
- **`modes/term.lua` `spawn_opts` is built inside `nvim_buf_call(bufnr, ...)` even though `on_exit` only touches the buffer by id.** The
  `nvim_buf_call` is doing no work for `spawn_opts`; the `modified = false` toggle inside is the only thing that needs buf context and
  could be a single `set_option_value` call.
- **`shared.cat` reaches into `poppy.exec`/`poppy.file`/`poppy.shell`
  to derive the user-facing category, but `resolve_poppy` already
  decided `mode` (`"term"` or `"file"`).** The two are not the same
  mapping (`shell` and `exec` both map to `mode == "term"` but
  different `cat`). `shared.cat` is correct for cat-derivation but
  feels duplicated with `resolve_poppy`'s classification. A small
  `cat_from_resolved(resolved)` would centralize.

### Recent shape (working-tree diff vs HEAD)

The working-tree changes add a `recovering` flag + `pcall` wrapping in
`cleanup()` and `M.recover()`, plus a `BufRead` API path in
`modes/file.lua` (replacing `:edit` inside `nvim_buf_call` because
`:edit`'s behaviour depends on the current window's buffer). Both
fixes are correct and address real bugs:

- The `recovering` flag closes the race where `WinClosed` re-fires
  during teardown and spawns a fresh empty content window mid-cleanup.
  The pcall ensures a thrown error in the cleanup pipeline surfaces
  a notify instead of silently corrupting state.
- The `file.lua` change fixes a real bug: `:edit` in a `nvim_buf_call`
  context loads into the *current* window's buffer, not `bufnr`,
  leaving `bufnr` empty. The comment block explaining why is good;
  the new path is window-independent and guarantees the contents
  land in `bufnr`.

The cost: `cleanup` and `recover` now both wrap their body in `pcall`

- `recovering` toggle + `recovering = false` reset on error. This is
  the third "guard the recovery path" mechanism in the file (alongside
  the augroup-clear and the existing checks). It's accumulating. A
  small `state.with_recovery(fn)` helper that handles
  `recovering = true; local ok, err = pcall(fn); recovering = false; notify on err` would consolidate all three call sites. Worth doing
  before a fourth mechanism gets added.

## Overall shape

The plugin reads and works today. The architecture is small and
honest — three concerns (state, session orchestration, UI rendering)
with one module per concern at the top, and clean deps going down.
The session orchestrator is overloaded and the state shape is
dual-purpose, but neither is blocking. The biggest risk is the
absence of a safety net (tests) while the shape is in flux — every
small optimization is "did this break the user's setup", and the
public Lua API mirrors the session facade exactly, which constrains
refactors (good — keeps the public surface small).

Top-3 actionable items, in order of cost-effectiveness:

1. Fix the autohide-kill-then-show staleness (~5 lines, real bug).
1. Resolve `menu_width` function-vs-number mismatch (~3 lines, sharp
   edge).
1. Move the double `view.refresh_poppies()` out of `M.open` into
   `M.enter_landing` (~3 lines, removes a foot-gun for future
   contributors).

Then, when shape stabilizes: split `session/init.lua` actions out
and pick one of the `state.poppies` shapes.

