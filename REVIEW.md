# REVIEW

## What it is

`poppy.nvim` is a single floating-window manager for a user-declared set of
"poppies" (`exec` TUIs, `file` buffers, `shell` sessions). Users register them
in `setup({poppies = {...}})` and the manager renders a unified UI: outer
wrapper, sidebar list panel, content window for the active poppy, optional
header, keybinding hints panel, and an optional bottom-right "Menu" hint
shown only in autohide mode.

The interaction is built around one binding (`keys.poppy_action`, default
`<C-_>`) that cycles: open (landing) → focused content → focused sidebar →
closed (double-hit). `:Poppy` user command exposes the same plus
`:Poppy open <name>` and `:Poppy close`. A public Lua API mirrors it.

## Actual shape

```
lua/poppy/
  init.lua           thin re-export of core.session
  config.lua         defaults + merge + per-key WARN-on-bad validation
  _types.lua         LuaCATS class definitions

  core/
    shared.lua       cross-module helpers (ensure_setup, opts_field,
                      cat, is_poppy_window, hide_poppy, show_menu_hint,
                      try_focus_win, apply_win_marker, with_modifiable)
    session/
      state.lua       single mutable instance (default_state) + poppy
                      registry, lookup helpers, set_current_poppy_name
      init.lua        setup + open/close/toggle + switch_*/kill_* +
                      transition_to_content/enter_landing/recover +
                      autocmd registration + :Poppy command + cleanup
      menu.lua        toggle_menu / exit_menu (focus router + autohide)
      keymaps.lua     buffer-local list/content keymap setup +
                      focus_list_with_cursor
    ui/
      view.lua        wrapper/content windows, mount/unmount, sidebar
                      visibility, refresh_poppies, SIDEBAR/LANDING mode
      render.lua      header/list/hints panel renderers + sign placement
                      + bottom-right hint window
      style.lua       highlight group definitions + ColorScheme refresh
                      + per-window winhl assignment
      layout.lua      dimensions (compute_wrapper_dimensions,
                      compute_landing_view_width, normalize_dimension)
    modes/
      term.lua        exec + shell lifecycle (jobstart, on_exit cleanup)
      file.lua        file-buffer lifecycle (write-file-if-missing + edit)
```

This is one **monolith orchestrator** (`session/init.lua`, ~680 lines, 41
`M.X = function()` exports) and one **monolith UI driver** (`ui/view.lua`,
~390 lines) sitting on top of small, focused `render`/`style`/`layout`
modules. The README's architecture tree (`setup.lua`, `manager.lua`,
`actions.lua`, `menu.lua`, `wrapper.lua`, `panels.lua`,
`list_panel.lua`, etc.) doesn't match what's on disk — at least
`panels.lua`, `actions.lua`, `setup.lua`, `manager.lua` are referenced in
the README and `_CLEANED.md` but never existed in this snapshot, or were
collapsed into `view.lua` and `session/init.lua` during a recent
refactor.

## Good

- **Strict config validation.** Every public option is type-checked;
  bad values get a `vim.notify(..., WARN)` and fall back to the default.
  Unknown top-level keys warn with the list of known keys. Poppy configs
  that aren't tables warn up-front instead of erroring per-field during
  resolution.
- **Single mutable state module** (`session/state.lua`) with a typed
  `default_state()` factory and zero circular imports into it. Every
  other module pulls state through it. `windows.opts` is set exactly
  once (in `M.setup`) and read via `shared.opts_field()` everywhere
  else, with direct access only at setup-time.
- **Display-order is stable.** `state.poppies` is a sorted array built
  once at setup (cat → name); open/close only toggles each entry's
  `runtime_state` field. Array index = display row, always.
- **Modes are tiny and orthogonal.** Both implement `M.run(name, opts,
  parent_win)` and own their buffer/job lifecycle. The session never
  touches a terminal job or file load directly.
- **Two pure-render modules.** `render.lua` and `layout.lua` have no
  state access — they're called with buffers/wins/dimensions and return
  things. This is the right boundary; it makes the panel-rendering
  logic auditable in isolation.
- **`try_focus_win` and `is_poppy_window`** are centralized in
  `shared.lua`. The autoclose watcher, keymap callbacks, and
  menu/exit_menu all use them consistently.
