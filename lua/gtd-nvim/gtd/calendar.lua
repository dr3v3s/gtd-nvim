-- Apple Calendar integration for GTD system
-- - Create calendar events from tasks with SCHEDULED/DEADLINE dates
-- - Import calendar events as tasks
-- - Sync task dates with calendar events
-- - Bidirectional date synchronization

local M = {}

-- ============================================================================
-- Config
-- ============================================================================
M.cfg = {
  gtd_root = "~/Documents/GTD",
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  
  -- Calendar settings
  default_calendar = "GTD",              -- Calendar for exported events
  event_duration = 60,                   -- Default duration in minutes
  import_calendars = {},                 -- Empty = all calendars
  excluded_calendars = {"Birthdays", "Holidays"},
  
  -- Event creation settings
  create_from_scheduled = true,          -- Create events from SCHEDULED dates
  create_from_deadline = true,           -- Create events from DEADLINE dates
  deadline_as_allday = true,            -- Make deadline events all-day
  scheduled_as_timed = true,            -- Make scheduled events timed (9 AM default)
  
  -- Sync settings
  sync_on_date_change = true,            -- Update calendar when task dates change
  import_future_only = true,             -- Only import future events
  days_ahead = 90,                       -- Import events up to N days ahead
  
  -- States to sync
  sync_states = {"TODO", "NEXT", "WAITING"},
  
  -- Advanced
  auto_sync_on_save = false,
  create_zk_notes = false,
}

-- ============================================================================
-- Helpers
-- ============================================================================
local function xp(p) return vim.fn.expand(p) end
local function j(a,b) return (a:gsub("/+$","")).."/"..(b:gsub("^/+","")) end
local function ensure_dir(p) vim.fn.mkdir(vim.fn.fnamemodify(xp(p), ":h"), "p") end
local function readfile(p) return vim.fn.filereadable(xp(p)) == 1 and vim.fn.readfile(xp(p)) or {} end
local function writefile(p, lines) ensure_dir(xp(p)); vim.fn.writefile(lines, xp(p)) end
local function append_lines(path, lines) 
  ensure_dir(path)
  vim.fn.writefile({""}, xp(path), "a")
  vim.fn.writefile(lines, xp(path), "a")
end

local task_id = require("gtd-nvim.gtd.utils.task_id")
local ui = require("gtd-nvim.gtd.ui")

local function safe_exec_applescript(script)
  local handle = io.popen('osascript -e ' .. vim.fn.shellescape(script))
  if not handle then return nil, "Failed to execute osascript" end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if not success then return nil, "AppleScript execution failed" end
  return result
end

-- ============================================================================
-- Date Parsing & Formatting
-- ============================================================================

-- Parse AppleScript date to YYYY-MM-DD or YYYY-MM-DD HH:MM
function M.parse_apple_date(date_str)
  if not date_str or date_str == "" or date_str == "NO_DATE" then 
    return nil 
  end
  
  local clean = date_str:gsub("^DATE:", "")
  
  -- Danish months
  local danish_months = {
    januar = "01", februar = "02", marts = "03", april = "04",
    maj = "05", juni = "06", juli = "07", august = "08",
    september = "09", oktober = "10", november = "11", december = "12"
  }
  
  -- English months
  local english_months = {
    january = "01", february = "02", march = "03", april = "04", may = "05", june = "06",
    july = "07", august = "08", september = "09", october = "10", november = "11", december = "12"
  }
  
  -- Try: "20. juni 2025 kl. 14:30:00"
  local day, month_name, year, hour, min = clean:match("(%d+)%. (%w+) (%d+).*(%d%d):(%d%d)")
  if day and month_name and year then
    local month_num = danish_months[month_name:lower()] or english_months[month_name:lower()]
    if month_num then
      if hour and min then
        return string.format("%04d-%s-%02d %02d:%02d", tonumber(year), month_num, tonumber(day), tonumber(hour), tonumber(min))
      else
        return string.format("%04d-%s-%02d", tonumber(year), month_num, tonumber(day))
      end
    end
  end
  
  -- Try: "June 20, 2025 at 2:30:00 PM"
  local month_eng, day_eng, year_eng = clean:match("(%w+) (%d+), (%d+)")
  if month_eng and day_eng and year_eng then
    local month_num = english_months[month_eng:lower()]
    if month_num then
      local h, m, ampm = clean:match("(%d+):(%d+):%d+ (%a+)")
      if h and m and ampm then
        h = tonumber(h)
        if ampm:lower() == "pm" and h < 12 then h = h + 12 end
        if ampm:lower() == "am" and h == 12 then h = 0 end
        return string.format("%04d-%s-%02d %02d:%02d", tonumber(year_eng), month_num, tonumber(day_eng), h, tonumber(m))
      else
        return string.format("%04d-%s-%02d", tonumber(year_eng), month_num, tonumber(day_eng))
      end
    end
  end
  
  return nil
