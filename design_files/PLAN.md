# Poppy.nvim — Navigation & Layout Redesign Plan

## Overview

Replace `<M-p>N` prefix-based keybind approach with a minimal 3-key system (`poppy_action`, `select`, `kill`). Overhaul landing view to show color-coded, icon-decorated poppy list with status dots. Add `menu_autohide` option.

**Files modified (8):** `config.lua`, `input.lua`, `session.lua`, `list_panel.lua`, `hints_panel.lua`, `panels.lua`, `style.lua`, `content.lua`

---

## Stage 1 — Config Schema (`config.lua`)

- Add `keys` to defaults: `{ poppy_action = "<C-_>", select = "<CR>", kill = "k" }`
- Add `icons` to defaults: `{ exec = "🛠", shell = "$", file = "🗋" }`
- Add `menu_autohide = false` to defaults
- Remove `prefix_bind` and `whichkey_disable` from defaults + `---@class`
- Add `keys`, `icons`, `menu_autohide` fields to `---@class PoppyConfig`
- `sanitize()`: validate all 3 keys are non-empty strings; validate 3 icons present; validate `menu_autohide` is boolean
- **BREAKING:** `prefix_bind` → `keys.poppy_action`. `whichkey_disable` removed. User's manual global keybind becomes redundant (plugin handles it now)

---

## Stage 2 — Input Module Rewrite (`input.lua`)

- Delete current `setup(buf, sorted, prefix, wk, skip_kill, skip_hide)` entirely
- Add `M.setup_global(keys)`:
  - Maps `keys.poppy_action` for `{"n","t"}` to `session.toggle()`
  - Called once from `session.setup()`
  - Replaces user's manual `vim.keymap.set(...)` for toggling
- Add `M.setup_landing(buf, sorted_poppies, keys)`:
  - `keys.select` (default `<CR>`) → `session.switch_by_cursor()`
  - `{1..N}` number keys → `session.switch_by_index(i)`
  - No kill mapping in landing (no "current" to kill, hints confirm this)
- Add `M.setup_content(buf, keys)`:
  - `keys.poppy_action` → `session.toggle_menu()` (show menu). Overrides global mapping for this buffer
- Add `M.teardown(buf)` — clear all buffer-local keymaps (addresses old stale-mapping issue)

---

## Stage 3 — Session Orchestrator (`session.lua`)

- **`setup()`:** after style setup and opts merge, call `input.setup_global(opts.keys)`
- **Remove** `M._prefix()` and `M._wk()` helpers entirely — all call sites updated

**3a — Landing open (`open()` else-branch):**
- Replace `input.setup(buf, sorted, prefix, wk, true, true)` → `input.setup_landing(buf, sorted, opts.keys)`
- Set `vim.bo[list_buf].filetype = "poppy_menu"`
- Update `compute_landing_view_width()` to use new hints format text for sizing

**3b — Active open (`open()` if-branch):**
- After `switch()` completes, call `input.setup_content(content_buf, opts.keys)` instead of old `input.setup()`

**3c — `switch()` landing→active transition:**
- Replace old `input.setup(content_buf, sorted, prefix, wk)` with `input.setup_content(content_buf, opts.keys)`
- After successful switch, if `opts.menu_autohide`: call `panels.hide_for_autohide(M.content_win)`
- Autohide resize: content fills wrapper (minus border)

**3d — `_recover()` landing transition:**
- Replace old `input.setup(buf, sorted, prefix, wk, true, true)` → `input.setup_landing(buf, sorted, opts.keys)`

**3e — `refresh()`:**
- Pass `opts.keys` to `hints_panel.update()` instead of prefix string
- Delete `M._prefix()` and `M._wk()` accessor functions

**3f — Added `M.switch_by_cursor()`:**
- Get cursor line from current buffer
- Parse the index number from line format `" [dot] [icon] N Title"`
- Call `switch_by_index(N)`

**3g — Added `M.toggle_menu()`:**
- Delegates to `panels.toggle(M.content_win)`
- Used by content buffer's `poppy_action` override

---

## Stage 4 — List Panel Visual Rework (`list_panel.lua`)

**4a — New line layout in `update()`:**
```
[• 🛠 1  LazyGit        ]
[  $ 2  Scratch Term    ]
[• 🗋 3  Project TODOs  ]
```
- Column widths: dot(2) + icon(2) + space + right-aligned index + space + title
- Remove category separator lines (no `prev_cat` blank-line spacer)
- `update()` receives `icons` table and passes it through for rendering