- **`shared.ensure_setup()`** guards every public function (and most
  internal lifecycle functions) so direct access to internal modules
  before `setup()` runs yields a clean WARN instead of a nil-deref.
- **ColorScheme autocmd refreshes highlights + signs together**, which
  was the only solution to the resolved TODO about extmarks not
  updating on theme reload.
- **Z-index is consistent.** All poppy windows sit at 48 (just below
  Neovim's 50 default); the bottom-right hint and the hints panel sit
  at 49 to draw above wrapper/content but still below transient
  overlays. Stated intent (README §About) matches the implementation.
- **Static hints are written once** at mount time and never re-touched.
  Only the list panel re-renders on state change.

## Bad

### `session/init.lua` is doing too much

The file is ~680 lines and owns: `setup`, public getters, lifecycle
(open/close/toggle), `setup_autocmds`, `setup_command`,
`setup_exclusive_float`, `init_or_reset_state`, `sort_config`,
`cleanup`, `clear_poppies`, `open_wrapper`, the SIDEBAR/LANDING-aware
view transitions (`transition_to_content`/`enter_landing`/`recover`),
the WinClosed `watch_content_window` watcher, and the `switch_*` /
`kill_*` resolver plus entry points. None of this is independently
reusable; it all funnels through `M.X`.

The split that the README + `_CLEANED.md` already attempted — separating
`actions.lua`, `manager.lua`, `setup.lua` — is real and worth doing.
Candidates for extraction, in roughly descending urgency:

- **`watch_content_window` + its augroup registration.** Recursive,
  schedule-coupled, owns the `poppy_ui` augroup. Belongs in a small
  `watcher.lua` next to `state.lua` so the `M.recover` path that also
  clears `poppy_ui` (`session/init.lua:660`) can stay in sync.
- **`setup_autocmds` + `setup_command` + `setup_global_key` +
  `setup_exclusive_float`.** All setup-time side effects, all named
  consistently. Move them into `core/session/setup.lua` and have
  `init.lua` just call one `wire()` function.
- **`switch_*` and `kill_*` resolver machinery** (`resolve`,
  `cursor_to_poppy_index`, `_kill`, plus the public entry points).
  These form a tight cluster. `actions.lua` would be a natural home.
- **`transition_to_content` / `enter_landing` / `recover`** — the
  view-state transition trio. Closely related to but distinct from
  the lifecycle.

None of this is critical today — the file is *one* file, readable, with
clear section comments — but it caps at ~680 lines and the next
lifecycle-shaped feature will overflow it.

### README's structure block is out of date

The `## Structure` section in the README lists `setup.lua`,
`manager.lua`, `actions.lua`, `menu.lua`, `wrapper.lua`,
`content.lua`, `panels.lua`, `list_panel.lua`, `hints_panel.lua`,
`header_panel.lua` as separate files. Of those, only `menu.lua`,
`init.lua` (used as `setup.lua`'s replacement), and `view.lua` (which
absorbs wrapper/content/panels) exist. The other six files are
referenced in narrative and in `_CLEANED.md` but don't exist on disk.
This is actively misleading for anyone trying to navigate the code,
and `REVIEW.md` itself — by listing the same files — preserves the
mistake.

`lua/poppy/core/ui/` currently has 4 files; the README suggests 9.
Bring the tree in line with reality or actually re-split the panels
out of `view.lua`. Right now it reads like aspirational documentation.

### `state.poppies` is still dual-purpose, just less than before

The split into `state.poppies_config` (array) + `state.poppies_runtime`
(map) was discussed in `_CLEANED.md` and not done. Current shape: one
array of `{name, config, runtime_state?}`. The `runtime_state?` field
makes the array's contents meaningful in two different ways depending
on whether you've opened the poppy, and at least four sites read
`runtime_state` while iterating `ipairs(state.poppies)`:

- `render.list.update` uses `runtime_state` to decide active/hidden dot.
- `session/init.lua:255` (`clear_poppies`) iterates and reads `rt.bufnr`.
- `session/init.lua:646` (`M.recover` fallback) iterates via
  `state.poppies_runtime()` (which filters on `runtime_state ~= nil`)
  and then double-checks `entry.runtime_state and entry.runtime_state.hidden`
  even though the filter already guarantees `runtime_state` is truthy.
- `session/init.lua:371` reads `state.poppy(last_poppy).runtime_state`
  three times on one line.

A `state.poppies_runtime()` accessor that hides the array shape is
fine, but the call sites should pick *one* form to read, not mix.
Specifically, the `entry.runtime_state and entry.runtime_state.hidden`
checks at lines 641 and 647 are dead-defensive — the function name and
the iteration source already say `runtime_state` is non-nil.

### Magic numbers and numbers that live in three places

- **`menu_width` default = `25`** is defined in `config.lua:72` (default
  opts), in `view.lua:184` (`local menu_width = function() return shared.opts_field("menu_width") or 25 end`),
  and was inlined as `panel_width = ... or 25` in the removed
  `actions.lua`. The default is now in `view.menu_width()` (exported),
  so call sites should use that, not `state.windows.opts.menu_width`
  directly. There's still a literal `25` lurking in
  `session/init.lua:569` (`local w = menu_w or 25`) inside
  `watch_content_window`'s default argument.
- **`menu_width` is treated as a number everywhere** despite the config
  type allowing `number|function` (see `PoppyConfig.menu_width` in
  `_types.lua:29`). `view.menu_width()` does `opts_field("menu_width") or 25`
  without resolving functions. Either narrow the type to `number`, or
  resolve the function in `view.menu_width()`. The code currently lies.
- **`win_height` and `win_width` accept `number|function`** and the
  resolution happens in `layout.normalize_dimension` /
  `compute_wrapper_dimensions`. That's fine. The asymmetry with
  `menu_width` (also `number|function` per types but never resolved as
  such) is a bug-shaped inconsistency.

### `M.open` and `M.switch_by_name` double-render

`session/init.lua:387` (`M.open`) calls `view.refresh_poppies()`
unconditionally, but the two branches before it both already do:

- `M.enter_landing` mounts the panels but **does not refresh** the list
  contents.
- `M.transition_to_content` + `M.switch_by_name` mounts panels
  (transition_to_content) and refreshes the list (switch_by_name line
  463).

So the post-branch `view.refresh_poppies()` on line 387 is required
for the landing path (list would otherwise be empty) and redundant for
the content path. Move the refresh into `M.enter_landing` and drop it
from `M.open`. Same shape as the `_CLEANED.md` already-noted
"Double render on every has_content open".

### `M.open` initializes wrapper width state inconsistently

```lua
local win = open_wrapper(landing_width)
state.windows.wrapper_win = win
state.set_current_poppy_name(nil)
state.windows.is_landing = should_land
```

`is_landing` is set *after* `open_wrapper` (which calls
`view.wrapper.ensure`), but the wrapper's `view.content.create` is
later called in `M.transition_to_content`. The wrapper width was set
to `landing_width` on the landing branch, then resized inside
`transition_to_content`. That's fine — but `enter_landing` later calls
`view.mount`, which calls `view.unmount` (closing existing panels).
The first-call sequence lands/contents/mount dance is hard to follow
without the orchestrator comment block explicitly walking through it.

### `M.kill_active` and `_kill` overlap

`M.kill_active` (492–512) and `_kill` (514–535) both delete the buffer
and clear `runtime_state`, but only `M.kill_active` calls `M.recover()`.
The cleanup logic is duplicated. The cleaner shape is: `_kill` is the
core, and `kill_active` is `_kill(state.poppy(current_name))` plus
`recover()`. Currently `_kill` checks for the active case and
recurses; the recursion is one-deep but the indirection makes it
harder than necessary.

### `M.recover` schedules but also performs synchronous work

```lua
M.recover = function()
    state.set_current_poppy_name(nil)
    vim.schedule(function()
        ...
        M.enter_landing()
        view.refresh_poppies()
    end)
end
```

The synchronous prefix is just clearing `current_poppy_name`. The
rest is in the scheduled callback. The `vim.schedule` makes sense
because `recover` is called from autocmd callbacks (BufUnload, WinClosed)
where deferring is correct. But the outer-scope
`state.set_current_poppy_name(nil)` is fine because by the time the
callback runs, the scheduler guarantees the new win layout is settled.
Two comments explaining *why* it's scheduled would help.

### Mode plugins leak knowledge of session internals

`modes/term.lua:78–89` and `modes/file.lua` both reach into
`state.poppy(name).runtime_state` to set/clear it. That's fine —
they're the runtime owners — but `term.lua` also calls
`session.kill_active()` from the `on_exit` callback, which couples the
mode to the session facade. A `state.clear_runtime(name)` setter or a
`term.lua`-internal "what to do when the job dies" callback passed by
the session would invert this nicely. Right now `term.lua` knows that
"if I'm the current poppy, killing myself means recover(); otherwise
just clear my runtime". That's session policy living in the mode
plugin.

### `setup_autocmds` registers handlers for `BufUnload` from the moment
`setup()` runs, with `e.buf` referring to any buffer that has a
`poppy_popup` var. This means if the user opens a buffer with that
variable set from somewhere else (extremely unlikely but technically
possible), poppy will respond. Minor.

### Unused LuaCATS classes

In `_types.lua`:

- `PoppyEntry` (line 64) — only used in `layout.compute_landing_view_width`'s
  `@param` annotation. The actual session array is `PoppySessionEntry[]`.
  They're almost identical but `PoppyEntry` has no `runtime_state` field
  while `PoppySessionEntry` does. The doc comment says
  `compute_landing_view_width` takes `PoppyEntry[]` but it actually
  receives `state.poppies` which is `PoppySessionEntry[]`. Wrong type.
- `PoppyListEntry` (line 86) — defined but never referenced. The list
  renderer's local table shape is inline-annotated in
  `render.lua:266-274`.
- `PoppyPanelHandles` (line 80) — defined, never used (the
  `_CLEANED.md` notes that panel creation functions used to return
  this and it was dropped). Dead type.

## Ugly

### `config.merge` carries too many `string.format` calls

`config.lua` has 8 `vim.notify(string.format(...), vim.log.levels.WARN)`
calls, each ~5 lines. Combined with the `sanitize_string_fields` helper
that's a ~30-line closure, the file is 290 lines for what is essentially:
(1) merge with defaults, (2) validate each field, (3) resolve poppy
configs. A small `notify_warn(template, ...)` helper would compress
this without losing detail, and a `validate_field(opts, key, predicate,
message)` helper would let you table-drive the validation block at
line 188–222.

This is style, not correctness — but the file already feels like it's
in flux (multiple `WARN` paths added in different rounds, see
`_CLEANED.md`) and a tighter form would survive the next addition.

### `style.setup` is 100 lines of hardcoded highlight math

`style.lua:112-221` is one giant function doing `nvim_get_hl` for
~10 source groups and `nvim_set_hl` for ~25 derived groups. The CATEGORY
loop appears three times (lines 165, 174, 185, 200 — actually four
times, two for `Hidden` variants). Each iteration does a small color
adjustment. The function is correct but a `for _, cat in ipairs({"File",
"Exec", "Shell"}) do ... end` style with shared subroutines for the
"normal-tint", "hidden-darken", "current-bold" derivations would be
~40 lines instead of ~100.

### `render.lua` mixes three panels in one file with parallel structure

`header`, `list`, and `hints` each have their own `create` + `recreate`
+ `update` functions inside one file, plus a fourth (bottom-right hint)
inside `hints`. The mode table `SIDEBAR`/`LANDING` in `view.lua:191`
already acknowledges the parallel structure. Splitting into
`render/header.lua`, `render/list.lua`, `render/hints.lua` (with a
shared `create_buf()` and `apply_win_marker()` helper module) would
make each panel ~150 lines and self-contained.

Not urgent; the current shape is grep-able because the namespace
prefixes (`header_ns`, `list_ns`, `hints_ns`) make it clear which panel
owns what.

### `M.transition_to_content` and `M.enter_landing` both manually fiddle
with `state.windows.content_win` / `content_buf`

The pair of functions are the only places that clear these fields, but
they're not symmetrical:

- `enter_landing` sets `content_win = nil, content_buf = nil` (correct
  — landing has no content).
- `transition_to_content` sets them after `view.content.create`.

That's correct, but a small `state.set_content(win, buf)` setter
(paralleling `state.set_current_poppy_name`) would consolidate it.
`state.windows.content_win` is set in `session/init.lua:580, 613`,
cleared in 309, 620. Three write sites.

### `cleanup` deletes buffers in a confusing order

`cleanup` (264–312) closes wrapper/content wins, then deletes a bunch
of scratch buffers including the wrapper_buf, hints/list/header bufs,
and menu_hint buf. The conditional logic (`if not has_running_popies
then ...`) controls which buffers get deleted — but
`has_running_popies` checks `next(state.poppies) ~= nil`, which is
*always* true after setup (the array has entries even if none are
open). The variable name lies; the intent appears to be "any open
poppy has a non-nil `runtime_state`". Currently, `cleanup(true)` (from
`M.close`) wipes all poppies first, so `has_running_popies` is `false`
by the time the check runs; `cleanup()` (from `M.toggle`) sees the
poppies still in the array. The conditional *does* work — but only as
a side effect of always calling `cleanup(true)` when we mean to wipe
poppies. A direct "wipe_poppy_buffers" parameter would read better.

