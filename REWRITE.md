# Refactoring Summary

This session focused on simplifying `poppy.nvim` by removing complex abstractions and improving native Neovim integration.

## Key Changes
- **Removed tmux dependency:** Completely ripped out tmux backend code, logic, and configuration (`preferred_backend`).
- **Implemented Hybrid Backend:**
    - **`float` backend (New):** Files now open in native, isolated floating windows.
    - **`term` backend:** Commands/executables continue to use terminal buffers.
- **Architecture Improvements:**
    - Restructured backends under `lua/poppy/backends/`.
    - Enabled persistent, isolated file notes by setting `buflisted = false` and `bufhidden = "hide"`.
    - Fixed rendering issues (image previews) by removing nested terminal sessions for file popups.
- **UI/UX Fixes:**
    - Fixed `SignColumn` background color in floating windows.
    - Fixed alignment configuration errors (`centre` -> `center`).
    - Corrected footer keybinding label alignment.
