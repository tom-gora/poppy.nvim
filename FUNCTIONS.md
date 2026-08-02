# FUNCTIONS

Per-file function signatures, generated via lua-language-server.

## lua/poppy/config.lua

- `local sanitize_string_fields = function(defaults, user, keys, max_display_width)` ** LOCAL **
- `local title_fallback = function(mode, value)` ** LOCAL **
- `local resolve_poppy = function(name, poppy)` ** LOCAL **
- `M.merge = function(user_opts)` ** SHARED ** [used in: core/session/init.lua]

## lua/poppy/core/input.lua

- `M.setup_global = function(keys)` ** SHARED ** [used in: core/session/init.lua]
- `M.setup_menu = function(buf, keys)` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]
- `M.setup_content = function(buf, keys)` ** SHARED ** [used in: core/session/actions.lua]

## lua/poppy/core/modes/file.lua

- `M.run = function(poppy_name, opts, parent_win)` ** SHARED ** [used in: core/modes/term.lua]

## lua/poppy/core/modes/term.lua

- `local term_get_or_create_buffer = function(poppy_name, opts, p_state)` ** LOCAL **
- `local term_resolve_command = function(poppy_opts)` ** LOCAL **
- `local term_spawn = function(command, opts)` ** LOCAL **
- `M.run = function(poppy_name, opts, parent_win)` ** SHARED ** [used in: core/modes/file.lua]

## lua/poppy/core/session/actions.lua

- `local focus = function(win)` ** LOCAL **
- `local menu_width = function()` ** LOCAL **
- `local cursor_to_poppy_index = function(poppies)` ** LOCAL **
- `M.refresh_panels = function(sorted_poppies)` ** SHARED ** [used in: core/session/manager.lua]
- `list_panel_update = function(sorted_poppies, menu_width)` ** LOCAL **
- `local focus_list_with_cursor = function()` ** LOCAL **
- `local show_menu_hint_or_close = function()` ** LOCAL **
- `M.switch_by_name = function(poppy_name)` ** SHARED ** [used in: core/session/init.lua, core/session/manager.lua, init.lua]
- `M.switch_by_index = function(index)` ** SHARED ** [used in: core/session/init.lua, init.lua]
- `M.switch_by_cursor = function()` ** SHARED ** [used in: core/session/init.lua]
- `M.toggle_menu = function()` ** SHARED ** [used in: core/session/init.lua]
- `M.exit_menu = function()` ** SHARED ** [used in: core/session/events.lua, core/session/init.lua]
- `M.recover = function()` ** SHARED ** [used in: core/session/events.lua, core/shared.lua]
- `M.kill_active = function()` ** SHARED ** [used in: core/modes/term.lua, core/session/init.lua, core/shared.lua, init.lua]
- `local _kill = function(resolved)` ** LOCAL **
- `M.kill_by_name = function(name)` ** SHARED ** [used in: core/session/init.lua, init.lua]
- `M.kill_by_index = function(index)` ** SHARED ** [used in: core/session/init.lua, init.lua]
- `M.kill_by_cursor = function()` ** SHARED ** [used in: core/session/init.lua]

## lua/poppy/core/session/commands.lua

- `M.setup = function(opts, callbacks)` ** SHARED ** [used in: core/session/events.lua, core/session/init.lua, core/ui/style.lua, init.lua]

## lua/poppy/core/session/events.lua

- `M.setup_exclusive_float = function()` ** SHARED ** [used in: core/session/manager.lua]
- `M.setup = function(opts, callbacks)` ** SHARED ** [used in: core/session/commands.lua, core/session/init.lua, core/ui/style.lua, init.lua]

## lua/poppy/core/session/init.lua

- `M.setup = function(user_opts)` ** SHARED ** [used in: core/session/commands.lua, core/session/events.lua, core/ui/style.lua, init.lua]

## lua/poppy/core/session/manager.lua

- `local cleanup = function(drop_poppies)` ** LOCAL **
- `M.close = function()` ** SHARED ** [used in: core/session/init.lua, init.lua]
- `M.toggle = function()` ** SHARED ** [used in: core/session/init.lua, init.lua]
- `local open_wrapper = function(width_override)` ** LOCAL **
- `M.open = function(poppy_name)` ** SHARED ** [used in: core/session/init.lua, init.lua]

