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

## 0. Lurking issues (out of scope of the dedup sprint)

Flagged during the read-through but not on the dedup list. Each one is
small, but they interact with items in §1–§4, so cluster them with the
matching section when you cut them.

- [ ] **`killing.kill_active` order-of-operations** —
  `lua/poppy/core/session/killing.lua:69-88`. `M.recover()` is called
  *before* `vim.api.nvim_buf_delete(target_bufnr)`. `recover()` schedules
  a `vim.schedule` that may re-focus `state.content_win`; if the recovered
  flow opens a new poppy in the same content window, the schedule could
  run while the old buffer is still alive. Either delete the buffer
  first, or move the buf-delete into the scheduled callback (or drop the
  schedule and do the recovery synchronously).

- [ ] **`events.lua:78` "internal hop" detection** — `poppy_ui_window`
  is set on every poppy win (wrapper, content, header, list, hints,
  bottom-right hint) but the allow-list isn't centralized. The
  `WinLeave`/`TermEnter` autoclose checks `poppy_ui_window` via
  `pcall(nvim_win_get_var)`. If a future panel forgets to set the var,
  autoclose will eat it silently. Promote `ui.mark(win)` / `ui.is_marked(win)`
  to `panels.lua` so the rule is grep-able, and call it from the wrapper
  / content / header / list / hints / bottom-right hint creators.

- [ ] **`modes/term.lua` session coupling** —
  `lua/poppy/core/modes/term.lua:2`. `local session = require("poppy.core.session")`
  pulls the whole session module into the mode just to call
  `session.kill_active()` from `on_exit`. Either define a "current
  session died" hook on `poppy_state` (the natural owner) and call that,
  or accept a callback param so the caller wires `kill_active` in.

______________________________________________________________________

## Summary — top wins

1. **`switching.switch_by_name` landing→content transition** —
   `lua/poppy/core/session/switching.lua:93-114`. ~22 lines of
   "destroy landing panels, resize wrapper, create content, watch
   it, setup menu" that re-does `manager.open`'s normal path.
   Expose a `manager.transition_to_content()` once and have both
   call it.
2. **`killing.recover` landing transition** —
   `lua/poppy/core/session/killing.lua:30-65`. ~35 lines of
   "resize wrapper, create landing panels, focus list, set
   is_landing" that re-does `manager.open`'s landing path.
   Expose a `manager.enter_landing()` once and have both call it.
3. **`menu_hint_win` close-and-nil pattern** —
   `lua/poppy/core/session/switching.lua:63-72, 160-164` and
   `killing.lua:30-33`. Three near-identical `if valid then close;
   state.menu_hint_win=nil; state.menu_hint_buf=nil` blocks.
   Extract `local close_menu_hint = function() … end` and own the
   state from `panels` or `hints_panel` so `killing` doesn't
   reach across.
4. **`switching.M.switch_by_name` size** —
   `lua/poppy/core/session/switching.lua:75-138`. ~65 lines doing
   state-capture, landing→content, mode dispatch, focus,
   start-insert-in-terminal, refresh. Split into
   `M.switch_by_name` (entrypoint) + private helpers
   `transition_from_landing` / `apply_focused_state` /
   `focus_content`.
5. **`killing.M.recover` size** —
   `lua/poppy/core/session/killing.lua:11-67`. ~57 lines, mostly
   the landing transition. After `manager.enter_landing()` is
   extracted, the body becomes a few early-returns + the
   fallback search.
6. **`config.merge` keys/icons sanitization loops** —
   `lua/poppy/config.lua:89-108`. Two near-identical
   `for k in ipairs({...}) do … end` blocks. One
   `local sanitize_strings = function(defaults, user, keys) … end`
   helper handles both.
7. **`poppy_state.clear` and `rebuild_from_sorted` clearing** —
   `lua/poppy/core/session/poppy_state.lua:38-51`. Both contain
   `for k in pairs(_poppies) do _poppies[k] = nil end`. Have
   `rebuild_from_sorted` call `M.clear()` first.
8. **`internal-hop` field-nulling pattern** —
   `lua/poppy/core/session/{killing,manager,switching}.lua`. The
   sequence
   `local ps = poppy_state.runtime_get(name); if ps then ps.active=false; ps.hidden=true; ps.win=nil end`
   appears in 3+ places. Promote to `poppy_state.hide(name)`.
9. **`pcall(nvim_set_option_value, "modifiable", true, {buf=buf}) … modifiable false` boilerplate** —
   `lua/poppy/core/ui/header_panel.lua:39-41`,
   `hints_panel.lua:51-53,154-156`,
   `list_panel.lua:156-158`. Add a `util.with_modifiable(buf, fn)`
   helper.
10. **`pcall(nvim_set_current_win, win)` pattern** —
    `lua/poppy/core/session/killing.lua:63,86`,
    `manager.lua:196`. Wrap once as `util.focus(win)`.
