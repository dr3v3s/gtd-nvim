-- ============================================================================
-- GTD-NVIM WEEKLY REVIEW MODULE V2
-- ============================================================================
-- Split-based Weekly Review Cockpit with Chronos Daemon Integration
-- Phases: GET CLEAR → GET CURRENT → GET CREATIVE
--
-- @module gtd-nvim.gtd.review
-- @version 2.5.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "2.6.0"
M._UPDATED = "2025-12-27"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local shared = safe_require("gtd-nvim.gtd.shared") or {}
local chronos = safe_require("gtd-nvim.gtd.chronos")
local chronos_client = safe_require("gtd-nvim.gtd.chronos-client")
local g = shared.glyphs or {}

-- Glyph shortcuts
local gs = g.state or {}
local gc = g.container or {}
local gr = g.review or {}
local gu = g.ui or {}
local gx = g.checkbox or {}
local gp = g.progress or {}

-- ============================================================================
-- COLORS (Catppuccin Mocha)
-- ============================================================================

local colors = {
  mauve     = "#cba6f7",
  red       = "#f38ba8",
  peach     = "#fab387",
  yellow    = "#f9e2af",
  green     = "#a6e3a1",
  teal      = "#94e2d5",
  sky       = "#89dceb",
  blue      = "#89b4fa",
  lavender  = "#b4befe",
  text      = "#cdd6f4",
  subtext1  = "#bac2de",
  subtext0  = "#a6adc8",
  overlay1  = "#7f849c",
  overlay0  = "#6c7086",
  surface2  = "#585b70",
  surface1  = "#45475a",
  surface0  = "#313244",
}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.cfg = {
  reviews_subdir = "Reviews",
  state_file = ".review_state.json",
  history_file = ".review_history.json",
  checklists_file = ".review_checklists.json",
  calendar_days_back = 7,
  calendar_days_forward = 14,
  left_panel_width = 38,
  auto_save = true,
}

-- ============================================================================
-- PATH HELPERS
-- ============================================================================

local function gtd_root()
  return shared.gtd_home and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
end

local function zk_root()
  return shared.notes_home and shared.notes_home() or vim.fn.expand("~/Documents/Notes")
end

local function reviews_dir()
  return zk_root() .. "/" .. M.cfg.reviews_subdir
end

local function state_file()
  return gtd_root() .. "/" .. M.cfg.state_file
end

local function history_file()
  return gtd_root() .. "/" .. M.cfg.history_file
end

-- ============================================================================
-- JSON HELPERS
-- ============================================================================

local function read_json(path)
  if vim.fn.filereadable(path) ~= 1 then return {} end
  local content = table.concat(vim.fn.readfile(path), "\n")
  local ok, data = pcall(vim.fn.json_decode, content)
  return ok and data or {}
end

local function write_json(path, data)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, encoded = pcall(vim.fn.json_encode, data)
  if ok then vim.fn.writefile({ encoded }, path) end
end

-- ============================================================================
-- REVIEW STEPS DEFINITION
-- ============================================================================

M.steps = {
  -- GET CLEAR
  { id = "collect",    phase = "CLEAR",    label = "Collect loose papers",     icon = gc.inbox or "", action = "note" },
  { id = "inbox",      phase = "CLEAR",    label = "Process Inbox to zero",    icon = gc.inbox or "", action = "inbox" },
  { id = "mail",       phase = "CLEAR",    label = "Email Inbox Zero",         icon = "󰇮", action = "mail_inbox" },
  { id = "empty",      phase = "CLEAR",    label = "Empty your head",          icon = "󰐕", action = "note" },
  -- GET CURRENT
  { id = "actions",    phase = "CURRENT",  label = "Review Action lists",      icon = gs.NEXT or "󰁔", action = "next" },
  { id = "past_cal",   phase = "CURRENT",  label = "Review past calendar",     icon = gc.calendar or "", action = "calendar_past" },
  { id = "future_cal", phase = "CURRENT",  label = "Review upcoming calendar", icon = gc.calendar or "", action = "calendar_future" },
  { id = "waiting",    phase = "CURRENT",  label = "Review Waiting For",       icon = gs.WAITING or "󰈸", action = "waiting" },
  { id = "projects",   phase = "CURRENT",  label = "Review Projects",          icon = gc.projects or "󰉋", action = "projects" },
  { id = "stuck",      phase = "CURRENT",  label = "Review Stuck Projects",    icon = gp.blocked or "", action = "stuck" },
  { id = "checklists", phase = "CURRENT",  label = "Review Checklists",        icon = gx.checked or "", action = "checklists" },
  -- GET CREATIVE
  { id = "someday",    phase = "CREATIVE", label = "Review Someday/Maybe",     icon = gs.SOMEDAY or "󰋚", action = "someday" },
  { id = "brainstorm", phase = "CREATIVE", label = "Be creative & brainstorm", icon = gu.rocket or "", action = "note" },
}

-- ============================================================================
-- STATE
-- ============================================================================

M.state = {
  active = false,
  paused = false,
  current_step = 1,
  completed = {},
  start_time = nil,
  week_id = nil,
  review_id = nil,
  review_note_path = nil,
  metrics = {},
  mail_stats = {},
  buffers = {},
  windows = {},
  review_tab = nil,
  checklist_items = {},
  active_checklist = nil,
  checklist_cursor = 1,
}

local function get_week_id()
  return os.date("%Y-W%W")
end

local function generate_review_id()
  return os.date("%Y%m%d%H%M%S")
end

-- ============================================================================
-- DATA FETCHING (via Chronos Daemon)
-- ============================================================================

local function fetch_metrics()
  if not chronos then return {} end
  local data = chronos.query("gtd", "metrics", {})
  return data or {}
end