### `watch_content_window` uses forward-declaration pattern

```lua
local watch_content_window = nil
watch_content_window = function(win_id, menu_w)
    ...
    if type(watch_content_window) == "function" then
        watch_content_window(c_win, w)
    end
end
```

The forward declaration is there so the recursive call from inside the
WinClosed callback can find the variable. But the recursive call only
matters the first time the callback runs (it's `once = true`, so the
autocmd self-destructs after firing once). The recursive call
registers a watcher for the *replacement* content window created by
the callback. So the recursion is real.

The forward declaration pattern is ugly. A local forward declaration
+ `local function watch_content_window(win_id, menu_w) ... end` would
let Lua's hoisting handle it (local functions are hoisted in
`local function` declarations). The pattern as written also keeps
`watch_content_window` mutable from outside the module — `local
function` would close it over properly.

### Comment-driven clarity is high but redundant

The codebase has a lot of "what this does" comments. Some are good
(they explain non-obvious decisions: the `init_or_reset_state`
pattern, the `vim.schedule` rationale, the UTF-8 byte-offset
workaround in `header_panel`). Some are obvious-from-code
(`-- Sidebar visibility (autohide mode). No-op in landing.` above
`view.set_visible`). Net positive, but a pass to remove the
obvious ones would help the non-obvious ones stand out.

