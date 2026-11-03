require("poppy._types")

local M = {}

local api = vim.api
local state = require("poppy.core.session.state")
local view = require("poppy.core.ui.mount")
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
local label_for = function(name)
	local configured = state.poppy_configured(name)
	local raw = configured and (configured.config.title or configured.name) or name
	return vim.fn.fnamemodify(raw, ":t")
end

local show_or_mount = function()
	if shared.opts_field("autohide_menu") and state.windows.menu_hidden then
		view.set_visible(true, state.windows.content_win)
	else
		view.mount(state.windows.wrapper_win)
	end
end

---For display. String configs show what the user wrote (~, relative paths, etc.).
---Function configs have no declared string, so the expanded value is shown.
---@return string
local display_path_for = function(name)
	local configured = state.poppy_configured(name)
	if not configured or configured.config.mode ~= "file" then
		return ""
	end
	local value = configured.config.value
	if type(value) == "string" then
		return value
	end
	return shared.expand_file_value(value)
end

---For filesystem operations. Resolves `~` and environment so filereadable and
---create_file_with_parents see the real path.
---@return string
local expanded_path_for = function(name)
	local configured = state.poppy_configured(name)
	if not configured or configured.config.mode ~= "file" then
		return ""
	end
	return shared.expand_file_value(configured.config.value)
end

---@param name string
---@return table
local spec_for_kill_confirm = function(name)
	return {
		id = "confirm",
		focusable = true,
		trap = true,
		menu_header = {
			("%s has unsaved changes."):format(label_for(name)),
			"Save before closing?",
			"",
			"",
		},
		rows = {
			{ label = "Save", marks = { "PoppyDotNone", "PoppyAnswerSave" } },
			{ label = "Discard", marks = { "PoppyDotNone", "PoppyAnswerDiscard" } },
			{ label = "Go back", marks = { "PoppyDotNone", "PoppyAnswerCancel" } },
		},
		hints = {
			{ "select", "Select" },
		},
		keymaps = {
			{
				"select",
				"Select",
				function()
					M.resolve(M.answer())
				end,
			},
			{
				"s",
				"Save",
				function()
					M.resolve(OUTCOME_SAVE)
				end,
			},
			{
				"d",
				"Discard",
				function()
					M.resolve(OUTCOME_DISCARD)
				end,
			},
			{
				"x",
				"Go back",
				function()
					M.resolve(OUTCOME_GO_BACK)
				end,
			},
		},
	}
end

---Checked at UI entry so files created after setup are honored.
---@param name string
---@return boolean
M.needs_file_decision = function(name)
	local path = expanded_path_for(name)
	return path ~= "" and vim.fn.filereadable(path) ~= 1
end

---Pre-selected row is "Yes" so accidental <CR> does the constructive thing.
---@param name string
---@return table
local spec_for_missing = function(name)
	local path = display_path_for(name)
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
			"",
		},
		rows = {
			{ label = "Yes", marks = { "PoppyDotNone", "PoppyAnswerYes" } },
			{ label = "No", marks = { "PoppyDotNone", "PoppyAnswerNo" } },
		},
		hints = {
			{ "select", "Select" },
		},
		keymaps = {
			{
				"select",
				"Select",
				function()
					M.resolve(M.answer())
				end,
			},
			{
				"y",
				"Yes",
				function()
					M.resolve(OUTCOME_CREATE)
				end,
			},
			{
				"n",
				"No",
				function()
					M.resolve(OUTCOME_DROP)
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

---The answer under the cursor. Dialogs are lettered by a sign rather than numbered,
---and <CR> takes the highlighted row.
---@return string
M.answer = function()
	local dialog = state.windows.dialog
	local is_missing = dialog ~= nil and dialog.kind == "missing_file"
	local table_used = is_missing and ROW_TO_OUTCOME_MISSING or ROW_TO_OUTCOME_KILL
	local fallback = is_missing and OUTCOME_DROP or OUTCOME_GO_BACK

	local win = state.windows.menu_win
	if not win or not api.nvim_win_is_valid(win) then
		return fallback
	end
	local ok, cursor = pcall(api.nvim_win_get_cursor, win)
	local row = (ok and cursor and cursor[1]) or 1
	return table_used[row] or fallback
end

---Force-closing a panel = destructive answer (Discard for kill-confirm, Drop for missing-file);
---guarded on the dialog still being live so a remount can't settle an answered question.
local watch_panels = function()
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

---@return integer
local create_body_buf = function()
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "poppy_dialog"
	shared.guard_insert_mode(buf)
	api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			menu_ui.clear_lhs(buf)
		end,
	})
	return buf
