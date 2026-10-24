require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local menu_ui = require("poppy.core.session.menu")
local shared = require("poppy.core.shared")

local OUTCOME_SAVE, OUTCOME_DISCARD, OUTCOME_GO_BACK = "save", "discard", "go_back"
local OUTCOME_CREATE, OUTCOME_DROP = "create", "drop"
local DIALOG_GROUP = "poppy_dialog_panels"

---@return boolean
M.trapped = function()
	return state.windows.dialog ~= nil
end

---Terminals are excluded: their `modified` flag is cleared at spawn and stays clear no matter how much they print.
---@param name string
---@return boolean
M.needs_confirmation = function(name)
	local rt = state.runtime(name)
	return rt ~= nil and rt.bufnr ~= nil and api.nvim_buf_is_valid(rt.bufnr) and vim.bo[rt.bufnr].modified == true
end

---@param name string
---@return string
local function label_for(name)
	local configured = state.poppy_configured(name)
	local raw = configured and (configured.config.title or configured.name) or name
	return vim.fn.fnamemodify(raw, ":t")
end

-- Under autohide the panel is hidden between switches; unhide keeps its current row.
local function show_or_mount()
	if shared.opts_field("autohide_menu") and state.windows.menu_hidden then
		view.set_visible(true, state.windows.content_win)
	else
		view.mount(state.windows.wrapper_win)
	end
end

---@return string Absolute path of the poppy's file, or empty if not file-mode.
local function file_path_for(name)
	local configured = state.poppy_configured(name)
	if not configured then
		return ""
	end
	local config = configured.config
	if config.mode ~= "file" then
		return ""
	end
	return shared.expand_file_value(config.value)
end

-- One binding only: poppy_action is trapped, so no kill/exit/toggle.
---@param name string
---@return table
local function spec_for(name)
	return {
		id = "confirm",
		focusable = true,
		trap = true,
		menu_header = {
			("%s has unsaved changes."):format(label_for(name)),
			"Save before closing?",
			"",
		},
		rows = {
			{ label = "Save", marks = { "PoppyDotNone", "PoppyConfirmYes" } },
			{ label = "Discard", marks = { "PoppyDotNone", "PoppyConfirmNo" } },
			{ label = "Go back", marks = { "PoppyDotNone", "PoppyConfirmCancel" } },
		},
		hints = { { "select", "Select" } },
		keymaps = {
			{
				"select",
				"Select",
				function()
					M.resolve(M.answer())
				end,
			},
		},
	}
end

---Checked at UI entry so files created after setup are honored.
---@param name string
---@return boolean
M.needs_file_decision = function(name)
	local path = file_path_for(name)
	return path ~= "" and vim.fn.filereadable(path) ~= 1
end

---Pre-selected row is "Yes" so accidental <CR> does the constructive thing.
---@param name string
---@return table
local function spec_for_missing(name)
	local path = file_path_for(name)
	return {
		id = "missing_file",
		focusable = true,
		trap = true,
		menu_header = {
			('"%s"'):format(label_for(name)),
			"File does not exist.",
			"Create it?",
			"",
			path,
		},
		rows = {
			{ label = "Yes", marks = { "PoppyDotNone", "PoppyConfirmYes" } },
			{ label = "No", marks = { "PoppyDotNone", "PoppyConfirmNo" } },
		},
		hints = { { "select", "Select" } },
		keymaps = {
			{
				"select",
				"Select",
				function()
					M.resolve(M.answer())
				end,
			},
		},
	}
end

local ROW_TO_OUTCOME_KILL = {
	[1] = OUTCOME_SAVE,
	[2] = OUTCOME_DISCARD,
	[3] = OUTCOME_GO_BACK,
}

local ROW_TO_OUTCOME_MISSING = {
	[1] = OUTCOME_CREATE,
	[2] = OUTCOME_DROP,
}

---A count prefix picks the row; out-of-range counts fall back to the cursor.
---@return string
M.answer = function()
	local count = vim.v.count
	local dialog = state.windows.dialog
	local is_missing = dialog ~= nil and dialog.kind == "missing_file"
	local table_used = is_missing and ROW_TO_OUTCOME_MISSING or ROW_TO_OUTCOME_KILL
	if count > 0 then
		local picked = table_used[count]
		if picked then
			return picked
		end
	end
	local fallback = is_missing and OUTCOME_DROP or OUTCOME_GO_BACK
	local win = state.windows.menu_win
	if not win or not api.nvim_win_is_valid(win) then
		return fallback
	end
	local ok, cursor = pcall(api.nvim_win_get_cursor, win)
	local row = (ok and cursor and cursor[1]) or 1
	return table_used[row] or fallback