local function fetch_mail_stats()
  if not chronos_client then return nil end
  local data, err = chronos_client.query_daemon("mail", "stats")
  if not data then return nil end
  return {
    accounts = data.accounts or {},
    inbox_unread = data.inbox_unread or 0,
    total_unread = data.total_unread or 0,
  }
end

local function fetch_tasks(states)
  if not chronos then return {} end
  local data = chronos.query("gtd", "tasks", { states = states })
  return data and data.tasks or {}
end

local function fetch_projects()
  if not chronos then return {} end
  local data = chronos.query("gtd", "projects", {})
  return data and data.projects or {}
end

local function fetch_inbox()
  local tasks = fetch_tasks({ "TODO", "NEXT", "WAITING", "SOMEDAY" })
  local inbox = {}
  for _, t in ipairs(tasks) do
    if t.file and t.file:match("/Inbox%.org$") then
      table.insert(inbox, t)
    end
  end
  return inbox
end

local function fetch_calendar_events(direction)
  -- Query chronos-bridge directly for calendar events
  local bridge_socket = vim.fn.expand("~/.cache/chronos/chronos-bridge.sock")
  if vim.fn.filereadable(bridge_socket) ~= 1 then
    return {}
  end
  
  -- Use "events" command which supports both days_ahead and days_back
  local cmd
  if direction == "past" then
    cmd = string.format('{"module":"calendar","cmd":"events","params":{"days_back":%d,"days_ahead":0}}', M.cfg.calendar_days_back)
  else
    cmd = string.format('{"module":"calendar","cmd":"events","params":{"days_ahead":%d,"days_back":0}}', M.cfg.calendar_days_forward)
  end
  
  local handle = io.popen(string.format("echo '%s' | nc -U '%s' 2>/dev/null", cmd, bridge_socket))
  if not handle then return {} end
  
  local result = handle:read("*a")
  handle:close()
  
  if not result or result == "" then return {} end
  
  local ok, data = pcall(vim.fn.json_decode, result)
  if not ok or not data or not data.data then return {} end
  
  local events = data.data.events or {}
  
  -- Transform and sort events
  local formatted = {}
  for _, e in ipairs(events) do
    local date_str = ""
    local time_str = ""
    
    if e.start then
      date_str = e.start:match("(%d%d%d%d%-%d%d%-%d%d)") or ""
      time_str = e.start:match("T(%d%d:%d%d)") or ""
    end
    
    table.insert(formatted, {
      title = e.title or "(untitled)",
      date = date_str,
      start_time = time_str,
      calendar = e.calendar,
      is_all_day = e.is_all_day,
      sort_key = e.start or "",
    })
  end
  
  -- Sort by date (past = newest first, future = oldest first)
  table.sort(formatted, function(a, b)
    if direction == "past" then
      return a.sort_key > b.sort_key
    else
      return a.sort_key < b.sort_key
    end
  end)
  
  return formatted
end

local function fetch_stuck_projects()
  local projects = fetch_projects()
  local stuck = {}
  for _, p in ipairs(projects) do
    if p.next_count == 0 and p.state ~= "DONE" then
      table.insert(stuck, p)
    end
  end
  return stuck
end

-- ============================================================================
-- STATE PERSISTENCE
-- ============================================================================

local function save_state()
  if not M.state.active and not M.state.paused then return end
  
  local completed_ids = {}
  for id, _ in pairs(M.state.completed) do
    table.insert(completed_ids, id)
  end
  
  local state_data = {
    week_id = M.state.week_id,
    review_id = M.state.review_id,
    current_step = M.state.current_step,
    completed_ids = completed_ids,
    start_time = M.state.start_time,
    review_note_path = M.state.review_note_path,
    paused = M.state.paused,
    paused_at = M.state.paused and os.time() or nil,
    checklist_items = M.state.checklist_items,
  }
  
  write_json(state_file(), state_data)
end

local function load_state()
  local data = read_json(state_file())
  if not data or not data.week_id then return nil end
  
  -- Restore completed as table
  local completed = {}
  for _, id in ipairs(data.completed_ids or {}) do
    completed[id] = true
  end
  data.completed = completed
  
  return data
end

local function clear_state()
  local path = state_file()
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

-- ============================================================================
-- HISTORY
-- ============================================================================

local function save_to_history()
  local history = read_json(history_file())
  
  local completed_ids = {}
  for id, _ in pairs(M.state.completed) do
    table.insert(completed_ids, id)
  end
  
  local entry = {
    review_id = M.state.review_id,
    week = M.state.week_id,
    date = os.date("%Y-%m-%d"),
    time = os.date("%H:%M"),
    steps = vim.tbl_count(M.state.completed),
    total = #M.steps,
    duration = M.state.start_time and (os.time() - M.state.start_time) or 0,
    note_path = M.state.review_note_path,
    completed_ids = completed_ids,
    current_step = M.state.current_step,
  }
  
  -- Update or append
  local found = false
  for i, h in ipairs(history) do
    if h.review_id == M.state.review_id then
      history[i] = entry
      found = true
      break
    end
  end
  if not found then
    table.insert(history, 1, entry)
  end
  
  -- Keep last 50
  while #history > 50 do
    table.remove(history)
  end
  
  write_json(history_file(), history)
end

-- ============================================================================
-- HIGHLIGHTS
-- ============================================================================