end

-- Format org date for AppleScript - FIXED!
function M.format_for_applescript(org_date, is_allday)
  if not org_date or org_date == "" then return nil end
  
  -- Extract date/time from <2025-06-20> or <2025-06-20 14:30>
  local date, time = org_date:match("(%d%d%d%d%-%d%d%-%d%d)%s*(%d%d:%d%d)?")
  if not date then return nil end
  
  if is_allday or not time then
    return string.format('date "%s 00:00:00"', date)
  else
    -- FIXED: Was "%s:%s:00", now "%s %s:00" (space instead of colon)
    return string.format('date "%s %s:00"', date, time)
  end
end

-- Add hours to a date string
function M.add_duration(date_str, minutes)
  if not date_str then return nil end
  
  local date, time = date_str:match("(%d%d%d%d%-%d%d%-%d%d)%s*(%d%d:%d%d)?")
  if not date then return nil end
  
  local hour = time and tonumber(time:match("(%d+):")) or 9
  local min = time and tonumber(time:match(":(%d+)")) or 0
  
  local total_mins = hour * 60 + min + minutes
  local new_hour = math.floor(total_mins / 60) % 24
  local new_min = total_mins % 60
  
  return string.format("%s %02d:%02d", date, new_hour, new_min)
end

-- ============================================================================
-- IMPORT: Calendar Events → GTD Tasks
-- ============================================================================

function M.fetch_calendar_events()
  local days_ahead = M.cfg.days_ahead
  local excluded = table.concat(vim.tbl_map(function(c) return '"'..c..'"' end, M.cfg.excluded_calendars), ", ")
  
  local script = string.format([[
tell application "Calendar"
  set startDate to current date
  set endDate to current date
  set time of endDate to 0
  set endDate to endDate + (%d * days)
  
  set output to ""
  repeat with cal in calendars
    set calName to name of cal
    
    if calName is not in {%s} then
      repeat with evt in (events of cal whose start date ≥ startDate and start date ≤ endDate)
        try
          set evtTitle to summary of evt
          set evtId to (uid of evt) as string
          
          set evtDescription to ""
          try
            if description of evt is not missing value then
              set evtDescription to description of evt
            end if
          end try
          
          set startText to "DATE:" & (start date of evt as string)
          set endText to "DATE:" & (end date of evt as string)
          
          set isAllDay to "false"
          try
            if allday event of evt is true then
              set isAllDay to "true"
            end if
          end try
          
          set evtLocation to ""
          try
            if location of evt is not missing value then
              set evtLocation to location of evt
            end if
          end try
          
          set output to output & evtTitle & "§§§" & calName & "§§§" & evtId & "§§§" & evtDescription & "§§§" & startText & "§§§" & endText & "§§§" & isAllDay & "§§§" & evtLocation & "
"
        end try
      end repeat
    end if
  end repeat
  return output
end tell
]], days_ahead, excluded)

  local result, err = safe_exec_applescript(script)
  if not result then
    return nil, err
  end
  
  local events = {}
  for line in result:gmatch("[^\r\n]+") do
    if line and line ~= "" then
      local parts = vim.split(line, "§§§", {plain = true})
      if #parts >= 8 then
        table.insert(events, {
          title = parts[1] or "",
          calendar = parts[2] or "",
          event_id = parts[3] or "",
          description = parts[4] or "",
          start_raw = parts[5] or "",
          end_raw = parts[6] or "",
          allday = parts[7] == "true",
          location = parts[8] or "",
        })
      end
    end
  end
  
  return events