## Real bugs / risk

### `M.kill_active` doesn't notify even if buffer delete fails

```lua
if target_bufnr and vim.api.nvim_buf_is_valid(target_bufnr) then
    vim.api.nvim_buf_delete(target_bufnr, { force = true })
end

state.poppy(target).runtime_state = nil
state.set_current_poppy_name(nil)
M.recover()
```

If `nvim_buf_delete` fails (e.g., buffer modified and `:quit` not used
correctly), `runtime_state` is still cleared and `recover` runs. The
buffer becomes orphan-state but not displayed. In practice with
`{ force = true }` this shouldn't happen, but the lack of a return
check is a fragile shape.

### `M.recover` fallback's `state.poppies_runtime()` is called as
`pairs(state.poppies_runtime())` — iterating a list with `pairs`. That
works (the runtime helper returns an array) but `ipairs` would be more
correct. Same shape at `state.poppies_runtime` (returns array). Two
ways to misuse the same function is risky; `pairs` works today only
because Lua array iteration is order-stable.

### `view.refresh_poppies` returns early if `state.windows.hidden` is
true, but the caller in `menu.lua:45` doesn't check whether the
sidebar is mounted before calling. After a kill in autohide mode, the
sidebar may be hidden — `refresh_poppies` no-ops, but the caller still
expects the list to reflect the change. When the sidebar is next
shown (`menu.toggle_menu` → `view.set_visible(true)`), the mount
function recreates the list buffer via `render.list.create` which
doesn't re-call `update` — meaning the new list shows the *stale*
state captured at the last `refresh_poppies`.

