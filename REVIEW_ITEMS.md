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

### 1.1 Major dedup

- [ ] **`switching.switch_by_name` landing→content transition** —
  `lua/poppy/core/session/switching.lua:93-114`. Re-creates content,
  panels, and rewires the wrapper width — same as `manager.open`'s
  normal path. Extract a `manager.transition_to_content()` once and
  have both call it.

- [ ] **`killing.recover` landing transition** —
  `lua/poppy/core/session/killing.lua:30-65`. Re-implements
  `manager.open`'s landing branch (resize wrapper, create landing
  panels, focus list, set `is_landing`). Extract a
  `manager.enter_landing()` once and have both call it.

- [ ] **`config.merge` keys/icons sanitization loops** —
  `lua/poppy/config.lua:89-108`. Two near-identical
  `for k in ipairs({...}) do … end` blocks. One
  `local sanitize_strings = function(defaults, user, keys) … end`
  helper handles both.

- [ ] **`pcall(nvim_set_option_value, "modifiable", true, {buf=buf}) … modifiable false` boilerplate** —
  `lua/poppy/core/ui/header_panel.lua:39-41`,
  `lua/poppy/core/ui/hints_panel.lua:51-53,154-156`,
  `lua/poppy/core/ui/list_panel.lua:156-158`. Add a
  `util.with_modifiable(buf, fn)` helper.

- [ ] **`pcall(nvim_set_current_win, win)` pattern** —
  `lua/poppy/core/session/killing.lua:63,86`,
  `manager.lua:196`. Wrap once as `util.focus(win)`.

### 1.2 Minor dedup

- [/] **`session/init.lua` forward decls in switching.lua** —
  `lua/poppy/core/session/switching.lua:12-13`. `list_panel_update`
  forward decl is actually needed — it's referenced inside
  `M.refresh_panels` (defined at line 16, before its assignment at
  line 39) so without the decl the closure would grab the global.
  Either keep the decl or reorder the file so the helper is defined
  before `M.refresh_panels`. `focus_list_with_cursor` forward decl
  has been dropped; `local` was added at the definition site.

- [ ] **`util.compute_landing_view_width` placeholder format** —
  `lua/poppy/core/util.lua:74-86`. The proposed dedup is wrong: the
  format `" %s %s %d %s", " ", icon, i, title` produces 3 leading
  spaces; `" %s %d %s", icon, i, title` produces 1. Dropping the
  prefix arg shifts the landing width by 2 chars. Leave as-is.

- [/] **`panels.lua` `state.hint_height` cache** —
  `lua/poppy/core/ui/panels.lua:16, 104, 149`. `hint_height` has
  been dropped (set 3×, read 0× — fully dead). `state.header_height`
  is kept: it's read in `rebuild` (`panels.lua:68`). The deeper
  refactor to derive both from `state.opts` is still open.

- [ ] **`lua/poppy/init.lua` callback indirection** —
  `lua/poppy/core/session/init.lua:40-46`. `events.setup(state.opts, { toggle = M.toggle })`
  captures the current binding. If `M.toggle` is ever replaced, the
  callback still points to the old one. Either freeze the callbacks
  at setup time or document the capture.

______________________________________________________________________

## 2. Idiomatic Style (matches the project baseline)

### 2.1 Deep nesting → early returns

- [ ] **`killing.M.recover`** — `lua/poppy/core/session/killing.lua:11-67`.
  ~57 lines, mostly the landing transition. After extracting
  `manager.enter_landing()` (see 1.1), the body becomes a few
  early-returns + the fallback search.

- [ ] **`switching.M.switch_by_name`** —
  `lua/poppy/core/session/switching.lua:75-138`. The function
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

- [ ] **`switching.M.refresh_panels` mode dispatch** —
  `lua/poppy/core/session/switching.lua:35`.
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
  `lua/poppy/core/input.lua:11, 20, 29, 35`. Hoist
  `local session = require("poppy.core.session")` to module top.

- [ ] **`_watch_content_window` lives in `manager.lua`** —
  `lua/poppy/core/session/manager.lua:22-46`. The augroup
  `poppy_ui` it uses is also defined here. Both belong in
  `events.lua` for consistency with the other autocmd setup.

- [ ] **`util.lua` is getting large** — `lua/poppy/core/util.lua`
  mixes title-fallback, term-spawn, term-resolve, term-buffer,
  cursor, landing-width, sort, cat, session-state-accessors. If
  a future change needs to grow any of those, split into
  `util_text` / `util_term` / `util_session`.

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
  — the dedup items in §1 already touch this; if the work is
  scheduled, the refactor in §1.1 items 1–4 are a good first
  slice.

