-- GTD Weekly Review Cockpit (Split-based)
-- Uses nvim splits for reliability
-- GET CLEAR → GET CURRENT → GET CREATIVE

local M = {}

M.cfg = {
  gtd_root = "~/Documents/GTD",
  zk_root = "~/Documents/Zettelkasten",
  review_history_file = "~/Documents/GTD/.review_history.json",
  custom_checklists_file = "~/Documents/GTD/.review_checklists.json",
  calendar_days_back = 7,
  calendar_days_forward = 14,
  icalbuddy_path = "/opt/homebrew/bin/icalBuddy",
  left_panel_width = 34,
}

local function xp(p) return vim.fn.expand(p) end

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local lists = safe_require("gtd-nvim.gtd.lists")
local capture = safe_require("gtd-nvim.gtd.capture")
local zettelkasten = safe_require("gtd-nvim.zettelkasten")

M.steps = {
  { id = "collect",    phase = "CLEAR",    label = "Collect loose papers",   icon = "📋", action = "checklist" },
  { id = "inbox",      phase = "CLEAR",    label = "Process Inbox to zero",  icon = "📥", action = "inbox" },
  { id = "empty",      phase = "CLEAR",    label = "Empty your head",        icon = "💭", action = "capture" },
  { id = "actions",    phase = "CURRENT",  label = "Review Action lists",    icon = "⚡", action = "next_actions" },
  { id = "past_cal",   phase = "CURRENT",  label = "Review past calendar",   icon = "📅", action = "calendar_past" },
  { id = "future_cal", phase = "CURRENT",  label = "Review upcoming calendar", icon = "🗓", action = "calendar_future" },
  { id = "waiting",    phase = "CURRENT",  label = "Review Waiting For",     icon = "⏳", action = "waiting" },
  { id = "projects",   phase = "CURRENT",  label = "Review Projects",        icon = "📂", action = "projects" },
  { id = "checklists", phase = "CURRENT",  label = "Review Checklists",      icon = "✅", action = "custom_checklists" },
  { id = "someday",    phase = "CREATIVE", label = "Review Someday/Maybe",   icon = "💫", action = "someday" },
  { id = "brainstorm", phase = "CREATIVE", label = "Be creative",            icon = "🚀", action = "brainstorm" },
}

M.state = {
  current_step = 1,
  completed = {},
  start_time = nil,
  metrics = {},
  active = false,
  buffers = {},
  -- Checklist state
  checklist_items = {},      -- { checklist_key = { item_id = true/false } }
  active_checklist = nil,    -- Currently displayed checklist key
  checklist_cursor = 1,      -- Current item in checklist
  view_mode = "steps",       -- "steps" or "checklist"
}

local function read_json(path)
  local expanded = xp(path)
  if vim.fn.filereadable(expanded) ~= 1 then return {} end
  local content = table.concat(vim.fn.readfile(expanded), "\n")
  local ok, data = pcall(vim.fn.json_decode, content)
  return ok and data or {}
end

local function write_json(path, data)
  local expanded = xp(path)
  vim.fn.mkdir(vim.fn.fnamemodify(expanded, ":h"), "p")
  local ok, encoded = pcall(vim.fn.json_encode, data)
  if ok then vim.fn.writefile({ encoded }, expanded) end
end

local function collect_metrics()
  local gtd_root = xp(M.cfg.gtd_root)
  local m = { inbox = 0, next = 0, todo = 0, waiting = 0, someday = 0, projects = 0 }
  
  local handle = io.popen(string.format("find %q -type f -name '*.org' ! -name 'Archive.org' 2>/dev/null", gtd_root))
  if not handle then return m end
  
  for filepath in handle:lines() do
    local lines = vim.fn.readfile(filepath)
    local in_inbox = filepath:match("Inbox%.org$")
    local is_project = filepath:match("/Projects/") or filepath:match("/Areas/")
    
    for _, line in ipairs(lines) do
      local state = line:match("^%*+%s+([A-Z]+)%s")
      if state then
        if state == "NEXT" then m.next = m.next + 1
        elseif state == "TODO" then m.todo = m.todo + 1
        elseif state == "WAITING" then m.waiting = m.waiting + 1
        elseif state == "SOMEDAY" then m.someday = m.someday + 1
        end
        if in_inbox and state ~= "DONE" then m.inbox = m.inbox + 1 end
      end
    end
    if is_project then m.projects = m.projects + 1 end
  end
  handle:close()
  return m