Actually: `set_visible(true)` calls `mount_panels`, which calls
`ensure_panel("list_buf", ...)` which on a fresh mount (no valid buf)
calls `render.list.create` directly, never `render.list.update`. The
first-time mount from `M.open` works because `enter_landing` is
followed by `M.open`'s `view.refresh_poppies()`. But if you toggle off,
kill the active poppy (autohide is on, sidebar stays hidden), then
toggle menu back on — the new list won't reflect the kill until the
next `switch` or the next `kill`. Bug-shaped, latent.

### `term.lua` `on_exit` deletes the buffer unconditionally

```lua
on_exit = function()
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    if shared.session_is_open() and shared.session_get_current_poppy_name() == poppy_name then
        session.kill_active()
    else
        local entry = state.poppy(poppy_name)
        if entry then
            entry.runtime_state = nil
        end
    end
end,
```

If the buffer was already deleted by `M.kill_active` (the buffer
delete happens *before* `runtime_state = nil` is set), this
`on_exit` runs after the kill and calls `kill_active` again. With
`current_poppy_name == nil` after the kill, the second `kill_active`
no-ops. Safe today, but the path is fragile: any future change that
makes `kill_active` idempotent-but-nontrivial would double-fire.

### `setup_exclusive_float` uses `goto continue` with a surrounding
`if/wrap/::continue::`. The whole thing is wrapped in `vim.schedule`
and iterates *every* window in `nvim_list_wins()`. That's O(n) over
all windows — fine for typical use, but on a busy session with many
splits, the schedule fires once and walks all of them. Not a bug,
just noting it's an eager close.