local function setup_highlights()
  local hl = vim.api.nvim_set_hl
  
  hl(0, "GtdReviewTitle", { fg = colors.mauve, bold = true })
  hl(0, "GtdReviewSubtitle", { fg = colors.subtext0 })
  hl(0, "GtdPhaseClear", { fg = colors.sky, bold = true })
  hl(0, "GtdPhaseCurrent", { fg = colors.teal, bold = true })
  hl(0, "GtdPhaseCreative", { fg = colors.yellow, bold = true })
  hl(0, "GtdStepCurrent", { fg = colors.text, bold = true })
  hl(0, "GtdStepDone", { fg = colors.green })
  hl(0, "GtdStepPending", { fg = colors.subtext0 })
  hl(0, "GtdProgressText", { fg = colors.subtext1 })
  hl(0, "GtdMetricInbox", { fg = colors.red })
  hl(0, "GtdMetricNext", { fg = colors.peach, bold = true })
  hl(0, "GtdMetricWaiting", { fg = colors.yellow })
  hl(0, "GtdMetricStuck", { fg = colors.red, bold = true })
  hl(0, "GtdCalendarEvent", { fg = colors.overlay1 })
  hl(0, "GtdShortcutKey", { fg = colors.mauve, bold = true })
  hl(0, "GtdShortcutDesc", { fg = colors.subtext0 })
end

-- ============================================================================
-- UI RENDERING
-- ============================================================================

