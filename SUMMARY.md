# Poppy.nvim Technical Summary

Poppy.nvim is a declarative Neovim plugin designed to manage floating windows that can contain a terminal session, a file view, or a shell.

---

## `lua/poppy/init.lua`
The main entry point for the plugin. It manages setup, user commands, and orchestrates popup lifecycle.

### Key Functions
- `M.setup(user_opts)`: Initializes the plugin, merges configuration, sets up user commands, and registers shared autocmds.
- `open_popup(popup_name)`: Orchestrates opening a popup by dispatching to the appropriate mode (`exec`, `file`, or `shell`).

---

## `lua/poppy/modes/`
Encapsulates backend-specific logic.

### Shared Logic (`lua/poppy/modes/utils.lua`)
- `M.spawn_term(command, opts)`: Handles terminal spawning (abstracting jobstart/termopen).
- `M.title_fallback(mode, value)`: Generates smart titles based on mode and command/file path.

### Mode Modules (`exec.lua`, `file.lua`, `shell.lua`)
- Each module provides a `run(popup_name, opts)`, `close_session(popup_name)`, and `hide_session(popup_name)` function.
- Responsible for window creation, buffer management, and keymap registration.

---

## `lua/poppy/state.lua`
Defines the global plugin state.

### Exported Data
- `M.popups`: A table tracking `{ active = boolean, hidden = boolean, bufnr = number, win = number, title = string }`.

---

## `lua/poppy/style.lua`
Handles UI-related calculations.

### Functions
- `M.calculate_layout(popup_opts, opts)`: Computes width, height, row, col, and alignment.
- `M.get_win_opts(...)`: Generates options for `vim.api.nvim_open_win`.

---

## `lua/poppy/config.lua`
Handles configuration validation and merging.

### Functions
- `M.merge(user_opts)`: Merges user-provided options with `default_opts`.
- `sanitize(opts)`: Validates configuration, enforces exclusive mode (`exec`/`file`/`shell`), and sets default titles via `utils.title_fallback`.

---

## LATEST SESSION
- **Refactored Architecture**:
  - Removed all IPC mechanism (watcher, state files, utils.send_ipc).
  - Adopted a native event-driven model completely within Neovim.
  - Flattened structure: Moved state to `lua/poppy/state.lua`, created `lua/poppy/modes/` for backend-specific logic.
- **Improved Configuration**:
  - Replaced implicit detection with explicit mode definition (`exec`, `file`, `shell`).
  - Added smart title fallback mechanism (`title_fallback`) in `modes/utils.lua`.
  - Added `title` field to the global state tracker for better introspection.
- **Maintenance**:
  - Cleaned up obsolete modules (`executor.lua`, `term.lua`, `float.lua`, `shared/`).
  - Improved error handling with fail-fast validation for mode configuration and graceful degradation for resource failures.
