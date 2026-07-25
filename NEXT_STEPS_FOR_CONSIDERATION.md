# Next Steps for Consideration — poppy.nvim

Working backlog for refining the codebase. Branch: `ui-rewrite`.
~2330 LOC, 22 Lua files. Updated 2026-07-25.

______________________________________________________________________

## 0. At-a-glance

The session monolith is gone. Top remaining items:

1. **README rewrite** (§2) — high-impact, low-effort. The README's
   `## Configuration` and `## Usage` sections are still behind the
   code, and a "Building custom UIs" subsection is missing for the
   new read API (§R).
1. **`panels.lua` boolean state machine** (§3.8 — superseded; see
   §P) — three booleans where one tagged state would do.
1. **`poppy_state` record factory** (§7 — partially done; the module
   exists but `modes/*.lua` still inline the `{active, hidden, bufnr,
   win, title}` shape).
1. **Tests / `CheckHealth`** (§13, §14).

The session split (§S) is complete: 8 small files replace the 719-LOC
monolith.

______________________________________________________________________

## 1. What's working — don't touch

- **`core/session/` decomposition** — 8 files, each ≤220 LOC: `state`,
  `poppy_state`, `switching`, `killing`, `manager`, `events`,
  `commands`, `init` (facade). `init.lua` exposes 15 thin wrappers;
  internals stay private. Don't merge anything back.
- **`poppy_state.lua` dual API** — internal storage API
  (`runtime_get` / `runtime_set` / `runtime_remove` / `entries` /
  `clear` / `is_empty` / `array_length` / `iter` /
  `rebuild_from_sorted` / `ensure_entries_loaded` /
  `landing_view_width`) for modes / switching / killing / manager;
  public read API (`get_poppy_by_name` / `get_poppy_by_index` /
  `get_poppies` / `get_current_poppy`) for users building pickers.
  One table, two surfaces. Don't merge them.
- **`state.lua` shared record** — every session submodule reads/writes
  the same `M` table via `require("poppy.core.session.state")`. No
  cycles; no late binding.
- **`util.lua` direct state read** — `session_is_open` and
  `session_get_current_poppy_name` read `state.lua` directly. No late
  binding, no `attach_session` dance.
- **`util.cursor_to_poppy_index`** — declarative-upfront lookup:
  cursor row N → array index N → poppy name. No string parsing.
- **Module decomposition (`core/ui/*`)** — wrapper, content, sidebar
  panels, list, hints, header, style. Don't subdivide further.
- **Mode dispatcher** — `require("poppy.core.modes." .. mode)` stays
  the plug-in point.
- **Buffer reuse across toggle cycles** — `cleanup` preserves
  `content_buf` / `wrapper_buf` / panel buffers when poppies table
  is non-empty.
- **`is_active` XOR `is_hidden`** — invariant; `list_panel.lua`
  relies on it.
- **Theme-aware highlight derivation** — `style.lua` re-derives both
  extmarks and signs on `:colorscheme`.
- **`by_*` naming consistency** — `switch_by_name`, `switch_by_index`,
  `kill_by_name`, `kill_by_index`, `kill_active`,
  `get_poppy_by_name`, `get_poppy_by_index`. No naked `switch` /
  `kill_current` / `get_poppy` anywhere. `grep` enforces it.

______________________________________________________________________

## 2. README / config drift (high priority, low cost)

The README's `## Configuration` and `## Usage` sections describe
designs that pre-date the state consolidation:

- **Outdated structure tree** — the doc lists `banner.lua` and
  `core/session.lua`. The engine lives at `core/session/init.lua`
  (with `state` / `poppy_state` / `switching` / `killing` /
  `manager` / `events` / `commands` siblings) and there is no
  `banner.lua`.
- **Stale config keys** — docs reference `prefix_bind = "<M-p>"` and
  `whichkey_disable`. The real keys are `keys.poppy_action` (default
  `<C-_>`), `keys.select` (`<CR>`), `keys.kill` (`d`),
  `keys.exit_menu` (`<Esc>`).
