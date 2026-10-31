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

---@class PoppyResolvedFileConfig
---@field mode "file"
---@field value string|function
---@field title string

---@class PoppyResolvedExecConfig
---@field mode "exec"
---@field value string|string[]|function
---@field title string

---@class PoppyResolvedShellConfig
---@field mode "shell"
---@field value string|string[]|function
---@field title string

---@alias PoppyResolvedConfig PoppyResolvedFileConfig|PoppyResolvedExecConfig|PoppyResolvedShellConfig

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

---@class PoppyHint
---@field [1] string A PoppyKeys field name or a literal lhs.
---@field [2] string Description

---@class PoppyHints
---@field landing PoppyHint[]
---@field body PoppyHint[]

---@class PoppyHintOpts
---@field width? integer
---@field height? integer

---@class MenuItem
---@field label string
---@field marks string[]
---@field hl string|nil

---@class MenuItems
---@field idx_width integer
---@field numbered boolean Whether rows carry an index number. Dialog rows are lettered by a sign instead.
---@field rows MenuItem[]

---@class PoppyMenuKeymap
---@field [1] string A PoppyKeys field name ("poppy_action", "select", "kill", "exit_menu") or a literal lhs.
---@field [2] string Description
---@field [3] fun() Handler

---@class PoppyMenuSpec
---@field id string
---@field focusable boolean
---@field trap boolean
---@field items (fun(panel_width: integer): MenuItem[])? Lazy row provider; `rows` is used when absent
---@field menu_header string[]? Question lines rendered above the body
---@field rows MenuItem[]
---@field hints PoppyHint[]
---@field keymaps PoppyMenuKeymap[]

---@class PoppyMenuLayout
---@field width_source "wrapper"|"menu"
---@field focusable boolean
---@field hints PoppyHint[]

---@class PoppyKillDialog
---@field kind "kill_confirm"
---@field name string
---@field resume fun()
---@field buf? integer The file buffer being saved, not the dialog's own buffer.
---@field body_buf? integer The dialog's answers buffer. Transient: deleted when the dialog resolves.

---@class PoppyMissingFileDialog
---@field kind "missing_file"
---@field name string
---@field resume fun()
---@field poppies string[]
---@field index integer
---@field body_buf? integer The dialog's answers buffer. Transient: deleted when the dialog resolves.

---@alias PoppyDialog PoppyKillDialog|PoppyMissingFileDialog
