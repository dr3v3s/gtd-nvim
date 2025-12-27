-- ============================================================================
-- GTD-NVIM AGENDA MODULE
-- ============================================================================
-- Daily/weekly agenda view powered by Chronos daemon
-- Combines GTD tasks with Apple Calendar events
-- Supports day navigation and workload prediction
--
-- @module gtd-nvim.gtd.agenda
-- @version 2.2.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "2.4.0"
M._UPDATED = "2025-12-27"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local shared = safe_require("gtd-nvim.gtd.shared")
local chronos = safe_require("gtd-nvim.gtd.chronos-client")
local fzf_actions = safe_require("gtd-nvim.capture.ui.fzf_actions")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.config = {
  -- Calendar filtering (nil = all calendars)
  calendars = nil, -- e.g., {"Work", "Personal"}
  
  -- Work hours for free slot calculation
  work_start = 9,
  work_end = 18,
  
  -- Limits
  max_next_actions = 15,
  max_waiting = 10,
  max_someday = 5,
  max_stuck = 5,
  
  -- Display options
  show_free_slots = true,
  show_focus_projects = true,  -- Show focus projects at top
  show_calendar = true,        -- Show calendar events section
  show_someday = true,
  show_stuck_projects = true,
  show_inbox_zero = true,  -- Show mail Inbox Zero status
  
  -- Week view settings
  week_days = 7,
  
  -- Colors (Catppuccin Mocha)
  colors = {
    reset     = "\27[0m",
    bold      = "\27[1m",
    dim       = "\27[2m",
    red       = "\27[38;2;243;139;168m",
    maroon    = "\27[38;2;235;160;172m",
    peach     = "\27[38;2;250;179;135m",
    yellow    = "\27[38;2;249;226;175m",
    green     = "\27[38;2;166;227;161m",
    teal      = "\27[38;2;148;226;213m",
    sky       = "\27[38;2;137;220;235m",
    sapphire  = "\27[38;2;116;199;236m",
    blue      = "\27[38;2;137;180;250m",
    lavender  = "\27[38;2;180;190;254m",
    mauve     = "\27[38;2;203;166;247m",
    text      = "\27[38;2;205;214;244m",
    subtext1  = "\27[38;2;186;194;222m",
    subtext0  = "\27[38;2;166;173;200m",
    overlay1  = "\27[38;2;127;132;156m",
    surface0  = "\27[38;2;49;50;68m",
  },
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local C = M.config.colors

local function get_glyphs()
  if shared and shared.glyphs then
    return shared.glyphs
  end
  return {
    state = {
      NEXT = "󱥦", TODO = "", WAITING = "", SOMEDAY = "󰋊",
      DONE = "󰸟", PROJECT = "", CANCELLED = "󰅚",
    },
    container = { calendar = "", inbox = "" },
    ui = { clock = "", warning = "", bullet = "" },
    progress = { overdue = "", blocked = "" },
  }
end

local function format_time(iso_str)
  if not iso_str then return "" end
  local hour, min = iso_str:match("T(%d%d):(%d%d)")
  if hour and min then
    return hour .. ":" .. min
  end
  return ""
end

local function format_date(iso_str)
  if not iso_str then return "" end
  local date = iso_str:match("^(%d%d%d%d%-%d%d%-%d%d)")
  return date or ""
end

local function days_overdue(deadline_str, today_str)
  if not deadline_str or not today_str then return 0 end
  local dy, dm, dd = deadline_str:match("^(%d+)%-(%d+)%-(%d+)")
  local ty, tm, tdd = today_str:match("^(%d+)%-(%d+)%-(%d+)")
  if not dy or not ty then return 0 end
  
  local dl_time = os.time({year=tonumber(dy), month=tonumber(dm), day=tonumber(dd)})
  local td_time = os.time({year=tonumber(ty), month=tonumber(tm), day=tonumber(tdd)})
  
  return math.floor((td_time - dl_time) / 86400)
end

local function state_color(state)
  if state == "NEXT" then return C.yellow
  elseif state == "TODO" then return C.blue
  elseif state == "WAITING" then return C.peach
  elseif state == "SOMEDAY" then return C.overlay1
  elseif state == "DONE" then return C.green
  elseif state == "PROJECT" then return C.mauve
  end
  return C.text
end

--- Get date string for N days from a base date
---@param base_date string YYYY-MM-DD
---@param offset number Days to add (can be negative)
---@return string YYYY-MM-DD
local function date_offset(base_date, offset)
  local y, m, d = base_date:match("^(%d+)%-(%d+)%-(%d+)")
  if not y then return os.date("%Y-%m-%d") end
  local base_time = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d)})
  return os.date("%Y-%m-%d", base_time + (offset * 86400))
