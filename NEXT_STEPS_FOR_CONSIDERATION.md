# Next Steps for Consideration — poppy.nvim

This document captures a code review of the current state (branch `ui-rewrite`,
~890 LOC of Lua across 14 files). Findings are grouped by severity. Nothing
here is mandatory — it is a working backlog to pick from when the codebase
stabilizes at MVP.

---

## 1. Documentation Drift (high priority, low cost)

The `README.md` describes a substantially older design. Several public-facing
claims no longer match the code, which will confuse new users.

- **Outdated structure tree.** README lists `banner.lua` and `core/session.lua`
  as the engine, but the actual UI tree is:
  `core/ui/{wrapper,content,panels,list_panel,hints_panel,header_panel,style}.lua`.
  There is no `banner.lua`.
- **Stale config keys.** README documents `prefix_bind = "<M-p>"` and
  `whichkey_disable`, but `config.lua` has neither. The real key knob is
  `keys.poppy_action` (default `<C-_>`), with `keys.select` / `keys.kill` /
  `keys.exit_menu` as siblings.
- **Wrong defaults.** README says "Prefix for all poppy keybinds. Default: `<M-p>`"
  but `config.lua:19` defaults to `<C-_>`. There is no `<M-p>` prefix
  registered anywhere in the code.
- **`exec` shape mismatch.** README claims
  `exec = string | string[] | function`, but `modes/term.lua` only reads
  `poppy_opts.exec` as a scalar passed to `jobstart`/`termopen`. Arrays and
  function values for `exec` are not actually handled.
- **Stale "Usage" table.** `<M-p>1`–`<M-p>N` is described as the primary
  switching keybind, but the implementation registers only
  `keys.poppy_action`, `keys.select`, `keys.kill`, `keys.exit_menu` —
  there is **no per-index prefix-bind setup**. The actual flow is: open
  the manager with `keys.poppy_action`, focus the sidebar, then `<count><CR>`
  or `<count>d` to switch / kill.
- **`:Poppy open <name>`** is correctly described as tab-completable, but the
  README's `## Usage` table omits the `menu` subcommand that `session.lua:625`
  supports.

**Suggestion:** rewrite `README.md` to mirror the current `config.lua` schema
and the actual `keys.*` set. Either drop claims about `<M-p>N` prefix binds
or implement them. Either drop the `string[]` and `function` support rows
from the mode table, or actually implement them in `modes/term.lua`.

---

## 2. State Management in `core/session.lua` (medium priority)

`session.lua` is the largest file (~665 LOC) and the place where most of the
refinement opportunity lives. A few specifics:

### 2.1. Metatable trick is dead code

Lines 11, 646–663 set `M.poppies`, `M.current_poppy_name` as plain fields
*and* also install a `__index` / `__newindex` metatable that intercepts
reads/writes to `current_poppy_name`. The plain assignment at line 11
(`M.current_poppy_name = nil`) is shadowed by the metatable, which itself
just shuttles to a local upvalue. Net effect: the metatable is a no-op that
re-routes one name to a local. Either commit to the metatable approach
(every external read/write of `current_poppy_name` flows through it) or
drop the metatable entirely and use a normal field on `M`.

### 2.2. Module-level mutable state should be grouped into a state record

There are ~12 module-level upvalues (`wrapper_win`, `content_win`,
`content_buf`, `autohide_hint_win`, `autohide_hint_buf`, `current_poppy_name`,
`is_landing`, `menu_focused`, `landing_view_width`, `_suppress_watch`,
plus the upvalues of `_recover` and `_watch_content_window` that close
over them). Two of them — `autohide_hint_win`/`autohide_hint_buf` — are
genuinely transient UI scratch and arguably belong on the `panels` state
record, not on the engine.

A single `M.state = { ... }` table would make it obvious what is engine
state vs. transient UI state, and would make `_recover` and
`_watch_content_window` self-contained rather than needing forward
declarations (lines 27–28).

### 2.3. `_suppress_watch` flag is a smell

Used in `cleanup` (lines 521–527) and `_recover` (lines 467–473) to
prevent the `WinClosed` autocmd from reacting to its own teardown. The
right tool is `vim.api.nvim_win_set_config(win, { ... })` without closing,
or scoping the autocmd with a stronger guard, or using a single
`augroup` that is fully cleared on teardown rather than a per-callback
boolean.

### 2.4. `M.open` does too much

`M.open` (lines 148–217) handles: reentry guard, landing-vs-active
branch, wrapper (re)creation, content creation, panel creation,
side-panel input setup, and post-refresh. It is the only function that
knows about both the landing and active states at the same time. The
landing branch and the active branch should be two distinct entry points,
each calling a shared `_create_manager(win, is_landing)` helper.

### 2.5. `M.switch` is over-broad

