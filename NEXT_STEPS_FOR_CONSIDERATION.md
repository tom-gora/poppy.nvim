# Next Steps for Consideration

## Resolved Issues

### 1. Stale README
References old config schema (`popups_backend`, `position`, `border`, etc.) and claims "file based IPC" — none of which exist in the current code.

*Resolved: README rewritten to match current architecture.*

### 6. `list_panel.lua` stores `M.width` as module state
Set in `create()`, read in `update()`. Fragile if `create` is called again with different width. Pass width explicitly to `update`.

*Resolved: Panel lifecycle moved to `panels.lua`; `recreate()` takes buffer + wrapper config. Width managed via local upvalues + panels state, not on `M`.*

### 2. & 3. Banner removed, replaced with landing view
Banner was an ugly ASCII art placeholder that overflowed on narrow windows. Replaced with a clean landing view: a narrow centered window showing only the poppy list + minimal hints. Width auto-computed from content. No kill/hide hints in landing mode.

### 11. `_watch_content_window` autocmd cascade
When recovering to landing mode, closing the content window triggered `WinClosed` which recreated it, leaving an orphaned floating window. Fixed with `M._suppress_watch` flag.

## Remaining Issues

### 4. No tests, CI, or doc help file
Acceptable for personal MVP, but notable. Optionally add basic tests.

### 5. `session.lua` god-object
289 lines mixing state, orchestration, UI recovery, autocmd setup. Split state into `state.lua`; keep `session.lua` as pure orchestration.

### 6. `input.lua` re-maps on every switch
`input.setup()` re-maps all `<M-p>1..N` keybinds each time a poppy is switched. The banner buffer could accumulate stale keymaps if the sorted poppy list changes. Clean old mappings before re-applying, or map once on open and use a callback layer.

### 7. `modes/file.lua` uses `vim.cmd("edit ...")`
Side-effect-heavy, triggers autocmds and filetype detection. Use `vim.fn.readfile()` + `nvim_buf_set_lines()` instead.

### 8. No LuaLS type annotations
Only `config.lua` has basic `---@class` blocks. Missing annotations on `mode`, `cat` fields (added dynamically in `config.lua`). Add annotations across all modules.

### 9. `title_fallback` duplicate branches
`exec` and `term` arms are identical (`utils.lua:22-31`). Collapse.

### 10. `M.poppies` / `opts.poppies` naming collision
`M.poppies` (runtime state) clashes with `opts.poppies` (config). Rename `M.poppies` → `M.active` or `M.state`.

### 12. `poppy_popup` typo
Buffer variable is named `poppy_popup` but should be `poppy_poppy` (or `poppy_name`). Cosmetic but inconsistent.

### 13. No `plugin/` directory for auto-loading
User must call `require("poppy").setup()` manually. No `plugin/poppy.vim` to auto-register `:Poppy` command or set defaults on startup. Fine for a personal plugin but worth noting for distribution.