end

--- Get day name for a date
---@param date_str string YYYY-MM-DD
---@return string Day name (Mon, Tue, etc.)
local function day_name(date_str)
  local y, m, d = date_str:match("^(%d+)%-(%d+)%-(%d+)")
  if not y then return "" end
  local t = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d)})
  return os.date("%a", t)
end

--- Check if date is today
---@param date_str string YYYY-MM-DD
---@return boolean
local function is_today(date_str)
  return date_str == os.date("%Y-%m-%d")
end

--- Check if date is tomorrow
---@param date_str string YYYY-MM-DD
---@return boolean
local function is_tomorrow(date_str)
  return date_str == date_offset(os.date("%Y-%m-%d"), 1)
end

--- Format date for display
---@param date_str string YYYY-MM-DD
---@return string Formatted date
local function format_date_display(date_str)
  if is_today(date_str) then
    return "Today (" .. date_str .. ")"
  elseif is_tomorrow(date_str) then
    return "Tomorrow (" .. date_str .. ")"
  else
    return day_name(date_str) .. " " .. date_str
  end
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================

local function safe_table(val)
  if val == nil or val == vim.NIL then return {} end
  if type(val) ~= "table" then return {} end
  return val
end

local function fetch_gtd_agenda(date)
  if not chronos or not chronos.is_available() then
    return nil, "Chronos daemon not available"
  end
  
  date = date or os.date("%Y-%m-%d")
  local data, err = chronos.query_daemon("gtd", "agenda", { date = date })
  if not data then
    return nil, err or "Failed to fetch agenda"
  end
  
  return {
    date = data.date or date,
    due_today = safe_table(data.due_today),
    scheduled_today = safe_table(data.scheduled_today),
    overdue = safe_table(data.overdue),
    next_actions = safe_table(data.next_actions),
    waiting = safe_table(data.waiting),
    someday = safe_table(data.someday),
    stuck_projects = safe_table(data.stuck_projects),
  }, nil
end

--- Fetch projects marked as Focus (FOCUS: t property)
---@return table[] Array of focus projects with their next actions
local function fetch_focus_projects()
  if not chronos or not chronos.is_available() then
    return {}
  end
  
  -- Get all projects
  local projects, err = chronos.query_daemon("gtd", "projects_timeline")
  if not projects then
    return {}
  end
  
  -- Filter to focus projects
  local focus = {}
  for _, proj in ipairs(projects) do
    local is_focus = false
    
    -- Check properties for FOCUS: t
    if proj.properties and proj.properties.FOCUS == "t" then
      is_focus = true
    end
    
    -- Also check direct focus field
    if proj.focus == true or proj.focus == "t" then
      is_focus = true
    end
    
    if is_focus then
      table.insert(focus, proj)
    end
  end
  
  return focus
end

