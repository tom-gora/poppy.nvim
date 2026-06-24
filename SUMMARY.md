# Poppy.nvim Technical Summary

Poppy.nvim is a Neovim plugin designed to manage floating windows that can either contain a terminal session or a file view. The project has been flattened to remove unnecessary backend multiplexer abstractions.

---

## `lua/poppy/init.lua`
The main entry point for the plugin. It manages setup, user commands, and IPC communication.

### Dependencies
- `poppy.config`: For merging user configurations.
- `poppy.shared.state`: For tracking the active state of popups.
- `poppy.executor`: For determining if an `exec` is a terminal command or a file.
- `poppy.term`: For handling terminal-based floating windows.
- `poppy.float`: For handling file-based floating windows.

### Key Functions
- `M.setup(user_opts)`: Initializes the plugin, merges configuration, sets up the state directory, and starts a file watcher (via `vim.loop.new_fs_event`) to handle IPC updates from external processes.
- `open_popup(popup_name)`: Orchestrates opening a popup.
  - Deactivates current active popups.
  - Determines if the popup is a terminal or file view using `executor.is_executable`.
  - Calls `term.run` or `float.run`.
- `M._sync_state(raw_popup_name, action)`: Syncs the internal state when an IPC message is received (e.g., 'hide' or 'close' from the running terminal process).
- **User Commands**: Defines `Poppy`, `PoppyClose`, and `PoppyHide` to interact with popups.
- **Autocommands**: Defines a `WinLeave` autocommand to automatically hide the popup when focus is lost.

---

## `lua/poppy/term.lua`
Handles floating windows that spawn a terminal process.

### Dependencies
- `poppy.executor`: For preparing the execution command.
- `poppy.shared.state`: For updating global popup state.
- `poppy.utils`: For IPC communication (`send_ipc`) and process spawning (`spawn_term`).
- `poppy.style`: For calculating window layout and options.

### Key Functions
- `M.run(popup_name, opts)`:
  - Calculates layout using `style`.
  - Creates a new buffer or uses an existing one if available.
  - Opens a floating window with `vim.api.nvim_open_win`.
  - Sets terminal keymaps for hiding/closing (`<C-d>`/`<C-q>`).
  - Calls `utils.spawn_term` to start the terminal process, with an `on_exit` callback to clean up the buffer/window.
- `M.close_session(popup_name)` and `M.hide_session(popup_name)`: Clean up the window/buffer and update state.

---

## `lua/poppy/float.lua`
Handles floating windows that display a file.

### Dependencies
- `poppy.shared.state`: For tracking active windows/buffers.
- `poppy.style`: For layout calculations.
- `poppy.executor`: For verifying execution parameters.

### Key Functions
- `M.run(popup_name, opts)`:
  - Similar to `term.run`, but instead of a terminal process, it opens a file in the buffer using `vim.cmd("edit ...")` if the `exec` is a file path.
- `M.close_session(popup_name)` and `M.hide_session(popup_name)`: Clean up the window/buffer and update state.

---

## `lua/poppy/utils.lua`
Low-level utility functions for IPC and terminal management.

### Dependencies
- `poppy.shared.state`: To access `STATE_FILE`.

### Key Functions
- `M.send_ipc(popup_name, action)`: Writes an IPC action (`hide`/`close`) to the state file in JSON format.
- `M.spawn_term(command, opts)`: Wraps terminal spawning, using `jobstart` (for Neovim 0.11+) or `termopen` (for older versions).

---

## `lua/poppy/style.lua`
Handles UI-related calculations.

### Functions
- `M.calculate_layout(popup_opts, opts)`: Computes width, height, row, col, and alignment based on screen dimensions and plugin configuration.
- `M.get_win_opts(...)`: Generates the options table required by `vim.api.nvim_open_win`, including borders, titles, and footers.

---

## `lua/poppy/config.lua`
Handles configuration validation and merging.

### Functions
- `M.merge(user_opts)`: Merges user-provided options with `default_opts`.
- `sanitize(opts)`: Validates width, height, and popup executables, clamping values and removing invalid entries.
- `check_exec(exec)`: Helper function to determine if a string or table is executable or a readable file.

---

## `lua/poppy/executor.lua`
Responsible for interpreting and preparing the execution command.

### Functions
- `M.is_executable(exec)`: Checks if a string or table command is an executable.
- `M.prepare(exec)`: Prepares the execution string. If it's a file, it wraps it in a minimal `nvim` instance with specific styling and settings (no shada, no swapfile).

---

## `lua/poppy/shared/state.lua`
Defines the global plugin state.

### Exported Data
- `M.popups`: A table tracking `{ active = boolean, hidden = boolean, bufnr = number, win = number }`.
- `M.STATE_DIR` and `M.STATE_FILE`: Paths for the IPC communication file.