end

---@param name string
---@param kind "kill_confirm"|"missing_file"
---@param resume fun()
---@param buf? integer
---@param poppies? string[]
---@param index? integer
local install_dialog = function(name, kind, resume, buf, poppies, index)
	-- One buffer for the whole dialog flow: a row of questions repaints it.
	local body_buf = state.windows.dialog and state.windows.dialog.body_buf
	if not (body_buf and api.nvim_buf_is_valid(body_buf)) then
		body_buf = create_body_buf()
	end
	state.windows.dialog_body_buf = body_buf

	if kind == "missing_file" then
		state.windows.dialog = {
			kind = kind,
			name = name,
			resume = resume,
			poppies = poppies or {},
			index = index or 1,
			body_buf = body_buf,
		}
		return
	end
	state.windows.dialog = {
		kind = kind,
		name = name,
		resume = resume,
		buf = buf,
		body_buf = body_buf,
	}
end

---Show (or re-show) the menu_wrapper, focus the answer body, park the cursor on row 1,
---and arm WinClosed watchers for the current dialog. Called by every dialog entry point
---after the spec override is installed.
---@return nil
local present_dialog = function()
	if state.windows.dialog and state.windows.dialog.kind == "missing_file" then
		local layout = require("poppy.core.ui.layout")
		local ww = state.windows.wrapper_win
		if ww and vim.api.nvim_win_is_valid(ww) then
			local wc = vim.api.nvim_win_get_config(ww)
			local column_w = layout.landing_width(state.windows.opts, state.poppies_configured, vim.o.columns)
			local column_h = layout.compute(layout.resolve_spec(menu_ui.current_spec(), column_w)).height
			if wc.width ~= column_w or wc.height ~= column_h then
				layout.resize(ww, {
					width = column_w,
					height = column_h,
					col = math.floor((vim.o.columns - column_w) / 2),
					row = math.floor((layout.editor_height() - column_h) / 2),
				})
			end
		end
	end
	show_or_mount()
	view.set_focused(true)
	menu_ui.focus_body()
	menu_ui.set_row(state.windows.menu_win, 1)
	watch_panels()
end

---@param name string
---@param resume fun() Carries out the interrupted close once answered.
---@return nil
M.open = function(name, resume)
	if M.trapped() then
		return
	end
	local rt = state.runtime(name)
	install_dialog(name, "kill_confirm", resume, rt and rt.bufnr)
	menu_ui.set_override(spec_for_kill_confirm(name))
	present_dialog()
end

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
	present_dialog()
end

-- Must run before the next mount: recovery resolves by switching (refreshes body) or landing (remounts), and either way the panel would survive as a reference to a closed window.
local drop_question = function()
	local win, buf = state.windows.menu_header_win, state.windows.menu_header_buf
	if win and api.nvim_win_is_valid(win) then
		pcall(api.nvim_win_close, win, true)
	end
	if buf and api.nvim_buf_is_valid(buf) then
		pcall(api.nvim_buf_delete, buf, { force = true })
	end
	state.windows.menu_header_win = nil
	state.windows.menu_header_buf = nil
end

---@return nil
local release_body_buf = function()
	local buf = state.windows.dialog_body_buf
	if buf and api.nvim_buf_is_valid(buf) then
		pcall(api.nvim_buf_delete, buf, { force = true })
	end
	state.windows.dialog_body_buf = nil
	if state.windows.dialog then
		state.windows.dialog.body_buf = nil
	end
end

local restore_content = function()
	if not shared.session_is_open() then
		return
	end
	local autohide = shared.opts_field("autohide_menu")
	if autohide then
		view.set_visible(false, state.windows.content_win)
		shared.show_menu_hint()
	end
	if not (autohide and state.windows.menu_hidden) then
		view.mount(state.windows.wrapper_win)
	end
	shared.try_focus_win(state.windows.content_win)
end

---@param name string
---@param reason? string
local drop_poppy = function(name, reason)
	local configured = state.poppy_configured(name)
	if not configured then
		return
	end
	local path = configured.config.value
	shared.drop_poppy(name, reason or ("poppy '" .. name .. "' not created: " .. tostring(path)))
end

