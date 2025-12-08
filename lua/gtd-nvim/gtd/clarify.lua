-- Fixed clarify module: no DONE tasks, no notes, proper fzf config
-- Enhanced with comprehensive WAITING FOR support and metadata management

local M = {}
local shared = require("gtd-nvim.gtd.shared")

-- Focus-mode integration (Sketchybar HUD)
local focus_mode = (function()
  local ok, mod = pcall(require, "utils.focus_mode")
  if ok and mod and type(mod.set) == "function" then
    return mod
  end
  return nil
end)()

-- ---------- helpers ----------
local function buf_lines(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local function set_buf_lines(buf, L) vim.api.nvim_buf_set_lines(buf, 0, -1, false, L) end
local function safe_require(name) local ok, m = pcall(require, name); return ok and m or nil end

local task_id  = safe_require("gtd-nvim.gtd.utils.task_id")
local org_dates = safe_require("gtd-nvim.gtd.utils.org_dates")  -- ✅ Added
local projects = safe_require("gtd-nvim.gtd.projects")
local refile   = safe_require("gtd-nvim.gtd.refile")

-- ---------- WAITING FOR Support ----------

local WAITING_CONTEXTS = {
  "email", "phone", "meeting", "text", "slack", "teams",
  "verbal", "letter", "other"
}

local WAITING_PRIORITIES = {
  "low", "medium", "high", "urgent"
}

-- Date validation and calculation helpers
local function is_valid_date(date_str)
  if not date_str or date_str == "" then return true end
  return date_str:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

local function future_date(days)
  local future_time = os.time() + (days * 24 * 60 * 60)
  return os.date("%Y-%m-%d", future_time)
end

-- Extract WAITING properties from lines
local function extract_waiting_properties(lines, h_start, h_end)
  local waiting_data = {}
  local props_start, props_end = nil, nil

  -- Find properties drawer
  for i = h_start, h_end do
    if (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
      props_start = i
    elseif props_start and (lines[i] or ""):match("^%s*:END:%s*$") then
      props_end = i
      break
    end
  end

  if not props_start or not props_end then return waiting_data end

  -- Extract WAITING properties
  for i = props_start + 1, props_end - 1 do
    local line = lines[i] or ""
    local key, value = line:match("^%s*:([^:]+):%s*(.*)%s*$")
    if key and value then
      if key == "WAITING_FOR" then waiting_data.waiting_for = value
      elseif key == "WAITING_WHAT" then waiting_data.waiting_what = value
      elseif key == "REQUESTED" then waiting_data.requested_date = value
      elseif key == "FOLLOW_UP" then waiting_data.follow_up_date = value
      elseif key == "CONTEXT" then waiting_data.context = value
      elseif key == "PRIORITY" then waiting_data.priority = value
      elseif key == "WAITING_NOTES" then waiting_data.notes = value
      end
    end
  end

  return waiting_data
end

-- Remove WAITING properties from task
local function clean_waiting_properties(lines, h_start, h_end)
  local changes_made = false
  local waiting_props = {
    "WAITING_FOR", "WAITING_WHAT", "REQUESTED", "FOLLOW_UP",
    "CONTEXT", "PRIORITY", "WAITING_NOTES"
  }

  for i = h_end, h_start, -1 do
    local line = lines[i] or ""
    local key = line:match("^%s*:([^:]+):")
    if key then
      for _, prop in ipairs(waiting_props) do
        if key == prop then
          table.remove(lines, i)
          changes_made = true
          break
        end
      end
    end
  end

  return lines, changes_made
end

-- Add WAITING properties to task
local function add_waiting_properties(lines, h_start, h_end, waiting_data)
  if not waiting_data then return lines, h_end end

  local props_end = nil
  for i = h_start, h_end do
    if (lines[i] or ""):match("^%s*:END:%s*$") then
      props_end = i
      break
    end
  end

  if not props_end then return lines, h_end end

  local props_to_add = {}
  if waiting_data.waiting_for then
    table.insert(props_to_add, ":WAITING_FOR: " .. waiting_data.waiting_for)
  end
  if waiting_data.waiting_what then
    table.insert(props_to_add, ":WAITING_WHAT: " .. waiting_data.waiting_what)
  end
  if waiting_data.requested_date then
    table.insert(props_to_add, ":REQUESTED: " .. waiting_data.requested_date)
  end
  if waiting_data.follow_up_date then
    table.insert(props_to_add, ":FOLLOW_UP: " .. waiting_data.follow_up_date)
  end
  if waiting_data.context then
    table.insert(props_to_add, ":CONTEXT: " .. waiting_data.context)
  end
  if waiting_data.priority then
    table.insert(props_to_add, ":PRIORITY: " .. waiting_data.priority)
  end
  if waiting_data.notes and waiting_data.notes ~= "" then
    table.insert(props_to_add, ":WAITING_NOTES: " .. waiting_data.notes)
  end

  -- Insert properties before :END:
  for i, prop in ipairs(props_to_add) do
    table.insert(lines, props_end + i - 1, prop)
  end

  return lines, h_end + #props_to_add
end

-- Collect WAITING metadata with prompts
local function collect_waiting_metadata(existing_data, cb)
  if not cb then return end

  local waiting_data = existing_data or {}

  -- WHO are we waiting for?
  local who_prompt = "Waiting for WHO (person/org): "
  if waiting_data.waiting_for then
    who_prompt = who_prompt .. "[" .. waiting_data.waiting_for .. "] "
  end

  vim.ui.input({ prompt = who_prompt, default = waiting_data.waiting_for }, function(who)
    if not who or who == "" then
      if not waiting_data.waiting_for then return end -- Must have someone
      who = waiting_data.waiting_for
    end
    waiting_data.waiting_for = who

    -- WHAT are we waiting for?
    local what_prompt = "Waiting for WHAT (deliverable): "
    if waiting_data.waiting_what then
      what_prompt = what_prompt .. "[" .. waiting_data.waiting_what .. "] "
    end

    vim.ui.input({ prompt = what_prompt, default = waiting_data.waiting_what }, function(what)
      if not what or what == "" then
        if not waiting_data.waiting_what then return end
        what = waiting_data.waiting_what
      end
      waiting_data.waiting_what = what

      -- WHEN was it requested?
      local today = os.date("%Y-%m-%d")
      local when_default = waiting_data.requested_date or today
      local when_prompt = "When requested (YYYY-MM-DD) [" .. when_default .. "]: "

      vim.ui.input({ prompt = when_prompt, default = when_default }, function(when)
        waiting_data.requested_date = (when and when ~= "" and when or when_default)

        if not is_valid_date(waiting_data.requested_date) then
          shared.notify("Invalid date format, using today", "WARN")
          waiting_data.requested_date = today
        end

        -- FOLLOW-UP date
        local default_followup = waiting_data.follow_up_date or future_date(7)
        local followup_prompt = "Follow up on (YYYY-MM-DD) [" .. default_followup .. "]: "

        vim.ui.input({ prompt = followup_prompt, default = default_followup }, function(followup)
          waiting_data.follow_up_date = (followup and followup ~= "" and followup or default_followup)

          if not is_valid_date(waiting_data.follow_up_date) then
            shared.notify("Invalid follow-up date, using default", "WARN")
            waiting_data.follow_up_date = default_followup
          end

          -- CONTEXT (how was it requested?)
          local context_items = vim.tbl_deep_extend("force", {}, WAITING_CONTEXTS)
          if waiting_data.context and not vim.tbl_contains(context_items, waiting_data.context) then
            table.insert(context_items, 1, waiting_data.context)
          end

          vim.ui.select(context_items, {
            prompt = "How was it requested?",
            format_item = function(item)
              return item == waiting_data.context and (item .. " (current)") or item
            end
          }, function(context)
            waiting_data.context = context or waiting_data.context or "email"

            -- PRIORITY/URGENCY
            local priority_items = vim.tbl_deep_extend("force", {}, WAITING_PRIORITIES)

            vim.ui.select(priority_items, {
              prompt = "Priority level",
              format_item = function(item)
                return item == waiting_data.priority and (item .. " (current)") or item
              end
            }, function(priority)
              waiting_data.priority = priority or waiting_data.priority or "medium"

              -- Optional notes
              local notes_prompt = "Additional notes (optional): "
              if waiting_data.notes then
                notes_prompt = notes_prompt .. "[" .. waiting_data.notes:sub(1, 30) .. "...] "
              end

              vim.ui.input({ prompt = notes_prompt, default = waiting_data.notes }, function(notes)
                waiting_data.notes = notes or waiting_data.notes or ""
                cb(waiting_data)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- Update task body with WAITING summary
local function update_waiting_body(lines, h_start, h_end, waiting_data)
  if not waiting_data then return lines, h_end end

  -- Find where to insert the summary (after properties drawer)
  local insert_pos = h_start + 1
  local i = h_start + 1
  while i <= h_end and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  if i <= h_end and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= h_end do
      if (lines[j] or ""):match("^%s*:END:%s*$") then
        insert_pos = j + 1
        break
      end
      j = j + 1
    end
  end

  -- Remove existing WAITING summary if present
  local summary_start, summary_end = nil, nil
  for k = insert_pos, h_end do
    if (lines[k] or ""):match("^Waiting for:") then
      summary_start = k
      -- Find end of summary
      for j = k + 1, h_end do
        if (lines[j] or ""):match("^%s*$") then
          summary_end = j - 1
          break
        end
      end
      summary_end = summary_end or k + 3 -- Default to a few lines
      break
    end
  end

  if summary_start and summary_end then
    for _ = summary_start, summary_end do
      table.remove(lines, summary_start)
      h_end = h_end - 1
    end
  end

  -- Add new summary
  local summary_lines = {
    "",
    string.format("Waiting for: %s", waiting_data.waiting_for or ""),
    string.format("Expecting: %s", waiting_data.waiting_what or ""),
    string.format("Requested: %s via %s",
      waiting_data.requested_date or "", waiting_data.context or ""),
  }

  if waiting_data.notes and waiting_data.notes ~= "" then
    table.insert(summary_lines, "")
    table.insert(summary_lines, "Notes: " .. waiting_data.notes)
  end

  for idx, line in ipairs(summary_lines) do
    table.insert(lines, insert_pos + idx - 1, line)
  end

  return lines, h_end + #summary_lines
end

-- ---------- Core clarify functions ----------

local function find_heading(lines, lnum)
  for i = lnum, 1, -1 do
    local lvl = shared.heading_level(lines[i] or "")
    if lvl then
      local j = i + 1
      while j <= #lines do
        local lv2 = shared.heading_level(lines[j] or "")
        if lv2 and lv2 <= lvl then break end
        j = j + 1
      end
      return i, j - 1, lvl
    end
  end
  return nil
end

local function ensure_props(lines, h_start)
  local i = h_start + 1
  while i <= #lines and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  if i <= #lines and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= #lines do
      if (lines[j] or ""):match("^%s*:END:%s*$") then return i, j end
      j = j + 1
    end
  end
  local pos = h_start + 1
  table.insert(lines, pos, ":PROPERTIES:")
  table.insert(lines, pos + 1, ":END:")
  return pos, pos + 1
end

local function ensure_zk_link(lines, h_start, h_end, id)
  if not id or id == "" then return end
  for i = h_start, h_end do
    if (lines[i] or ""):find("%[%[zk:" .. id .. "%]%]") then return end
  end
  local i = h_start + 1
  while i <= h_end and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  local p_end = nil
  if i <= h_end and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= h_end do
      if (lines[j] or ""):match("^%s*:END:%s*$") then p_end = j; break end
      j = j + 1
    end
  end
  local insert_pos = (p_end and (p_end + 1)) or (h_start + 1)
  table.insert(lines, insert_pos, ("ID:: [[zk:%s]]"):format(id))
end

local function promote_line_to_heading(lines, lnum, status_kw)
  local status = status_kw or "TODO"
  local line = lines[lnum] or ""
  if line:match("^%s*$") then
    local title = nil
    vim.ui.input({ prompt = "Task title: " }, function(input) title = input end)
    title = title and title:gsub("^%s+",""):gsub("%s+$","") or ""
    if title == "" then title = "New Task" end
    lines[lnum] = ("* %s %s"):format(status, title)
  else
    lines[lnum] = ("* %s %s"):format(status, line:gsub("^%s+",""))
  end
  if (lines[lnum + 1] or "") ~= "" then
    table.insert(lines, lnum + 1, "")
  end
  return lnum, lnum, 1
end

local function set_dates(lines, h_start, h_end, scheduled, deadline)
  local insert_at = h_start + 1
  local i = h_start + 1
  while i <= h_end and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  if i <= h_end and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= h_end do
      if (lines[j] or ""):match("^%s*:END:%s*$") then insert_at = j + 1; break end
      j = j + 1
    end
  end

  local sched_idx, dead_idx
  for k = h_start + 1, h_end do
    local L = lines[k] or ""
    if L:match("^%s*SCHEDULED:%s*<") then sched_idx = k end
    if L:match("^%s*DEADLINE:%s*<") then dead_idx = k end
  end

  local function fmt_date(d) return ("<%s>"):format(d) end

  if scheduled ~= nil and scheduled ~= "" then
    if scheduled == "-" then
      if sched_idx then table.remove(lines, sched_idx) end
    else
      local sline = "SCHEDULED: " .. fmt_date(scheduled)
      if sched_idx then
        lines[sched_idx] = sline
      else
        table.insert(lines, insert_at, sline); insert_at = insert_at + 1; h_end = h_end + 1
      end
    end
  end

  if deadline ~= nil and deadline ~= "" then
    if deadline == "-" then
      if dead_idx then table.remove(lines, dead_idx) end
    else
      local dline = "DEADLINE: " .. fmt_date(deadline)
      if dead_idx then
        lines[dead_idx] = dline
      else
        table.insert(lines, insert_at, dline); h_end = h_end + 1
      end
    end
  end

  return lines, h_end
end

local function set_status(lines, h_start, p_start, p_end, status_kw)
  if not status_kw or status_kw == "" then return p_end end
  if (lines[h_start] or ""):match("^%*+%s+%u+%s") then
    lines[h_start] = lines[h_start]:gsub("^(%*+)%s+%u+%s", "%1 " .. status_kw .. " ")
  else
    lines[h_start] = lines[h_start]:gsub("^(%*+)%s+", "%1 " .. status_kw .. " ")
  end
  local have = false
  for i = p_start + 1, p_end - 1 do
    if (lines[i] or ""):match("^%s*:STATUS:%s") then
      lines[i] = ":STATUS: " .. status_kw
      have = true
    end
  end
  if not have then
    table.insert(lines, p_end, ":STATUS: " .. status_kw); p_end = p_end + 1
  end
  return p_end
end

local function append_note(lines, h_start, h_end, note)
  if not note or note == "" then return h_end end
  local insert_at = h_start + 1
  local i = h_start + 1
  while i <= h_end and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  if i <= h_end and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= h_end do
      if (lines[j] or ""):match("^%s*:END:%s*$") then insert_at = j + 1; break end
      j = j + 1
    end
  end
  table.insert(lines, insert_at, note)
  if (lines[insert_at + 1] or "") ~= "" then
    table.insert(lines, insert_at + 1, "")
  end
  return h_end + 1
end

-- ---------- Enhanced Status picker with WAITING support ----------
local STATES = { "NEXT", "TODO", "WAITING", "SOMEDAY", "DONE" }

local function pick_status(prompt, current, cb)
  local fzf = safe_require("fzf-lua")
  if fzf then
    local header = current and ("Current: " .. current) or ""
    fzf.fzf_exec(STATES, {
      prompt = (prompt or "Status> ") .. " ",
      fzf_opts = {
        ["--no-info"] = true,
        ["--tiebreak"] = "index",
        ["--header"] = header
      },
      winopts = { height = 0.30, width = 0.50, row = 0.10 },
      actions = {
        ["default"] = function(sel)
          local s = sel and sel[1]
          if s then cb(s) end
        end,
      },
    })
  else
    vim.ui.select(STATES, { prompt = prompt or "Status" }, function(choice)
      if choice then cb(choice) end
    end)
  end
end

-- ---------- Enhanced Post-actions menu ----------
local function post_actions_menu(ctx)
  local fzf = safe_require("fzf-lua")
  if not fzf then return end
  local items = {
    "Finish",
    (projects and "Link to project") or nil,
    (refile   and "Refile into project") or nil,
    "Open ZK note",
    "Mark DONE",
  }

  -- Add WAITING-specific actions if this is a WAITING item
  local current_status = (ctx.lines and ctx.lines[ctx.h_start] or ""):match("^%*+%s+(%u+)%s")
  if current_status == "WAITING" then
    table.insert(items, 2, "Edit WAITING details")
    table.insert(items, 3, "Convert from WAITING")
  end

  local filtered = {}
  for _, v in ipairs(items) do if v then table.insert(filtered, v) end end

  fzf.fzf_exec(filtered, {
    prompt = "After clarify> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    actions = {
      ["default"] = function(sel)
        local act = sel and sel[1]
        if act == "Link to project" and projects and projects.link_task_to_project_at_cursor then
          projects.link_task_to_project_at_cursor({})
        elseif act == "Refile into project" and refile and refile.to_project_at_cursor then
          refile.to_project_at_cursor({})
        elseif act == "Edit WAITING details" then
          M.update_waiting_at_cursor()
        elseif act == "Convert from WAITING" then
          M.convert_from_waiting_at_cursor()
        elseif act == "Open ZK note" then
          local item = {
            path = ctx.path,
            h_start = ctx.h_start,
            h_end = ctx.h_end,
          }
          shared.open_zk_link(item)
        elseif act == "Mark DONE" then
          local lines = buf_lines(0)
          local p_s, p_e = ensure_props(lines, ctx.h_start)
          p_e = set_status(lines, ctx.h_start, p_s, p_e, "DONE")
          set_buf_lines(0, lines)
        end
      end
    },
  })
end

-- ---------- Public functions ----------

function M.fast(opts)
  opts = opts or {}

  -- GTD focus: fast clarify is still GTD work
  if focus_mode and focus_mode.set then
    focus_mode.set("gtd")
  end

  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = buf_lines(buf)

  local h_start, h_end, lvl = find_heading(lines, lnum)
  if not h_start then
    if opts.promote_if_needed then
      h_start, h_end, lvl = promote_line_to_heading(lines, lnum, opts.status or "TODO")
    else
      shared.notify("Clarify: no org heading at/above cursor (won't promote).", "WARN")
      return
    end
  end

  local p_start, p_end = ensure_props(lines, h_start)
  local new_lines, id = task_id.ensure_in_properties(lines, h_start)
  lines = new_lines

  if opts.status and opts.status ~= "" then
    p_end = set_status(lines, h_start, p_start, p_end, opts.status)
  end

  local j = h_start + 1
  while j <= #lines do
    local lv2 = shared.heading_level(lines[j] or "")
    if lv2 and lv2 <= (lvl or 1) then break end
    j = j + 1
  end
  h_end = j - 1

  ensure_zk_link(lines, h_start, h_end, id)
  set_buf_lines(buf, lines)
  vim.api.nvim_win_set_cursor(0, { h_start, 0 })
  shared.notify("Clarified (ID " .. id .. ")", "INFO")
  return id
end

function M.clarify(opts)
  opts = opts or {}

  -- GTD focus: full clarify flow
  if focus_mode and focus_mode.set then
    focus_mode.set("gtd")
  end

  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = buf_lines(buf)

  local h_start, h_end, lvl = find_heading(lines, lnum)
  if not h_start then
    h_start, h_end, lvl = promote_line_to_heading(lines, lnum, "TODO")
  end

  local p_start, p_end = ensure_props(lines, h_start)
  local new_lines, id = task_id.ensure_in_properties(lines, h_start)
  lines = new_lines

  local current_status = (lines[h_start] or ""):match("^%*+%s+(%u+)%s") or nil
  local was_waiting = (current_status == "WAITING")

  pick_status("Clarify status", current_status, function(status_choice)
    if not status_choice then return end

    local is_becoming_waiting = (status_choice == "WAITING" and not was_waiting)
    local is_leaving_waiting = (was_waiting and status_choice ~= "WAITING")

    -- Handle WAITING metadata
    local function continue_with_status()
      p_end = set_status(lines, h_start, p_start, p_end, status_choice)

      local j = h_start + 1
      while j <= #lines do
        local lv2 = shared.heading_level(lines[j] or "")
        if lv2 and lv2 <= (lvl or 1) then break end
        j = j + 1
      end
      h_end = j - 1

      vim.ui.input({ prompt = "Append note (optional): " }, function(note)
        h_end = append_note(lines, h_start, h_end, note or "")

        local today = os.date("%Y-%m-%d")

        -- Special handling for WAITING status - use follow-up date as SCHEDULED
        if status_choice == "WAITING" then
          local waiting_data = extract_waiting_properties(lines, h_start, h_end)
          if waiting_data.follow_up_date then
            lines, h_end = set_dates(lines, h_start, h_end, waiting_data.follow_up_date, "")
            shared.notify("Set follow-up date as SCHEDULED", "INFO")
          else
            -- No follow-up date set, ask for defer only
            vim.ui.input({ prompt = ("Defer/SCHEDULED (YYYY-MM-DD, empty=keep, -=clear) [e.g. %s]: "):format(today) }, function(sched_in)
              local sched = sched_in or ""
              lines, h_end = set_dates(lines, h_start, h_end, sched, "")

              ensure_zk_link(lines, h_start, h_end, id)
              set_buf_lines(buf, lines)
              vim.api.nvim_win_set_cursor(0, { h_start, 0 })
              shared.notify(("Clarified → %s (ID %s)"):format(status_choice, id), "INFO")

              post_actions_menu({
                buf = buf, lines = lines, h_start = h_start, h_end = h_end,
                id = id, path = vim.api.nvim_buf_get_name(buf)
              })
            end)
            return
          end
        else
          -- Normal date handling for non-WAITING items
          vim.ui.input({ prompt = ("Defer/SCHEDULED (YYYY-MM-DD, empty=keep, -=clear) [e.g. %s]: "):format(today) }, function(sched_in)
            local sched = sched_in or ""
            local plus3 = os.date("%Y-%m-%d", os.time() + 3*24*3600)
            vim.ui.input({ prompt = ("Due/DEADLINE (YYYY-MM-DD, empty=keep, -=clear) [e.g. %s]: "):format(plus3) }, function(dead_in)
              local dead = dead_in or ""
              lines, h_end = set_dates(lines, h_start, h_end, sched, dead)

              ensure_zk_link(lines, h_start, h_end, id)
              set_buf_lines(buf, lines)
              vim.api.nvim_win_set_cursor(0, { h_start, 0 })
              shared.notify(("Clarified → %s (ID %s)"):format(status_choice, id), "INFO")

              post_actions_menu({
                buf = buf, lines = lines, h_start = h_start, h_end = h_end,
                id = id, path = vim.api.nvim_buf_get_name(buf)
              })
            end)
          end)
          return
        end

        ensure_zk_link(lines, h_start, h_end, id)
        set_buf_lines(buf, lines)
        vim.api.nvim_win_set_cursor(0, { h_start, 0 })
        shared.notify(("Clarified → %s (ID %s)"):format(status_choice, id), "INFO")

        post_actions_menu({
          buf = buf, lines = lines, h_start = h_start, h_end = h_end,
          id = id, path = vim.api.nvim_buf_get_name(buf)
        })
      end)
    end

    -- Handle status transitions
    if is_becoming_waiting then
      -- Converting TO WAITING - collect metadata
      shared.notify("Converting to WAITING - collecting metadata...", "INFO")
      collect_waiting_metadata(nil, function(waiting_data)
        lines, h_end = add_waiting_properties(lines, h_start, h_end, waiting_data)
        lines, h_end = update_waiting_body(lines, h_start, h_end, waiting_data)
        continue_with_status()
      end)
    elseif is_leaving_waiting then
      -- Converting FROM WAITING - clean up metadata
      shared.notify("Converting from WAITING - cleaning up metadata...", "INFO")
      lines, _ = clean_waiting_properties(lines, h_start, h_end)
      continue_with_status()
    else
      -- No status change or staying as WAITING
      continue_with_status()
    end
  end)
end

-- ---------- WAITING-specific functions ----------

-- Update WAITING metadata for task at cursor
function M.update_waiting_at_cursor()
  -- Still GTD work
  if focus_mode and focus_mode.set then
    focus_mode.set("gtd")
  end

  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = buf_lines(buf)

  local h_start, h_end = find_heading(lines, lnum)
  if not h_start then
    shared.notify("No heading found at cursor", "WARN")
    return
  end

  local current_status = (lines[h_start] or ""):match("^%*+%s+(%u+)%s")
  if current_status ~= "WAITING" then
    shared.notify("Task is not in WAITING status", "WARN")
    return
  end

  local existing_data = extract_waiting_properties(lines, h_start, h_end)
  collect_waiting_metadata(existing_data, function(waiting_data)
    -- Clean old properties and add new ones
    lines, _ = clean_waiting_properties(lines, h_start, h_end)

    -- Recalculate h_end after cleaning
    local j = h_start + 1
    while j <= #lines do
      local lv2 = shared.heading_level(lines[j] or "")
      if lv2 and lv2 <= 1 then break end
      j = j + 1
    end
    h_end = j - 1

    lines, h_end = add_waiting_properties(lines, h_start, h_end, waiting_data)
    lines, h_end = update_waiting_body(lines, h_start, h_end, waiting_data)

    -- Update SCHEDULED date to follow-up date if provided
    if waiting_data.follow_up_date then
      lines, h_end = set_dates(lines, h_start, h_end, waiting_data.follow_up_date, "")
    end

    set_buf_lines(buf, lines)
    shared.notify("Updated WAITING details", "INFO")
  end)
end

-- Convert task from WAITING to another status
function M.convert_from_waiting_at_cursor()
  -- Still GTD work
  if focus_mode and focus_mode.set then
    focus_mode.set("gtd")
  end

  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = buf_lines(buf)

  local h_start, h_end = find_heading(lines, lnum)
  if not h_start then
    shared.notify("No heading found at cursor", "WARN")
    return
  end

  local current_status = (lines[h_start] or ""):match("^%*+%s+(%u+)%s")
  if current_status ~= "WAITING" then
    shared.notify("Task is not in WAITING status", "WARN")
    return
  end

  local non_waiting_states = {"NEXT", "TODO", "SOMEDAY", "DONE"}
  vim.ui.select(non_waiting_states, { prompt = "Convert to status:" }, function(new_status)
    if not new_status then return end

    local p_start, p_end = ensure_props(lines, h_start)
    p_end = set_status(lines, h_start, p_start, p_end, new_status)

    -- Clean up WAITING properties
    lines, _ = clean_waiting_properties(lines, h_start, h_end)

    set_buf_lines(buf, lines)
    shared.notify("Converted from WAITING to " .. new_status, "INFO")
  end)
end

-- ---------- FIXED clarify picker (no DONE, no notes) ----------

function M.clarify_pick_any(opts)
  opts = opts or {}

  -- Enter GTD focus when using the clarify picker
  if focus_mode and focus_mode.set then
    focus_mode.set("gtd")
  end

  if not shared.have_fzf() then
    shared.notify("fzf-lua required for clarify_pick_any()", "WARN")
    return
  end

  -- Use filtered scanning (no DONE, no notes)
  local items = shared.scan_gtd_files_robust(opts)

  if #items == 0 then
    shared.notify("No actionable tasks found for clarify", "INFO")
    return
  end

  -- Create display list with proper priority order
  local display = {}
  for _, item in ipairs(items) do
    local state_tag = item.state and ("[" .. item.state .. "] ") or "[TODO] "
    local waiting_indicator = (item.state == "WAITING") and "⏳ " or ""
    local line = string.format("%s%s %s%s (%s)",
      item.context_icon, waiting_indicator, state_tag, item.title, item.filename)
    table.insert(display, line)
  end

  local fzf_config = shared.create_fzf_config(
    " GTD Clarify - Actionable Tasks Only ",
    "Clarify> ",
    "Enter: Clarify • Ctrl-E: Edit & Return • Ctrl-W: Update WAITING"
  )

  local actions = shared.create_standard_actions(display, items, M.clarify_pick_any, opts)

  -- Override default action for clarify workflow
  actions["default"] = function(sel)
    if not sel or not sel[1] then return end
    local idx = vim.fn.index(display, sel[1]) + 1
    local item = items[idx]
    if not item then return end

    vim.cmd("edit " .. vim.fn.fnameescape(item.path))
    vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })

    -- Run clarify workflow
    vim.schedule(function()
      M.clarify({})
    end)
  end

  -- Add WAITING-specific action
  actions["ctrl-w"] = function(sel)
    if not sel or not sel[1] then return end
    local idx = vim.fn.index(display, sel[1]) + 1
    local item = items[idx]
    if not item then return end

    vim.cmd("edit " .. vim.fn.fnameescape(item.path))
    vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })

    if item.state == "WAITING" then
      vim.schedule(function()
        M.update_waiting_at_cursor()
        M.clarify_pick_any(opts) -- Return to picker
      end)
    else
      shared.notify("Task is not in WAITING status", "WARN")
      vim.schedule(function() M.clarify_pick_any(opts) end)
    end
  end

  local fzf = require("fzf-lua")
  fzf.fzf_exec(display, vim.tbl_extend("force", fzf_config, {
    actions = actions
  }))
end

-- ---------- Utility functions ----------

-- List all WAITING items for review
function M.list_waiting_items()
  -- Also GTD mode
  if focus_mode and focus_mode.set then
    focus_mode.set("gtd")
  end

  local fzf = safe_require("fzf-lua")
  if not fzf then
    shared.notify("fzf-lua required for waiting items list", "WARN")
    return
  end

  local items = shared.scan_gtd_files_robust({ include_states = { "WAITING" } })

  if #items == 0 then
    shared.notify("No WAITING items found", "INFO")
    return
  end

  local display = {}
  for _, item in ipairs(items) do
    local priority_indicator = ""
    -- Extract priority if available (would need to be added to scan function)
    local follow_up_text = "" -- Could extract follow-up date too

    table.insert(display, string.format("⏳ %s | %s (%s)%s",
      item.title,
      item.filename,
      item.context_icon:gsub("📁 ", ""):gsub("📧 ", ""):gsub("📋 ", ""),
      follow_up_text))
  end

  fzf.fzf_exec(display, {
    prompt = "WAITING FOR> ",
    fzf_opts = { ["--no-info"] = true },
    winopts = { height = 0.60, width = 0.90, row = 0.10 },
    actions = {
      ["default"] = function(sel)
        local line = sel and sel[1]
        if not line then return end
        local idx = vim.fn.index(display, line) + 1
        local item = items[idx]
        if item then
          vim.cmd("edit " .. vim.fn.fnameescape(item.path))
          vim.api.nvim_win_set_cursor(0, {item.lnum, 0})
        end
      end,
    },
  })
end

-- Backward compatibility
function M.at_cursor(opts) return M.clarify(opts) end

return M