# REVIEW_ITEMS

Refactor list for `poppy.nvim`. Scope: **make the code leaner and more
idiomatic without changing behavior.** Out of scope: bug hunting, new
features, API additions. The MVP is assumed to work; nothing here should
introduce a regression.

Style baseline (per project owner):

- `local foo = function() … end` over `function foo() … end`
- Lua ternary `a and b or c` over nested `if/else`
- Early returns / `goto continue` over deep nesting
- `pcall` only when there is a real reason; never as decoration

Conventions assumed: tabs, 1-based indexing, snake_case locals,
UPPERCASE constants, `M.x` module API.

______________________________________________________________________

## 1. Code Conciseness / Duplication

### 1.2 Minor dedup

- [ ] **`util.compute_landing_view_width` placeholder format** —
  `lua/poppy/core/util.lua:74-86`. The proposed dedup is wrong: the
  format `" %s %s %d %s", " ", icon, i, title` produces 3 leading
  spaces; `" %s %d %s", icon, i, title` produces 1. Dropping the
  prefix arg shifts the landing width by 2 chars. Leave as-is.

- [/] **`panels.lua` `state.hint_height` cache** —
  `lua/poppy/core/ui/panels.lua:16, 104, 149`. `hint_height` has
  been dropped (set 3×, read 0× — fully dead). `state.header_height`
  is kept: it's read in `rebuild` (`panels.lua:68`). The deeper
  refactor to derive both from `state.opts` is still open. _Note: the
  dead `hint_height` state field is gone; only the parameter on
  `list_panel.create/recreate` + `panels.create` remains as
  positional plumbing — also a candidate for the same opts-derivation
  refactor._

- [ ] **`lua/poppy/init.lua` callback indirection** —
  `lua/poppy/core/session/init.lua:41-47`. `events.setup(state.opts, { toggle = M.toggle })`
  and `commands.setup(state.opts, { toggle, open, close, toggle_menu })`
  capture the current bindings. If `M.toggle` etc. are ever replaced,
  the callbacks still point to the old ones. Either freeze the callbacks
  at setup time or document the capture.

______________________________________________________________________

## 2. Idiomatic Style (matches the project baseline)

### 2.1 Deep nesting → early returns

- [ ] **`actions.M.recover`** — `lua/poppy/core/session/actions.lua:174-217`.
  ~44 lines. After the `util.enter_landing()` extraction the
  landing branch collapsed to cleanup + `util.enter_landing()` +
  `setup_menu` + `refresh_panels`. The outer `vim.schedule` +
  guards + fallback search are still inline. Extract
  `_find_fallback_name` and pull the landing branch into
  `_enter_landing_from_recover` (or just call `util.enter_landing`
  directly without the schedule wrapper if the cleanup can be
  done synchronously).

- [ ] **`actions.M.switch_by_name`** —
  `lua/poppy/core/session/actions.lua:70-111`. The function
  captures state, runs the landing→content transition, dispatches
  the mode, focuses, starts insert in terminals, and refreshes.
  Split into
  `M.switch_by_name` (entrypoint) + private helpers
  `transition_from_landing` / `apply_focused_state` / `focus_content`.

### 2.2 De Morgan / readability

_Nothing open in this section. The 4-condition chain in `modes/file.lua`
was collapsed to `poppy_state.is_usable(name)` (see §1.2 review notes
on `poppy_state.is_usable`)._

### 2.3 Lua ternary (`a and b or c`)

- [ ] **`config.merge` boolean coercion** —
  `lua/poppy/config.lua:137-140`.
  `menu_autohide = merged.menu_autohide == true` →
  `menu_autohide = not not merged.menu_autohide`.

- [ ] **`actions.M.refresh_panels` mode dispatch** —
  `lua/poppy/core/session/actions.lua:34`.
  `local mode = state.menu_focused and "active_focused" or "active_menu"`
  is already ternary — good. The same shape could replace the
  `if layout == "landing" then … elseif …` block in
  `hints_panel.update` (see 2.5).