`M.switch` (lines 291–356) does: hide previous, transition out of
landing, resize the wrapper, create content, dispatch to mode, set up
content input, manage autohide hint, refresh sidebar, and set current
window. ~65 LOC. A reasonable split is:

- `M._leave_current()`
- `M._transition_landing_to_active()`
- `M._enter_current(name)` (the mode dispatch + per-mode book-keeping)

### 2.6. `:Poppy` command parser is hand-rolled

`session.lua:619–643` parses `args` with `args:sub(1, 5) == "open "`.
That will break on `args == "open"` (no trailing space) and on multi-word
poppy names. A `vim.split(args, " ", { plain = true })` + first-element
dispatch (with completion that supplies `"open "` only for known
poppy names) is more robust.

---

## 3. Duplicated Sizing Logic (medium priority)

Window-size normalization is implemented three times:

- `config.lua` — `sanitize_win_height` / `sanitize_win_width` (lines 31–61)
- `core/ui/wrapper.lua` — `compute_geometry` (lines 4–70)
- `core/session.lua` — `_active_width` (lines 136–146)

Each handles the "ratio vs. absolute pixel" branch independently, and
each emits its own `vim.notify` warnings. The boundary between
"sanitize" (config-time) and "compute" (open-time, screen-dependent) is
real and should be preserved, but `sanitize` should only normalize
type/range and **not** re-clamp what `compute_geometry` will clamp again.
Right now, a user who configures `win_height = 0.1` gets clamped to `0.2`
at sanitize, then `compute_geometry` re-clamps it. A user who configures
`win_height = 5` is silently coerced to a 5-pixel window at sanitize
time. A `vim.notify` would be more honest there.

A `core/geometry.lua` module exporting `normalize_ratio_or_pixels(value)`
+ `compute_dimensions(opts, screen_cols, screen_lines, override_width)`
would centralize this and remove the three-way drift.

---

## 4. Config Sanitization Mutates User Input (medium priority)

