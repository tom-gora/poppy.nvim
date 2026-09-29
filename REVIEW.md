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

### Correctness / data risk

- `file.lua:89-96` blows away the whole buffer on every open
  (`nvim_buf_set_lines(bufnr, 0, -1, ...)` then `modified = false`).
  Switching away from a file poppy and back silently discards unsaved
  edits. For a plugin whose whole point is "come back to my things", this
  is the worst bug in the codebase.
- `session/init.lua:544-546` force-deletes a poppy's buffer on kill with
  no `modified` check, so a modified file buffer is gone with no prompt.
- `layout.lua:21-27` computes landing width with `#line` (bytes) while
  `render.lua` trims by `strdisplaywidth`. The default 🛠/🗋 icons are 4
  bytes / 2 cells, so the landing float is systematically too wide. The
  format string also has a doubled leading space (`" %s %s %d %s", " "`,
  `icon`, …) that the render path doesn't reproduce.
- `M.recover` (`session/init.lua:725`) clears `current_poppy_name`
  unconditionally *before* scheduling, so the `or state.windows.current_poppy_name`
  check inside the scheduled body at line 730 can never be true. It works
  by accident, via `recover_pick_fallback` instead.
- `render.lua:154`: `math.max(1, hint_offset and (h - hint_offset) or h)` —
  `hint_offset` always defaults to 5 and is always truthy, so the `or h`
  branch is unreachable. The `and/or` idiom also silently misbehaves if
  the expression ever yields `0`.
- `session/init.lua:110-115`: the `BufUnload` handler calls
  `state.poppy_configured(poppy_name)` twice for the same name, discarding
  the first result.

### Doc drift

- **`confirm_create_file` is documented but does not exist.** It's in
  `_types.lua:34`-era config docs, two README sections, and the whole
  "Confirm file creation" section — but `config.lua` never reads it, so
  setting it trips the "unknown config key" warning while `file.lua:73-87`
  unconditionally `mkdir -p` + `writefile`s the file anyway. A documented
  safety confirmation that does nothing, on the one code path that touches
  the filesystem.
- `_types.lua:17-19` types `file?: string` and `exec?: string|string[]`,
  but both accept `function` per README and per `config.lua`'s own
  `resolve_and_validate_value`. `shell?` is typed `string|function` while
  `exec?` isn't, with no reason for the asymmetry. LSP will flag valid
  configs as wrong.
- README says the plugin "bundles a `.luarc.json` pointing at the
  `$VIMRUNTIME` meta files". It points at a hardcoded absolute path,
  `/home/tomeczku/Programming/nvim_types/_meta` — not portable, and not
  `$VIMRUNTIME`.
- `state.lua:51` comments that `poppies_configured` is "immutable after
  setup", but `shared.drop_poppy` mutates it at runtime.
- `M.transition_to_content`, `M.enter_landing`, and `M.recover` are public
  on the session module and reachable, but absent from the README's Lua
  API list. Either document or make them local.
- `:Poppy menu` is listed in the README, but `menu.toggle_menu` returns
  early when the session is closed, so the documented "toggle just the
  sidebar" silently no-ops on a closed manager.

### Dead code

- `render.lua:441-455` builds a whole `per_line_segments` table with hint
  text, padding, and highlight slots, then never reads it. Only the plain
  `lines` strings are used. ~15 lines of pure dead weight, and it
  misleadingly suggests the hints bar is extmark-rendered.
- `render.lua:134-140`: `list.create` registers a buffer-local
  `InsertEnter → stopinsert` autocmd with no group, on every list-buffer
  creation. Buffers are reused across mounts so it doesn't pile up much,
  but it's an unbounded pattern for a guard that could live on the buffer
  once at creation.
- `relative.md` is a zero-byte tracked file.

### Structure & ergonomics

- `session/init.lua` at 748 lines holds setup, the `:Poppy` command,
  completion, all four autocmds, cleanup, open/close/toggle, switch, kill,
  the `WinClosed` watcher, and the landing/content transitions. The
  autocmd and command registration (~120 lines) are the obvious
  extraction candidates and would leave a readable orchestrator.
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
- `cleanup(drop_poppies)` branches on `has_live_poppy` to decide which
  scratch buffers to delete, but `has_live_poppy` is always false when
  `drop_poppies` is true (which is the only caller that passes true) —
  the branch only ever matters on the `cleanup()`-from-toggle path, where
  the answer is always true. The condition is doing nothing.
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