### 2.4 `goto` where it pays off

- [ ] The `goto continue` in `events.setup_exclusive_float`
  (`lua/poppy/core/session/events.lua:18-23`) is the right call —
  keep that style. When extracting dedup helpers, prefer
  `goto next` over a nested `if` if the alternative is a flag
  variable or early-return-with-state.

### 2.5 Long if/elseif dispatch → table

_Resolved (see §1.2 notes on `hints_panel.HINT_SPECS`). The if/elseif
cascade in `M.update` was replaced with a single lookup table._

### 2.6 Dead pcall / dead guards

- [ ] **`panels.M.is_hidden` wrapper** —
  `lua/poppy/core/ui/panels.lua:203-205`. Single-line passthrough
  to `state.hidden`. Either inline at the 2 call sites or keep,
  but don't add a third indirection layer.

______________________________________________________________________

## 3. Module / State Organization

- [ ] **`state` is a god-object** — `lua/poppy/core/session/state.lua:3-12`
  exposes `M.wrapper_win`, `M.menu_hint_win`, etc. as bare module
  fields mutated from 6+ files. Either group them by area
  (`state.windows`, `state.buffers`, `state.poppy`, `state.ui`)
  or expose `state.set(key, val)` / `state.get(key)` so the
  mutation surface is grep-friendly.

- [ ] **`panels` has its own parallel `state`** —
  `lua/poppy/core/ui/panels.lua:6-18`. The wrapper_win / hints_win /
  list_win / header_win / hint_height / header_height etc. all
  belong in the central state module alongside `content_win`. The
  two truths drift.

- [ ] **`input.lua` inlines `require` inside callbacks** —
  `lua/poppy/core/input.lua:5,11,20,29`. Hoist
  `local session = require("poppy.core.session")` to module top.

- [x] **`_watch_content_window` lives in `manager.lua`** —
  moved to `lua/poppy/core/util.lua:156-181` alongside
  `transition_to_content` (its sole caller). The `poppy_ui`
  augroup was relocated too. Done as part of the §3 "2 callers
  → util.lua" rule (called from `manager.open` + `actions.switch_by_name`).

- [ ] **`util.lua` is getting large** — `lua/poppy/core/util.lua`
  (now ~225 lines) mixes leaf helpers (title-fallback,
  term-spawn, term-resolve, term-buffer, cursor, landing-width,
  sort, cat, session-state-accessors, `with_modifiable`) with
  session-coordinator logic (`transition_to_content`,
  `enter_landing`, `watch_content_window`). The session-coordinator
  additions grew out of the dedup pass; splitting into
  `util_text` / `util_term` / `util_session` is now overdue.

______________________________________________________________________

## 4. Optional / lower priority

- [ ] **`style.M.setup` split** — `lua/poppy/core/ui/style.lua:42-125`
  is 80+ straight-line lines. Split into
  `setup_base_colors`, `setup_category_colors`, `setup_hidden_fg`,
  `setup_current_row`, `setup_signs`, `setup_autocmd`.

- [ ] **`poppy_state` dual-index storage** —
  `lua/poppy/core/session/poppy_state.lua:6, 14, 18, 22`.
  `_poppies` is indexed by both integer (list view) and string
  (runtime view). Split into `_entries` (array) and `_runtime`
  (map) so the two roles don't share a table.

- [ ] **`TASK.md` open item** — `TODO.md:25`:
  *"restructure. modes also land in 'core' their helpers into util.
  Session needs breaking up into smaller logical structure scripts"*
  — partial: `switching.lua` + `killing.lua` were merged into
  `session/actions.lua`, and `transition_to_content` + `enter_landing`
  + `watch_content_window` moved to `util.lua`. Remaining: modes
  helpers (the first half of the TODO line) and any further session
  internal splits (e.g. `util.lua` split per §3 item above).