### `modes/file.lua:33` calls `poppy_opts.file()` if it's a function,
then `vim.fn.expand(file_val)`. If the function returns nil (e.g.
git_root not found in the README's example), `expand("nil")` would
return `nil`, and the subsequent `filereadable` check would call
`vim.fn.filereadable(nil)` — which would error in some Neovim
versions. The README example returns a fallback, but a user-supplied
function returning `nil` would crash.

## Maintainability shape

The plugin is in genuine exploration phase. The signal:

- `_CLEANED.md` lists 16 items that were recently resolved; each is
  small but real (magic numbers, dual-purpose state, lazy requires,
  UTF-8 byte offsets, dead code). The list is the output of an
  iterative agent loop.
- `REVIEW.md` (the prior version) lists only one item under "Ugly" and
  zero under "Bad" / "Real bugs". That's the optimistic pre-iteration
  view.
- `TODO.md` says "Code style and optimisations" and "refine-base" are
  in progress / deferred. So shape is *expected* to change.

That's fine for an exploration phase. The risks this creates:

- **Tests don't exist**, so every optimization is "did this break the
  user's setup". The README says "do not focus on CICD stuff like
  tests" — accepted — but the optimization loop has no safety net.
  Manual smoke tests are described in `_CLEANED.md` but not codified.
- **The public Lua API mirrors the session facade exactly.** Any
  session refactor (the `actions.lua`/`manager.lua` split) needs to
  keep `init.lua` exports stable, which constrains the refactor.
  That's actually a feature, not a bug — it forces the public surface
  to stay small.

## Where to push next

Without forcing premature shape:

1. **Sync README structure with reality.** Either re-split panels into
   separate files (consistent with the rest of the README's design
   intent) or rewrite the README tree. Right now it lies.
2. **Resolve the `menu_width` function-vs-number mismatch.** Either
   narrow the type or resolve the function in `view.menu_width()`.
   Trivial but a sharp edge.
3. **Land the `actions.lua` extraction.** The README expects it; the
   README's architecture section reads better with it. ~200 lines move
   out of `session/init.lua`.
4. **Fix the `view.refresh_poppies` early-return under autohide.** The
   kill-then-show-menu sequence has a latent staleness. Either force
   a refresh on `set_visible(true)`, or have the list renderer always
   read live state.
5. **Decide on `state.poppies` shape.** The dual-purpose question
   (`_CLEANED.md` item, partially resolved) is still open. Picking
   one shape and committing cuts ~5 defensive checks.

None of these are blocking. The plugin reads and works today; the
shape is exploratory; refactoring aggressively while shape is in flux
is the actual risk.