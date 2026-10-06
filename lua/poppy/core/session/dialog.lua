require("poppy._types")

-- Confirmation dialog. Visually a menu with a menu_header, so rendering goes through the menu
-- backend. What lives here is what a generic menu cannot know: this menu is a question, must
-- not be escapable while up, and resolves to exactly one decision before leaving nothing behind.

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.view")
local menu_ui = require("poppy.core.session.menu")
local shared = require("poppy.core.shared")

local OUTCOME_SAVE, OUTCOME_DISCARD, OUTCOME_GO_BACK = "save", "discard", "go_back"
local DIALOG_GROUP = "poppy_dialog_panels"

---@return boolean
M.trapped = function()
	return state.windows.dialog ~= nil
end

---Would closing this poppy throw away unsaved edits?
---Terminals are excluded by measurement: their `modified` flag is cleared at spawn (term.lua) and
---stays clear no matter how much they print.
---@param name string
---@return boolean
M.needs_confirmation = function(name)
	local rt = state.runtime(name)
	return rt ~= nil
		and rt.bufnr ~= nil
		and api.nvim_buf_is_valid(rt.bufnr)
		and vim.bo[rt.bufnr].modified == true
end

---@param name string
---@return string
local function label_for(name)
	local configured = state.poppy_configured(name)
	local raw = configured and (configured.config.title or configured.name) or name
	return vim.fn.fnamemodify(raw, ":t")
end

---The question menu. One binding only: no kill, no exit, no toggle (poppy_action is trapped).
---Only an answer or a forced close exits.
---@param name string
---@return table
local function spec_for(name)
	return {
		id = "confirm",
		width = "content",
		focusable = true,
		trap = true,
		menu_header = {
			("%s has unsaved changes."):format(label_for(name)),
			"Save before closing?",
			-- Trailing blank: the last question line is short, so a text-only gap would butt up.
			"",
		},
		rows = {
			{ label = "Save", marks = { "PoppyDotNone", "PoppyConfirmYes" } },
			{ label = "Discard", marks = { "PoppyDotNone", "PoppyConfirmNo" } },
			{ label = "Go back", marks = { "PoppyDotNone", "PoppyConfirmCancel" } },
		},
		hints = { { "select", "Select" } },
		keymaps = {
			{ "select", "Select", function()
				M.resolve(M.answer())
			end },
		},
	}
end

local ROW_TO_OUTCOME = {
	[1] = OUTCOME_SAVE,
	[2] = OUTCOME_DISCARD,
	[3] = OUTCOME_GO_BACK,
}

---The answer row under the cursor.
---@return integer
M.answer_row = function()
	local win = state.windows.menu_win
	if not win or not api.nvim_win_is_valid(win) then
		return 1
	end
	local ok, cursor = pcall(api.nvim_win_get_cursor, win)
	return (ok and cursor and cursor[1]) or 1
end

---Which answer to act on. Count prefix picks the row; out-of-range counts and the no-count case
---fall back to the cursor (Go back if even that fails -- the only safe fallback).
---@return string
M.answer = function()
	local count = vim.v.count
	if count > 0 then
		local picked = ROW_TO_OUTCOME[count]
		if picked then
			return picked
		end
	end
	return ROW_TO_OUTCOME[M.answer_row()] or OUTCOME_GO_BACK
end

---Force-closing a panel counts as Discard: intent, not a re-ask. Guarded on the dialog still
---being live so a later remount cannot settle an answered question.
local function watch_panels()
	api.nvim_create_augroup(DIALOG_GROUP, { clear = true })
	for _, key in ipairs({ "menu_win", "menu_header_win", "hints_win", "header_win" }) do
		local win = state.windows[key]
		if win then
			api.nvim_create_autocmd("WinClosed", {
				group = DIALOG_GROUP,
				pattern = tostring(win),
				once = true,
				callback = function()
					if M.trapped() then
						M.resolve(OUTCOME_DISCARD)
					end
				end,
			})
		end
	end
end

---Put the question up, leaving the session otherwise untouched. Override installed before
---any mount so the question is what gets rendered.
---@param name string
---@param resume fun() Carries out the interrupted close once answered.
---@return nil
M.open = function(name, resume)
	if M.trapped() then
		return
	end
	local rt = state.runtime(name)
	state.windows.dialog = { name = name, resume = resume, buf = rt and rt.bufnr }
	menu_ui.set_override(spec_for(name))

	if shared.opts_field("menu_autohide") and state.windows.hidden then
		view.set_visible(true, state.windows.content_win)
	else
		view.mount(state.windows.wrapper_win)
	end
	view.set_focused(true)
	menu_ui.focus_body()
	-- Preselect "No": answering by accident should not be the destructive answer.
	menu_ui.set_row(state.windows.menu_win, 1)
	watch_panels()
end

---Tear the question panel down explicitly. Can't be left to the next mount: recovery resolves
---either by switching (refreshes body) or by landing (remount), and either way the panel would
---survive as a reference to a closed window.
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

	-- The dialog's only mapping must not outlive the dialog. Binding an empty set clears body
	-- keys without installing any, so the buffer is left as a menu that had never been focused.
	-- Inert while not focusable, but get_keymap would still report it as claimed.
	local body = state.windows.menu_buf
	if body and api.nvim_buf_is_valid(body) then
		menu_ui.bind(body, {})
	end
end

---Re-run the panel layout. Dropping the question changes how much room the body has; a repaint
---alone leaves the body sitting below the gap it left (body is sized by what's above it).
local function relayout()
	local wrapper_win = state.windows.wrapper_win
	if not shared.session_is_open() or not wrapper_win then
		return
	end
	if shared.opts_field("menu_autohide") and state.windows.hidden then
		return
	end
	view.mount(wrapper_win)
end

---Put the view back after Go back. Nothing was torn down, so this restores what the dialog
---displaced: menu visibility and focus on the buffer.
local function restore_content()
	if not shared.session_is_open() then
		return
	end
	-- Only needed here: Save and Discard go on to tear the poppy down (that path remounts).
	relayout()
	-- Mirror the tail of a real selection so autohide settles the same way.
	if shared.opts_field("menu_autohide") then
		view.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	end
	shared.try_focus_win(state.windows.content_win)
end

---@param outcome string One of the OUTCOME_* values.
M.resolve = function(outcome)
	local dialog = state.windows.dialog
	if not dialog then
		return
	end

	local function finish(after)
		menu_ui.clear_override()
		pcall(api.nvim_clear_autocmds, { group = DIALOG_GROUP })
		drop_question()
		-- Trap stays engaged across the continuation. The resume deletes the poppy's buffer
		-- while the content pane still shows it, firing its WinClosed watcher; with the trap
		-- already released, the watcher would rebuild the pane and a second recovery would
		-- re-show the question for a poppy that's already gone. Cleared only after the
		-- continuation (even if it throws) so a failure can't leave the session permanently trapped.
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

	-- Saving means jumping to another window and writing the buffer, both textlock-forbidden
	-- from inside a mapping callback. Defer and take the user to the file.
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

return M
