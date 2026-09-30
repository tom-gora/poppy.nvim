# REVIEW — poppy.nvim (MVP assessment)

## Summary

poppy.nvim is a floating-window manager for a small, user-declared set of
"poppies" — terminal TUIs, file buffers, shell sessions. You declare them
once in `setup()`, hit one key, and get a sidebar list plus a content pane.
One binding cycles open / sidebar / closed; the sidebar switches and kills
entries. It exists because toggleterm.nvim didn't fit: many independent
buffers, each wanting its own keymap, each piling up silently in the window
list. Small, personal-scope, no feature pressure.

## Overall shape

The tree is honestly layered. `init.lua` is a thin façade re-exporting
`session/init.lua`, which is the orchestrator: setup validation, open /
close / toggle, switch / kill, the `:Poppy` command, and a `recover()` path
for when a content window is `:bd`'d or `:q`'d out from under the manager.
All mutable state lives in one table in `session/state.lua` (window ids,
buffer ids, configured registry, runtime map, merged config, a few
booleans) and everything else reads through it. `shared.lua` is the
cross-cutting helper bag (win markers, notifications, focus, `drop_poppy`).
The two mode plugins — `modes/term.lua`, `modes/file.lua` — sit behind one
interface, `run(name, config, parent_win, on_die)`, and own their own
buffer/job lifecycle, which is the right cut. UI splits into `layout.lua`
(pure dimension math), `render.lua` (panel painters, extmarks, signs),
`style.lua` (highlights, re-ran on `ColorScheme`), and `view.lua` (window
lifecycle). The seams are real; `session/init.lua` at 748 lines is the one
overloaded module and the place where the shape gets muddy.

## Good things

- `layout.lua` is genuinely pure — no `vim.api`, no state access. Free to
  test, and the ratio-vs-absolute resolution is easy to reason about.
- `shared.ensure_setup()` guards every public entry point, so calling
  `require("poppy").open()` before `setup()` gives a clear notify instead
  of a nil-index error.
- The `state.windows.recovering` flag, checked in the `WinClosed` watcher,
  is a real re-entrancy guard — closing the content window during cleanup
  would otherwise resurrect it mid-teardown. Easy to miss, correctly done.
- `watch_content_window` re-arms itself on the replacement window, so a
  user who `:q`s the content pane doesn't brick the manager.
- `require("poppy.core.session")` is deferred *inside* the keymap closures
  rather than at module top, which cleanly breaks the
  `session ↔ keymaps ↔ menu` require cycle.
- `config.merge` validates every field (unknown keys, bools, numbers,
  location enum, string shape) and warns-then-falls-back rather than
  throwing. Icons get display-width and `%` checks because they end up in
  `string.format` — that's a real bug caught by a real check.
- `_types.lua` is centralized rather than scattered, and the annotations
  mostly match the code.
- `pcall` is used where it's warranted: `sign_define` against a
  misconfigured theme, `mkdir`/`writefile` at open, `nvim_buf_set_name`
  against name collisions.
- Comments explain *why*, not *what*: the `zindex = 48` reasoning against
  Neovim's 50 ceiling, why `bufhidden = "hide"` is set, why the binary is
  pre-checked on `$PATH` before spawning.
- The README is thorough and mostly accurate — the feature set is
  documented as carefully as it's built.

## Bad things

### Structure & ergonomics

- `state.windows` is a flat bag of 17 fields that callers reach into
  directly (`state.windows.content_win = ...` from `view.lua`, `menu.lua`,
  `keymaps.lua`, and `session/init.lua`). The single-state-table idea is
  good; the missing accessor layer is what makes it sprawl. A dozen
  `content_win()` / `set_content_win()` pairs would fix most of it.
- `shared.opts_field` is typed `---@return any` and is the only way any
  module reads config. Every caller re-implements the same
  `type(v) == "function" and v() or v` dance (`view.lua:169`,
  `layout.lua:87-96`).
- `argv0` is duplicated verbatim in `config.lua:69-76` and
  `term.lua:53-60`. They should be one function in `shared.lua`.
- The `recovering` flag is a boolean guarding re-entrancy across
  `cleanup`, `recover`, and `recover_goto_landing`. It works, but it's
  load-bearing and undocumented from the outside; a comment at each of
  the three call sites saying what sets and clears it would help.
- Naming is inconsistent with the `_types.lua` annotation: everything is
  annotated `Poppy*` in camelCase, the modules are lowercase, the internal
  tables are snake_case. Not wrong, just three conventions in one tree.

### Missing infra

- No tests, no lint config, no CI. `layout.lua` and `render.list.update`'s
  `trim_title` / `max_index_width` / `pick_sign` are pure and trivially
  testable — the highest-value place to start, given they're also the
  code with the byte-vs-cell bug.
- `state.poppy_configured` / `poppy_index` are linear scans. Correct and
  fine for a handful of poppies; noted only because the comments already
  acknowledge the tradeoff.
- `layout.resolve_dimension` warns about too-small/too-large absolute
  dimensions on *every* wrapper open. A correctly-configured user will
  see the same warning repeatedly.