- **`exec` shape mismatch** — config annotates `exec` as
  `string | string[] | function`, but `modes/term.lua` only reads
  `string`. Arrays work by accident.
- **Stale "Usage" table** — `<M-p>1`–`<M-p>N` prefix-bind is described
  but doesn't exist. Real flow: open with `keys.poppy_action`, focus
  sidebar, then `<count><CR>` or `<count>d`.
- **`menu` subcommand** — supported by `session/commands.lua` but not
  in README.
- **Missing "Building custom UIs" subsection** — the read API
  (`require("poppy").get_poppies` / `get_poppy_by_name` /
  `get_poppy_by_index` / `get_current_poppy` /
  `get_current_poppy_name` / `is_open` and the picker integration
  methods `switch_by_name` / `switch_by_index` / `kill_by_name` /
  `kill_by_index` / `kill_active`) isn't documented.

**Suggestion:** rewrite README §Configuration, §Usage, and add a new
"Building custom UIs" subsection against the current schema.

______________________________________________________________________

## 3. State & control flow in `core/session/`

### 3.1. ~~Metatable trick is dead code~~ — done

The metatable `__index`/`__newindex` shim was removed. Replaced with
explicit `M.get_current_poppy_name()`. Later refactored into
`util.session_get_current_poppy_name` (reads `state.lua` directly).

### 3.2. ~~Module-level state → state record~~ — done

All engine upvalues live in `state`. `state.lua` exposes `reset` /
`init` (init preserves `state.opts`).

### 3.3. ~~`_suppress_watch` flag is a smell~~ — done

`poppy_ui` augroup cleared via `nvim_create_augroup(_, {clear=true})`
inside `cleanup` and `M.recover`. No suppress flag.

### 3.4. ~~`M.open` does too much~~ — done (refactor in §S)

`manager.M.open` still does a lot, but it's now isolated in one
function in one file. The original split suggestion
(`_open_landing` / `_open_active` / `open`) didn't happen — instead
the function lives in `manager.lua` as a single ~70-LOC block. If
touched again, prefer extracting `_open_active` /
`_open_landing` helpers, not splitting the file.

### 3.5. ~~`M.switch` is over-broad~~ — done (renamed, see §N)

`M.switch` was renamed `M.switch_by_name` and moved to
`session/switching.lua` (~70 LOC). Not split further — the function
is one cohesive flow (mark previous hidden → maybe transition out of
landing → spawn new mode → refresh panels → focus content).

### 3.6. ~~`:Poppy` command parser is hand-rolled~~ — done

Switched `nargs = "?"` → `nargs = "*"` and routed on
`cmd_opts.fargs[1]`. Multi-word poppy names work via
`table.concat(fargs, " ", 2)`. Subcommand-aware completion. Now lives
in `session/commands.lua`.

### 3.7. ~~`mode` and `cat` are coupled fields~~ — done

`cat` is derived at use sites via `util.cat(poppy)`. No field on
the record anymore.

### 3.8. ~~Boolean state machine for the sidebar~~ — done (in `panels.lua`)

`panels.lua` now uses one boolean (`hidden`) for the menu state.
The `autohidden` boolean was removed.

### 3.9. ~~`M.poppies` direct table writes~~ — done (refactor in §S)

`M.poppies` field on session is gone. Modes / killing / switching /
manager use `poppy_state.runtime_get/set/remove/entries` exclusively.

______________________________________________________________________

## 4. ~~Config sanitization mutates user input~~ — done

`config.merge` builds a fresh opts table. `poppies_resolved` holds
the engine-internal `mode` / `title`. Latent
`vim.tbl_deep_extend` mutation fixed.

______________________________________________________________________

## 5. ~~Duplicated sizing logic~~ — done

`core/ui/layout.lua` exposes `normalize_ratio_or_pixels` and
`compute_dimensions`. Three callers share them.