`config.lua:63–139` `sanitize(opts)` mutates `opts` in place, including
adding `poppy.mode`, `poppy.cat`, and `poppy.title` to the user's
poppy tables. The result is that the user's original config table is
now littered with internal fields. If `setup` is called twice (it
isn't currently, but only by convention), the second call would double
classify. Returning a new table from `sanitize` is the obvious fix and
matches the spirit of "merge then validate".

Also note that `poppy_opts` is read at switch-time (e.g.
`modes/term.lua:17` and `modes/file.lua:5`) for `mode` / `cat` /
`file` / `exec` / `shell` / `title`. The `mode` and `cat` are
engine-internal, so they should live on a sibling `poppy._resolved`
field or in a separate table returned from `merge`, not on the user's
config.

---

## 5. `list_panel.lua` Module-Level Mutable State (low–medium)

Line 4: `local sb_width = 25` is a module-level local that is
re-assigned every time `create`/`recreate` is called. The variable is
then read by `M.update` (line 137) at refresh time, meaning the most
recent width wins regardless of which buffer is being updated. In
practice this is fine because only one sidebar exists at a time, but it
is implicit coupling. Pass width as an argument to `M.update` and drop
the upvalue.

---

## 6. Fragile List-Index Parsing (low priority)

`core/session.lua:373` and `:437` extract the index from the list line
with `line:match("%s+(%d+)%s")`. The format that `list_panel.update:139`
emits is `string.format("%s %" .. idx_width .. "d %s", icon, display_idx, title)`.
The widths, gaps, and the digit position must agree exactly — a single
space added in the format string breaks the parser. Options:

- Store the index in an extmark or buffer-local variable per line
  and look it up by cursor position.
- Use a virt_text number column or statuscolumn.
- Put the index in a `vim.b[buf].poppy_index_by_line` map.

Any of these is more robust than the regex round-trip.

---

## 7. `panels.lua` Mixes Two Concerns (low priority)

`panels.lua` is both a **panel container manager** (creates/destroys
child windows for the wrapper) and a **state machine** (`hidden`,
`autohidden`, `visible`, plus the focus/landing modes). The state
machine is encoded as boolean fields rather than an explicit
discriminated union. A small enum-like field (`M.state = "active" | "hidden" | "autohidden" | "landing"`) would make transitions
explicit and would let the `hide` / `show` / `toggle` / `focus_sidebar` /
`unfocus_sidebar` / `hide_for_autohide` / `show_for_autohide` /
`destroy` methods be a single dispatch on `state` instead of a chain
of `if state.hidden then ...` guards. A few of the methods are now
near-duplicates of each other (`focus_sidebar` vs `unfocus_sidebar` is
only the `hl`/`focusable` arguments, for example).

---

## 8. Mode-Dispatch Table Has No Schema (low–medium)

`modes/term.lua:54` and `modes/file.lua:36–37` independently build the
poppy state record:

```lua
{ active = true, hidden = false, bufnr = bufnr, win = parent_win, title = poppy_opts.title }
```

The fields are read in `session.lua` and `list_panel.lua` but never
documented in one place. If a new field is needed (e.g. `last_used`
for an LRU), the update has to be made in two places and there's no
help from the type system.

**Suggestion:** a `poppy_state = function(poppy_name, opts, bufnr, win)`
factory in `core/session.lua` (or a small `core/poppy_state.lua`)
returning the canonical record shape. Both modes call it.

---

## 9. Highlight Groups Are Recreated on `ColorScheme` But Signs Are Not (low)

`style.lua:83–89` re-runs `M.setup()` on `ColorScheme`, which
redefines all `Poppy*` highlight groups and re-fetches the
`NormalPoppy*` derivations. The fix from `TODO.md` (`[x] Bug: Extmarks
do not get updated when theme is being reloaded live during runtime`)
covers the extmark highlights, but the **signs** defined in
`list_panel.lua:8–24` are only defined once at module load
(`define_poppy_signs()` on line 26). After `:colorscheme`, the sign
texts do not re-derive. Either move sign definition into
`M.setup` or call a `list_panel.refresh_signs()` from the
`ColorScheme` callback.

---

## 10. `:CheckHealth` and Lazy-Load Hints Missing (low)

- No `lua/poppy/health.lua` registered with `vim.api.nvim_create_user_command("CheckHealth", ...)` or the modern
  `vim.health.start` / `vim.health.report_*` API. Adding one for
  config validity, screen-size sanity, and the `:Poppy` command
  presence would help debugging significantly.
- No `lazy` / `folke/snacks` style `opts = { cmd = "PoppyToggle" }`
  or `event = "VeryLazy"` hints. A 4-line addition to the README
  showing how to register a lazy spec would be a nice touch.

---

## 11. Mode Support Claims vs. Reality (low)

`modes/term.lua:5–14` `resolve_command` only handles
`poppy_opts.shell` (string or function, plus `"default"`). For
`poppy_opts.exec`, the function returns the raw value and passes it
to `jobstart` / `termopen`. README and config types claim
`exec` can be `string | string[] | function`, but the
implementation does not support arrays or functions. Either:

- Document `exec` as `string` only, or
- Extend `resolve_command` to handle the array and function shapes
  (jobstart accepts a list, so the array case is essentially free;
  the function case is a single line).

---

## 12. Title-Fallback Coupling Creates an Awkward Import (low)

`config.lua:131` requires `poppy.modes.utils` to call
`title_fallback`. The dependency direction is unusual — config
depends on a mode util, but modes depend on session. Moving
`title_fallback` to a small `core/text.lua` or
`core/titles.lua` would keep `config.lua` depending only on
`core/*` and remove the cross-tree require.

---

## 13. No Tests (medium, but costly to add)

There is no test framework, no fixtures, no CI. The state machine in
`session.lua` (open / switch / kill / recover / hide / autohide /
landing) is exactly the kind of logic that wants unit tests, but the
modules are tightly coupled to `vim.api` so a pure-Lua test would
need to mock or extract the I/O.

**Suggestions** in order of increasing effort:

1. Extract pure functions (sizing math, title fallback, mode
   classification) to `core/*.lua` and add `plenary.nvim`-style
   `tests/` with `describe` / `it` blocks for them.
2. Add a minimal GitHub Actions workflow that runs `nvim --headless
   -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"`
   on push.
3. For UI behavior, write a smoke-test that drives `session.open` /
   `session.switch` in a headless `nvim` and asserts window
   creation.

---

## 14. Minor Idiomatic / Style Nits (low)

- `modes/term.lua:25,31,33,39` and `modes/file.lua:14,21,22,26,31` use
  `pcall` to swallow errors from buffer name sets / file existence
  checks / option sets. The reasons are mostly real (e.g. terminal
  buffers reject some options), but a one-line comment naming the
  reason for each `pcall` would help future readers.
- `core/session.lua:646–663` re-declares `M.current_poppy_name` after
  the metatable. The metatable already handles assignment, so the
  pre-metatable plain assignment on line 24 (`current_poppy_name =
  nil`) is the only one needed.
- `core/ui/panels.lua:71` passes `sw` as the second positional
  argument to `list_panel.recreate`, but `list_panel.recreate`'s
  second parameter is `width`, and `sw` is a width. That part is
  fine. The *third* positional argument is `focusable = false`,
  fourth is `hint_lines = hl` — the parameter naming there is
  inconsistent (some modules use `hint_lines`, some use `hl`).
  Pick one. The "hl" abbreviation is ambiguous with "highlight".
- Z-indexes 200, 201, 202, 203, 204 are scattered across
  `wrapper.lua`, `content.lua`, `list_panel.lua`,
  `hints_panel.lua`, `header_panel.lua`. A single constant block
  in `core/ui/style.lua` (or a new `core/ui/zindex.lua`) would
  make the stacking order obvious at a glance.
- `core/session.lua:359` calls `get_sorted_poppies()` in
  `M.switch_by_index`, but then the index is used to dispatch
  directly. `switch_by_index` could be a thin wrapper around
  `switch(sorted[index].name)`; today it is, but it re-sorts. If
  the caller already has a sorted list, this is wasted work.
  Not a hot path, just noting it.

---

## 15. Quick Wins (low effort, high clarity)

These are isolated, one-file changes that noticeably improve the
codebase:

- [ ] Rename README's `prefix_bind` to `keys.poppy_action` and
      update the example config to match the actual schema.
- [ ] Drop the dead metatable in `session.lua` (lines 646–663).
- [ ] Move `title_fallback` out of `modes/utils.lua` to
      `core/titles.lua`; remove the `modes/utils` require from
      `config.lua`.
- [ ] Centralize z-index constants in `core/ui/style.lua`.
- [ ] Add a `CheckHealth` provider that reports config validity
      and warns when `win_height`/`win_width` ratios fall outside
      `[0.2, 1.0]` post-sanitize.
- [ ] Move `define_poppy_signs` invocation inside `M.setup` so
      signs re-derive on `:colorscheme` (or call it from the
      `ColorScheme` autocmd).
- [ ] Resolve the `<M-p>N` vs. `keys.poppy_action` naming
      discrepancy: either implement per-index prefix binds (clean
      addition: a `LhsRange` keymap or `<count><CR>` shortcut
      inside the sidebar already exists; document it) or remove
      the claim from the README.
- [ ] Extract `core/geometry.lua` for the sizing math duplicated
      in `config.lua`, `wrapper.lua`, and `session.lua`.

---

## 16. Larger Refactors (worth a dedicated branch, not a quick fix)

- **Decouple state from module upvalues** in `core/session.lua`
  by introducing a `M.state = { ... }` record. Lets `_recover`
  and `_watch_content_window` be plain local functions without
  forward declarations, and makes state transitions testable in
  isolation.
- **Split `core/session.lua` into `core/manager.lua`
  (open/close/toggle/recover/window lifecycle) and
  `core/poppy_state.lua` (per-poppy record, kill, switch)**.
  This would also make it easier to expose
  `poppy.core.session` as a stable public API later (right now it
  is not officially public, but `modes/*` depend on it).
- **Introduce a `core/events.lua` module** with named events
  (`PoppyOpen`, `PoppySwitch`, `PoppyKill`, `PoppyClose`,
  `PoppyThemeChange`) so downstream users can `vim.api.nvim_create_autocmd("User", { pattern = "PoppySwitch" })`. The
  current code already has the data to emit these — it just
  doesn't.
- **Replace `M.poppies[poppy_name]` with a tiny record manager**
  (insert / remove / list / get) and add a `poppy_state` factory
  (see §8) so the schema is enforced in one place.

---

## Summary Table

| # | Area | Severity | Effort | Files |
|---|------|----------|--------|-------|
| 1 | README / config drift | High | Low | `README.md`, `config.lua` |
| 2 | `session.lua` state & control flow | Medium | Medium | `core/session.lua` |
| 3 | Sizing math duplication | Medium | Low | `config.lua`, `core/ui/wrapper.lua`, `core/session.lua` |
| 4 | Config mutation | Medium | Low | `config.lua` |
| 5 | `list_panel` module state | Low–Med | Low | `core/ui/list_panel.lua` |
| 6 | Index parsing | Low | Low | `core/session.lua`, `core/ui/list_panel.lua` |
| 7 | `panels.lua` two concerns | Low | Low–Med | `core/ui/panels.lua` |
| 8 | Mode state schema | Low–Med | Low | `modes/*.lua`, `core/session.lua` |
| 9 | Signs on `ColorScheme` | Low | Low | `core/ui/list_panel.lua`, `core/ui/style.lua` |
| 10 | CheckHealth / lazy hints | Low | Low | new `lua/poppy/health.lua`, `README.md` |
| 11 | `exec` shape claim | Low | Low | `modes/term.lua`, `README.md` |
| 12 | `title_fallback` import | Low | Low | `modes/utils.lua`, `config.lua` |
| 13 | Tests | Medium | High | new `tests/`, CI |
| 14 | Idiomatic nits | Low | Low | various |
| 15 | Quick wins | Low | Low | various |
| 16 | Larger refactors | — | High | `core/session.lua` primarily |
