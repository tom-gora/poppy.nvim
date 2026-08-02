# FUNCTIONS

Per-file function signatures, generated via lua-language-server.

## lua/poppy/config.lua

- `local sanitize_string_fields = function(defaults, user, keys, max_display_width)` ** LOCAL **
- `local resolve_poppy = function(name, poppy)` ** LOCAL **
- `M.merge = function(user_opts)` ** SHARED ** [used in: init.lua]

## lua/poppy/core/input.lua

- `M.setup_global = function(keys)` ** SHARED ** [used in: init.lua]
- `M.setup_menu = function(buf, keys)` ** SHARED ** [used in: actions.lua, manager.lua]
- `M.setup_content = function(buf, keys)` ** SHARED ** [used in: actions.lua]

## lua/poppy/core/modes/file.lua

- `M.run = function(poppy_name, opts, parent_win)` ** SHARED ** [used in: term.lua]

## lua/poppy/core/modes/term.lua

- `M.run = function(poppy_name, opts, parent_win)` ** SHARED ** [used in: file.lua]

## lua/poppy/core/session/actions.lua

- `M.refresh_panels = function(sorted_poppies)` ** SHARED ** [used in: manager.lua]
- `list_panel_update = function(sorted_poppies, menu_width)` ** LOCAL **
- `local focus_list_with_cursor = function()` ** LOCAL **
- `local show_menu_hint_or_close = function()` ** LOCAL **
- `M.switch_by_name = function(poppy_name)` ** SHARED ** [used in: init.lua, manager.lua, init.lua]
- `M.switch_by_index = function(index)` ** SHARED ** [used in: init.lua, init.lua]
- `M.switch_by_cursor = function()` ** SHARED ** [used in: init.lua]
- `M.toggle_menu = function()` ** SHARED ** [used in: init.lua]
- `M.exit_menu = function()` ** SHARED ** [used in: events.lua, init.lua]
- `M.recover = function()` ** SHARED ** [used in: events.lua, util.lua]
- `M.kill_active = function()` ** SHARED ** [used in: 4 other files]
- `local _kill = function(resolved)` ** LOCAL **
- `M.kill_by_name = function(name)` ** SHARED ** [used in: init.lua, init.lua]
- `M.kill_by_index = function(index)` ** SHARED ** [used in: init.lua, init.lua]
- `M.kill_by_cursor = function()` ** SHARED ** [used in: init.lua]

## lua/poppy/core/session/commands.lua

- `M.setup = function(opts, callbacks)` ** SHARED ** [used in: 4 other files]

## lua/poppy/core/session/events.lua

- `M.setup_exclusive_float = function()` ** SHARED ** [used in: manager.lua]
- `M.setup = function(opts, callbacks)` ** SHARED ** [used in: 4 other files]

## lua/poppy/core/session/init.lua

- `M.setup = function(user_opts)` ** SHARED ** [used in: 4 other files]

## lua/poppy/core/session/manager.lua

- `local cleanup = function(drop_poppies)` ** LOCAL **
- `M.close = function()` ** SHARED ** [used in: init.lua, init.lua]
- `M.toggle = function()` ** SHARED ** [used in: init.lua, init.lua]
- `local open_wrapper = function(width_override)` ** LOCAL **
- `M.open = function(poppy_name)` ** SHARED ** [used in: init.lua, init.lua]

## lua/poppy/core/session/poppy_state.lua