end

---Force-closing a panel counts as the destructive answer: Discard for kill-confirm, Drop for missing-file.
---Guarded on the dialog still being live so a later remount cannot settle an answered question.
local function watch_panels()
	api.nvim_create_augroup(DIALOG_GROUP, { clear = true })
	local dialog = state.windows.dialog
	local destructive = dialog and dialog.kind == "missing_file" and OUTCOME_DROP or OUTCOME_DISCARD
	for _, key in ipairs({ "menu_win", "menu_header_win", "hints_win", "header_win" }) do
		local win = state.windows[key]
		if win then
			api.nvim_create_autocmd("WinClosed", {
				group = DIALOG_GROUP,
				pattern = tostring(win),
				once = true,
				callback = function()
					if M.trapped() then
						M.resolve(destructive)
					end
				end,
			})
		end
	end
end

---@param name string
---@param kind "kill_confirm"|"missing_file"
---@param resume fun()
---@param buf? integer
---@param poppies? string[]
---@param index? integer
local function install_dialog(name, kind, resume, buf, poppies, index)
	if kind == "missing_file" then
		state.windows.dialog = {
			kind = kind,
			name = name,
			resume = resume,
			poppies = poppies or {},
			index = index or 1,
		}
		return
	end
	state.windows.dialog = {
		kind = kind,
		name = name,
		resume = resume,
		buf = buf,
	}
end

---First call shows the kill-confirm dialog; the spec is reflowed in place for subsequent missing-file entries.
---@param name string
---@param resume fun() Carries out the interrupted close once answered.
---@return nil
M.open = function(name, resume)
	if M.trapped() then
		return
	end
	local rt = state.runtime(name)
	install_dialog(name, "kill_confirm", resume, rt and rt.bufnr)
	menu_ui.set_override(spec_for(name))
	show_or_mount()
	view.set_focused(true)
	menu_ui.focus_body()
	menu_ui.set_row(state.windows.menu_win, 1)
	watch_panels()
end

---Mount the missing-file question for the first entry in the list, then loop through
---the rest in place. After the last answer, calls on_complete.
---@param poppies string[] Names in declaration order.
---@param on_complete fun() Called once the queue drains and the dialog is dismissed.
---@return nil
M.open_missing_file = function(poppies, on_complete)
	if M.trapped() then
		return
	end
	if #poppies == 0 then
		if on_complete then
			on_complete()
		end
		return
	end
	install_dialog(poppies[1], "missing_file", on_complete, nil, poppies, 1)
	menu_ui.set_override(spec_for_missing(poppies[1]))
	show_or_mount()
	view.set_focused(true)
	menu_ui.focus_body()
	menu_ui.set_row(state.windows.menu_win, 1)
	watch_panels()
end

-- Must run before the next mount: recovery resolves by switching (refreshes body) or landing (remounts), and either way the panel would survive as a reference to a closed window.
local function drop_question()
	local win, buf = state.windows.menu_header_win, state.windows.menu_header_buf
	if win and api.nvim_win_is_valid(win) then
		pcall(api.nvim_win_close, win, true)
	end
	if buf and api.nvim_buf_is_valid(buf) then
		pcall(api.nvim_buf_delete, buf, { force = true })
	end
	state.windows.menu_header_win = nil
	state.windows.menu_header_buf = nil

	-- Binding an empty set clears body keys without installing any. Inert while not focusable,
	-- but get_keymap would still report them as claimed.
	local body = state.windows.menu_buf
	if body and api.nvim_buf_is_valid(body) then
		menu_ui.bind(body, {})
	end
end

