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
---@field exec? string|string[]|function
---@field file? string|function
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
---@field runtime_state PoppyRuntimeState?

---@class PoppyHintOpts
---@field row? integer
---@field row_offset? integer
---@field col? integer
---@field width? integer
---@field height? integer
---@field hints? {string, string}[]

---@alias PoppyMenuWidth "declared"|"content"

---@class MenuItem
---@field label string
---@field marks string[]
---@field hl string|nil

---@class MenuItems
---@field idx_width integer
---@field rows MenuItem[]

---@class PoppyMenuKeymap
---@field field string
---@field desc string
---@field fn function

---@class PoppyMenuSpec
---@field id string
---@field width PoppyMenuWidth
---@field focusable boolean
---@field trap boolean
---@field rows MenuItem[]
---@field hints {string, string}[]
---@field keymaps PoppyMenuKeymap[]

---@class PoppyMenuTarget
---@field menu_buf integer
---@field hints_buf integer?
---@field list_width integer
---@field hints_width integer