- `M.entries = function()` ** SHARED ** [used in: actions.lua, manager.lua]
- `M.runtime_get = function(name)` ** SHARED ** [used in: 5 other files]
- `M.runtime_set = function(name, record)` ** SHARED ** [used in: file.lua, term.lua]
- `M.runtime_remove = function(name)` ** SHARED ** [used in: term.lua, actions.lua, events.lua]
- `M.iter = function()` ** SHARED ** [used in: actions.lua, manager.lua]
- `M.is_empty = function()` ** SHARED ** [used in: manager.lua]
- `M.array_length = function()` ** SHARED ** [used in: actions.lua]
- `M.is_usable = function(name)` ** SHARED ** [used in: file.lua]
- `M.resolve = function(name_or_index)` ** SHARED ** [used in: actions.lua]
- `M.hide = function(name)` ** SHARED ** [used in: actions.lua, manager.lua]
- `M.clear = function()` ** SHARED ** [used in: manager.lua]
- `M.rebuild_from_sorted = function(sorted)` ** SHARED ** [used in: init.lua]
- `M.ensure_entries_loaded = function()` ** SHARED ** [used in: manager.lua]
- `M.landing_view_width = function()` ** SHARED ** [used in: actions.lua, manager.lua]
- `local build_poppy_public_data = function(i, entry)` ** LOCAL **
- `M.get_poppy_by_name = function(name)` ** SHARED ** [used in: init.lua, init.lua]
- `M.get_poppy_by_index = function(index)` ** SHARED ** [used in: init.lua, init.lua]
- `M.get_current_poppy = function()` ** SHARED ** [used in: init.lua, init.lua]
- `M.get_poppies = function()` ** SHARED ** [used in: init.lua, init.lua]

## lua/poppy/core/session/state.lua

- `M.init = function()` ** SHARED ** [used in: init.lua]

## lua/poppy/core/ui/content.lua

- `M.create = function(wrapper_win, list_panel_width)` ** SHARED ** [used in: 6 other files]

## lua/poppy/core/ui/header_panel.lua

- `M.create = function(wrapper_win, width_override, col_override)` ** SHARED ** [used in: 5 other files]
- `M.recreate = function(wrapper_win, buf, width_override, col_override)` ** SHARED ** [used in: 4 other files]

## lua/poppy/core/ui/hints_panel.lua

- `local fmt_hint = function(key, label)` ** LOCAL **
- `M.create = function(wrapper_win, opts)` ** SHARED ** [used in: 5 other files]
- `M.create_bottom_right = function(parent_win, keys)` ** SHARED ** [used in: actions.lua]
- `M.recreate = function(wrapper_win, buf, opts)` ** SHARED ** [used in: 4 other files]
- `M.update = function(buf, keys, count, wrapper_width, kind, mode)` ** SHARED ** [used in: actions.lua, list_panel.lua]

## lua/poppy/core/ui/layout.lua

- `M.get_header_height = function(opts)` ** SHARED ** [used in: util.lua]
- `M.normalize_ratio_or_pixels = function(value, default)` ** SHARED ** [used in: config.lua]
- `local resolve_dimension = function(value, total, name)` ** LOCAL **
- `M.compute_wrapper_dimensions = function(opts, vim_cols, vim_lines, override_width)` ** SHARED ** [used in: wrapper.lua, util.lua]

## lua/poppy/core/ui/list_panel.lua

- `local pick_sign = function(dot, cat, is_active, is_hidden)` ** LOCAL **
- `M.create = function(wrapper_win, menu_width, focusable, hint_height, row_override)` ** SHARED ** [used in: 5 other files]
- `M.recreate = function(wrapper_win, buf, menu_width, focusable, hint_height, row_override)` ** SHARED ** [used in: 4 other files]
- `local max_index_width = function(count)` ** LOCAL **
- `local trim_title = function(title, max_width)` ** LOCAL **
- `M.update = function(buf, sorted_poppies, poppies, icons, menu_width)` ** SHARED ** [used in: actions.lua, hints_panel.lua]

## lua/poppy/core/ui/panels.lua