______________________________________________________________________

## 6. ~~Fragile list-index parsing~~ — done

Replaced with `util.cursor_to_poppy_index(poppies)`: cursor row N →
array index N → poppy name. No string parsing, no extmark, no buffer
map. Lua array semantics do the work; the integers in the rendered
list are now purely human-facing. The original two suggestions
(extmark metadata, buffer-local `poppy_index_by_line`) were both
heavier solutions to a problem that doesn't exist when you trust the
sorted-array invariant.

Both `switch_by_cursor` and `kill_by_cursor` now share the helper.
Internal only — not exposed at `require("poppy")` because cursor
position only makes sense inside the poppy menu.

______________________________________________________________________

## 7. Mode-dispatch has no schema (partial)

`modes/term.lua` and `modes/file.lua` still build the runtime record
inline:

```lua
poppy_state.runtime_set(poppy_name,
    { active = true, hidden = false, bufnr = bufnr, win = parent_win, title = poppy_opts.title })
```

The same `{active, hidden, bufnr, win, title}` shape in two places.
The `poppy_state` module exists but doesn't expose a record factory.

**Suggestion:** add `poppy_state.M.make_runtime(bufnr, win, title)` or
similar; both modes call it. Removes the duplicated literal.

______________________________________________________________________

## 8. `exec` shape claim vs. reality

`modes/term.lua` `term_resolve_command` (in `util.lua` now) handles
`poppy_opts.shell` (string / function / `"default"`). For
`poppy_opts.exec` it returns the raw value to `jobstart` /
`termopen`. README and config annotations claim `exec` can be
`string | string[] | function`; only `string` actually works.

Either document `exec` as `string` only, or extend `term_resolve_command`
to handle the array and function shapes.

______________________________________________________________________

## 9. ~~Title-fallback import direction~~ — done

`title_fallback` and the other helpers live in `core/util.lua`.
`modes/utils.lua` deleted.

______________________________________________________________________

## 10. `list_panel.lua` module-level mutable state

Line 6: `local mv = 25` is a module-local re-assigned every
`create` / `recreate` and read by `M.update`. Pass `width` as an arg
to `M.update` instead of relying on the upvalue.

______________________________________________________________________

## 11. ~~Highlight signs not refreshed on `ColorScheme`~~ — done

`define_poppy_signs` lives in `core/ui/style.lua` and runs on every
`M.setup` (initial + every `ColorScheme` autocmd).

______________________________________________________________________

## 12. ~~Z-indexes scattered~~ — done

Centralized as `layout.POPPY_Z_INDEX = 48` in `core/ui/layout.lua`.
All sites read from the constant.

______________________________________________________________________

## 13. `:CheckHealth` / lazy-load hints

- No `lua/poppy/health.lua` registered with `vim.health`. Adding one
  for config validity + screen-size sanity would help debugging.
- No `lazy.nvim` / `folke/snacks` `opts = { cmd = "PoppyToggle" }`
  or `event = "VeryLazy"` hints in the README.

______________________________________________________________________

## 14. No tests

Smoke test at `/tmp/poppy_smoke_test.lua` (25 assertions) covers
the key state-machine + reset paths. No test framework, no CI.

Promote to plenary-driven `tests/` with `describe` / `it`. Pure-Lua
unit tests for `core/ui/layout.lua` are now trivial. Add a GitHub
Actions workflow.

______________________________________________________________________

## 15. Idiomatic nits

- `list_panel.lua` `mv = 25` upvalue (see §10).
- `core/ui/panels.lua` parameter abbreviations (`sw`, `hl`, `hdr`)
  are ambiguous — rename to `sidebar_w`, `hint_lines`,
  `header_lines`.
- `pcall` calls in modes need comments explaining what they're
  guarding.

______________________________________________________________________

## 16. Quick wins — open items

