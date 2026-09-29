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
---@field exec? string|string[]
---@field file? string
---@field shell? string|function
---@field title? string

---@class PoppyConfig
---@field keys? PoppyKeys # Keybindings: poppy_action, select, kill, exit_menu. Default: { poppy_action = "<C-_>", select = "<CR>", kill = "d", exit_menu = "<Esc>" }
---@field icons? PoppyIcons # Icons per poppy type: exec, shell, file. Default: { exec = "🛠", shell = "$", file = "🗋" }
---@field menu_autohide? boolean # If true, hide sidebar style menu after selecting a poppy. Default: false
---@field title_header? boolean # Show "POPPY" header panel above list. Default: true
---@field autoclose? boolean # Close the manager when focus leaves all poppy windows. Default: true
---@field exclusive_float? boolean # When poppy opens close all other floating windows
---@field menu_width? number|function # Width of side panels. Function re-evaluated on each mount and sidebar toggle. Default: 25
---@field win_height? number|function # Height ratio of screen (0.2-1.0), or absolute columns/lines (>1), or function returning same. Default: 0.75
---@field win_width? number|function # Width ratio of screen (0.2-1.0), or absolute columns/lines (>1), or function returning same. Default: 0.8
---@field win_location? "center"|"top"|"bottom" # Vertical position of the wrapper. Default: "center"
---@field poppies? table<string, PoppyItemConfig>

---@class PoppyMergedConfig
---@field keys PoppyKeys
---@field icons PoppyIcons
---@field menu_autohide boolean
---@field title_header boolean
---@field autoclose boolean
---@field exclusive_float boolean
---@field menu_width number|function
---@field win_height number|function
---@field win_width number|function
---@field win_location "center"|"top"|"bottom"
---@field poppies table<string, PoppyItemConfig>
---@field poppies_resolved table<string, PoppyResolvedConfig>
---@field dropped_names string[]

---@class PoppyResolvedConfig
---@field exec? string|string[]
---@field file? string
---@field shell? string|function
---@field mode "term"|"file"
---@field title string

---@class PoppyRuntimeState
---@field active boolean
---@field hidden boolean
---@field bufnr integer
---@field win integer|nil
---@field title string

---@class PoppySessionEntry
---@field name string
---@field config PoppyResolvedConfig
---@field runtime_state PoppyRuntimeState? nil ⇔ never opened or just closed; non-nil ⇔ currently open with the inner runtime table.

---@class PoppyHintOpts
---@field kind? "landing"|"menu"
---@field row? integer
---@field col? integer
---@field width? integer
---@field height? integer