- `local valid_buf = function(b)` ** LOCAL **
- `local resize_content = function(win, width, height, row)` ** LOCAL **
- `local close_panel = function(win)` ** LOCAL **
- `local close_all_panels = function()` ** LOCAL **
- `local ensure_panel = function(buf_key, win_key, create, recreate, skip)` ** LOCAL **
- `local rebuild = function(hl, focusable)` ** LOCAL **
- `M.create = function(wrapper_win, menu_width, hint_height, header_height)` ** SHARED ** [used in: 6 other files]
- `M.create_landing = function(wrapper_win, header_height)` ** SHARED ** [used in: util.lua]
- `M.focus_menu = function()` ** SHARED ** [used in: actions.lua]
- `M.unfocus_menu = function()` ** SHARED ** [used in: actions.lua]
- `M.hide_menu = function(content_win)` ** SHARED ** [used in: actions.lua]
- `M.show_menu = function(content_win)` ** SHARED ** [used in: actions.lua]
- `M.destroy = function()` ** SHARED ** [used in: actions.lua, manager.lua, util.lua]
- `M.is_hidden = function()` ** SHARED ** [used in: actions.lua]
- `M.mark_poppy_window = function(win)` ** LOCAL **
- `M.is_poppy_window = function(win)` ** SHARED ** [used in: events.lua]
- `M.get_hints_buf = function()` ** SHARED ** [used in: actions.lua, manager.lua]
- `M.get_list_buf = function()` ** SHARED ** [used in: actions.lua, manager.lua, util.lua]
- `M.get_list_win = function()` ** SHARED ** [used in: actions.lua, util.lua]
- `M.get_header_buf = function()` ** SHARED ** [used in: manager.lua]

## lua/poppy/core/ui/style.lua

- `local adjust_brightness = function(color, factor)` ** LOCAL **
- `local define_poppy_signs = function()` ** LOCAL **
- `local set_winhl_deferred = function(win, mappings)` ** LOCAL **
- `M.setup = function()` ** SHARED ** [used in: 4 other files]
- `M.apply_hints_panel_style = function(win)` ** SHARED ** [used in: hints_panel.lua]
- `M.apply_list_panel_style = function(win)` ** SHARED ** [used in: header_panel.lua, list_panel.lua]
- `M.apply_content_style = function(win, ext_number, ext_relativenumber)` ** SHARED ** [used in: content.lua]
- `M.apply_border_style = function(win)` ** SHARED ** [used in: wrapper.lua]

## lua/poppy/core/ui/wrapper.lua

- `local open_with = function(buf, poppy_opts, width_override)` ** LOCAL **
- `M.create = function(poppy_opts, width_override)` ** SHARED ** [used in: 6 other files]
- `M.recreate = function(buf, poppy_opts, width_override)` ** SHARED ** [used in: 4 other files]

## lua/poppy/core/util.lua

- `M.session_is_open = function()` ** SHARED ** [used in: 5 other files]
- `M.session_get_current_poppy_name = function()` ** SHARED ** [used in: term.lua, init.lua]
- `M.close_menu_hint = function()` ** SHARED ** [used in: actions.lua, manager.lua]
- `M.keys = function()` ** SHARED ** [used in: actions.lua, init.lua, manager.lua]
- `M.focus = function(win)` ** SHARED ** [used in: actions.lua]
- `M.menu_width = function()` ** SHARED ** [used in: actions.lua]
- `M.term_spawn = function(command, opts)` ** SHARED ** [used in: term.lua]
- `M.term_resolve_command = function(poppy_opts)` ** SHARED ** [used in: term.lua]
- `M.with_modifiable = function(buf, fn)` ** SHARED ** [used in: header_panel.lua, hints_panel.lua, list_panel.lua]
- `M.term_get_or_create_buffer = function(poppy_name, opts, p_state)` ** SHARED ** [used in: term.lua]
- `M.cursor_to_poppy_index = function(poppies)` ** SHARED ** [used in: actions.lua]
- `M.compute_landing_view_width = function(opts, poppies)` ** SHARED ** [used in: poppy_state.lua]
- `M.get_sorted_poppies = function(opts)` ** SHARED ** [used in: init.lua, poppy_state.lua]
- `M.title_fallback = function(mode, value)` ** SHARED ** [used in: config.lua]
- `M.cat = function(poppy)` ** SHARED ** [used in: config.lua, poppy_state.lua, list_panel.lua]
- `watch_content_window = function(win_id, menu_width)` ** LOCAL **
- `M.transition_to_content = function()` ** SHARED ** [used in: actions.lua, manager.lua]
- `M.enter_landing = function()` ** SHARED ** [used in: actions.lua, manager.lua]

## lua/poppy/init.lua

- _(none)_