- [x] Centralize z-index constants (`layout.POPPY_Z_INDEX = 48` in
  `core/ui/layout.lua`) (§12).
- [x] Cursor-based poppy lookup via array index (§6).
- [x] `poppy_state` module with internal + public APIs (§S).
- [x] `util.cursor_to_poppy_index` helper (§6).
- [x] Public read API at `require("poppy").get_*` (§R).
- [x] Consistent `by_*` naming across the surface (§N).
- [ ] Add a `CheckHealth` provider (§13).
- [ ] Rewrite README §Configuration, §Usage, add "Building custom UIs"
  (§2, §R).

______________________________________________________________________

## 17. Larger refactors (dedicated branch each)

- **Panels state-machine rewrite** — currently uses one boolean
  (`hidden`). If we ever add `autohide-hint` again, lift to tagged
  state.
- **`core/events.lua`** with named events (`PoppyOpen`, `PoppySwitch`,
  `PoppyKill`, `PoppyClose`, `PoppyThemeChange`) so downstream users
  can `vim.api.nvim_create_autocmd("User", { pattern = ... })`.
- **Further split of `manager.lua`** if it grows past ~300 LOC.
  Likely targets: `_open_landing` / `_open_active` private helpers.

______________________________________________________________________

## N. Naming consistency — `by_*` convention

Every "look up an entity and act on it" method follows the
`by_*` pattern:

| Operation | Switch / select | Kill |
|---|---|---|
| by name | `switch_by_name` | `kill_by_name` |
| by index | `switch_by_index` | `kill_by_index` |
| by cursor | `switch_by_cursor` *(internal)* | `kill_by_cursor` *(internal)* |
| displayed (no qualifier) | — | `kill_active` |

Read API follows the same pattern:

| Read | Method |
|---|---|
| list all | `get_poppies` |
| by name | `get_poppy_by_name` |
| by index | `get_poppy_by_index` |
| currently displayed | `get_current_poppy` |

The rename pass retired `M.switch` (→ `switch_by_name`),
`M.kill_current` (→ `kill_active`), and `M.get_poppy` (→
`get_poppy_by_name`). All renames applied at every level
(killing/switching/poppy_state internals + `session/init.lua`
facade + top-level `poppy/init.lua`). `grep -r kill_current lua/`
returns nothing; `grep -r "M\.switch\b" lua/` returns nothing;
`grep -r "M\.get_poppy\b" lua/` returns nothing. Naming is enforced
by convention, not by linter.

Internal-only methods kept on `session` (not exposed at top-level):
`switch_by_cursor`, `kill_by_cursor`. Cursor position only makes
sense inside the poppy menu.

______________________________________________________________________

## P. `panels.lua` state model (post-§3.8)

Currently:
- `M.hidden: boolean` — single boolean. Menu is shown iff not hidden.
- `M.is_hidden()` returns it.
- `panels.show_menu()` / `panels.hide_menu()` toggle it.

If `menu_autohide` (config option) is ever re-introduced, lift to
a tagged state:

```lua
M.state = "visible" | "manually_hidden" | "auto_hidden"
```

Three values collapse six near-duplicate methods.

______________________________________________________________________

## R. Public read API for custom UIs

Top-level `require("poppy")` exposes 15 methods, grouped into three
buckets:

```lua
-- lifecycle (4)
M.toggle, M.open, M.close, M.setup

-- picker integration (5)
M.switch_by_name(name), M.switch_by_index(idx),
M.kill_by_name(name), M.kill_by_index(idx),
M.kill_active()

-- read API (6)
M.get_poppies(),
M.get_poppy_by_name(name), M.get_poppy_by_index(idx),
M.get_current_poppy(),
M.get_current_poppy_name(),
M.is_open()
```

`get_poppy_by_name(name)` and `get_poppy_by_index(idx)` return a
record:

```lua
{
    name = "lazygit", index = 1,
    title = "LazyGit", mode = "term", cat = "exec",
    is_current = false,
    active = false, hidden = true, has_been_opened = true,
    bufnr = 1234, win = nil,
}
```