11. **`close_panel` + nil triplet** —
    `lua/poppy/core/ui/panels.lua:174-179, 194-201`. Destroy and
    `hide_menu` repeat
    `for … do close_panel(…) end; state.x_win = nil`. Extract
    `local close_and_clear = function(panel_names) … end`.
12. **`hints_panel.recreate` 7 optional params** —
    `lua/poppy/core/ui/hints_panel.lua:60-86`. Collapse the
    optional overrides into a single `opts` table.

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

- [ ] **`menu_hint_win` close-and-nil pattern** —
  `lua/poppy/core/session/switching.lua:63-72, 160-164`
  and `lua/poppy/core/session/killing.lua:30-33`. Three near-identical
  `if valid then close; state.menu_hint_win=nil; state.menu_hint_buf=nil`
  blocks. Extract `local close_menu_hint = function() … end` and own
  the state from `panels` or `hints_panel` so `killing` doesn't
  reach into it.

- [ ] **`config.merge` keys/icons sanitization loops** —
  `lua/poppy/config.lua:89-108`. Two near-identical
  `for k in ipairs({...}) do … end` blocks. One
  `local sanitize_strings = function(defaults, user, keys) … end`
  helper handles both.

- [ ] **`poppy_state.clear` and `rebuild_from_sorted` clearing** —
  `lua/poppy/core/session/poppy_state.lua:38-51`. Both contain
  `for k in pairs(_poppies) do _poppies[k] = nil end`. Have
  `rebuild_from_sorted` call `M.clear()` first.

- [ ] **`internal-hop` field-nulling pattern** —
  `lua/poppy/core/session/{killing,manager,switching}.lua`. The
  sequence
  `local ps = poppy_state.runtime_get(name); if ps then ps.active=false; ps.hidden=true; ps.win=nil end`
  appears in multiple places. Promote to
  `poppy_state.hide(name)`.

- [ ] **`pcall(nvim_set_option_value, "modifiable", true, {buf=buf}) … modifiable false` boilerplate** —
  `lua/poppy/core/ui/header_panel.lua:39-41`,
  `lua/poppy/core/ui/hints_panel.lua:51-53,154-156`,
  `lua/poppy/core/ui/list_panel.lua:156-158`. Add a
  `util.with_modifiable(buf, fn)` helper.

- [ ] **`pcall(nvim_set_current_win, win)` pattern** —
  `lua/poppy/core/session/killing.lua:63,86`,
  `lua/poppy/core/session/manager.lua:196`. Wrap once as
  `util.focus(win)`.

- [ ] **`close_panel` + nil triplet** —
  `lua/poppy/core/ui/panels.lua:174-179, 194-201`. Destroy and
  `hide_menu` repeat
  `for … do close_panel(…) end; state.x_win = nil`. Extract
  `local close_and_clear = function(panel_names) … end`.

### 1.2 Minor dedup

- [/] **`session/init.lua` forward decls in switching.lua** —
  `lua/poppy/core/session/switching.lua:12-13`. `list_panel_update`
  forward decl is actually needed — it's referenced inside
  `M.refresh_panels` (defined at line 16, before its assignment at
  line 39) so without the decl the closure would grab the global.
  Either keep the decl or reorder the file so the helper is defined
  before `M.refresh_panels`. `focus_list_with_cursor` forward decl
  has been dropped; `local` was added at the definition site.

- [ ] **`content.lua` `ext_config_opts` table** —
  `lua/poppy/core/ui/content.lua:26` and
  `lua/poppy/core/ui/style.lua:149-168`. `apply_content_style(win, { number=…, relativenumber=… })`
  unpacks two values that are already available as locals — pass
  positionally.

- [ ] **`hints_panel.recreate` 7 optional params** —
  `lua/poppy/core/ui/hints_panel.lua:60-86`. Collapse the optional
  overrides into a single `opts` table.

- [ ] **`util.title_fallback` `exec`/`term` duplication** —
  `lua/poppy/core/util.lua:98-116`. The two terminal-style branches
  are identical. Combine:
  ```lua
  if mode == "file" then return vim.fs.basename(vim.fn.expand(v)) end
  local first = type(v) == "table" and v[1] or vim.split(v, " ")[1]
  return vim.fs.basename(first)
  ```

- [ ] **`util.compute_landing_view_width` placeholder format** —
  `lua/poppy/core/util.lua:65-77`. `string.format(" %s %s %d %s", " ", icon, i, title)`
  has a literal `" "` as the first format arg. Drop the extra
  `%s " "` pair; the result is unchanged.

- [ ] **`config.lua` `merged.X == true` chain** —
  `lua/poppy/config.lua:137-140`. Once `vim.tbl_deep_extend` has
  filled defaults, `merged.X == true` is mostly cosmetic. Either
  drop the `== true` and trust the merge, or use
  `not not merged.X` once. Pick one.

- [ ] **`config.lua` keys/icons list literals** —
  `lua/poppy/config.lua:91, 102`. Hoist
  `local DEFAULT_KEYS  = {"poppy_action", "select", "kill", "exit_menu"}` and
  `local DEFAULT_ICONS = {"exec", "shell", "file"}` to module scope.

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