end

function M.import_events(events)
  local inbox_path = j(xp(M.cfg.gtd_root), M.cfg.inbox_file)
  local imported = 0
  local skipped = 0
  
  -- Check for existing event IDs
  local existing_ids = {}
  local existing_lines = readfile(inbox_path)
  for _, line in ipairs(existing_lines) do
    local eid = line:match(":EVENT_ID:%s*(.+)")
    if eid then existing_ids[eid] = true end
  end
  
  for _, event in ipairs(events) do
    if existing_ids[event.event_id] then
      skipped = skipped + 1
      goto continue
    end
    
    -- Apply calendar filter
    if #M.cfg.import_calendars > 0 then
      local found = false
      for _, allowed in ipairs(M.cfg.import_calendars) do
        if event.calendar == allowed then found = true; break end
      end
      if not found then
        skipped = skipped + 1
        goto continue
      end
    end
    
    local id = task_id.generate()
    local title = event.title or "Imported Event"
    local cal_tag = (event.calendar or "CAL"):gsub("%s+", "_"):upper():gsub("[^%w_]", "")
    
    local lines = {}
    table.insert(lines, string.format("* TODO %s  :%s:", title, cal_tag))
    
    -- Parse and add dates
    local start_date = M.parse_apple_date(event.start_raw)
    local end_date = M.parse_apple_date(event.end_raw)
    
    if start_date then
      if event.allday then
        -- All-day event → DEADLINE
        table.insert(lines, "DEADLINE: <" .. start_date:match("(%d%d%d%d%-%d%d%-%d%d)") .. ">")
      else
        -- Timed event → SCHEDULED
        table.insert(lines, "SCHEDULED: <" .. start_date .. ">")
      end
    end
    
    table.insert(lines, ":PROPERTIES:")
    table.insert(lines, ":ID:        " .. id)
    table.insert(lines, ":TASK_ID:   " .. id)
    table.insert(lines, ":EVENT_ID:  " .. event.event_id)
    table.insert(lines, ":CALENDAR:  " .. event.calendar)
    if event.location and event.location ~= "" then
      table.insert(lines, ":LOCATION:  " .. event.location)
    end
    table.insert(lines, ":END:")
    table.insert(lines, string.format("ID:: [[zk:%s]]", id))
    
    if event.description and event.description ~= "" then
      table.insert(lines, "")
      table.insert(lines, event.description)
    end
    
    if event.location and event.location ~= "" then
      table.insert(lines, "")
      table.insert(lines, "Location: " .. event.location)
    end
    
    table.insert(lines, "")
    table.insert(lines, string.format("#+IMPORTED: %s from Calendar (%s)", 
      os.date("%Y-%m-%d %H:%M"), event.calendar))
    
    append_lines(inbox_path, lines)
    imported = imported + 1
    
    ::continue::
  end
  
  return imported, skipped
end

