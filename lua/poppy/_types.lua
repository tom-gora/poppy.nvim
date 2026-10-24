---@class PoppyKeys
---@field poppy_action string
---@field select string
---@field kill string
---@field exit_menu string

---@class PoppyIcons
---@field exec string
---@field shell string
---@field file string

---@class PoppyItemConfig
---@field exec? string|string[]|function
---@field file? string|function
---@field shell? string|function
---@field title? string

---@class PoppyConfig
---@field keys? PoppyKeys
---@field icons? PoppyIcons
---@field autohide_menu? boolean
---@field title_header? boolean
---@field hints_footer? boolean
---@field close_on_focus_lost? boolean
---@field close_other_floats_on_open? boolean
---@field assume_multiplexer? boolean
---@field menu_width? number|function
---@field win_height? number|function
---@field win_width? number|function
---@field win_location? "center"|"top"|"bottom"
---@field poppies? table<string, PoppyItemConfig>
---@field border? PoppyBorder

---@class PoppyMergedConfig
---@field keys PoppyKeys
---@field icons PoppyIcons
---@field autohide_menu boolean
---@field title_header boolean
---@field hints_footer boolean
---@field close_on_focus_lost boolean
---@field close_other_floats_on_open boolean
---@field assume_multiplexer boolean
---@field menu_width number|function
---@field win_height number|function
---@field win_width number|function
---@field win_location "center"|"top"|"bottom"
---@field poppies table<string, PoppyItemConfig>
---@field poppies_resolved table<string, PoppyResolvedConfig>
---@field dropped_names string[]
---@field use_borders boolean
---@field border_style "none"|"single"|"double"|"rounded"|"shadow"|string[]

---@alias PoppyBorder "none"|"solid"|"single"|"double"|"rounded"|"shadow"|string[]

---@class PoppyResolvedConfig
---@field mode "exec"|"file"|"shell"
---@field value string|string[]|function
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
---@field runtime_state PoppyRuntimeState?

---@class PoppyHintOpts
---@field width? integer
---@field height? integer
---@field hints? {string, string}[]

---@class MenuItem
---@field label string
---@field marks string[]
---@field hl string|nil

---@class MenuItems
---@field idx_width integer
---@field rows MenuItem[]

---@class PoppyMenuKeymap
---@field [1] string PoppyKeys field name ("poppy_action", "select", "kill", "exit_menu")
---@field [2] string Description
---@field [3] fun() Handler

---@class PoppyMenuSpec
---@field id string
---@field focusable boolean
---@field trap boolean
---@field items (fun(panel_width: integer): MenuItem[])? Lazy row provider; `rows` is used when absent
---@field menu_header string[]? Question lines rendered above the body
---@field rows MenuItem[]
---@field hints {string, string}[]
---@field keymaps PoppyMenuKeymap[]
