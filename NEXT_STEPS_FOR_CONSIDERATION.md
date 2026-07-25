# Next Steps for Consideration — poppy.nvim

Working backlog for refining the codebase. Branch: `ui-rewrite`.
~2100 LOC, 15 Lua files. Updated 2026-07-19.

______________________________________________________________________

## 0. At-a-glance

The top-five items from the previous revision are all done. The
active backlog is now scoped to:

1. **README rewrite** (§2) — high-impact, low-effort. The README's
   `## Configuration` and `## Usage` sections describe a design
   that's two refactors behind the code.
1. **Panels state-machine rewrite** (§3.8) — collapse the three
   boolean state machine in `panels.lua` to a single tagged state.
1. **Sign-fix on `ColorScheme`** ✓, **mode schema** (§7),
   **index parsing** (§6), **z-index centralization** (§12) —
   small but easy.

Larger items (§3.3–3.7, §13, §14, §17) take a branch each.

______________________________________________________________________

## 1. What's working — don't touch

- **Module decomposition** — `core/ui/*` cleanly splits the wrapper,
  content window, sidebar panels, list, hints, header, style. Each
  file is read in \<5 min. Don't subdivide further unless §17 happens.
- **Mode dispatcher** — `require("poppy.modes." .. mode)` is the right
  plug-in point. Don't replace with a dispatch table unless a fourth
  mode appears.
- **Buffer reuse across toggle cycles** — `cleanup` preserves
  `content_buf` / `wrapper_buf` / panel buffers when `M.poppies` is
  non-empty. Re-opening doesn't re-spawn every TUI. Intentional, not
  a leak.
- **`is_active` XOR `is_hidden`** — real invariant; `list_panel.lua`
  relies on it.
- **Theme-aware highlight derivation** — `style.lua` re-derives both
  extmarks and signs on `:colorscheme`.
- **Per-poppy `on_exit` in `term.lua`** — delegates kill-or-recover to
  `session` rather than doing the bookkeeping itself.

______________________________________________________________________

## 2. README / config drift (high priority, low cost)

The README's `## Configuration` and `## Usage` sections describe
designs that pre-date the state consolidation:

- **Outdated structure tree** — the doc lists `banner.lua` and
  `core/session.lua`. The engine lives at `core/session/init.lua`
  and there is no `banner.lua`.
- **Stale config keys** — docs reference `prefix_bind = "<M-p>"` and
  `whichkey_disable`. The real keys are `keys.poppy_action` (default
  `<C-_>`), `keys.select` (`<CR>`), `keys.kill` (`d`),
  `keys.exit_menu` (`<Esc>`).
- **`exec` shape mismatch** — config annotates `exec` as `string|string[]`,
  but `modes/term.lua` only reads `string`. Arrays work by accident.
- **Stale "Usage" table** — `<M-p>1`–`<M-p>N` prefix-bind is described
  but doesn't exist. Real flow: open with `keys.poppy_action`, focus
  sidebar, then `<count><CR>` or `<count>d`.
- **`menu` subcommand** — supported by `session.lua` but not in README.

**Suggestion:** rewrite README §Configuration and §Usage against the
current schema. Or drop the `<M-p>N` claims and the `exec = function`
row.

______________________________________________________________________

## 3. State & control flow in `core/session.lua`

### 3.1. ~~Metatable trick is dead code~~ — done (Option B: explicit getter)

The metatable `__index`/`__newindex` shim that forwarded
`M.current_poppy_name` reads/writes to `current_poppy_name` was
removed. Replaced with `M.get_current_poppy_name()` (a function
returning `state.current_poppy_name`); the only external reader
(`modes/term.lua`) calls it directly. `state` is the canonical
storage; the metatable was hidden indirection that grep wouldn't
catch.

### 3.2. ~~Module-level state → state record~~ — done

All 9 engine upvalues now live in `state`. `reset_state()` /
`init_state()` consolidate the reset paths. `M.poppies` is a
back-reference to `state.poppies`. `_landing_view_width` and
`state.opts` are session-persistent (intentionally outside state).