function M.import_all()
  vim.notify("📅 Importing from Calendar...", vim.log.levels.INFO)
  
  local events, err = M.fetch_calendar_events()
  if not events then
    vim.notify("❌ Failed to fetch: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end
  
  if #events == 0 then
    vim.notify("No events found to import", vim.log.levels.INFO)
    return
  end
  
  local imported, skipped = M.import_events(events)
  vim.notify(string.format("✅ Imported %d events, skipped %d", imported, skipped), 
    vim.log.levels.INFO)
end

-- ============================================================================
-- EXPORT: GTD Tasks → Calendar Events
-- ============================================================================

function M.scan_tasks_for_calendar()
  local files = vim.fn.globpath(xp(M.cfg.gtd_root), "**/*.org", false, true)
  local tasks = {}
  
  for _, path in ipairs(files) do
    local lines = readfile(path)
    
    for i, line in ipairs(lines) do
      if line:match("^%*+%s+") then
        local state = line:match("^%*+%s+(%u+)%s")
        
        -- Only sync configured states
        local should_sync = false
        for _, s in ipairs(M.cfg.sync_states) do
          if state == s then should_sync = true; break end
        end
        
        if should_sync then
          local title = line:gsub("^%*+%s+%u+%s+", ""):gsub("%s*:%w+:%s*$", "")
          local task_id_val, event_id, scheduled, deadline, location
          
          for j = i + 1, math.min(i + 20, #lines) do
            if lines[j]:match("^%*") then break end
            task_id_val = task_id_val or lines[j]:match(":TASK_ID:%s*(.+)")
            event_id = event_id or lines[j]:match(":EVENT_ID:%s*(.+)")
            location = location or lines[j]:match(":LOCATION:%s*(.+)")
            scheduled = scheduled or lines[j]:match("SCHEDULED:%s*<([^>]+)>")
            deadline = deadline or lines[j]:match("DEADLINE:%s*<([^>]+)>")
          end
          
          -- Only include tasks with dates
          if (scheduled or deadline) and title ~= "" then
            table.insert(tasks, {
              title = title,
              state = state,
              task_id = task_id_val,
              event_id = event_id,
              scheduled = scheduled,
              deadline = deadline,
              location = location,
              path = path,
              lnum = i,
            })
          end
        end
      end
    end
  end
  
  return tasks
end

function M.create_event(task, calendar_name)
  calendar_name = calendar_name or M.cfg.default_calendar
  
  -- Decide which date to use and whether it's all-day
  local start_date, is_allday
  
  if M.cfg.create_from_scheduled and task.scheduled then
    start_date = task.scheduled
    is_allday = not start_date:match("%d%d:%d%d")
  elseif M.cfg.create_from_deadline and task.deadline then
    start_date = task.deadline
    is_allday = M.cfg.deadline_as_allday
  else
    return nil, "No suitable date found"
  end
  
  local start_str = M.format_for_applescript(start_date, is_allday)
  if not start_str then
    return nil, "Failed to format start date: " .. tostring(start_date)
  end
  
  -- Calculate end date
  local end_date
  if is_allday then
    -- For all-day events, end date is same as start
    end_date = start_date
  else
    -- For timed events, add duration
    end_date = M.add_duration(start_date, M.cfg.event_duration)
  end
  
  local end_str = M.format_for_applescript(end_date, is_allday)
  if not end_str then
    return nil, "Failed to format end date: " .. tostring(end_date)
  end
  
  -- Build the properties
  local properties = string.format("{summary:%s, start date:%s, end date:%s",
    vim.fn.shellescape(task.title),
    start_str,
    end_str
  )
  
  if is_allday then
    properties = properties .. ", allday event:true"
  end
  
  if task.location and task.location ~= "" then
    properties = properties .. string.format(", location:%s", vim.fn.shellescape(task.location))
  end
  
  properties = properties .. "}"
  
  local script = string.format([[
tell application "Calendar"
  tell calendar "%s"
    set newEvent to make new event with properties %s
    return (uid of newEvent) as string
  end tell
end tell
]], calendar_name, properties)
  
  local result, err = safe_exec_applescript(script)
  if not result then
    return nil, err or "AppleScript execution failed"
  end
  
  return result:gsub("%s+$", "")
end

function M.update_event(event_id, task)
  -- Find which date changed
  local start_date = task.scheduled or task.deadline
  if not start_date then
    return false, "No date found"
  end
  
  local is_allday = not start_date:match("%d%d:%d%d")
  local start_str = M.format_for_applescript(start_date, is_allday)
  
  local end_date
  if is_allday then
    end_date = start_date
  else
    end_date = M.add_duration(start_date, M.cfg.event_duration)
  end
  
  local end_str = M.format_for_applescript(end_date, is_allday)
  
  local location_str = task.location and 
    string.format('set location of targetEvent to %s', vim.fn.shellescape(task.location)) or ""
  
  local script = string.format([[
tell application "Calendar"
  set targetEvent to first event whose uid is "%s"
  set summary of targetEvent to %s
  set start date of targetEvent to %s
  set end date of targetEvent to %s
  set allday event of targetEvent to %s
  %s
  return "OK"
end tell
]], 
    event_id,
    vim.fn.shellescape(task.title),
    start_str,
    end_str or start_str,
    is_allday and "true" or "false",
    location_str
  )
  
  local result, err = safe_exec_applescript(script)
  return result ~= nil, err
end

function M.delete_event(event_id)
  if not event_id or event_id == "" then
    return false
  end
  
  local script = string.format([[
tell application "Calendar"
  try
    set targetEvent to first event whose uid is "%s"
    delete targetEvent
    return "OK"
  on error
    return "ERROR"
  end try
end tell
]], event_id)
  
  local result = safe_exec_applescript(script)
  return result and result:find("OK") ~= nil
end

function M.export_to_calendar()
  vim.notify("📆 Exporting tasks to Calendar...", vim.log.levels.INFO)
  
  local tasks = M.scan_tasks_for_calendar()
  if #tasks == 0 then
    vim.notify("No tasks with dates found to export", vim.log.levels.INFO)
    return
  end
  
  local created, updated, errors = 0, 0, 0
  
  for _, task in ipairs(tasks) do
    if task.event_id and task.event_id ~= "" then
      -- Update existing event
      local ok, err = M.update_event(task.event_id, task)
      if ok then
        updated = updated + 1
      else
        errors = errors + 1
        vim.notify(string.format("⚠️  Failed to update: %s (%s)", task.title, err or "unknown"), 
          vim.log.levels.WARN)
      end
    else
      -- Create new event
      local event_id, err = M.create_event(task, M.cfg.default_calendar)
      if event_id then
        created = created + 1
        M.add_event_id_to_task(task.path, task.lnum, event_id)
      else
        errors = errors + 1
        vim.notify(string.format("⚠️  Failed to create: %s (%s)", task.title, err or "unknown"),
          vim.log.levels.WARN)
      end
    end
  end
  
  vim.notify(string.format("✅ Export complete: %d created, %d updated, %d errors", 
    created, updated, errors), vim.log.levels.INFO)
end

function M.add_event_id_to_task(path, lnum, event_id)
  local lines = readfile(path)
  if not lines or #lines == 0 then return end
  
  -- Find properties drawer
  local prop_start, prop_end
  for i = lnum + 1, math.min(lnum + 15, #lines) do
    if lines[i]:match("^%s*:PROPERTIES:%s*$") then
      prop_start = i
    elseif prop_start and lines[i]:match("^%s*:END:%s*$") then
      prop_end = i
      break
    end
  end
  
  if prop_start and prop_end then
    -- Check if EVENT_ID exists
    for i = prop_start + 1, prop_end - 1 do
      if lines[i]:match(":EVENT_ID:") then
        lines[i] = ":EVENT_ID:  " .. event_id
        writefile(path, lines)
        return
      end
    end
    -- Add new EVENT_ID
    table.insert(lines, prop_end, ":EVENT_ID:  " .. event_id)
    writefile(path, lines)
  end
end

-- ============================================================================
-- SYNC Operations
-- ============================================================================

function M.bidirectional_sync()
  vim.notify("🔄 Starting bidirectional calendar sync...", vim.log.levels.INFO)
  
  -- Import new events
  M.import_all()
  
  -- Export/update tasks with dates
  M.export_to_calendar()
  
  vim.notify("✅ Bidirectional sync complete", vim.log.levels.INFO)
end

-- ============================================================================
-- Utilities
-- ============================================================================

function M.test_basic()
  vim.notify("🧪 Testing Calendar access...", vim.log.levels.INFO)
  
  local result, err = safe_exec_applescript('tell application "Calendar" to return "OK"')
  
  if result and result:find("OK") then
    vim.notify("✅ Calendar access works", vim.log.levels.INFO)
  else
    vim.notify("❌ Failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    vim.notify("Check System Settings → Privacy & Security → Automation", vim.log.levels.INFO)
  end
end

function M.show_config()
  local info = {
    "📅 Calendar Configuration:",
    "",
    "Calendar: " .. M.cfg.default_calendar,
    "Event duration: " .. M.cfg.event_duration .. " minutes",
    "Days ahead: " .. M.cfg.days_ahead,
    "",
    "Create events from:",
    "  SCHEDULED: " .. tostring(M.cfg.create_from_scheduled),
    "  DEADLINE: " .. tostring(M.cfg.create_from_deadline),
    "  Deadline as all-day: " .. tostring(M.cfg.deadline_as_allday),
    "",
    "Sync states: " .. table.concat(M.cfg.sync_states, ", "),
    "Excluded calendars: " .. table.concat(M.cfg.excluded_calendars, ", "),
  }
  
  vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end

function M.configure()
  local options = {
    "1. Show configuration",
    "2. Toggle: Create from SCHEDULED",
    "3. Toggle: Create from DEADLINE",
    "4. Toggle: Deadline as all-day",
    "5. Test: Calendar access",
    "6. Help: Setup instructions",
  }
  
  ui.select(options, { prompt = "Configure Calendar" }, function(choice)
    if not choice then return end
    
    if choice:find("Show") then
      M.show_config()
    elseif choice:find("Create from SCHEDULED") then
      M.cfg.create_from_scheduled = not M.cfg.create_from_scheduled
      vim.notify("✅ Create from SCHEDULED: " .. tostring(M.cfg.create_from_scheduled), vim.log.levels.INFO)
    elseif choice:find("Create from DEADLINE") then
      M.cfg.create_from_deadline = not M.cfg.create_from_deadline
      vim.notify("✅ Create from DEADLINE: " .. tostring(M.cfg.create_from_deadline), vim.log.levels.INFO)
    elseif choice:find("Deadline as all-day") then
      M.cfg.deadline_as_allday = not M.cfg.deadline_as_allday
      vim.notify("✅ Deadline as all-day: " .. tostring(M.cfg.deadline_as_allday), vim.log.levels.INFO)
    elseif choice:find("Test") then
      M.test_basic()
    elseif choice:find("Help") then
      local help = {
        "📚 Calendar Setup:",
        "",
        "1. Grant permissions:",
        "   System Settings → Privacy & Security → Automation",
        "   → [Your Terminal] → Enable 'Calendar'",
        "",
        "2. Commands:",
        "   :GtdImportEvents      - Import from Calendar",
        "   :GtdExportToCalendar  - Export tasks to Calendar",
        "   :GtdSyncCalendar      - Bidirectional sync",
        "",
        "3. Properties:",
        "   :EVENT_ID:  - Links task to Calendar event",
        "   :CALENDAR:  - Source calendar name",
        "   :LOCATION:  - Event location",
        "",
        "4. Date handling:",
        "   SCHEDULED → Timed calendar event (9 AM default)",
        "   DEADLINE → All-day calendar event",
      }
      vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
    end
  end)
end

-- ============================================================================
-- Setup
-- ============================================================================

function M.setup(user_cfg)
  if user_cfg then
    M.cfg = vim.tbl_deep_extend("force", M.cfg, user_cfg)
  end
  
  ensure_dir(j(xp(M.cfg.gtd_root), M.cfg.inbox_file))
  ensure_dir(j(xp(M.cfg.gtd_root), M.cfg.projects_dir))
  
  vim.api.nvim_create_user_command("GtdImportEvents", function() M.import_all() end, {})
  vim.api.nvim_create_user_command("GtdExportToCalendar", function() M.export_to_calendar() end, {})
  vim.api.nvim_create_user_command("GtdSyncCalendar", function() M.bidirectional_sync() end, {})
  vim.api.nvim_create_user_command("GtdCalendarConfig", function() M.configure() end, {})
  vim.api.nvim_create_user_command("GtdCalendarTest", function() M.test_basic() end, {})
  
  -- Auto-sync on save if configured
  if M.cfg.auto_sync_on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = "*.org",
      callback = function()
        local path = vim.fn.expand("%:p")
        if path:find(xp(M.cfg.gtd_root), 1, true) then
          vim.schedule(function()
            M.export_to_calendar()
          end)
        end
      end,
    })
  end
end

return M