`get_current_poppy()` is convenience for
`get_poppy_by_name(get_current_poppy_name())`. `is_open()` returns
bool. `get_current_poppy_name()` returns string or nil.

The picker integration methods (`switch_by_*` / `kill_by_*` /
`kill_active`) cover the typical custom UI flow:
1. `get_poppies()` to discover available poppies + indices.
2. User picks one.
3. `switch_by_name(name)` or `switch_by_index(idx)`.
4. Or `kill_by_name(name)` / `kill_by_index(idx)` / `kill_active()`.

`switch_by_cursor` and `kill_by_cursor` are deliberately **not**
exposed at top-level — cursor position only has meaning inside the
poppy menu sidebar.

Philosophy (per design intent): no built-in pickers shipped —
"ship the data getter, let users build their own pickers /
statuslines / whatever". The read API is the contract.

______________________________________________________________________

## S. Session split (done)

`lua/poppy/core/session/init.lua` was 719 LOC and mixed six
concerns. Now split into 8 files:

| File | LOC | Owns |
|---|---|---|
| `state.lua` | 32 | Shared state record + reset/init |
| `poppy_state.lua` | 99 | Internal storage + public read APIs |
| `switching.lua` | 204 | switch, toggle_menu, exit_menu, refresh_panels |
| `killing.lua` | 126 | kill_active, kill_by_name, kill_by_index, kill_by_cursor, recover |
| `manager.lua` | 220 | open, close, toggle, cleanup, watch_content_window |
| `events.lua` | 76 | BufUnload / CursorHold / WinLeave-TermEnter autocmds |
| `commands.lua` | 54 | `:Poppy` user command + completion |
| `init.lua` | 45 | Thin facade — 15 wrappers + setup |

Dependency graph (no cycles):

```
init (facade)
 ├─ state          (leaf — no deps)
 ├─ poppy_state   ─→ state, util
 ├─ killing      ─→ state, poppy_state, switching, panels, input, layout, util
 ├─ switching    ─→ state, poppy_state, panels, content, hints_panel, util, layout, input
 ├─ manager      ─→ state, poppy_state, killing, panels, content, wrapper, hints_panel, layout, util, input
 ├─ events       ─→ state, poppy_state, killing, switching, util
 └─ commands     ─→ state
```

`state.lua` is the only true leaf in the dependency tree. Every
submodule reads / writes the same `state` table; there is no copy or
late binding. The cycle-prone late binding (`util._session` /
`util.attach_session`) was retired — `util.session_is_open` and
`util.session_get_current_poppy_name` now read `state.lua`
directly.

External changes (callers outside `session/`):
- `lua/poppy/init.lua` (top-level) gained the read API and the
  renamed `by_*` picker methods.
- `core/modes/term.lua` and `core/modes/file.lua` stopped writing
  `session.poppies[name]` directly; they use
  `poppy_state.runtime_get/set/remove`.
- `core/util.lua` gained `util.term_get_or_create_buffer` and
  `util.cursor_to_poppy_index` (pure helpers, no session dep).

______________________________________________________________________

## Changelog

- **2026-07-25** — Session split into 8 modules (§S); naming
  consistency pass `by_*` everywhere (§N); public read API for
  custom UIs (§R); `util.cursor_to_poppy_index` replaces fragile
  line parsing (§6); `util.term_get_or_create_buffer` extracted from
  `modes/term.lua`; `state.lua` introduced; late binding retired.
  Top-five from previous revision still pending: README rewrite,
  panels state machine, record factory for modes, tests,
  `CheckHealth`.

- **2026-07-19** — State consolidation + quick-wins cleanup. Top-five
  items done; smoke test at 25 assertions. Bugs fixed: autohide-hint
  leak, empty-list-after-toggle, `M.poppies` back-ref breakage,
  `util.is_open()` no-arg, metatable shadow.