-- Replaces the spec override in place so the same float re-renders with the next question.
---@param dialog PoppyMissingFileDialog
local advance_missing_file_queue = function(dialog)
	local poppies = dialog.poppies
	local next_name = poppies[dialog.index]
	menu_ui.clear_override()
	menu_ui.set_override(spec_for_missing(next_name))
	-- Same buffer for the next question in the row: one continuous dialog flow.
	dialog.body_buf = state.windows.dialog_body_buf
	-- Clear old WinClosed watchers: closing old panels would re-enter M.resolve on stale state.
	pcall(api.nvim_clear_autocmds, { group = DIALOG_GROUP })
	present_dialog()
	dialog.name = next_name
	dialog.index = dialog.index + 1
end

---Release a trapped dialog without answering it. Used by a hard reset (setup) where the
---session is being replaced and the question no longer has a subject.
---@return nil
M.force_release = function()
	if not M.trapped() then
		return
	end
	menu_ui.clear_override()
	pcall(api.nvim_clear_autocmds, { group = DIALOG_GROUP })
	drop_question()
	release_body_buf()
	state.windows.dialog = nil
end

---`release_after` defaults true so the trap clears before M.open's drain re-entry;
---false keeps it through `after`'s teardown to prevent re-arming.
---@param after fun()
---@param release_after? boolean Default true.
local finish_dialog = function(after, release_after)
	release_after = release_after ~= false
	menu_ui.clear_override()
	pcall(api.nvim_clear_autocmds, { group = DIALOG_GROUP })
	drop_question()
	release_body_buf()
	-- Closing the dialog drops focus back to the editor window. The recovery that
	-- follows is what puts poppy back, so the session must not be torn down in
	-- between: hold the recovering gate across the whole teardown.
	state.windows.recovering = true
	if release_after then
		state.windows.dialog = nil
		local ok, err = pcall(after)
		if not ok then
			state.windows.recovering = false
			error(err, 0)
		end
	else
		local ok, err = pcall(after)
		state.windows.dialog = nil
		if not ok then
			state.windows.recovering = false
			error(err, 0)
		end
	end
	-- The resume path may have started a recovery, which clears the flag itself
	-- once the session is restored. Otherwise nothing will, so release it here.
	vim.defer_fn(function()
		if state.windows.recovering then
			state.windows.recovering = false
		end
	end, 0)
end

---@param dialog PoppyMissingFileDialog
---@param outcome string One of the OUTCOME_* values.
local resolve_missing_file = function(dialog, outcome)
	local poppy_dropped = false
	local handle_one = function()
		local name = dialog.name
		if outcome == OUTCOME_CREATE then
			local expanded = expanded_path_for(name)
			if expanded == "" then
				drop_poppy(name, "poppy '" .. name .. "' has no resolvable file path")
				poppy_dropped = true
			else
				local ok, err = require("poppy.core.modes.file").create_file_with_parents(expanded)
				if not ok then
					drop_poppy(name, "could not create " .. expanded .. ": " .. tostring(err))
					shared.notify_warn("poppy '%s' not created: %s", name, tostring(err))
					poppy_dropped = true
				else
					require("poppy.core.session.watch").add(name, expanded)
				end
			end
		elseif outcome == OUTCOME_DROP then
			drop_poppy(name)
			poppy_dropped = true
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
	if poppy_dropped then
		finish_dialog(function()
			require("poppy.core.session.manager").goto_landing()
		end)
		return
	end
	finish_dialog(dialog.resume)
end

---@param dialog PoppyKillDialog
---@param outcome string One of the OUTCOME_* values.
local resolve_kill_confirm = function(dialog, outcome)
	if outcome == OUTCOME_GO_BACK then
		finish_dialog(restore_content)
		return
	end

	if outcome ~= OUTCOME_SAVE then
		finish_dialog(dialog.resume, false)
		return
	end

	if not dialog.buf or not api.nvim_buf_is_valid(dialog.buf) then
		shared.notify_warn("poppy '%s' buffer is gone; nothing to save", dialog.name)
		finish_dialog(restore_content)
		return
	end

	-- Jumping to another window and writing are textlock-forbidden from inside a mapping.
	vim.schedule(function()
		shared.try_focus_win(state.windows.content_win)
		if api.nvim_buf_is_valid(dialog.buf) then
			pcall(api.nvim_buf_call, dialog.buf, function()
				vim.cmd("write")
			end)
		end
		finish_dialog(dialog.resume, false)
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
