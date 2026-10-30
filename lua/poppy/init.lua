local M = {}
local session = require("poppy.core.session")

M.setup = session.setup

-- Lazy wrappers: ensure_loaded on first call, then delegate. Lets the plugin load
-- cheaply without side effects; the first API call or :Poppy command bootstraps it.
local lazy = function(name)
	return function(...)
		session.ensure_loaded()
		return session[name](...)
	end
end

for _, name in ipairs({
	"toggle",
	"open",
	"close",
	"switch_by_name",
	"switch_by_index",
	"switch_by_cursor",
	"kill_active",
	"kill_by_name",
	"kill_by_index",
	"kill_by_cursor",
	"get_poppies",
	"get_poppy_by_name",
	"get_poppy_by_index",
	"get_current_poppy",
	"get_current_poppy_name",
	"is_open",
}) do
	M[name] = lazy(name)
end

return M