end

local function get_calendar_events(days_offset, days_count)
  local events = {}
  local icalbuddy = M.cfg.icalbuddy_path
  if vim.fn.executable(icalbuddy) ~= 1 then return events end
  
  local cmd
  if days_offset < 0 then
    local start_date = os.date("%Y-%m-%d", os.time() + days_offset * 86400)
    local end_date = os.date("%Y-%m-%d")
    cmd = string.format("%s -nc -nrd -df '%%Y-%%m-%%d' -tf '%%H:%%M' eventsFrom:%s to:%s 2>/dev/null", icalbuddy, start_date, end_date)
  else
    cmd = string.format("%s -nc -nrd -df '%%Y-%%m-%%d' -tf '%%H:%%M' eventsToday+%d 2>/dev/null", icalbuddy, days_count)
  end
  
  local handle = io.popen(cmd)
  if handle then
    for line in handle:lines() do
      if line ~= "" then 
        local cleaned = line:gsub("^%s*•%s*", "")
        table.insert(events, cleaned)
      end
    end
    handle:close()
  end
  return events
end

local function get_last_review()
  local history = read_json(M.cfg.review_history_file)
  return history[#history]
end

local function save_review()
  local history = read_json(M.cfg.review_history_file)
  table.insert(history, {
    date = os.date("%Y-%m-%d"),
    week = os.date("%Y-W%W"),
    duration = M.state.start_time and math.floor((os.time() - M.state.start_time) / 60) or 0,
    steps = vim.tbl_count(M.state.completed),
    total = #M.steps,
  })
  while #history > 52 do table.remove(history, 1) end
  write_json(M.cfg.review_history_file, history)
end

local function load_checklists()
  local data = read_json(M.cfg.custom_checklists_file)
  if vim.tbl_isempty(data) then
    data = {
      weekly = { 
        name = "Weekly Review Prep", 
        items = {
          { id = "desk", label = "Clear physical desk/workspace" },
          { id = "downloads", label = "Process Downloads folder" },
          { id = "notes", label = "Review notes & Zettelkasten", action = "zettelkasten" },
          { id = "wallet", label = "Empty wallet receipts" },
          { id = "voice", label = "Process voice memos" },
          { id = "email", label = "Inbox zero (email)" },
        }
      },
      monthly = { 
        name = "Monthly Review", 
        items = {
          { id = "goals", label = "Review monthly goals" },
          { id = "habits", label = "Evaluate habits & routines" },
          { id = "finances", label = "Review financial summaries" },
          { id = "subscriptions", label = "Review subscriptions" },
        }
      },
      triggers = {
        name = "Trigger List",
        items = {
          { id = "projects", label = "Professional projects" },
          { id = "meetings", label = "Upcoming meetings/events" },
          { id = "people", label = "People to contact" },
          { id = "errands", label = "Errands to run" },
          { id = "home", label = "Home improvements" },
          { id = "health", label = "Health/medical items" },
          { id = "family", label = "Family commitments" },
          { id = "learning", label = "Learning/development" },
        }
      },
    }
    write_json(M.cfg.custom_checklists_file, data)
  end
  return data
end

-- Render left panel
local function render_left()
  local buf = M.state.buffers.left
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local lines = {}
  local phase = nil
  
  table.insert(lines, "╔══════════════════════════════╗")
  table.insert(lines, "║   📋 GTD WEEKLY REVIEW       ║")
  table.insert(lines, "║   Week " .. os.date("%W") .. " • " .. os.date("%Y-%m-%d") .. "    ║")
  table.insert(lines, "╚══════════════════════════════╝")
  table.insert(lines, "")
  
  for i, step in ipairs(M.steps) do
    if step.phase ~= phase then
      phase = step.phase
      if phase == "CLEAR" then table.insert(lines, "── 🧹 GET CLEAR ──────────────")
      elseif phase == "CURRENT" then table.insert(lines, "── 🔄 GET CURRENT ────────────")
      elseif phase == "CREATIVE" then table.insert(lines, "── 💡 GET CREATIVE ───────────")
      end
    end
    local done = M.state.completed[step.id] and "✅" or "⬜"
    local cur = i == M.state.current_step and "▶" or " "
    table.insert(lines, string.format("%s %s %s %s", cur, done, step.icon, step.label))
  end
  
  table.insert(lines, "")
  local c = vim.tbl_count(M.state.completed)
  local pct = math.floor((c / #M.steps) * 100)
  local bar = string.rep("█", math.floor(c / #M.steps * 20)) .. string.rep("░", 20 - math.floor(c / #M.steps * 20))
  table.insert(lines, bar .. " " .. pct .. "%")
  table.insert(lines, "Steps: " .. c .. "/" .. #M.steps)
  if M.state.start_time then
    table.insert(lines, "Time: " .. math.floor((os.time() - M.state.start_time) / 60) .. " min")
  end
  
  local last = get_last_review()
  if last then table.insert(lines, "Last: " .. (last.date or "?")) end
  
  table.insert(lines, "")
  table.insert(lines, "────────────────────────────────")
  local m = M.state.metrics
  table.insert(lines, "📥 Inbox:" .. (m.inbox or 0) .. " ⚡NEXT:" .. (m.next or 0))
  table.insert(lines, "⏳ WAIT:" .. (m.waiting or 0) .. " 📂 Proj:" .. (m.projects or 0))
  table.insert(lines, "")
  table.insert(lines, "────────────────────────────────")
  table.insert(lines, "j/k:Move  Space:Done  Enter:Act")
  table.insert(lines, "n:Next r:Refresh R:Report z:ZK")
  table.insert(lines, "s:Save  q:Quit")
  
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Render right panel
local function render_right(content)
  local buf = M.state.buffers.right
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local lines = {}
  local step = M.steps[M.state.current_step]
  
  table.insert(lines, "╔═══════════════════════════════════════════════════════════════╗")
  table.insert(lines, "║  " .. (step and (step.icon .. " " .. step.label) or "GTD Review") .. string.rep(" ", 50) .. "║")
  table.insert(lines, "╚═══════════════════════════════════════════════════════════════╝")
  table.insert(lines, "")
  
  if content == "checklist" then
    table.insert(lines, "  Physical task - gather items into your inbox:")
    table.insert(lines, "")
    table.insert(lines, "    • Business cards & receipts")
    table.insert(lines, "    • Paper notes & post-its")
    table.insert(lines, "    • Meeting notes")
    table.insert(lines, "    • Items from bags, pockets, wallet")
    table.insert(lines, "    • Desktop & Downloads folder")
    table.insert(lines, "    • Voice memos")
    table.insert(lines, "")
    table.insert(lines, "  Press SPACE when done, j to move on")
    
  elseif content == "calendar_past" then
    table.insert(lines, "  Past " .. M.cfg.calendar_days_back .. " days - review for actions/follow-ups:")
    table.insert(lines, "")
    for _, e in ipairs(get_calendar_events(-M.cfg.calendar_days_back, M.cfg.calendar_days_back)) do
      table.insert(lines, "  • " .. e)
    end
    
  elseif content == "calendar_future" then
    table.insert(lines, "  Next " .. M.cfg.calendar_days_forward .. " days - prepare/trigger actions:")
    table.insert(lines, "")
    for _, e in ipairs(get_calendar_events(0, M.cfg.calendar_days_forward)) do
      table.insert(lines, "  • " .. e)
    end
    
  elseif content == "brainstorm" then
    table.insert(lines, "  Ask yourself:")
    table.insert(lines, "")
    table.insert(lines, "    • What projects would make a difference?")
    table.insert(lines, "    • What am I avoiding?")
    table.insert(lines, "    • What would I do if I couldn't fail?")
    table.insert(lines, "    • What's draining my energy?")
    table.insert(lines, "")
    table.insert(lines, "  Press Enter to capture ideas")
    
  elseif content == "custom_checklists" then
    local checklists = load_checklists()
    
    if M.state.active_checklist then
      -- Show active checklist with interactive items
      local cl = checklists[M.state.active_checklist]
      if cl then
        table.insert(lines, "  ✅ " .. cl.name)
        table.insert(lines, "  ─────────────────────────────────────────────────────")
        table.insert(lines, "")
        
        local items = cl.items or {}
        local checked = M.state.checklist_items[M.state.active_checklist] or {}
        
        for i, it in ipairs(items) do
          local is_current = (i == M.state.checklist_cursor)
          local is_checked = checked[it.id or it.label]
          local checkbox = is_checked and "✅" or "⬜"
          local marker = is_current and " ▶ " or "   "
          local action_hint = it.action and " 🔗" or ""
          table.insert(lines, marker .. checkbox .. " " .. it.label .. action_hint)
        end
        
        table.insert(lines, "")
        table.insert(lines, "  ─────────────────────────────────────────────────────")
        table.insert(lines, "  j/k: navigate │ Space: toggle │ Enter: action")
        table.insert(lines, "  b: back to list │ a: mark all done")
      end
    else
      -- Show checklist selection
      table.insert(lines, "  Select a checklist to review:")
      table.insert(lines, "")
      
      local keys = {}
      for k in pairs(checklists) do table.insert(keys, k) end
      table.sort(keys)
      
      for i, k in ipairs(keys) do
        local cl = checklists[k]
        local checked = M.state.checklist_items[k] or {}
        local total = #(cl.items or {})
        local done = 0
        for _, it in ipairs(cl.items or {}) do
          if checked[it.id or it.label] then done = done + 1 end
        end
        local status = done == total and "✅" or string.format("(%d/%d)", done, total)
        table.insert(lines, string.format("  %d. %s %s", i, cl.name, status))
      end
      
      table.insert(lines, "")
      table.insert(lines, "  Press 1/2/3 to select checklist")
    end
    
  elseif content == "report" then
    table.insert(lines, "  ══════════════════════════════════════")
    table.insert(lines, "  REVIEW COMPLETE")
    table.insert(lines, "  Date: " .. os.date("%Y-%m-%d %H:%M"))
    table.insert(lines, "  Steps: " .. vim.tbl_count(M.state.completed) .. "/" .. #M.steps)
    if M.state.start_time then
      table.insert(lines, "  Duration: " .. math.floor((os.time() - M.state.start_time) / 60) .. " min")
    end
    table.insert(lines, "")
    table.insert(lines, "  ─────────────────────────────────────────")
    table.insert(lines, "  z → Export to Zettelkasten 📝")
    table.insert(lines, "  s → Save history and close")
    table.insert(lines, "  ─────────────────────────────────────────")
    
  else
    table.insert(lines, '  "Your mind is for having ideas, not holding them."')
    table.insert(lines, "                                      — David Allen")
    table.insert(lines, "")
    table.insert(lines, "  Navigate with j/k, press Enter to act, Space to complete.")
  end
  
  table.insert(lines, "")
  table.insert(lines, "  ─────────────────────────────────────────────────────────────")
  table.insert(lines, "  Space:complete │ Enter:action │ j/k:navigate │ q:quit")
  
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

local function refresh_ui()
  render_left()
  local step = M.steps[M.state.current_step]
  render_right(step and step.action or "welcome")
end

-- Navigation
function M.next_step()
  if M.state.current_step < #M.steps then
    M.state.current_step = M.state.current_step + 1
    refresh_ui()
  end
end

function M.prev_step()
  if M.state.current_step > 1 then
    M.state.current_step = M.state.current_step - 1
    refresh_ui()
  end
end

function M.next_incomplete()
  for i = 1, #M.steps do
    local idx = ((M.state.current_step - 1 + i) % #M.steps) + 1
    if not M.state.completed[M.steps[idx].id] then
      M.state.current_step = idx
      refresh_ui()
      return
    end
  end
  vim.notify("🎉 All steps complete!", vim.log.levels.INFO)
end

function M.toggle_complete()
  local step = M.steps[M.state.current_step]
  if step then
    M.state.completed[step.id] = not M.state.completed[step.id] or nil
    refresh_ui()
    if vim.tbl_count(M.state.completed) == #M.steps then
      vim.notify("🎉 Review complete! Press R for report, s to save.", vim.log.levels.INFO)
    end
  end
end

-- Checklist navigation and interaction
function M.checklist_next()
  if not M.state.active_checklist then return end
  local cl = load_checklists()[M.state.active_checklist]
  if cl and M.state.checklist_cursor < #(cl.items or {}) then
    M.state.checklist_cursor = M.state.checklist_cursor + 1
    refresh_ui()
  end
end

function M.checklist_prev()
  if not M.state.active_checklist then return end
  if M.state.checklist_cursor > 1 then
    M.state.checklist_cursor = M.state.checklist_cursor - 1
    refresh_ui()
  end
end

function M.checklist_toggle()
  if not M.state.active_checklist then return end
  local cl = load_checklists()[M.state.active_checklist]
  if not cl then return end
  
  local items = cl.items or {}
  local item = items[M.state.checklist_cursor]
  if not item then return end
  
  local key = M.state.active_checklist
  M.state.checklist_items[key] = M.state.checklist_items[key] or {}
  local item_id = item.id or item.label
  M.state.checklist_items[key][item_id] = not M.state.checklist_items[key][item_id]
  
  refresh_ui()
end

function M.checklist_action()
  if not M.state.active_checklist then return end
  local cl = load_checklists()[M.state.active_checklist]
  if not cl then return end
  
  local item = (cl.items or {})[M.state.checklist_cursor]
  if not item or not item.action then return end
  
  if item.action == "zettelkasten" then
    M.pause()
    if zettelkasten and zettelkasten.find then
      zettelkasten.find()
    else
      vim.cmd("edit " .. xp(M.cfg.zk_root))
    end
    vim.notify("📝 Review notes, :GtdReview to continue", vim.log.levels.INFO)
  end
end

function M.checklist_mark_all()
  if not M.state.active_checklist then return end
  local cl = load_checklists()[M.state.active_checklist]
  if not cl then return end
  
  local key = M.state.active_checklist
  M.state.checklist_items[key] = M.state.checklist_items[key] or {}
  
  for _, item in ipairs(cl.items or {}) do
    local item_id = item.id or item.label
    M.state.checklist_items[key][item_id] = true
  end
  
  refresh_ui()
  vim.notify("✅ All items marked done", vim.log.levels.INFO)
end

function M.checklist_back()
  M.state.active_checklist = nil
  M.state.checklist_cursor = 1
  refresh_ui()
end

function M.select_checklist(num)
  local checklists = load_checklists()
  local keys = {}
  for k in pairs(checklists) do table.insert(keys, k) end
  table.sort(keys)
  
  if keys[num] then
    M.state.active_checklist = keys[num]
    M.state.checklist_cursor = 1
    M.state.checklist_items[keys[num]] = M.state.checklist_items[keys[num]] or {}
    refresh_ui()
  end
end

-- Smart navigation (handles both step and checklist modes)
function M.nav_down()
  local step = M.steps[M.state.current_step]
  if step and step.action == "custom_checklists" and M.state.active_checklist then
    M.checklist_next()
  else
    M.next_step()
  end
end

function M.nav_up()
  local step = M.steps[M.state.current_step]
  if step and step.action == "custom_checklists" and M.state.active_checklist then
    M.checklist_prev()
  else
    M.prev_step()
  end
end

function M.smart_toggle()
  local step = M.steps[M.state.current_step]
  if step and step.action == "custom_checklists" and M.state.active_checklist then
    M.checklist_toggle()
  else
    M.toggle_complete()
  end
end

function M.smart_action()
  local step = M.steps[M.state.current_step]
  if step and step.action == "custom_checklists" and M.state.active_checklist then
    M.checklist_action()
  else
    M.execute_action()
  end
end

function M.execute_action()
  local step = M.steps[M.state.current_step]
  if not step then return end
  
  local action = step.action
  
  -- Actions that open external views - pause review (preserves state)
  if action == "inbox" then
    M.pause()
    if lists and lists.inbox then lists.inbox() end
  elseif action == "capture" then
    M.pause()
    if capture and capture.capture_quick then capture.capture_quick() end
  elseif action == "next_actions" then
    M.pause()
    if lists and lists.next_actions then lists.next_actions() end
  elseif action == "waiting" then
    M.pause()
    if lists and lists.waiting then lists.waiting() end
  elseif action == "projects" then
    M.pause()
    if lists and lists.projects then lists.projects() end
  elseif action == "someday" then
    M.pause()
    if lists and lists.someday_maybe then lists.someday_maybe() end
  else
    -- Actions that show content in the right panel (no pause)
    render_right(action)
  end
end

function M.refresh()
  M.state.metrics = collect_metrics()
  refresh_ui()
  vim.notify("📊 Refreshed", vim.log.levels.INFO)
end

function M.show_report()
  render_right("report")
end

function M.export_to_zettelkasten()
  local zk_root = xp(M.cfg.zk_root)
  local timestamp = os.date("%Y%m%d%H%M%S")
  local date = os.date("%Y-%m-%d")
  local week = os.date("%Y-W%W")
  local filename = string.format("%s-weekly-review-%s.md", timestamp, os.date("%Y-W%W"))
  local filepath = zk_root .. "/" .. filename
  
  local m = M.state.metrics
  local completed_count = vim.tbl_count(M.state.completed)
  local duration = M.state.start_time and math.floor((os.time() - M.state.start_time) / 60) or 0
  
  local lines = {
    "---",
    "id: " .. timestamp,
    "title: Weekly Review " .. week,
    "date: " .. date,
    "tags: [gtd, weekly-review]",
    "---",
    "",
    "# Weekly Review " .. week,
    "",
    "**Date:** " .. date,
    "**Duration:** " .. duration .. " minutes",
    "**Steps Completed:** " .. completed_count .. "/" .. #M.steps,
    "",
    "## GTD Metrics Snapshot",
    "",
    "| Category | Count |",
    "|----------|-------|",
    "| 📥 Inbox | " .. (m.inbox or 0) .. " |",
    "| ⚡ NEXT | " .. (m.next or 0) .. " |",
    "| 📋 TODO | " .. (m.todo or 0) .. " |",
    "| ⏳ WAITING | " .. (m.waiting or 0) .. " |",
    "| 📂 Projects | " .. (m.projects or 0) .. " |",
    "| 💫 Someday | " .. (m.someday or 0) .. " |",
    "",
    "## Review Steps",
    "",
  }
  
  for _, step in ipairs(M.steps) do
    local status = M.state.completed[step.id] and "✅" or "⬜"
    table.insert(lines, "- " .. status .. " " .. step.icon .. " " .. step.label)
  end
  
  -- Add checklist progress
  table.insert(lines, "")
  table.insert(lines, "## Checklists Completed")
  table.insert(lines, "")
  
  local checklists = load_checklists()
  for key, cl in pairs(checklists) do
    local checked = M.state.checklist_items[key] or {}
    local total = #(cl.items or {})
    local done = 0
    for _, it in ipairs(cl.items or {}) do
      if checked[it.id or it.label] then done = done + 1 end
    end
    if done > 0 then
      table.insert(lines, "### " .. cl.name .. " (" .. done .. "/" .. total .. ")")
      for _, it in ipairs(cl.items or {}) do
        local item_id = it.id or it.label
        local status = checked[item_id] and "✅" or "⬜"
        table.insert(lines, "- " .. status .. " " .. it.label)
      end
      table.insert(lines, "")
    end
  end
  
  table.insert(lines, "## Notes")
  table.insert(lines, "")
  table.insert(lines, "_Add your reflections here..._")
  table.insert(lines, "")
  
  -- Write the file
  vim.fn.mkdir(zk_root, "p")
  vim.fn.writefile(lines, filepath)
  
  -- Open the note
  vim.cmd("edit " .. filepath)
  vim.notify("📝 Review exported to Zettelkasten: " .. filename, vim.log.levels.INFO)
end

function M.save_and_close()
  if vim.tbl_count(M.state.completed) > 0 then
    save_review()
    vim.notify("✅ Review saved", vim.log.levels.INFO)
  end
  M.state.paused = false  -- Clear paused state on intentional save
  M.state.start_time = nil  -- Reset for next session
  M.state.completed = {}
  M.close()
end

-- Pause review (keeps state, closes UI)
function M.pause()
  M.state.paused = true
  M.state.active = false
  
  -- Close buffers but keep state
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  M.state.buffers = {}
  
  vim.notify("📋 Review paused - :GtdReview to continue", vim.log.levels.INFO)
end

function M.close()
  if not M.state.active then return end
  M.state.active = false
  
  -- Close buffers and windows
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  M.state.buffers = {}
end

-- Quit completely (clears state, no resume)
function M.quit()
  M.state.paused = false
  M.state.start_time = nil
  M.state.completed = {}
  M.state.current_step = 1
  M.state.checklist_items = {}
  M.state.active_checklist = nil
  M.close()
  
  -- Only close tab if there are multiple tabs
  if vim.fn.tabpagenr('$') > 1 then
    vim.cmd("tabclose")
  else
    -- If only one tab, just go to a blank buffer
    vim.cmd("enew")
  end
end

function M.start()
  if M.state.active then
    vim.notify("Review already open", vim.log.levels.WARN)
    return
  end
  
  -- Check if resuming from pause
  local resuming = M.state.paused and M.state.start_time
  
  if resuming then
    -- Resume: keep state, just refresh metrics
    M.state.metrics = collect_metrics()
    M.state.active = true
    M.state.paused = false
    vim.notify("📋 Resuming review...", vim.log.levels.INFO)
  else
    -- Fresh start
    M.state = {
      current_step = 1,
      completed = {},
      start_time = os.time(),
      metrics = collect_metrics(),
      active = true,
      paused = false,
      buffers = {},
      checklist_items = {},
      active_checklist = nil,
      checklist_cursor = 1,
    }
  end
  
  M.state.buffers = {}
  
  -- Create layout: vertical split
  vim.cmd("tabnew")
  vim.cmd("vsplit")
  
  -- Left panel (narrow)
  vim.cmd("wincmd h")
  vim.cmd("vertical resize " .. M.cfg.left_panel_width)
  local left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(left_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(left_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(left_buf, "GTD-Review-Steps")
  vim.api.nvim_set_current_buf(left_buf)
  M.state.buffers.left = left_buf
  
  -- Right panel (main content)
  vim.cmd("wincmd l")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(right_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(right_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(right_buf, "GTD-Review-Content")
  vim.api.nvim_set_current_buf(right_buf)
  M.state.buffers.right = right_buf
  
  -- Keymaps for both buffers
  local opts = { noremap = true, silent = true }
  for _, buf in pairs(M.state.buffers) do
    -- Smart navigation (handles both step and checklist modes)
    vim.api.nvim_buf_set_keymap(buf, "n", "j", ":lua require('gtd-nvim.gtd.review').nav_down()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "k", ":lua require('gtd-nvim.gtd.review').nav_up()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<Down>", ":lua require('gtd-nvim.gtd.review').nav_down()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<Up>", ":lua require('gtd-nvim.gtd.review').nav_up()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "n", ":lua require('gtd-nvim.gtd.review').next_incomplete()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<Space>", ":lua require('gtd-nvim.gtd.review').smart_toggle()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", ":lua require('gtd-nvim.gtd.review').smart_action()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "r", ":lua require('gtd-nvim.gtd.review').refresh()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "R", ":lua require('gtd-nvim.gtd.review').show_report()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "s", ":lua require('gtd-nvim.gtd.review').save_and_close()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":lua require('gtd-nvim.gtd.review').quit()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "z", ":lua require('gtd-nvim.gtd.review').export_to_zettelkasten()<CR>", opts)
    -- Checklist-specific
    vim.api.nvim_buf_set_keymap(buf, "n", "b", ":lua require('gtd-nvim.gtd.review').checklist_back()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "a", ":lua require('gtd-nvim.gtd.review').checklist_mark_all()<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "1", ":lua require('gtd-nvim.gtd.review').select_checklist(1)<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "2", ":lua require('gtd-nvim.gtd.review').select_checklist(2)<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "3", ":lua require('gtd-nvim.gtd.review').select_checklist(3)<CR>", opts)
  end
  
  refresh_ui()
  vim.cmd("wincmd h") -- Focus left panel
end

function M.history()
  local h = read_json(M.cfg.review_history_file)
  if #h == 0 then
    vim.notify("No review history yet", vim.log.levels.INFO)
    return
  end
  local lines = { "📊 REVIEW HISTORY", "" }
  for i = #h, math.max(1, #h - 10), -1 do
    local e = h[i]
    table.insert(lines, string.format("%s | %s | %d/%d | %d min", e.date, e.week, e.steps, e.total, e.duration or 0))
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.setup(opts)
  if opts then
    for k, v in pairs(opts) do M.cfg[k] = v end
  end
  
  vim.api.nvim_create_user_command("GtdReview", function() M.start() end, { desc = "GTD Weekly Review" })
  vim.api.nvim_create_user_command("GtdReviewHistory", function() M.history() end, { desc = "Review history" })
  vim.api.nvim_create_user_command("GtdReviewChecklists", function()
    vim.cmd("edit " .. xp(M.cfg.custom_checklists_file))
  end, { desc = "Edit checklists" })
end

return M