local function fetch_calendar_events(date)
  if not chronos then return {}, nil end
  if not chronos.is_bridge_available or not chronos.is_bridge_available() then
    return {}, nil
  end
  
  -- Use date-specific query if available
  local data, err = chronos.query_bridge("calendar", "events", { date = date })
  if not data then
    -- Fallback to today
    data, err = chronos.query_bridge("calendar", "today")
  end
  if not data then return {}, err end
  
  local events = data.events or data
  if type(events) ~= "table" then events = {} end
  
  -- Filter by date if we got multi-day response
  local target_date = date or os.date("%Y-%m-%d")
  local filtered = {}
  for _, event in ipairs(events) do
    local event_date = format_date(event.start or event.startDate or "")
    if event_date == target_date or event_date == "" then
      table.insert(filtered, event)
    end
  end
  
  -- Filter by selected calendars
  if M.config.calendars and #M.config.calendars > 0 then
    local allowed = {}
    for _, cal in ipairs(M.config.calendars) do
      allowed[cal:lower()] = true
    end
    local cal_filtered = {}
    for _, event in ipairs(filtered) do
      if event.calendar and allowed[event.calendar:lower()] then
        table.insert(cal_filtered, event)
      end
    end
    filtered = cal_filtered
  end
  
  -- Sort by time
  table.sort(filtered, function(a, b)
    return (a.start or a.startDate or "") < (b.start or b.startDate or "")
  end)
  
  return filtered, nil
end

--- Fetch mail stats from chronosd mail provider
---@return table|nil stats {accounts, inbox_unread, total_unread}
---@return string|nil error
local function fetch_mail_stats()
  if not chronos then return nil, "Chronos not available" end
  
  local data, err = chronos.query_daemon("mail", "stats")
  if not data then
    return nil, err or "Failed to fetch mail stats"
  end
  
  return {
    accounts = data.accounts or {},
    inbox_unread = data.inbox_unread or 0,
    total_unread = data.total_unread or 0,
  }, nil
end

-- ============================================================================
-- DISPLAY BUILDING
-- ============================================================================

