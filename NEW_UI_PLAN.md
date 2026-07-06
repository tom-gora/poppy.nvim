# Poppy.nvim New UI Implementation Plan

This document outlines the structured, step-by-step approach to implementing the new unified UI for poppy.nvim, keeping the development iterative and non-breaking by leveraging the `ui-rewrite` feature branch and a modular `lua/poppy/ui/` structure.

## Phase 1: Architecture & Foundations
1. **Establish Feature Branch**: Switch to and ensure you are working on the `ui-rewrite` branch.
2. **Create New UI Module Directory**: Create `lua/poppy/ui/` to house the new implementation.
3. **Centralize UI State Logic**: Consolidate UI state management and lifecycle tracking within `lua/poppy/state.lua` to maintain a single source of truth.

## Phase 2: Master UI Core (The Wrapper)
4. **Implement Master Controller**: Create `lua/poppy/ui/wrapper.lua` to handle primary floating window creation and positioning (replacing prototype's `create_main_window`).
5. **Abstract Content Renderer**: Create a utility to manage loading existing `modes/` (exec, shell, file) into the Master Controller's central buffer.

## Phase 3: Sidebar & Component Orchestration
6. **Implement Sidebar Components**: Create `lua/poppy/ui/sidebar_right.lua` (for tab list) and `lua/poppy/ui/sidebar_left.lua` (for keybind helper).
7. **Sync Mechanism**: Implement a "UI Refresher" function that reads from the `Poppy State Store` and updates sidebar buffers (extmarks/highlights) whenever the state changes.

## Phase 4: Input Handling
8. **Prefix-Mode Input Handler**: Create `lua/poppy/ui/input.lua` to catch keypresses in the wrapper window and implement `<Esc>`-based command logic.
9. **Keybind Mapping**: Define the mapping table for new "prefix mode" actions (e.g., dismissing, switching tabs, killing poppies).

## Phase 5: Integration & Cleanup
10. **Bridge to Legacy API**: Create a compatibility shim in `lua/poppy/init.lua` so existing `Poppy <name>` calls can optionally spawn the new UI.
11. **Refactor and Migrate**: Gradually move legacy logic into new UI modules, validating against `modes/` until legacy popups are fully deprecated.
12. **Verify & Polish**: Ensure performance, fix remaining window focus/input issues, and clean up the `prototyping.lua` file.
