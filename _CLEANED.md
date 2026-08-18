# \_CLEANED

Resolved items moved out of `REVIEW.md`.

- `panels.lua:99` `rebuild` references `state.windows.menu_width` and
  `state.windows.header_height` which are local state — but the panel
  width is also passed in as `menu_width` and silently ignored in
  favor of the state field. Either remove the parameter or use it.

- `focus()` helper is duplicated verbatim in `actions.lua:9–15` and
  `menu.lua:7–13`. Identical five-line body in both. Should live in
  `shared.lua`.


