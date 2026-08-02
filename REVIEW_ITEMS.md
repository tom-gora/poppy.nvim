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

- [ ] **`compute_landing_view_width` placeholder format** —
  `lua/poppy/core/ui/layout.lua:16`. The proposed dedup is wrong: the
  format `" %s %s %d %s", " ", icon, i, title` produces 3 leading
  spaces; `" %s %d %s", icon, i, title` produces 1. Dropping the
  prefix arg shifts the landing width by 2 chars. Leave as-is.

- [/] **`panels.lua` `state.hint_height` cache** —
  `lua/poppy/core/ui/panels.lua:16, 86, 127`. `hint_height` has
  been dropped from the panels state block (was set 3×, read 0×
  — fully dead). `state.header_height` is kept: it's read in
  `rebuild` (`panels.lua:96`). The deeper refactor to derive both
  from `state.opts` is still open. _Note: the dead `hint_height`
  state field is gone; only the parameter on
  `list_panel.create/recreate` + `panels.create` remains as
  positional plumbing — also a candidate for the same opts-derivation
  refactor._

- [ ] **`setup.lua` callback indirection** —
  `lua/poppy/core/session/setup.lua:243-258`. Re-export block
  (`M.open = manager.open`, etc.) and the callbacks handed to
  `M.setup_autocmds` / `M.setup_command` capture the current
  bindings. If `M.toggle` etc. are ever replaced, the callbacks
  still point to the old ones. Either freeze the callbacks at setup
  time or document the capture.

______________________________________________________________________

## 2. Idiomatic Style (matches the project baseline)

### 2.1 Deep nesting → early returns

- [ ] **`actions.M.recover`** — `lua/poppy/core/session/actions.lua:232-274`.
  ~43 lines. The else branch (no fallback) is now `panels.destroy`
  + `close_menu_hint` + augroup reset + `close_content_win` +
  wrapper resize + `M.enter_landing()` + `refresh_panels` inline.
  The outer `vim.schedule` + early-return guards + fallback-name
  for-loop are still inline. Extract `_find_fallback_name` and
  pull the landing branch into
  `_enter_landing_from_recover` (or just call `M.enter_landing`
  directly without the schedule wrapper if the cleanup can be
  done synchronously).

- [ ] **`actions.M.switch_by_name`** —
  `lua/poppy/core/session/actions.lua:175-227`. The function
  captures state, runs the landing→content transition (calls
  `M.transition_to_content()`), dispatches the mode, sets up
  content keys, focuses, starts insert in terminals, and
  refreshes. Split into `M.switch_by_name` (entrypoint) +
  private helpers `transition_from_landing` /
  `setup_content_keys` / `focus_content`.

### 2.2 De Morgan / readability

_Nothing open in this section. The 4-condition chain in `modes/file.lua`
was collapsed to a local `usable(name)` (see §1.2 review notes)._

### 2.3 Lua ternary (`a and b or c`)

- [ ] **`config.merge` boolean coercion** —
  `lua/poppy/config.lua:144`. `menu_autohide = merged.menu_autohide`
  → `menu_autohide = not not merged.menu_autohide`.

- [ ] **`actions.M.refresh_panels` mode dispatch** —
  `lua/poppy/core/session/actions.lua:148`.
  `local mode = state.windows.menu_focused and "active_focused" or "active_menu"`
  is already ternary — good. The same shape could replace the
  `if layout == "landing" then … elseif …` block in
  `hints_panel.update` (see 2.5).

### 2.4 `goto` where it pays off

- [ ] The `goto continue` in `setup.setup_exclusive_float`
  (`lua/poppy/core/session/setup.lua:138-146`) is the right call —
  keep that style. When extracting dedup helpers, prefer
  `goto next` over a nested `if` if the alternative is a flag
  variable or early-return-with-state.

### 2.5 Long if/elseif dispatch → table

_Resolved (see §1.2 notes on `hints_panel.HINT_SPECS`). The if/elseif
cascade in `M.update` was replaced with a single lookup table._

### 2.6 Dead pcall / dead guards

- [ ] **`panels.M.is_hidden` wrapper** —
  `lua/poppy/core/ui/panels.lua:193-195`. Single-line passthrough
  to `state.windows.hidden`. Either inline at the 2 call sites or
  keep, but don't add a third indirection layer.

______________________________________________________________________

## 3. Module / State Organization

- [ ] **`shared.lua` is getting large** — `lua/poppy/core/shared.lua`
  (now ~87 lines) hosts leaf helpers (`session_is_open`,
  `session_get_current_poppy_name`, `close_menu_hint`,
  `show_menu_hint`, `keys`, `with_modifiable`, `get_sorted_poppies`,
  `cat`). Previously it also hosted session-coordinator logic
  (`transition_to_content` / `enter_landing` / `watch_content_window`);
  those have since moved to `actions.lua`. The remaining 87 lines
  are cohesive — splitting into `util_text`/`util_term`/`util_session`
  is no longer overdue.

______________________________________________________________________

## 4. Optional / lower priority

- [ ] **`style.M.setup` split** — `lua/poppy/core/ui/style.lua:50-159`
  is ~110 straight-line lines. Split into
  `setup_base_colors`, `setup_category_colors`, `setup_hidden_fg`,
  `setup_current_row`, `setup_signs`, `setup_autocmd`.

- [/] **`TASK.md` open item** — `TODO.md:25`:
  *"restructure. modes also land in 'core' their helpers into util.
  Session needs breaking up into smaller logical structure scripts"*
  — mostly resolved: `switching.lua` + `killing.lua` were merged
  into `session/actions.lua`; `commands.lua` + `events.lua` +
  `session/init.lua` merged into `session/setup.lua`; `input.lua`
  inlined; `transition_to_content` + `enter_landing` +
  `watch_content_window` moved to `actions.lua`. Remaining: any
  further file consolidation within `session/` or `ui/` if it
  earns its keep; modes helpers (the first half of the TODO line)
  remain in `modes/{file,term}.lua`.