---Restores what the dialog displaced: menu visibility and focus on the buffer.
local function restore_content()
	if not shared.session_is_open() then
		return
	end
	local autohide = shared.opts_field("autohide_menu")
	if autohide then
		view.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	end
	-- Dropping the question changes how much room the body has; a repaint alone leaves the body
	-- sitting below the gap it left (body is sized by what's above it).
	if not (autohide and state.windows.menu_hidden) then
		view.mount(state.windows.wrapper_win)
	end
	shared.try_focus_win(state.windows.content_win)
end

---@param name string
---@param reason? string
local function drop_poppy(name, reason)
	local configured = state.poppy_configured(name)
	if not configured then
		return
	end
	local path = configured.config.value
	shared.drop_poppy(name, reason or ("poppy '" .. name .. "' not created: " .. tostring(path)))
end

-- Dialog state is still set when this runs (we're inside finish); the spec override is
-- replaced in place so the same float re-renders with the next question.
---@param dialog PoppyMissingFileDialog
local function advance_missing_file_queue(dialog)
	local poppies = dialog.poppies
	-- Clear the override before re-installing so the spec text actually changes.
	menu_ui.clear_override()
	dialog.name = poppies[dialog.index]
	dialog.index = dialog.index + 1
	menu_ui.set_override(spec_for_missing(dialog.name))
	-- Clear WinClosed watchers before view.mount: closing old panels would re-enter
	-- M.resolve on the old dialog state. watch_panels() below installs new ones.
	pcall(api.nvim_clear_autocmds, { group = DIALOG_GROUP })
	show_or_mount()
	view.set_focused(true)
	menu_ui.focus_body()
	menu_ui.set_row(state.windows.menu_win, 1)
	watch_panels()
end

---@param dialog PoppyMissingFileDialog
---@param outcome string One of the OUTCOME_* values.
local function resolve_missing_file(dialog, outcome)
	local function finish(after)
		menu_ui.clear_override()
		pcall(api.nvim_clear_autocmds, { group = DIALOG_GROUP })
		drop_question()
		-- Clear the trap before the continuation so M.open's drain can re-run.
		state.windows.dialog = nil
		local ok, err = pcall(after)
		if not ok then
			error(err, 0)
		end
	end

	local function handle_one()
		local name = dialog.name
		if outcome == OUTCOME_CREATE then
			local expanded = file_path_for(name)
			if expanded ~= "" then
				local ok, err = require("poppy.core.modes.file").create_file_with_parents(expanded)
				if not ok then
					drop_poppy(name, "could not create " .. expanded .. ": " .. tostring(err))
					shared.notify_warn("poppy '%s' not created: %s", name, tostring(err))
				end
			end
		elseif outcome == OUTCOME_DROP then
			drop_poppy(name)
		end
		dialog.index = dialog.index + 1
		if dialog.index > #dialog.poppies then
			return false
		end
		advance_missing_file_queue(dialog)
		return true
	end

	if handle_one() then
		return
	end
	finish(dialog.resume)
end

---@param dialog PoppyKillDialog
---@param outcome string One of the OUTCOME_* values.
local function resolve_kill_confirm(dialog, outcome)
	local function finish(after)
		menu_ui.clear_override()
		pcall(api.nvim_clear_autocmds, { group = DIALOG_GROUP })
		drop_question()
		-- Trap stays engaged across the continuation: the resume deletes the poppy's buffer while
		-- the content pane shows it, firing WinClosed. Releasing earlier would let the watcher
		-- rebuild the pane and re-show the question for a poppy that's already gone.
		local ok, err = pcall(after)
		state.windows.dialog = nil
		if not ok then
			error(err, 0)
		end
	end

	if outcome == OUTCOME_GO_BACK then
		finish(restore_content)
		return
	end

	if outcome ~= OUTCOME_SAVE then
		finish(dialog.resume)
		return
	end

	-- Jumping to another window and writing are textlock-forbidden from inside a mapping.
	vim.schedule(function()
		shared.try_focus_win(state.windows.content_win)
		if dialog.buf and api.nvim_buf_is_valid(dialog.buf) then
			pcall(api.nvim_buf_call, dialog.buf, function()
				vim.cmd("write")
			end)
		end
		finish(dialog.resume)
	end)
end

M.resolve = function(outcome)
	local dialog = state.windows.dialog
	if not dialog then
		return
	end

	if dialog.kind == "missing_file" then
		resolve_missing_file(dialog, outcome)
		return
	end

	resolve_kill_confirm(dialog, outcome)
end

return M