**4b — Icons from opts:**
- Each line looks up `icons[item.config.cat]` (cat is `"exec"`, `"file"`, or `"shell"`)
- No nerdfont detection, no fallback logic — whatever is in opts.icons renders

**4c — Status dot logic (replaces old `PoppyActive`/`PoppyInactive` line highlights):**
- `poppies[name] == nil` (never opened) → space `" "` for dot, no extmark. Line gets cat color HL
- `poppies[name].active == true` → dot `"•"` with `PoppyActiveDot` hl. Line gets cat color HL
- `poppies[name].hidden == true` → dot `"•"` with `PoppyInactiveDot` hl. Line gets desaturated cat color (via separate derived HL)

**4d — Color coding per category:**
- Each line gets `line_hl_group` extmark: `"PoppyFile"`, `"PoppyExec"`, `"PoppyShell"`
- When poppy is hidden/background: apply desaturated variant of the cat hl
- Visible state determination: `update_hl_from_state()` or inline in the loop

---

## Stage 5 — Highlight Groups (`style.lua`)

- Add `desaturate(color, factor)` helper (blends toward gray)
- `M.setup()` additions:
  ```lua
  vim.api.nvim_set_hl(0, "PoppyFile",  { link = "Type" })
  vim.api.nvim_set_hl(0, "PoppyExec",  { link = "String" })
  vim.api.nvim_set_hl(0, "PoppyShell", { link = "Function" })
  vim.api.nvim_set_hl(0, "PoppyActiveDot",   { link = "Normal" })
  -- PoppyInactiveDot: no fg set (invisible by default)
  ```
- For hidden/background poppies: dynamically compute `PoppyFileHidden`, `PoppyExecHidden`, `PoppyShellHidden` by desaturating the cat color's fg

---

## Stage 6 — Hints Panel (`hints_panel.lua`)

- `update()` signature changes from `(buf, prefix, count, wrapper_width, mode)` to `(buf, keys, count, wrapper_width, mode)`
- Uses `keys.poppy_action`, `keys.select`, `keys.kill` for display text
- Landing mode: `" <keys.select> Select    <keys.poppy_action> Toggle Off "`
- Active mode (sidebar visible): `" <keys.select> Select    <keys.kill> Kill    <keys.poppy_action> Toggle Off "`
- Remove `prefix_col` parameter (no longer relevant)
- Keep hints panel full wrapper width (it spans the bottom of the wrapper)

---

## Stage 7 — Panels Autohide (`panels.lua`)

- Add `state.autohidden = false`
- Add `M.hide_for_autohide(content_win)`:
  - Closes hints + list windows, resizes content full wrapper
  - Sets `state.autohidden = true`
- Add `M.show_for_autohide(content_win)`:
  - Recreates list panel with `focusable=true` (so user can interact)
  - Recreates hints panel
  - Sets `state.autohidden = false`
- Add `M.is_autohidden()` accessor

---

## Stage 8 — Content Window (`content.lua`)

- Verify `border = "solid"` already set in `M.create()` config (it is)
- No structural changes needed

---

## Files Unchanged

| File | Reason |
|------|--------|
| `wrapper.lua` | Width/height/location logic untouched |
| `term.lua` | Mode execution unchanged |
| `file.lua` | Mode execution unchanged |
| `utils.lua` | Helpers unchanged |
| `init.lua` | Still pure delegation to session |
| `banner.lua` | Already deleted |

---

## Config Migration Guide

```lua
-- BEFORE:
require("poppy").setup({
    prefix_bind = "<M-,>",        -- REMOVED
    whichkey_disable = false,     -- REMOVED
    ...
})
vim.keymap.set({"n","t"}, "<M-,><M-,>", "<cmd>Poppy toggle<cr>", ...)  -- REDUNDANT

-- AFTER:
require("poppy").setup({
    keys = {
        poppy_action = "<M-,>",   -- same muscle memory
        select = "<CR>",
        kill = "k",
    },
    icons = {                      -- optional, defaults shown
        exec = "🛠",
        shell = "$",
        file = "🗋",
    },
    menu_autohide = false,         -- new, default false
    -- everything below unchanged:
    win_location = "center",
    win_height = function() ... end,
    win_width = function() ... end,
    sidebar_width = 22,
    poppies = { ... },
})
```