local function build_agenda_display(gtd_data, calendar_events, calls_data, mail_data, focus_projects, date)
  local g = get_glyphs()
  local display = {}
  local meta = {}
  
  calendar_events = calendar_events or {}
  focus_projects = focus_projects or {}
  
  local function add_section(title, icon, color)
    if #display > 0 then
      table.insert(display, "")
      table.insert(meta, { type = "separator" })
    end
    local header = string.format("%s%s%s %s%s", C.bold, color or C.mauve, icon or "", title, C.reset)
    table.insert(display, header)
    table.insert(meta, { type = "header", title = title })
    table.insert(display, C.surface0 .. string.rep("─", 50) .. C.reset)
    table.insert(meta, { type = "separator" })
  end
  
  local function add_task(task, prefix_icon, section_type, override_color)
    local state_icon = g.state[task.state] or g.ui.bullet
    local color = override_color or state_color(task.state)
    local project = task.project and (C.overlay1 .. " :" .. task.project .. C.reset) or ""
    
    local line = string.format("%s%s%s %s%s%s%s",
      color, prefix_icon or "", state_icon, C.reset,
      C.text, task.title or "?", project)
    
    table.insert(display, line)
    table.insert(meta, { 
      type = section_type, 
      task = task,
      file = task.file,
      lnum = task.line,
    })
  end
  
  local function add_event(event)
    local time_str = event.is_all_day and "All-day" or format_time(event.start or event.startDate)
    local cal = event.calendar and (C.overlay1 .. " (" .. event.calendar .. ")" .. C.reset) or ""
    local loc = event.location and event.location ~= "" and (C.subtext0 .. " @ " .. event.location .. C.reset) or ""
    
    local line = string.format("  %s%s%s  %s%s%s%s%s",
      C.sapphire, time_str, C.reset,
      C.text, event.title or "Event", C.reset, cal, loc)
    
    table.insert(display, line)
    table.insert(meta, { type = "event", event = event })
  end
  
  -- FREE TIME SLOTS
  if M.config.show_free_slots and chronos and chronos.calculate_free_slots then
    local slots = chronos.calculate_free_slots(calendar_events, M.config.work_start, M.config.work_end, 30)
    if slots and #slots > 0 then
      add_section("FREE TIME", "", C.teal)
      for _, slot in ipairs(slots) do
        local duration = slot.duration_min >= 60
          and string.format("%dh %dm", math.floor(slot.duration_min / 60), slot.duration_min % 60)
          or string.format("%d min", slot.duration_min)
        local line = string.format("  %s󰥔%s %s%s - %s%s  %s%s%s",
          C.teal, C.reset, C.green, slot.start_time, slot.end_time, C.reset, C.overlay1, duration, C.reset)
        table.insert(display, line)
        table.insert(meta, { type = "slot", slot = slot })
      end
    end
  end
  
  -- FOCUS PROJECTS (Areas of Focus with FOCUS: t property)
  if M.config.show_focus_projects and #focus_projects > 0 then
    add_section("FOCUS PROJECTS", "󰓎", C.lavender)
    for _, proj in ipairs(focus_projects) do
      -- Project title
      local proj_icon = g.state.PROJECT or "󰷐"
      local area_str = proj.area and (C.overlay1 .. " [" .. proj.area .. "]" .. C.reset) or ""
      local line = string.format("  %s%s%s %s%s%s",
        C.lavender, proj_icon, C.reset, C.text, proj.title or proj.name or "?", area_str)
      table.insert(display, line)
      table.insert(meta, { type = "focus_project", project = proj, file = proj.file, lnum = proj.line })
      
      -- Show next actions for this project (if available)
      local next_actions = proj.next_actions or (proj.tasks and proj.tasks.next_actions)
      if next_actions and type(next_actions) == "table" then
        for _, task in ipairs(next_actions) do
          local task_line = string.format("    %s%s%s %s%s",
            C.yellow, g.state.NEXT or "󱥦", C.reset, C.subtext1, task.title or "?")
          table.insert(display, task_line)
          table.insert(meta, { type = "focus_task", task = task, file = task.file, lnum = task.line })
        end
      elseif proj.tasks and proj.tasks.next and proj.tasks.next > 0 then
        -- Show count if we don't have details
        local count_line = string.format("    %s%d NEXT action(s)%s",
          C.overlay1, proj.tasks.next, C.reset)
        table.insert(display, count_line)
        table.insert(meta, { type = "info" })
      end
    end
  end
  
  -- INBOX ZERO (Mail Status)
  if M.config.show_inbox_zero and mail_data and mail_data.accounts then
    local has_unread = mail_data.inbox_unread > 0
    -- Only show if there are unread emails (or always show if configured)
    if has_unread or #mail_data.accounts > 0 then
      local section_color = has_unread and C.peach or C.green
      local section_icon = has_unread and "󰇮" or "󰗠"
      add_section("INBOX ZERO", section_icon, section_color)
      
      for _, acc in ipairs(mail_data.accounts) do
        local status_icon, status_color
        if acc.inbox_unread == 0 then
          status_icon = "✅"
          status_color = C.green
        else
          status_icon = "📬"
          status_color = C.peach
        end
        
        local stats_str = string.format("%d/%d", acc.inbox_unread, acc.total_unread)
        local line = string.format("  %s %s%-22s%s  %s%s%s",
          status_icon, status_color, acc.name, C.reset,
          C.overlay1, stats_str, C.reset)
        
        table.insert(display, line)
        table.insert(meta, { type = "mail_account", account = acc })
      end
      
      -- Show summary if multiple accounts
      if #mail_data.accounts > 1 then
        local total_status = mail_data.inbox_unread == 0 and C.green or C.peach
        local summary = string.format("  %s━━━ Total: %d inbox / %d total%s",
          total_status, mail_data.inbox_unread, mail_data.total_unread, C.reset)
        table.insert(display, summary)
        table.insert(meta, { type = "mail_summary" })
      end
    end
  end
  
  -- CALLS TO MAKE
  if calls_data and calls_data.to_call and #calls_data.to_call > 0 then
    add_section("CALLS TO MAKE", "󰏶", C.green)
    for _, task in ipairs(calls_data.to_call) do
      add_task(task, "  󰏲 ", "call", C.green)
    end
  end
  
  -- CALENDAR (Today's events)
  if M.config.show_calendar and #calendar_events > 0 then
    add_section("CALENDAR", "󰃭", C.sapphire)
    for _, event in ipairs(calendar_events) do
      add_event(event)
    end
  end
  
  -- SCHEDULED TODAY (GTD tasks)
  local scheduled_today = gtd_data.scheduled_today or {}
  local due_today = gtd_data.due_today or {}
  local scheduled_ids = {}
  for _, t in ipairs(scheduled_today) do
    scheduled_ids[t.task_id] = true
  end
  
  -- Filter due_today to exclude scheduled (avoid duplicates)
  local due_only = {}
  for _, task in ipairs(due_today) do
    if not scheduled_ids[task.task_id] then
      table.insert(due_only, task)
    end
  end
  
  if #scheduled_today > 0 or #due_only > 0 then
    add_section("TODAY", "󰃰", C.green)
    for _, task in ipairs(scheduled_today) do
      add_task(task, "  󰃭 ", "scheduled")
    end
    for _, task in ipairs(due_only) do
      add_task(task, "  󰀨 ", "due")
    end
  end
  
  -- OVERDUE
  local overdue = gtd_data.overdue or {}
  if #overdue > 0 then
    add_section("OVERDUE", "󰅜", C.red)
    for _, task in ipairs(overdue) do
      local days = task.deadline and days_overdue(format_date(task.deadline), date) or 0
      local days_str = days > 0 and (C.red .. " (" .. days .. "d)" .. C.reset) or ""
      local state_icon = g.state[task.state] or g.ui.bullet
      local project = task.project and (C.overlay1 .. " :" .. task.project .. C.reset) or ""
      local line = string.format("  %s󰀨 %s%s %s%s%s%s",
        C.red, state_color(task.state), state_icon, C.text, task.title or "?", project, days_str)
      table.insert(display, line)
      table.insert(meta, { type = "overdue", task = task, file = task.file, lnum = task.line })
    end
  end
  
  -- NEXT ACTIONS
  local next_actions = gtd_data.next_actions or {}
  if #next_actions > 0 then
    add_section("NEXT ACTIONS", "󱥦", C.yellow)
    local limit = math.min(#next_actions, M.config.max_next_actions)
    for i = 1, limit do
      add_task(next_actions[i], "  ", "next", C.yellow)
    end
    if #next_actions > limit then
      table.insert(display, C.overlay1 .. "    ... " .. (#next_actions - limit) .. " more" .. C.reset)
      table.insert(meta, { type = "info" })
    end
  end
  
  -- WAITING FOR
  local waiting = gtd_data.waiting or {}
  if #waiting > 0 then
    add_section("WAITING FOR", "", C.peach)
    local limit = math.min(#waiting, M.config.max_waiting)
    for i = 1, limit do
      local task = waiting[i]
      local waiting_for = task.waiting_for and (C.peach .. " → " .. task.waiting_for .. C.reset) or ""
      local project = task.project and (C.overlay1 .. " :" .. task.project .. C.reset) or ""
      local line = string.format("  %s%s %s%s%s%s",
        C.peach, g.state.WAITING or "", C.text, task.title or "?", waiting_for, project)
      table.insert(display, line)
      table.insert(meta, { type = "waiting", task = task, file = task.file, lnum = task.line })
    end
    if #waiting > limit then
      table.insert(display, C.overlay1 .. "    ... " .. (#waiting - limit) .. " more" .. C.reset)
      table.insert(meta, { type = "info" })
    end
  end
  
  -- STUCK PROJECTS
  local stuck = gtd_data.stuck_projects or {}
  if M.config.show_stuck_projects and #stuck > 0 then
    add_section("STUCK PROJECTS", "󰏤", C.maroon)
    local limit = math.min(#stuck, M.config.max_stuck)
    for i = 1, limit do
      local task = stuck[i]
      local line = string.format("  %s %s%s%s  %sneeds NEXT%s",
        C.maroon, g.state.PROJECT or "", C.text, task.title or "?", C.dim .. C.overlay1, C.reset)
      table.insert(display, line)
      table.insert(meta, { type = "stuck", task = task, file = task.file, lnum = task.line })
    end
  end
  
  -- SOMEDAY
  local someday = gtd_data.someday or {}
  if M.config.show_someday and #someday > 0 then
    add_section("SOMEDAY", "󰋊", C.overlay1)
    local limit = math.min(#someday, M.config.max_someday)
    for i = 1, limit do
      local task = someday[i]
      local line = string.format("  %s%s %s%s%s",
        C.overlay1, g.state.SOMEDAY or "󰋊", C.reset, C.subtext0, task.title or "?")
      table.insert(display, line)
      table.insert(meta, { type = "someday", task = task, file = task.file, lnum = task.line })
    end
  end
  
  return display, meta
end

-- ============================================================================
-- WEEK OVERVIEW
-- ============================================================================

--- Build week overview showing workload per day
---@param start_date string Starting date YYYY-MM-DD
---@return table display, table meta
local function build_week_overview(start_date)
  local display = {}
  local meta = {}
  local g = get_glyphs()
  
  for i = 0, M.config.week_days - 1 do
    local date = date_offset(start_date, i)
    local gtd_data = fetch_gtd_agenda(date)
    local cal_events = fetch_calendar_events(date)
    
    -- Calculate workload
    local scheduled = gtd_data and #(gtd_data.scheduled_today or {}) or 0
    local due = gtd_data and #(gtd_data.due_today or {}) or 0
    local overdue = gtd_data and #(gtd_data.overdue or {}) or 0
    local events = #(cal_events or {})
    local total = scheduled + due + events
    
    -- Determine load color
    local load_color = C.green
    if total > 8 or overdue > 0 then
      load_color = C.red
    elseif total > 5 then
      load_color = C.yellow
    elseif total > 3 then
      load_color = C.peach
    end
    
    -- Build workload bar
    local bar_len = math.min(total, 15)
    local bar = string.rep("█", bar_len) .. string.rep("░", 15 - bar_len)
    
    -- Day label
    local day_label = format_date_display(date)
    local is_current = is_today(date)
    local prefix = is_current and C.bold .. "▸ " or "  "
    
    -- Stats
    local stats = {}
    if events > 0 then table.insert(stats, events .. " 󰃰") end
    if scheduled > 0 then table.insert(stats, scheduled .. " 󰃭") end
    if due > 0 then table.insert(stats, due .. " 󰀨") end
    if overdue > 0 then table.insert(stats, C.red .. overdue .. " 󰅜" .. C.reset) end
    local stats_str = #stats > 0 and (" │ " .. table.concat(stats, " ")) or ""
    
    local line = string.format("%s%s%-25s %s%s%s  %s(%d)%s%s",
      prefix, is_current and C.yellow or C.text, day_label,
      load_color, bar, C.reset,
      C.overlay1, total, C.reset, stats_str)
    
    table.insert(display, line)
    table.insert(meta, { type = "day", date = date, workload = total })
  end
  
  return display, meta
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Show the agenda for a given date
---@param date string|nil Date in YYYY-MM-DD format (default: today)
function M.show(date)
  date = date or os.date("%Y-%m-%d")
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  if shared and shared.ensure_valid_cwd then
    shared.ensure_valid_cwd()
  end
  
  local gtd_data, gtd_err = fetch_gtd_agenda(date)
  if not gtd_data then
    vim.notify("Failed to fetch agenda: " .. (gtd_err or "unknown"), vim.log.levels.ERROR)
    return
  end
  
  local calendar_events = fetch_calendar_events(date) or {}
  
  local calls_data = nil
  if chronos and chronos.gtd_calls then
    local raw = chronos.gtd_calls()
    if raw then
      calls_data = { to_call = safe_table(raw.to_call) }
    end
  end
  
  -- Fetch mail stats for Inbox Zero section
  local mail_data = nil
  if M.config.show_inbox_zero then
    mail_data = fetch_mail_stats()
  end
  
  -- Fetch focus projects
  local focus_projects = fetch_focus_projects()
  
  local display, meta = build_agenda_display(gtd_data, calendar_events, calls_data, mail_data, focus_projects, date)
  
  if #display == 0 then
    vim.notify("No agenda items for " .. date, vim.log.levels.INFO)
    return
  end
  
  -- Strip ANSI for matching
  local function strip_ansi(s)
    return s and s:gsub("\27%[[%d;]*m", ""):gsub("\27%[[%d;]*[A-Za-z]", "") or ""
  end
  
  local function find_item(selected)
    if not selected then return nil end
    local stripped = strip_ansi(selected)
    for i, line in ipairs(display) do
      if strip_ansi(line) == stripped then
        return meta[i]
      end
    end
    return nil
  end
  
  local function open_task(task)
    if not task or not task.file then return end
    vim.cmd("edit " .. vim.fn.fnameescape(task.file))
    if task.line then
      pcall(vim.api.nvim_win_set_cursor, 0, { task.line, 0 })
      vim.cmd("normal! zz")
    end
  end
  
  -- Build lookup for fzf_actions
  local lookup = {}
  for i, line in ipairs(display) do
    local item = meta[i]
    if item and item.file and item.lnum then
      lookup[line] = { file = item.file, lnum = item.lnum }
    end
  end
  
  local header = "Enter=open │ C-e=edit │ C-r=refile │ C-d=delete │ ←/→=day │ C-w=week │ C-b=back"
  
  fzf.fzf_exec(display, {
    prompt = format_date_display(date) .. " ❯ ",
    fzf_opts = {
      ["--ansi"] = true,
      ["--no-info"] = true,
      ["--header"] = header,
      ["--header-first"] = true,
    },
    winopts = {
      height = 0.85,
      width = 0.80,
      title = string.format(" 󰃰 Agenda: %s ", format_date_display(date)),
      title_pos = "center",
    },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local item = find_item(sel[1])
        if not item then return end
        
        if item.task and item.task.file then
          open_task(item.task)
        elseif item.type == "event" and item.event then
          local e = item.event
          vim.notify(e.title .. (e.location and ("\n@ " .. e.location) or ""), vim.log.levels.INFO)
        elseif item.type == "mail_account" and item.account then
          -- Open Mail.app to the specific account's inbox
          local acc_name = item.account.name
          local script = string.format([[
            tell application "Mail"
              activate
              try
                set targetAccount to first account whose name is "%s"
                set targetMailbox to mailbox "INBOX" of targetAccount
                set selected mailboxes of first message viewer to {targetMailbox}
              end try
            end tell
          ]], acc_name:gsub('"', '\\"'))
          vim.fn.jobstart({"osascript", "-e", script}, { detach = true })
          vim.notify("Opening Mail: " .. acc_name, vim.log.levels.INFO)
        end
      end,
      
      ["ctrl-e"] = function(sel)
        if not sel or not sel[1] then return end
        local item = find_item(sel[1])
        if item and item.task and item.file then
          vim.schedule(function()
            if fzf_actions then
              fzf_actions.edit_task(item.file, item.lnum or item.task.line or 1)
            else
              open_task(item.task)
            end
          end)
        end
      end,
      
      ["ctrl-r"] = function(sel)
        if not sel or not sel[1] then return end
        local item = find_item(sel[1])
        if item and item.task and item.file then
          vim.schedule(function()
            if fzf_actions then
              fzf_actions.refile_task(item.file, item.lnum or item.task.line or 1)
            end
          end)
        end
      end,
      
      ["ctrl-d"] = function(sel)
        if not sel or not sel[1] then return end
        local item = find_item(sel[1])
        if item and item.task and item.file then
          vim.schedule(function()
            if fzf_actions then
              fzf_actions.delete_task(item.file, item.lnum or item.task.line or 1, function(deleted)
                if deleted then
                  M.show(date) -- Refresh
                end
              end)
            end
          end)
        end
      end,
      
      -- Day navigation
      ["left"] = function(_)
        vim.schedule(function()
          M.show(date_offset(date, -1))
        end)
      end,
      
      ["right"] = function(_)
        vim.schedule(function()
          M.show(date_offset(date, 1))
        end)
      end,
      
      ["ctrl-left"] = function(_)
        vim.schedule(function()
          M.show(date_offset(date, -7))
        end)
      end,
      
      ["ctrl-right"] = function(_)
        vim.schedule(function()
          M.show(date_offset(date, 7))
        end)
      end,
      
      -- Week overview
      ["ctrl-w"] = function(_)
        vim.schedule(function()
          M.week(date)
        end)
      end,
      
      -- Back to week (same as ctrl-w)
      ["ctrl-b"] = function(_)
        vim.schedule(function()
          M.week(date)
        end)
      end,
      
      -- Today
      ["ctrl-t"] = function(_)
        vim.schedule(function()
          M.show(os.date("%Y-%m-%d"))
        end)
      end,
    },
  })
end

--- Show week overview with workload
---@param start_date string|nil Starting date (default: today)
function M.week(start_date)
  start_date = start_date or os.date("%Y-%m-%d")
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local display, meta = build_week_overview(start_date)
  
  local header = "Enter=view day │ ←/→=week │ C-t=today │ C-b=back"
  
  fzf.fzf_exec(display, {
    prompt = "Week overview ❯ ",
    fzf_opts = {
      ["--ansi"] = true,
      ["--no-info"] = true,
      ["--header"] = header,
      ["--header-first"] = true,
    },
    winopts = {
      height = 0.45,
      width = 0.70,
      title = " 󰃭 Week Overview ",
      title_pos = "center",
    },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        -- Find the selected day
        local stripped = sel[1]:gsub("\27%[[%d;]*m", ""):gsub("\27%[[%d;]*[A-Za-z]", "")
        for i, _ in ipairs(display) do
          local m = meta[i]
          if m and m.type == "day" and m.date then
            -- Check if this line matches
            local line_stripped = display[i]:gsub("\27%[[%d;]*m", ""):gsub("\27%[[%d;]*[A-Za-z]", "")
            if line_stripped == stripped then
              vim.schedule(function()
                M.show(m.date)
              end)
              return
            end
          end
        end
      end,
      
      ["left"] = function(_)
        vim.schedule(function()
          M.week(date_offset(start_date, -7))
        end)
      end,
      
      ["right"] = function(_)
        vim.schedule(function()
          M.week(date_offset(start_date, 7))
        end)
      end,
      
      ["ctrl-t"] = function(_)
        vim.schedule(function()
          M.week(os.date("%Y-%m-%d"))
        end)
      end,
      
      -- Back to day view (today)
      ["ctrl-b"] = function(_)
        vim.schedule(function()
          M.show(os.date("%Y-%m-%d"))
        end)
      end,
    },
  })
end

--- Show today's agenda
function M.today()
  M.show(os.date("%Y-%m-%d"))
end

--- Show tomorrow's agenda
function M.tomorrow()
  M.show(date_offset(os.date("%Y-%m-%d"), 1))
end

--- Pick date via input
function M.pick_date()
  vim.ui.input({ prompt = "Date (YYYY-MM-DD): ", default = os.date("%Y-%m-%d") }, function(input)
    if input and input:match("^%d%d%d%d%-%d%d%-%d%d$") then
      M.show(input)
    elseif input then
      vim.notify("Invalid format. Use YYYY-MM-DD", vim.log.levels.WARN)
    end
  end)
end

--- Get summary for statusline
function M.summary(date)
  date = date or os.date("%Y-%m-%d")
  local gtd_data = fetch_gtd_agenda(date)
  local calendar_events = fetch_calendar_events(date)
  
  if not gtd_data then
    return { available = false }
  end
  
  return {
    due = #(gtd_data.due_today or {}),
    scheduled = #(gtd_data.scheduled_today or {}),
    overdue = #(gtd_data.overdue or {}),
    next = #(gtd_data.next_actions or {}),
    waiting = #(gtd_data.waiting or {}),
    events = #(calendar_events or {}),
    available = true,
  }
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
  C = M.config.colors
  
  vim.api.nvim_create_user_command("GtdAgenda", function(opts)
    if opts.args and opts.args ~= "" then
      M.show(opts.args)
    else
      M.today()
    end
  end, { nargs = "?", desc = "Show GTD agenda" })
  
  vim.api.nvim_create_user_command("GtdAgendaWeek", function()
    M.week()
  end, { desc = "Show week overview" })
  
  vim.api.nvim_create_user_command("GtdAgendaTomorrow", function()
    M.tomorrow()
  end, { desc = "Show tomorrow's agenda" })
end

return M