local function render_left()
  local buf = M.state.buffers.left
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local lines = {}
  local phase = nil
  
  -- Header
  table.insert(lines, "")
  table.insert(lines, "  " .. (gu.list or "") .. " WEEKLY REVIEW")
  table.insert(lines, "  " .. (M.state.week_id or get_week_id()))
  table.insert(lines, "")
  
  -- Steps grouped by phase
  for i, step in ipairs(M.steps) do
    if step.phase ~= phase then
      phase = step.phase
      table.insert(lines, "")
      local phase_icon = phase == "CLEAR" and (gr.clear or "󰃢") 
        or phase == "CURRENT" and (gr.current or "󰔚")
        or (gr.creative or "󰌵")
      table.insert(lines, "  " .. phase_icon .. " GET " .. phase)
    end
    
    local done = M.state.completed[step.id] and (gx.checked or "") or (gx.unchecked or "")
    local cursor = i == M.state.current_step and (gu.arrow_right or "") or " "
    table.insert(lines, "  " .. cursor .. " " .. done .. " " .. step.icon .. " " .. step.label)
  end
  
  -- Progress
  table.insert(lines, "")
  local completed = vim.tbl_count(M.state.completed)
  local pct = math.floor((completed / #M.steps) * 100)
  local bar_done = math.floor(completed / #M.steps * 16)
  local bar = string.rep("█", bar_done) .. string.rep("░", 16 - bar_done)
  table.insert(lines, "  " .. bar .. " " .. pct .. "%")
  
  if M.state.start_time then
    local mins = math.floor((os.time() - M.state.start_time) / 60)
    table.insert(lines, "  " .. (gu.clock or "") .. " " .. mins .. " min")
  end
  
  -- Metrics
  table.insert(lines, "")
  local m = M.state.metrics
  table.insert(lines, "  " .. (gc.inbox or "") .. " " .. (m.inbox or 0) 
    .. "  " .. (gs.NEXT or "󰁔") .. " " .. (m.next or 0)
    .. "  " .. (gs.WAITING or "󰈸") .. " " .. (m.waiting or 0))
  
  -- Shortcuts
  table.insert(lines, "")
  table.insert(lines, "  j/k Navigate  Space Toggle")
  table.insert(lines, "  Enter Execute n Next")
  table.insert(lines, "  c Capture  o Note  r Refresh")
  table.insert(lines, "  Tab/H/L Switch splits  C-b Back")
  table.insert(lines, "")
  table.insert(lines, "  p Pause    s Save+Close")
  table.insert(lines, "  W Complete q Quit")
  
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  
  -- Highlights
  local ns = vim.api.nvim_create_namespace("gtd_review_left")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("WEEKLY REVIEW") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdReviewTitle", row, 0, -1)
    elseif line:match("GET CLEAR") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdPhaseClear", row, 0, -1)
    elseif line:match("GET CURRENT") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdPhaseCurrent", row, 0, -1)
    elseif line:match("GET CREATIVE") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdPhaseCreative", row, 0, -1)
    elseif line:match(gu.arrow_right or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdStepCurrent", row, 0, -1)
    elseif line:match(gx.checked or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdStepDone", row, 0, -1)
    elseif line:match("█") or line:match("░") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdProgressText", row, 0, -1)
    end
  end
end

-- ============================================================================
-- CONTENT RENDERERS (lookup table pattern)
-- ============================================================================

local content_renderers = {}

function content_renderers.note(lines, step)
  table.insert(lines, "  Capture thoughts related to: " .. step.label)
  table.insert(lines, "")
  table.insert(lines, "  " .. (gu.bullet or "•") .. " What's on your mind?")
  table.insert(lines, "  " .. (gu.bullet or "•") .. " Any commitments to capture?")
  table.insert(lines, "  " .. (gu.bullet or "•") .. " Nagging thoughts or worries?")
  table.insert(lines, "")
  table.insert(lines, "  *Enter to open note, c for quick capture*")
end

function content_renderers.inbox(lines, _)
  local items = fetch_inbox()
  table.insert(lines, "  " .. (gc.inbox or "") .. " **" .. #items .. " items** to process")
  table.insert(lines, "")
  
  if #items == 0 then
    table.insert(lines, "  " .. (gx.checked or "") .. " Inbox is empty!")
  else
    for i, item in ipairs(items) do
      if i > 15 then
        table.insert(lines, "  ... and " .. (#items - 15) .. " more")
        break
      end
      table.insert(lines, "  " .. (gs[item.state] or "•") .. " " .. (item.title or "Untitled"))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  *Enter to open Inbox*")
end

function content_renderers.mail_inbox(lines, _)
  local mail = M.state.mail_stats
  if not mail or not mail.accounts or #mail.accounts == 0 then
    table.insert(lines, "  󰇮 Mail stats not available")
    table.insert(lines, "")
    table.insert(lines, "  Check that chronosd mail provider is running.")
    return
  end
  
  local inbox_zero = mail.inbox_unread == 0
  local status_icon = inbox_zero and "󰗠" or "󰇮"
  local status_text = inbox_zero and "INBOX ZERO ACHIEVED!" or (mail.inbox_unread .. " emails to process")
  
  table.insert(lines, "  " .. status_icon .. " **" .. status_text .. "**")
  table.insert(lines, "")
  table.insert(lines, "  ┌────────────────────────────┬───────────┐")
  table.insert(lines, "  │ Account                    │ Inbox/Tot │")
  table.insert(lines, "  ├────────────────────────────┼───────────┤")
  
  for _, acc in ipairs(mail.accounts) do
    local status = acc.inbox_unread == 0 and "✅" or "📬"
    local name = acc.name:sub(1, 24)
    local padding = string.rep(" ", 24 - #name)
    local stats = string.format("%3d/%-3d", acc.inbox_unread, acc.total_unread)
    table.insert(lines, string.format("  │ %s %s%s │ %s │", status, name, padding, stats))
  end
  
  table.insert(lines, "  └────────────────────────────┴───────────┘")
  table.insert(lines, "")
  
  if inbox_zero then
    table.insert(lines, "  " .. (gx.checked or "") .. " Great job! All inboxes clear.")
  else
    table.insert(lines, "  Process each inbox to zero:")
    table.insert(lines, "  " .. (gu.bullet or "•") .. " Delete/archive what you can")
    table.insert(lines, "  " .. (gu.bullet or "•") .. " Reply to 2-minute items")
    table.insert(lines, "  " .. (gu.bullet or "•") .. " Create tasks for actions needed")
    table.insert(lines, "  " .. (gu.bullet or "•") .. " File reference material")
  end
  table.insert(lines, "")
  table.insert(lines, "  *Enter to open Mail.app*")
end

function content_renderers.next(lines, _)
  local tasks = fetch_tasks({ "NEXT", "TODO" })
  local next_count, todo_count = 0, 0
  for _, t in ipairs(tasks) do
    if t.state == "NEXT" then next_count = next_count + 1 else todo_count = todo_count + 1 end
  end
  
  table.insert(lines, "  " .. (gs.NEXT or "󰁔") .. " " .. next_count .. " NEXT  "
    .. (gs.TODO or "󰄲") .. " " .. todo_count .. " TODO")
  table.insert(lines, "")
  
  -- Group by project/area
  local by_source = {}
  for _, t in ipairs(tasks) do
    local source = t.project or t.area or "Inbox"
    by_source[source] = by_source[source] or {}
    table.insert(by_source[source], t)
  end
  
  local shown = 0
  for source, stasks in pairs(by_source) do
    if shown >= 20 then break end
    table.insert(lines, "  ## " .. source)
    for _, t in ipairs(stasks) do
      if shown >= 20 then break end
      table.insert(lines, "  " .. (gs[t.state] or "•") .. " " .. (t.title or "Untitled"))
      shown = shown + 1
    end
    table.insert(lines, "")
  end
  
  table.insert(lines, "  *Enter to open Actions list*")
end

function content_renderers.calendar_past(lines, _)
  table.insert(lines, "  Review last " .. M.cfg.calendar_days_back .. " days:")
  table.insert(lines, "")
  
  local events = fetch_calendar_events("past")
  if #events == 0 then
    table.insert(lines, "  (No past events)")
  else
    local current_date = ""
    for _, e in ipairs(events) do
      local event_date = e.date or ""
      if event_date ~= current_date and event_date ~= "" then
        if current_date ~= "" then table.insert(lines, "") end
        current_date = event_date
        table.insert(lines, "  **" .. current_date .. "**")
      end
      local time = e.start_time or ""
      local title = e.title or "(untitled)"
      if e.is_all_day then
        table.insert(lines, "  " .. (gc.calendar or "") .. " " .. title)
      else
        table.insert(lines, "  " .. (gc.calendar or "") .. " " .. time .. " " .. title)
      end
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  *c to capture follow-up tasks*")
end

function content_renderers.calendar_future(lines, _)
  table.insert(lines, "  Prepare for next " .. M.cfg.calendar_days_forward .. " days:")
  table.insert(lines, "")
  
  local events = fetch_calendar_events("future")
  if #events == 0 then
    table.insert(lines, "  (No upcoming events)")
  else
    local current_date = ""
    for _, e in ipairs(events) do
      local event_date = e.date or ""
      if event_date ~= current_date and event_date ~= "" then
        if current_date ~= "" then table.insert(lines, "") end
        current_date = event_date
        table.insert(lines, "  **" .. current_date .. "**")
      end
      local time = e.start_time or ""
      local title = e.title or "(untitled)"
      if e.is_all_day then
        table.insert(lines, "  " .. (gc.calendar or "") .. " " .. title)
      else
        table.insert(lines, "  " .. (gc.calendar or "") .. " " .. time .. " " .. title)
      end
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  *c to capture preparation tasks*")
end

function content_renderers.waiting(lines, _)
  local tasks = fetch_tasks({ "WAITING" })
  table.insert(lines, "  " .. (gs.WAITING or "󰈸") .. " **" .. #tasks .. "** items waiting")
  table.insert(lines, "")
  
  if #tasks == 0 then
    table.insert(lines, "  " .. (gx.checked or "") .. " Nothing waiting!")
  else
    for i, t in ipairs(tasks) do
      if i > 15 then
        table.insert(lines, "  ... and " .. (#tasks - 15) .. " more")
        break
      end
      local ctx = t.waiting_for and (" ← " .. t.waiting_for) or ""
      table.insert(lines, "  " .. (gs.WAITING or "󰈸") .. " " .. (t.title or "Untitled") .. ctx)
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  *Enter to open Waiting list*")
end

function content_renderers.projects(lines, _)
  local projects = fetch_projects()
  local stuck = 0
  for _, p in ipairs(projects) do
    if p.next_count == 0 then stuck = stuck + 1 end
  end
  
  table.insert(lines, "  " .. (gc.projects or "󰉋") .. " **" .. #projects .. "** projects ("
    .. (gp.blocked or "") .. " " .. stuck .. " stuck)")
  table.insert(lines, "")
  
  for i, p in ipairs(projects) do
    if i > 15 then
      table.insert(lines, "  ... and " .. (#projects - 15) .. " more")
      break
    end
    local icon = p.next_count == 0 and (gp.blocked or "") or (gc.projects or "󰉋")
    local stats = string.format("(%d/%d/%d)", p.next_count or 0, p.todo_count or 0, p.waiting_count or 0)
    table.insert(lines, "  " .. icon .. " " .. (p.title or p.name or "Untitled") .. " " .. stats)
  end
  table.insert(lines, "")
  table.insert(lines, "  *Enter to open Projects*")
end

function content_renderers.stuck(lines, _)
  local stuck = fetch_stuck_projects()
  table.insert(lines, "  " .. (gp.blocked or "") .. " **" .. #stuck .. "** stuck projects")
  table.insert(lines, "")
  
  if #stuck == 0 then
    table.insert(lines, "  " .. (gx.checked or "") .. " All projects have NEXT actions!")
  else
    for _, p in ipairs(stuck) do
      table.insert(lines, "  " .. (gp.blocked or "") .. " " .. (p.title or p.name or "Untitled"))
      table.insert(lines, "     → What's the very next action?")
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  *Enter to open Stuck Projects*")
end

function content_renderers.someday(lines, _)
  local tasks = fetch_tasks({ "SOMEDAY" })
  table.insert(lines, "  " .. (gs.SOMEDAY or "󰋚") .. " **" .. #tasks .. "** someday items")
  table.insert(lines, "")
  
  if #tasks == 0 then
    table.insert(lines, "  (No someday items)")
  else
    for i, t in ipairs(tasks) do
      if i > 15 then
        table.insert(lines, "  ... and " .. (#tasks - 15) .. " more")
        break
      end
      table.insert(lines, "  " .. (gs.SOMEDAY or "󰋚") .. " " .. (t.title or "Untitled"))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  *Enter to open Someday list*")
end

function content_renderers.checklists(lines, _)
  -- TODO: Implement checklist rendering
  table.insert(lines, "  Review your custom checklists")
  table.insert(lines, "")
  table.insert(lines, "  *Press 1-9 to select a checklist*")
end

local function ensure_right_buffer()
  local buf = M.state.buffers.right
  
  -- Check if our scratch buffer is still valid AND displayed in right window
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local bufname = vim.api.nvim_buf_get_name(buf)
    -- Make sure it's our scratch buffer, not something else
    if bufname:match("Review%-Content") then
      return buf
    end
  end
  
  -- Need to create or restore the scratch buffer in right split
  -- Save current window to return to it
  local cur_win = vim.api.nvim_get_current_win()
  
  vim.cmd("wincmd l")
  local new_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[new_buf].buftype = "nofile"
  vim.bo[new_buf].bufhidden = "hide"
  vim.api.nvim_buf_set_name(new_buf, "Review-Content-" .. os.time())
  vim.api.nvim_set_current_buf(new_buf)
  vim.wo.number = false
  vim.wo.relativenumber = false
  M.state.buffers.right = new_buf
  
  -- Set up keymaps on the new buffer
  M.setup_buffer_keymaps(new_buf)
  
  -- Return to original window
  vim.api.nvim_set_current_win(cur_win)
  return new_buf
end

local function render_right()
  local buf = ensure_right_buffer()
  if not buf then return end
  
  local step = M.steps[M.state.current_step]
  local lines = {}
  
  -- Header
  table.insert(lines, "")
  table.insert(lines, "  # " .. (step and (step.icon .. " " .. step.label) or "Review"))
  table.insert(lines, "")
  
  -- Render content based on action type
  local renderer = step and content_renderers[step.action]
  if renderer then
    renderer(lines, step)
  else
    table.insert(lines, "  Navigate with j/k, Enter to act")
  end
  
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  
  -- Basic highlights
  local ns = vim.api.nvim_create_namespace("gtd_review_right")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("^%s+# ") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdReviewTitle", row, 0, -1)
    elseif line:match("^%s+## ") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdReviewSubtitle", row, 0, -1)
    end
  end
end

local function refresh_ui()
  render_left()
  render_right()
  if M.cfg.auto_save then
    save_state()
  end
end

-- ============================================================================
-- NAVIGATION & ACTIONS
-- ============================================================================

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
  for i = M.state.current_step + 1, #M.steps do
    if not M.state.completed[M.steps[i].id] then
      M.state.current_step = i
      refresh_ui()
      return
    end
  end
  -- Wrap around
  for i = 1, M.state.current_step do
    if not M.state.completed[M.steps[i].id] then
      M.state.current_step = i
      refresh_ui()
      return
    end
  end
  vim.notify("All steps complete!", vim.log.levels.INFO)
end

function M.toggle_complete()
  local step = M.steps[M.state.current_step]
  if step then
    M.state.completed[step.id] = not M.state.completed[step.id]
    refresh_ui()
  end
end

function M.execute_action()
  local step = M.steps[M.state.current_step]
  if not step then return end
  
  local action = step.action
  local lists = safe_require("gtd-nvim.gtd.lists")
  
  -- Go to right split for all actions except note
  if action ~= "note" then
    vim.cmd("wincmd l")
  end
  
  if action == "note" then
    M.open_review_note()
    
  elseif action == "inbox" then
    if lists and lists.inbox then
      lists.inbox()
    else
      vim.notify("lists.inbox not available", vim.log.levels.WARN)
    end
    
  elseif action == "mail_inbox" then
    -- Open Mail.app
    local script = [[
      tell application "Mail"
        activate
      end tell
    ]]
    vim.fn.jobstart({"osascript", "-e", script}, { detach = true })
    vim.notify("Opening Mail.app", vim.log.levels.INFO)
    
  elseif action == "next" then
    if lists and lists.next_actions then
      lists.next_actions()
    else
      vim.notify("lists.next_actions not available", vim.log.levels.WARN)
    end
    
  elseif action == "waiting" then
    if lists and lists.waiting then
      lists.waiting()
    else
      vim.notify("lists.waiting not available", vim.log.levels.WARN)
    end
    
  elseif action == "projects" then
    if lists and lists.projects then
      lists.projects()
    else
      vim.notify("lists.projects not available", vim.log.levels.WARN)
    end
    
  elseif action == "stuck" then
    if lists and lists.stuck_projects then
      lists.stuck_projects()
    else
      vim.notify("lists.stuck_projects not available", vim.log.levels.WARN)
    end
    
  elseif action == "someday" then
    if lists and lists.someday_maybe then
      lists.someday_maybe()
    else
      vim.notify("lists.someday_maybe not available", vim.log.levels.WARN)
    end
    
  elseif action == "calendar_past" then
    M.show_calendar_in_split("past")
    
  elseif action == "calendar_future" then
    M.show_calendar_in_split("future")
    
  elseif action == "checklists" then
    vim.notify("Checklists not yet implemented", vim.log.levels.INFO)
  else
    vim.notify("Unknown action: " .. tostring(action), vim.log.levels.WARN)
  end
end

--- Show calendar events in right split buffer
function M.show_calendar_in_split(direction)
  local buf = M.state.buffers.right
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local events = fetch_calendar_events(direction)
  local lines = {}
  
  local title = direction == "past" 
    and "  # " .. (gc.calendar or "") .. " Past " .. M.cfg.calendar_days_back .. " Days"
    or "  # " .. (gc.calendar or "") .. " Next " .. M.cfg.calendar_days_forward .. " Days"
  
  table.insert(lines, "")
  table.insert(lines, title)
  table.insert(lines, "")
  
  if #events == 0 then
    table.insert(lines, "  (No events)")
  else
    local current_date = ""
    for _, e in ipairs(events) do
      -- Group by date
      local event_date = e.date or e.start_date or ""
      if event_date ~= current_date then
        if current_date ~= "" then table.insert(lines, "") end
        current_date = event_date
        table.insert(lines, "  ## " .. current_date)
      end
      
      local time = e.start_time or e.time or ""
      local title_str = e.title or "(untitled)"
      local calendar = e.calendar and (" [" .. e.calendar .. "]") or ""
      
      if e.is_all_day then
        table.insert(lines, "  " .. (gc.calendar or "") .. " " .. title_str .. calendar)
      else
        table.insert(lines, "  " .. (gc.calendar or "") .. " " .. time .. " " .. title_str .. calendar)
      end
    end
  end
  
  table.insert(lines, "")
  table.insert(lines, "  *c to capture follow-up task*")
  
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  
  -- Highlights
  local ns = vim.api.nvim_create_namespace("gtd_review_right")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("^%s+# ") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdReviewTitle", row, 0, -1)
    elseif line:match("^%s+## ") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdReviewSubtitle", row, 0, -1)
    elseif line:match(gc.calendar or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdCalendarEvent", row, 0, -1)
    end
  end
end

function M.capture_to_note()
  -- Quick capture to review note
  vim.ui.input({ prompt = "Capture: " }, function(input)
    if not input or input == "" then return end
    
    local note_path = M.state.review_note_path
    if not note_path then return end
    
    local timestamp = os.date("- %H:%M ")
    local lines = vim.fn.readfile(note_path)
    table.insert(lines, timestamp .. input)
    vim.fn.writefile(lines, note_path)
    
    vim.notify("Captured to review note", vim.log.levels.INFO)
  end)
end

function M.open_review_note()
  if not M.state.review_note_path then return end
  vim.cmd("wincmd l")
  vim.cmd("edit " .. M.state.review_note_path)
  vim.cmd("normal! G")
end

function M.refresh()
  M.state.metrics = fetch_metrics()
  M.state.mail_stats = fetch_mail_stats()
  refresh_ui()
  vim.notify("Refreshed", vim.log.levels.INFO)
end


-- ============================================================================
-- PAUSE / RESUME
-- ============================================================================

function M.pause()
  if not M.state.active then return end
  
  M.state.paused = true
  M.state.active = false
  save_state()
  save_to_history()
  
  -- Close UI but keep state
  M.close_ui()
  
  local completed = vim.tbl_count(M.state.completed)
  vim.notify(string.format("Review paused (%d/%d) - use :GtdReviewResume to continue", 
    completed, #M.steps), vim.log.levels.INFO)
end

function M.resume()
  local saved = load_state()
  
  if not saved then
    vim.notify("No paused review found", vim.log.levels.WARN)
    return
  end
  
  if not saved.paused then
    vim.notify("Starting new review (previous was completed)", vim.log.levels.INFO)
    M.start()
    return
  end
  
  -- Resume with saved state
  M.start({
    resume = true,
    week_id = saved.week_id,
    review_id = saved.review_id,
  })
end

-- ============================================================================
-- CLOSE / QUIT
-- ============================================================================

function M.close_ui()
  -- Close buffers
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  M.state.buffers = {}
  
  -- Close tab if we created one
  if M.state.review_tab then
    pcall(vim.cmd, "tabclose " .. M.state.review_tab)
    M.state.review_tab = nil
  end
end

function M.save_and_close()
  save_state()
  save_to_history()
  M.state.active = false
  M.state.paused = false
  clear_state()
  M.close_ui()
  
  local completed = vim.tbl_count(M.state.completed)
  vim.notify(string.format("Review saved (%d/%d complete)", completed, #M.steps), vim.log.levels.INFO)
end

function M.complete_review()
  -- Mark all as complete
  for _, step in ipairs(M.steps) do
    M.state.completed[step.id] = true
  end
  
  save_to_history()
  clear_state()
  M.state.active = false
  M.close_ui()
  
  vim.notify("🎉 Weekly Review Complete!", vim.log.levels.INFO)
end

function M.quit()
  -- Quit without saving
  M.state.active = false
  M.state.paused = false
  M.close_ui()
end

-- ============================================================================
-- KEYMAPS
-- ============================================================================

--- Set keymaps on a single buffer
---@param buf number Buffer handle
function M.setup_buffer_keymaps(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local function map(key, fn, desc)
    vim.keymap.set("n", key, fn, { buffer = buf, desc = desc, nowait = true, silent = true })
  end
  
  -- Navigation (steps)
  map("j", M.next_step, "Next step")
  map("k", M.prev_step, "Previous step")
  map("n", M.next_incomplete, "Next incomplete")
  
  -- Split navigation
  map("H", function() vim.cmd("wincmd h") end, "Left split")
  map("L", function() vim.cmd("wincmd l") end, "Right split")
  map("<Tab>", function() vim.cmd("wincmd w") end, "Next split")
  map("<S-Tab>", function() vim.cmd("wincmd W") end, "Prev split")
  
  -- Actions
  map("<Space>", M.toggle_complete, "Toggle complete")
  map("<CR>", M.execute_action, "Execute action")
  map("c", M.capture_to_note, "Capture to note")
  map("o", M.open_review_note, "Open review note")
  map("r", M.refresh, "Refresh")
  
  -- Control
  map("p", M.pause, "Pause review")
  map("s", M.save_and_close, "Save and close")
  map("W", M.complete_review, "Complete review")
  map("q", M.quit, "Quit")
  
  -- Return to left panel
  map("<C-b>", function()
    vim.cmd("wincmd h")
    refresh_ui()
  end, "Back to steps")
end

function M.setup_keymaps()
  local bufs = { M.state.buffers.left, M.state.buffers.right }
  for _, buf in ipairs(bufs) do
    M.setup_buffer_keymaps(buf)
  end
  
  -- Setup autocmd to return to left split when entering review tab from outside
  local review_augroup = vim.api.nvim_create_augroup("GtdReviewReturn", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = review_augroup,
    callback = function()
      -- Only in review tab and when review is active
      if not M.state.active then return end
      if vim.fn.tabpagenr() ~= M.state.review_tab then return end
      
      local buf = vim.api.nvim_get_current_buf()
      local left_buf = M.state.buffers.left
      local right_buf = M.state.buffers.right
      
      -- If we're in one of our scratch buffers, all good
      if buf == left_buf or buf == right_buf then return end
      
      -- Otherwise, we came back from fzf or somewhere else
      -- Schedule return to left split (after fzf fully closes)
      vim.schedule(function()
        if not M.state.active then return end
        if vim.fn.tabpagenr() ~= M.state.review_tab then return end
        
        -- Check if left buffer is still valid
        if left_buf and vim.api.nvim_buf_is_valid(left_buf) then
          -- Find window with left buffer and go there
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(win) == left_buf then
              vim.api.nvim_set_current_win(win)
              return
            end
          end
        end
      end)
    end,
  })
end

-- ============================================================================
-- REVIEW NOTE CREATION
-- ============================================================================

local function create_review_note(week_id, review_id)
  local dir = reviews_dir()
  vim.fn.mkdir(dir, "p")
  
  local filename = string.format("WeeklyReview-%s-%s.md", week_id, review_id)
  local path = dir .. "/" .. filename
  
  if vim.fn.filereadable(path) == 1 then
    return path, false
  end
  
  local lines = {
    "# Weekly Review " .. week_id,
    "",
    "**Started:** " .. os.date("%Y-%m-%d %H:%M"),
    "",
    "## Clear",
    "",
    "## Current", 
    "",
    "## Creative",
    "",
    "## Notes",
    "",
  }
  
  vim.fn.writefile(lines, path)
  return path, true
end

-- ============================================================================
-- START
-- ============================================================================

function M.start(opts)
  opts = opts or {}
  
  if M.state.active then
    vim.notify("Review already open", vim.log.levels.WARN)
    return
  end
  
  -- Check for paused review
  if not opts.resume then
    local saved = load_state()
    if saved and saved.paused then
      vim.ui.select({ "Resume paused review", "Start new review" }, {
        prompt = "Found paused review from " .. (saved.week_id or "?"),
      }, function(choice)
        if choice == "Resume paused review" then
          M.start({ resume = true, week_id = saved.week_id, review_id = saved.review_id })
        else
          clear_state()
          M.start({ resume = false })
        end
      end)
      return
    end
  end
  
  local week_id = opts.week_id or get_week_id()
  local review_id = opts.review_id or generate_review_id()
  
  -- Load saved progress if resuming
  local saved = nil
  if opts.resume then
    saved = load_state()
  else
    -- Starting fresh - clear any old state
    clear_state()
  end
  
  -- Create review note
  local note_path, is_new = create_review_note(week_id, review_id)
  
  -- Initialize state - ALWAYS start at step 1 unless resuming
  M.state = {
    active = true,
    paused = false,
    current_step = (opts.resume and saved) and saved.current_step or 1,
    completed = (opts.resume and saved) and saved.completed or {},
    start_time = (opts.resume and saved) and saved.start_time or os.time(),
    week_id = week_id,
    review_id = review_id,
    review_note_path = note_path,
    metrics = fetch_metrics(),
    mail_stats = fetch_mail_stats(),
    buffers = {},
    windows = {},
    review_tab = nil,
    checklist_items = (opts.resume and saved) and saved.checklist_items or {},
    active_checklist = nil,
    checklist_cursor = 1,
  }
  
  setup_highlights()
  
  -- Create scratch buffers FIRST
  local left_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[left_buf].buftype = "nofile"
  vim.bo[left_buf].bufhidden = "hide"
  vim.bo[left_buf].swapfile = false
  vim.api.nvim_buf_set_name(left_buf, "Review-Steps-" .. os.time())
  
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[right_buf].buftype = "nofile"
  vim.bo[right_buf].bufhidden = "hide"
  vim.bo[right_buf].swapfile = false
  vim.api.nvim_buf_set_name(right_buf, "Review-Content-" .. os.time())
  
  -- Store buffer references immediately
  M.state.buffers.left = left_buf
  M.state.buffers.right = right_buf
  
  -- Create tab with left buffer
  vim.cmd("tabnew")
  M.state.review_tab = vim.fn.tabpagenr()
  
  -- Get current window and set left buffer
  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left_buf)
  vim.wo[left_win].number = false
  vim.wo[left_win].relativenumber = false
  vim.wo[left_win].wrap = false
  vim.wo[left_win].cursorline = false
  vim.cmd("vertical resize " .. M.cfg.left_panel_width)
  
  -- Create right split with right buffer
  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, right_buf)
  vim.wo[right_win].number = false
  vim.wo[right_win].relativenumber = false
  vim.wo[right_win].wrap = false
  vim.wo[right_win].cursorline = false
  
  -- Store window references
  M.state.windows = { left = left_win, right = right_win }
  
  -- Set up keymaps AFTER buffers are assigned
  M.setup_keymaps()
  
  -- Render content
  refresh_ui()
  
  -- Go back to left panel
  vim.cmd("wincmd h")
  
  if is_new then
    vim.notify("New review started: " .. week_id, vim.log.levels.INFO)
  elseif opts.resume then
    local done = vim.tbl_count(M.state.completed)
    vim.notify(string.format("Resumed review: %d/%d steps", done, #M.steps), vim.log.levels.INFO)
  end
end

-- ============================================================================
-- INDEX (browse past reviews)
-- ============================================================================

function M.index()
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local history = read_json(history_file())
  local current_week = get_week_id()
  
  local items = {}
  local lookup = {}
  
  -- Always offer to start new review first
  local new_line = (gr.current or "󰔚") .. " Start new review (" .. current_week .. ")"
  table.insert(items, new_line)
  lookup[new_line] = { action = "new" }
  
  -- Add past reviews
  for _, h in ipairs(history) do
    local pct = h.total and h.total > 0 and math.floor((h.steps / h.total) * 100) or 0
    local status_icon = pct == 100 and (gx.checked or "✓") 
      or pct > 0 and (gp.active or "") 
      or (gp.inactive or "○")
    local pct_str = pct == 100 and "" or string.format(" %d%%", pct)
    local duration = h.duration and h.duration > 60 and string.format(" %dm", math.floor(h.duration / 60)) or ""
    
    local line = string.format("%s %s  %s%s%s", 
      status_icon,
      h.week or "?", 
      h.date or "?",
      pct_str,
      duration)
    table.insert(items, line)
    lookup[line] = h
  end
  
  fzf.fzf_exec(items, {
    prompt = (gu.list or "") .. " Reviews ❯ ",
    winopts = { height = 0.5, width = 0.6 },
    fzf_opts = {
      ["--header"] = "Enter: open/resume │ Ctrl-E: edit note │ Ctrl-N: new",
    },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local h = lookup[sel[1]]
        if not h then return end
        
        if h.action == "new" then
          M.start()
        elseif h.steps and h.steps > 0 and h.steps < (h.total or #M.steps) then
          -- Resume incomplete review
          M.start({ resume = true, week_id = h.week, review_id = h.review_id })
        elseif h.note_path and vim.fn.filereadable(h.note_path) == 1 then
          vim.cmd("edit " .. h.note_path)
        end
      end,
      ["ctrl-e"] = function(sel)
        if not sel or not sel[1] then return end
        local h = lookup[sel[1]]
        if h and h.note_path and vim.fn.filereadable(h.note_path) == 1 then
          vim.cmd("edit " .. h.note_path)
        end
      end,
      ["ctrl-n"] = function()
        M.start()
      end,
    },
  })
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Debug function to check review state
function M.debug()
  print("=== GTD Review Debug ===")
  print("Version:", M._VERSION)
  print("Active:", M.state.active)
  print("Current step:", M.state.current_step)
  print("Review tab:", M.state.review_tab, "Current tab:", vim.fn.tabpagenr())
  print("Left buffer:", M.state.buffers.left, "Valid:", M.state.buffers.left and vim.api.nvim_buf_is_valid(M.state.buffers.left))
  print("Right buffer:", M.state.buffers.right, "Valid:", M.state.buffers.right and vim.api.nvim_buf_is_valid(M.state.buffers.right))
  print("Current buffer:", vim.api.nvim_get_current_buf())
  
  -- Check keymaps on current buffer
  local buf = vim.api.nvim_get_current_buf()
  local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
  local review_keys = {}
  for _, km in ipairs(keymaps) do
    if km.desc and km.desc:match("step") then
      table.insert(review_keys, km.lhs .. " -> " .. km.desc)
    end
  end
  print("Review keymaps on current buffer:", #review_keys)
  for _, k in ipairs(review_keys) do
    print("  ", k)
  end
end

function M.setup(opts)
  if opts then
    for k, v in pairs(opts) do M.cfg[k] = v end
  end
  
  vim.fn.mkdir(reviews_dir(), "p")
  
  vim.api.nvim_create_user_command("GtdReview", function() M.start() end, { desc = "Weekly Review" })
  vim.api.nvim_create_user_command("GtdReviewResume", function() M.resume() end, { desc = "Resume review" })
  vim.api.nvim_create_user_command("GtdReviewHistory", function() M.index() end, { desc = "Review history" })
  vim.api.nvim_create_user_command("GtdReviewPause", function() M.pause() end, { desc = "Pause review" })
end

return M