### 3.3. ~~`_suppress_watch` flag is a smell~~ - done

Used in `cleanup` and `_recover` to prevent `WinClosed` from reacting
to its own teardown. Either scope the `poppy_ui` augroup inside
cleanup (recreate after), or switch `poppy_ui` to `clear = true` on
`setup` and rely on augroup lifecycle.

### 3.4. `M.open` does too much

`M.open` handles: reentry guard, landing-vs-active branch, wrapper
recreation, content creation, panel creation, sidebar input, and
post-refresh. The only function that knows about both states at once.

Split: `M._open_landing()` / `M._open_active(name)` / `M.open(name)`.

### 3.5. `M.switch` is over-broad

~65 LOC. Split: `M._leave_current()` /
`M._transition_landing_to_active()` / `M._enter_current(name)`.

### 3.6. ~~`:Poppy` command parser is hand-rolled~~ — done

Switched `nargs = "?"` → `nargs = "*"` and routed on
`cmd_opts.fargs[1]` instead of `cmd_opts.args:sub(1, 5)`. Multi-word
poppy names (`open my stuff`) now work via `table.concat(fargs, " ", 2)`.
Unknown subcommands emit a `vim.log.levels.WARN` notify listing valid
options instead of silently toggling. `:Poppy open` with no name opens
landing (was: silently toggled). Completion is now subcommand-aware:
returns subcommand names at the first arg slot, poppy names at the
second (after `open`), and `{}` after argless subcommands.

### 3.7. ~~`mode` and `cat` are coupled fields~~ - done

`config.lua` (in `resolve_poppy` since the §4 rewrite) writes both
`poppy.mode` and `poppy.cat` onto every poppy. `cat` is fully
derivable from `mode` + which user-facing key (`exec` vs `shell`)
was set. Either drop `cat` and derive at use sites, or keep both and
document the invariant.

### 3.8. ~~Boolean state machine for the sidebar~~ - done

`panels.lua` encodes `hidden` and `autohidden` as two booleans. The
actual reachable states are `visible` / `manually_hidden` /
`auto_hidden`; `hidden=true && autohidden=true` is unreachable and
unguarded. Replace with a single `M.state = "visible" | "hidden" | "autohidden"` field + `set_state(s)` dispatch. Collapses ~6
near-duplicate methods.

______________________________________________________________________

## 4. ~~Config sanitization mutates user input~~ — done

`M.merge` now builds a fresh opts table. The user's `user_opts` is
not mutated. Engine-internal `mode`/`cat`/`title` live in a parallel
`poppies_resolved` map. Latent `vim.tbl_deep_extend` mutation of
`default_opts` fixed as a side effect (`{}` first arg).

______________________________________________________________________

## 5. ~~Duplicated sizing logic~~ — done