- [ ] **`modes/term.lua:18`** —
  `if not p_state or (not p_state.active and not p_state.hidden) then`
  is a triple-negative. De Morgan:
  `if not (p_state and (p_state.active or p_state.hidden)) then`.

- [ ] **`modes/file.lua:12`** —
  `if p_state and p_state.hidden and p_state.bufnr and vim.api.nvim_buf_is_valid(p_state.bufnr) then`
  is a 4-condition chain. Either early-return
  `if not (p_state and p_state.hidden) then … else if not valid_buf then … end`
  or extract `poppy_state.is_usable(name)`.

### 2.3 Lua ternary (`a and b or c`)

- [ ] **`config.merge` boolean coercion** —
  `lua/poppy/config.lua:137-140`.
  `menu_autohide = merged.menu_autohide == true` →
  `menu_autohide = not not merged.menu_autohide`.

- [ ] **`util.get_sorted_poppies` sort comparator** —
  `lua/poppy/core/util.lua:86-93`. After hoisting `cat_order` (see
  1.2), the comparator can use
  `local ord = function(c) return cat_order[M.cat(c)] or 99 end`
  and `local ord_a, ord_b = ord(a.config), ord(b.config); return ord_a ~= ord_b and ord_a < ord_b or a.name < b.name`.

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

- [ ] **`hints_panel.M.update` `line_specs` chain** —
  `lua/poppy/core/ui/hints_panel.lua:88-127`. Three branches
  (`if layout == "landing" then … elseif mode == "active_menu" or "active_focused" then … else {} end`).
  Promote to a lookup table:
  ```lua
  local SPECS = {
      landing       = { sep, select, toggle },
      active_menu   = { sep, select, kill, exit, toggle },
      active_focused = … same as active_menu …,
  }
  local specs = SPECS[layout == "landing" and "landing" or mode] or {}
  ```

- [ ] **`commands.lua` sub-dispatch** —
  `lua/poppy/core/session/commands.lua:7-24`. The if/elseif
  chain for `toggle / close / menu / open` could be a
  `local subs = { toggle = cb.toggle, close = cb.close, … }`
  table; the unknown-sub branch becomes
  `local fn = subs[sub]; if not fn then return vim.notify(…) end; fn(fargs)`.

### 2.6 Dead pcall / dead guards

- [ ] **`modes/term.lua:20`** — `pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })`.
  `nvim_buf_call` guarantees the buffer is valid, and `nvim_set_option_value`
  with a valid buf won't raise. Drop the pcall.

- [ ] **`modes/file.lua:14, 31`** — `pcall(vim.api.nvim_buf_set_var, …)`.
  The buffer is either freshly `nvim_create_buf`'d or already
  validity-checked. Drop the pcall.

- [ ] **`modes/file.lua:23`** — `pcall(vim.fn.writefile, {}, file_path)`.
  The pcall swallows real write errors. Either drop the pcall
  (so the user sees the error) or replace with
  `if vim.fn.filereadable(file_path) == 0 then vim.fn.writefile({}, file_path) end`.

- [ ] **`killing.lua:63, 86`** — `pcall(vim.api.nvim_set_current_win, list_win)`
  and `pcall(vim.api.nvim_set_current_win, state.content_win)`.
  Both calls are immediately preceded by an explicit
  `vim.api.nvim_win_is_valid(...)` check. Drop the pcall.

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

## 4. Dead / Unused

- [ ] **`poppy_state.runtime_iter` returning `pairs`** —
  `lua/poppy/core/session/poppy_state.lua:26-28`. The
  `for k, v in poppy_state.runtime_iter() do` pattern is
  one indirection away from `for k, v in pairs(_poppies) do`.
  Either inline or rename to `iter()` to make the indirection
  deliberate.

______________________________________________________________________

## 5. Optional / lower priority

- [ ] **`hints_panel.create` `layout` param shadowing** —
  `lua/poppy/core/ui/hints_panel.lua:18-23`. The function takes
  `layout` which shadows the imported `layout` module. Rename
  to `mode` or `kind`.

- [ ] **`commands.lua` body parsing** —
  `lua/poppy/core/session/commands.lua:28-30`. `cmd_line:gsub("^%s*:?[Pp]oppy%s+", "")`
  is fine but the parsing chain in `complete` is dense.
  `local cmd, rest = body:match("^(%S+)%s*(.*)")` once, then
  branch on `cmd`.

- [ ] **`style.M.setup` split** — `lua/poppy/core/ui/style.lua:42-125`
  is 80+ straight-line lines. Split into
  `setup_base_colors`, `setup_category_colors`, `setup_hidden_fg`,
  `setup_current_row`, `setup_signs`, `setup_autocmd`.

- [ ] **`list_panel.M.update` parallel arrays** —
  `lua/poppy/core/ui/list_panel.lua:103-170`. Three parallel
  arrays (`lines`, `rows`, `placelist`) walk the same iteration.
  Build one `entries` table, then split into the three
  downstream forms in one pass.

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
