-- Shared LuaCATS type definitions for poppy.nvim. Loaded via require for
-- side effect (registers @class blocks with LuaCATS-aware tooling); no
-- runtime exports.

---@class PoppyKeys
---@field poppy_action string # Toggle on / toggle menu / toggle off
---@field select string       # In sidebar: switch to count-th / cursor-row poppy
---@field kill string         # In sidebar: kill count-th / cursor-row poppy
---@field exit_menu string    # In sidebar: return focus to active poppy

---@class PoppyIcons
---@field exec string
---@field shell string
---@field file string

---@class PoppyItemConfig
---@field exec? string|string[]|function # Command for a terminal buffer. A function is called at setup (validation) and again at open.
---@field file? string|function # Path to open. A function is called at setup and again at open.
---@field shell? string|function # Shell binary, or "default" for $SHELL.
---@field title? string

---@class PoppyConfig
---@field keys? PoppyKeys # Keybindings: poppy_action, select, kill, exit_menu. Default: { poppy_action = "<C-_>", select = "<CR>", kill = "d", exit_menu = "<Esc>" }
---@field icons? PoppyIcons # Icons per poppy type: exec, shell, file. Default: { exec = "🛠", shell = "$", file = "🗋" }
---@field menu_autohide? boolean # If true, hide sidebar style menu after selecting a poppy. Default: false
---@field title_header? boolean # Show "POPPY" header panel above list. Default: true
---@field hints_footer? boolean # Show keybind legend below list. Default: true
---@field autoclose? boolean # Close the manager when focus leaves all poppy windows. Default: true
---@field exclusive_float? boolean # When poppy opens close all other floating windows
---@field assume_multiplexer? boolean # Force the <C-/> → <C-_> fallback regardless of env detection. Default: false
---@field menu_width? number|function # Width of side panels. Function re-evaluated on each mount and sidebar toggle. Default: 25
---@field win_height? number|function # Height ratio of screen (0.2-1.0), or absolute columns/lines (>1), or function returning same. Default: 0.75
---@field win_width? number|function # Width ratio of screen (0.2-1.0), or absolute columns/lines (>1), or function returning same. Default: 0.8
---@field win_location? "center"|"top"|"bottom" # Vertical position of the wrapper. Default: "center"
---@field poppies? table<string, PoppyItemConfig>
---@field experimental? { borders?: boolean } # WIP: opt-in to new bordered UI work. Default: { borders = false }.

---@class PoppyMergedConfig
---@field keys PoppyKeys
---@field icons PoppyIcons
---@field menu_autohide boolean
---@field title_header boolean
---@field hints_footer boolean
---@field autoclose boolean
---@field exclusive_float boolean
---@field assume_multiplexer boolean
---@field menu_width number|function
---@field win_height number|function
---@field win_width number|function
---@field win_location "center"|"top"|"bottom"
---@field poppies table<string, PoppyItemConfig>
---@field poppies_resolved table<string, PoppyResolvedConfig>
---@field dropped_names string[]

-- Only `mode` and `title` are actually resolved. exec/file/shell keep the
-- user's raw value verbatim (function included) so modes can re-evaluate at
-- open time; a `file` string is also unexpanded here.
---@class PoppyResolvedConfig
---@field exec? string|string[]|function
---@field file? string|function # Raw, unexpanded path or function returning one.
---@field shell? string|function
---@field mode "term"|"file"
---@field title string

---@class PoppyRuntimeState
---@field active boolean
---@field hidden boolean
---@field bufnr integer|nil
---@field win integer|nil
---@field title string

---@class PoppySessionEntry
---@field name string
---@field config PoppyResolvedConfig
---@field runtime_state PoppyRuntimeState? nil ⇔ never opened or just closed; non-nil ⇔ currently open with the inner runtime table.

---@class PoppyHintOpts
---@field row? integer
---@field row_offset? integer Nudges the panel down from `row`; placement only.
---@field col? integer
---@field width? integer
---@field height? integer Legend lines to render; the separator and trailing blank are added on top.
---@field hints? {string, string}[] Legend rows, used only to derive `height` when that is absent.

-- Menu backend vocabulary. A "menu" is a spec the backend renders into panels; the
-- poppy list is one instance of it and a dialog will be another. Nothing here is
-- poppy-specific -- `label` is display text, not a poppy's title, and it only
-- becomes a title where the spec is built from PoppyResolvedConfig.
---@alias PoppyMenuWidth "declared"|"content"

---@class MenuItem
---@field label string Display text for the row, already fitted to the panel width.
---@field marks string[] Sign names stacked in this row's signcolumn, highest priority first.
---@field hl string|nil Line highlight group, or nil for the default.

---@class MenuItems
---@field idx_width integer Width of the index gutter, in characters.
---@field rows MenuItem[]

---@class PoppyMenuKeymap
---@field field string PoppyKeys field naming the key, e.g. "select".
---@field desc string Short description, used for the mapping's desc and the legend label.
---@field fn function

---@class PoppyMenuSpec
---@field id string
---@field width PoppyMenuWidth "declared" honours menu_width; "content" sizes to content.
---@field focusable boolean May the body panel take focus.
---@field trap boolean Block every exit route while up. Dialogs only.
---@field rows MenuItem[]
---@field hints {string, string}[] Legend rows: PoppyKeys field name, label.
---@field keymaps PoppyMenuKeymap[]

---@class PoppyMenuTarget
---@field menu_buf integer Body buffer the rows are painted into.
---@field hints_buf integer? Legend buffer; skipped when nil.
---@field list_width integer Width the labels were fitted against.
---@field hints_width integer Width the legend rule spans.