`core/ui/layout.lua` exposes `normalize_ratio_or_pixels` (sanitize-time)
and `compute_dimensions(opts, cols, lines, override_width)` (open-time,
testable in isolation). Three callers (`config.lua`, `wrapper.lua`,
`session.lua`'s `_active_width`) all share it.

______________________________________________________________________

## 6. Fragile list-index parsing

`session.lua` extracts the cursor-line index via
`line:match("%s+(%d+)%s")` against `list_panel.update`'s
`string.format` line. One-character format drift breaks it.

Replace with: an extmark or buffer-local `poppy_index_by_line` map
populated by `list_panel.update`, or a `statuscolumn` number column.

______________________________________________________________________

## 7. Mode-dispatch has no schema

`modes/term.lua` and `modes/file.lua` independently build the runtime
record `{active, hidden, bufnr, win, title}`. Same shape in two
places, no documentation.

Add a `poppy_state` factory in `core/session.lua` (or
`core/poppy_state.lua`); both modes call it.

______________________________________________________________________

## 8. `exec` shape claim vs. reality

`modes/term.lua` `resolve_command` handles `poppy_opts.shell`
(string/function/`"default"`). For `poppy_opts.exec` it returns the
raw value to `jobstart`/`termopen`. README and config annotations
claim `exec` can be `string | string[] | function`; only `string`
actually works.

Either document `exec` as `string` only, or extend `resolve_command`
to handle the array and function shapes.

______________________________________________________________________

## 9. ~~Title-fallback import direction~~ — done

`title_fallback` and the other helpers that used to live in
`modes/utils.lua` now live in `core/util.lua`. `modes/utils.lua`
deleted. `config.lua`'s stale `require("poppy.modes.utils")` was
inadvertently fixed by the §4 rewrite.

______________________________________________________________________

## 10. `list_panel.lua` module-level mutable state

Line 4: `local sb_width = 25` is a module-local re-assigned every
`create`/`recreate` and read by `M.update`. Pass `width` as an arg
to `M.update` instead of relying on the upvalue. Removes a class of
"two sidebars fighting over the same upvalue" bugs.

______________________________________________________________________

## 11. ~~Highlight signs not refreshed on `ColorScheme`~~ — done

`define_poppy_signs` moved to `core/ui/style.lua` and called from
`M.setup` on every invocation, including the `ColorScheme` autocmd.
Smoke test verifies `sign_getdefined(...).texthl` survives
`:colorscheme default`.

______________________________________________________________________

## 12. ~~Z-indexes scattered~~ — done

Centralized as `layout.POPPY_Z_INDEX = 49` in `core/ui/layout.lua` (folded in
during the same change that renamed `geometry.lua` → `layout.lua`).
All six zindex sites now read from the constant; arbitrary 200–204
values replaced with the single value.

______________________________________________________________________

## 13. `:CheckHealth` / lazy-load hints

- No `lua/poppy/health.lua` registered with `vim.health`. Adding one
  for config validity + screen-size sanity would help debugging.
- No `lazy.nvim` / `folke/snacks` `opts = { cmd = "PoppyToggle" }`
  or `event = "VeryLazy"` hints in the README.

______________________________________________________________________

## 14. No tests

Smoke test at `/tmp/poppy_smoke_test.lua` (25 assertions) covers the
key state-machine + reset paths. No test framework, no CI.

Promote to plenary-driven `tests/` with `describe`/`it`. Pure-Lua
unit tests for `core/ui/layout.lua` are now trivial. Add a GitHub
Actions workflow running `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"`.

______________________________________________________________________

## 15. Idiomatic nits

`M.switch_by_index` already fixed (uses `M.poppies[index]` directly).
`pcall` calls in modes need comments. Parameter abbreviations in
`core/ui/panels.lua` (`sw`, `hl`, `hdr`) are ambiguous — rename to
`sidebar_w`, `hint_lines`, `header_lines`.

______________________________________________________________________

## 16. Quick wins — open items

- [x] Centralize z-index constants (`layout.POPPY_Z_INDEX = 49` in `core/ui/layout.lua`) (§12).
- [ ] Add a `CheckHealth` provider (§13).
- [ ] Rewrite README §Configuration and §Usage against the current
  schema (§2).

______________________________________________________________________

## 17. Larger refactors (dedicated branch each)

- **Split `core/session/`** into `manager.lua` (window lifecycle) and
  `poppy_state.lua` (per-poppy record). The folder structure
  (`core/session/init.lua`) is already in place for the move.
- **`core/events.lua`** with named events (`PoppyOpen`, `PoppySwitch`,
  `PoppyKill`, `PoppyClose`, `PoppyThemeChange`) so downstream users
  can `vim.api.nvim_create_autocmd("User", { pattern = ... })`.
- **Poppy record manager** — replace `M.poppies[name]` direct access
  with a tiny record-manager API and the `poppy_state` factory
  (§7). Enforces schema in one place.
- **Panels state-machine rewrite** — see §3.8.

______________________________________________________________________

## Changelog

- **2026-07-19** — State consolidation + quick-wins cleanup. Top-five
  items done; smoke test at 25 assertions. Bugs fixed: autohide-hint
  leak, empty-list-after-toggle, `M.poppies` back-ref breakage,
  `util.is_open()` no-arg, metatable shadow.