## lua/poppy/core/session/poppy_state.lua

- `local compute_landing_view_width = function(opts, poppies)` ** LOCAL **
- `M.entries = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]
- `M.runtime_get = function(name)` ** SHARED ** [used in: 5 other files]
- `M.runtime_set = function(name, record)` ** SHARED ** [used in: core/modes/file.lua, core/modes/term.lua]
- `M.runtime_remove = function(name)` ** SHARED ** [used in: core/modes/term.lua, core/session/actions.lua, core/session/events.lua]
- `M.iter = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]
- `M.is_empty = function()` ** SHARED ** [used in: core/session/manager.lua]
- `M.array_length = function()` ** SHARED ** [used in: core/session/actions.lua]
- `M.is_usable = function(name)` ** SHARED ** [used in: core/modes/file.lua]
- `M.resolve = function(name_or_index)` ** SHARED ** [used in: core/session/actions.lua]
- `M.hide = function(name)` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]
- `M.clear = function()` ** SHARED ** [used in: core/session/manager.lua]
- `M.rebuild_from_sorted = function(sorted)` ** SHARED ** [used in: core/session/init.lua]
- `M.ensure_entries_loaded = function()` ** SHARED ** [used in: core/session/manager.lua]
- `M.landing_view_width = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]
- `local build_poppy_public_data = function(i, entry)` ** LOCAL **
- `M.get_poppy_by_name = function(name)` ** SHARED ** [used in: core/session/init.lua, init.lua]
- `M.get_poppy_by_index = function(index)` ** SHARED ** [used in: core/session/init.lua, init.lua]
- `M.get_current_poppy = function()` ** SHARED ** [used in: core/session/init.lua, init.lua]
- `M.get_poppies = function()` ** SHARED ** [used in: core/session/init.lua, init.lua]

## lua/poppy/core/session/state.lua

- `M.init = function()` ** SHARED ** [used in: core/session/init.lua]

## lua/poppy/core/shared.lua

- `M.session_is_open = function()` ** SHARED ** [used in: 5 other files]
- `M.session_get_current_poppy_name = function()` ** SHARED ** [used in: core/modes/term.lua, core/session/init.lua]
- `M.close_menu_hint = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]
- `M.keys = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/init.lua, core/session/manager.lua]
- `M.with_modifiable = function(buf, fn)` ** SHARED ** [used in: core/ui/header_panel.lua, core/ui/hints_panel.lua, core/ui/list_panel.lua]
- `M.get_sorted_poppies = function(opts)` ** SHARED ** [used in: core/session/init.lua, core/session/poppy_state.lua]
- `M.cat = function(poppy)` ** SHARED ** [used in: config.lua, core/session/poppy_state.lua, core/ui/list_panel.lua]
- `watch_content_window = function(win_id, menu_width)` ** LOCAL **
- `M.transition_to_content = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]
- `M.enter_landing = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]

## lua/poppy/core/ui/content.lua

- `M.create = function(wrapper_win, list_panel_width)` ** SHARED ** [used in: 6 other files]

## lua/poppy/core/ui/header_panel.lua

- `M.create = function(wrapper_win, width_override, col_override)` ** SHARED ** [used in: 5 other files]
- `M.recreate = function(wrapper_win, buf, width_override, col_override)` ** SHARED ** [used in: core/ui/hints_panel.lua, core/ui/list_panel.lua, core/ui/panels.lua, core/ui/wrapper.lua]

## lua/poppy/core/ui/hints_panel.lua

- `local fmt_hint = function(key, label)` ** LOCAL **
- `M.create = function(wrapper_win, opts)` ** SHARED ** [used in: 5 other files]
- `M.create_bottom_right = function(parent_win, keys)` ** SHARED ** [used in: core/session/actions.lua]
- `M.recreate = function(wrapper_win, buf, opts)` ** SHARED ** [used in: core/ui/header_panel.lua, core/ui/list_panel.lua, core/ui/panels.lua, core/ui/wrapper.lua]
- `M.update = function(buf, keys, count, wrapper_width, kind, mode)` ** SHARED ** [used in: core/session/actions.lua, core/ui/list_panel.lua]

## lua/poppy/core/ui/layout.lua

- `M.get_header_height = function(opts)` ** SHARED ** [used in: core/shared.lua]
- `M.normalize_ratio_or_pixels = function(value, default)` ** SHARED ** [used in: config.lua]
- `local resolve_dimension = function(value, total, name)` ** LOCAL **
- `M.compute_wrapper_dimensions = function(opts, vim_cols, vim_lines, override_width)` ** SHARED ** [used in: core/shared.lua, core/ui/wrapper.lua]

## lua/poppy/core/ui/list_panel.lua

- `local pick_sign = function(dot, cat, is_active, is_hidden)` ** LOCAL **
- `M.create = function(wrapper_win, menu_width, focusable, hint_height, row_override)` ** SHARED ** [used in: 5 other files]
- `M.recreate = function(wrapper_win, buf, menu_width, focusable, hint_height, row_override)` ** SHARED ** [used in: core/ui/header_panel.lua, core/ui/hints_panel.lua, core/ui/panels.lua, core/ui/wrapper.lua]
- `local max_index_width = function(count)` ** LOCAL **
- `local trim_title = function(title, max_width)` ** LOCAL **
- `M.update = function(buf, sorted_poppies, poppies, icons, menu_width)` ** SHARED ** [used in: core/session/actions.lua, core/ui/hints_panel.lua]

## lua/poppy/core/ui/panels.lua

- `local valid_buf = function(b)` ** LOCAL **
- `local resize_content = function(win, width, height, row)` ** LOCAL **
- `local close_panel = function(win)` ** LOCAL **
- `local close_all_panels = function()` ** LOCAL **
- `local ensure_panel = function(buf_key, win_key, create, recreate, skip)` ** LOCAL **
- `local rebuild = function(hl, focusable)` ** LOCAL **
- `M.create = function(wrapper_win, menu_width, hint_height, header_height)` ** SHARED ** [used in: 6 other files]
- `M.create_landing = function(wrapper_win, header_height)` ** SHARED ** [used in: core/shared.lua]
- `M.focus_menu = function()` ** SHARED ** [used in: core/session/actions.lua]
- `M.unfocus_menu = function()` ** SHARED ** [used in: core/session/actions.lua]
- `M.hide_menu = function(content_win)` ** SHARED ** [used in: core/session/actions.lua]
- `M.show_menu = function(content_win)` ** SHARED ** [used in: core/session/actions.lua]
- `M.destroy = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua, core/shared.lua]
- `M.is_hidden = function()` ** SHARED ** [used in: core/session/actions.lua]
- `M.mark_poppy_window = function(win)` ** LOCAL **
- `M.is_poppy_window = function(win)` ** SHARED ** [used in: core/session/events.lua]
- `M.get_hints_buf = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua]
- `M.get_list_buf = function()` ** SHARED ** [used in: core/session/actions.lua, core/session/manager.lua, core/shared.lua]
- `M.get_list_win = function()` ** SHARED ** [used in: core/session/actions.lua, core/shared.lua]
- `M.get_header_buf = function()` ** SHARED ** [used in: core/session/manager.lua]

## lua/poppy/core/ui/style.lua

- `local adjust_brightness = function(color, factor)` ** LOCAL **
- `local define_poppy_signs = function()` ** LOCAL **
- `local set_winhl_deferred = function(win, mappings)` ** LOCAL **
- `M.setup = function()` ** SHARED ** [used in: core/session/commands.lua, core/session/events.lua, core/session/init.lua, init.lua]
- `M.apply_hints_panel_style = function(win)` ** SHARED ** [used in: core/ui/hints_panel.lua]
- `M.apply_list_panel_style = function(win)` ** SHARED ** [used in: core/ui/header_panel.lua, core/ui/list_panel.lua]
- `M.apply_content_style = function(win, ext_number, ext_relativenumber)` ** SHARED ** [used in: core/ui/content.lua]
- `M.apply_border_style = function(win)` ** SHARED ** [used in: core/ui/wrapper.lua]

## lua/poppy/core/ui/wrapper.lua

- `local open_with = function(buf, poppy_opts, width_override)` ** LOCAL **
- `M.create = function(poppy_opts, width_override)` ** SHARED ** [used in: 6 other files]
- `M.recreate = function(buf, poppy_opts, width_override)` ** SHARED ** [used in: core/session/manager.lua, core/ui/header_panel.lua, core/ui/hints_panel.lua, core/ui/list_panel.lua]

## lua/poppy/init.lua

- _(none)_
