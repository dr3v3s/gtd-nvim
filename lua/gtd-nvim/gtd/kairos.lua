-- ============================================================================
-- GTD-NVIM KAIROS INTEGRATION
-- ============================================================================
-- Integration with Kairos daemon for real-time GTD metrics, calendar, and reminders
-- Single source of truth for all external data (replaces iCalBuddy, calendar.lua)
--
-- @module gtd-nvim.gtd.kairos
-- @version 1.0.0
-- @see ~/Developer/kairos (daemon source)
-- @see ~/Developer/kairos-bridge (Swift EventKit CLI)
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2024-12-18"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.config = {
  socket_path = vim.fn.expand("~/.cache/kairos/kairos.sock"),
  cache_dir = vim.fn.expand("~/.cache/kairos"),
  
  -- Cache file names (for fallback reads)
  cache_files = {
    gtd = "gtd.json",
    calendar = "calendar.json",
    reminders = "reminders.json",
    mail = "mail.json",
  },
  
  -- Timeouts
  socket_timeout_ms = 1000,
  cache_max_age_s = 300,  -- 5 minutes
  
  -- Behavior
  fallback_to_cache = true,
  debug = false,
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function log(msg)
  if M.config.debug then
    vim.notify("[kairos] " .. msg, vim.log.levels.DEBUG)
  end
end

local function file_exists(path)
  return vim.fn.filereadable(path) == 1
end

local function read_json_file(path)
  if not file_exists(path) then
    return nil, "File not found: " .. path
  end
  
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return nil, "Failed to read file: " .. path
  end
  
  local content = table.concat(lines, "\n")
  local decode_ok, data = pcall(vim.fn.json_decode, content)
  if not decode_ok or not data then
    return nil, "Failed to parse JSON: " .. path
  end
  
  return data, nil
end

local function cache_path(provider)
  local filename = M.config.cache_files[provider]
  if not filename then
    return nil
  end
  return M.config.cache_dir .. "/" .. filename
end

local function file_age(path)
  if not file_exists(path) then
    return math.huge
  end
  local stat = vim.loop.fs_stat(path)
  if not stat then
    return math.huge
  end
  return os.time() - stat.mtime.sec
end

-- ============================================================================
-- DAEMON STATUS
-- ============================================================================

--- Check if Kairos daemon socket exists
---@return boolean
function M.is_available()
  return file_exists(M.config.socket_path)
end

--- Check if daemon is running (socket exists and process alive)
---@return boolean, string|nil
function M.is_running()
  if not M.is_available() then
    return false, "Socket not found"
  end
  
  local pid_path = M.config.cache_dir .. "/kairosd.pid"
  if file_exists(pid_path) then
    local pid_lines = vim.fn.readfile(pid_path)
    if pid_lines and pid_lines[1] then
      local pid = tonumber(pid_lines[1])
      if pid then
        local handle = io.popen("kill -0 " .. pid .. " 2>/dev/null && echo running || echo stopped")
        if handle then
          local result = handle:read("*l")
          handle:close()
          if result == "running" then
            return true, nil
          end
        end
      end
    end
  end
  
  return false, "Daemon not responding"
end

--- Get daemon status summary
---@return table
function M.status()
  local available = M.is_available()
  local running, err = M.is_running()
  
  local gtd_cache_age = file_age(cache_path("gtd"))
  local cal_cache_age = file_age(cache_path("calendar"))
  
  return {
    available = available,
    running = running,
    error = err,
    socket_path = M.config.socket_path,
    cache_dir = M.config.cache_dir,
    gtd_cache_age = gtd_cache_age,
    calendar_cache_age = cal_cache_age,
    cache_fresh = gtd_cache_age < M.config.cache_max_age_s,
  }
end

-- ============================================================================
-- SOCKET COMMUNICATION (Synchronous)
-- ============================================================================

--- Send query to Kairos daemon via Unix socket
--- Protocol: {"module":"gtd", "cmd":"metrics", "params":{}}
---@param module string Provider name (gtd, calendar, reminders, mail)
---@param cmd string Command to execute
---@param params table|nil Optional parameters
---@return table|nil, string|nil Response data or nil, error message
function M.query(module, cmd, params)
  if not M.is_available() then
    return nil, "Kairos daemon not available"
  end
  
  -- Build request - only include params if non-empty to avoid JSON encoding issues
  -- (empty Lua tables encode as [] instead of {} which breaks Go unmarshaling)
  local request = {
    module = module,
    cmd = cmd,
  }
  
  -- Only add params if we have actual parameters
  if params and next(params) then
    request.params = params
  end
  
  local json_request = vim.fn.json_encode(request)
  
  -- Use nc (netcat) to query the socket
  local nc_cmd = string.format(
    'echo \'%s\' | nc -U %s 2>/dev/null',
    json_request:gsub("'", "\\'"),
    M.config.socket_path
  )
  
  log("Query: " .. json_request)
  
  local handle = io.popen(nc_cmd)
  if not handle then
    return nil, "Failed to connect to socket"
  end
  
  local response = handle:read("*a")
  handle:close()
  
  if not response or response == "" then
    return nil, "Empty response from daemon"
  end
  
  local ok, data = pcall(vim.fn.json_decode, response)
  if not ok then
    return nil, "Invalid JSON response: " .. response:sub(1, 100)
  end
  
  log("Response: success=" .. tostring(data.success))
  
  if not data.success then
    return nil, data.error or "Query failed"
  end
  
  return data.data, nil
end

-- ============================================================================
-- ASYNC SOCKET COMMUNICATION
-- ============================================================================

--- Async query to Kairos daemon
---@param module string Provider name
---@param cmd string Command
---@param params table|nil Parameters
---@param callback function Callback(data, err)
function M.query_async(module, cmd, params, callback)
  if not M.is_available() then
    vim.schedule(function()
      callback(nil, "Kairos daemon not available")
    end)
    return
  end
  
  -- Build request - only include params if non-empty to avoid JSON encoding issues
  local request = {
    module = module,
    cmd = cmd,
  }
  
  if params and next(params) then
    request.params = params
  end
  
  local json_request = vim.fn.json_encode(request)
  local nc_cmd = string.format(
    'echo \'%s\' | nc -U %s 2>/dev/null',
    json_request:gsub("'", "\\'"),
    M.config.socket_path
  )
  
  local stdout_chunks = {}
  
  vim.fn.jobstart(nc_cmd, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line and line ~= "" then
          table.insert(stdout_chunks, line)
        end
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code ~= 0 then
          callback(nil, "Socket query failed with exit code " .. exit_code)
          return
        end
        
        local response = table.concat(stdout_chunks, "\n")
        if response == "" then
          callback(nil, "Empty response")
          return
        end
        
        local ok, data = pcall(vim.fn.json_decode, response)
        if not ok then
          callback(nil, "Invalid JSON response")
          return
        end
        
        if not data.success then
          callback(nil, data.error or "Query failed")
          return
        end
        
        callback(data.data, nil)
      end)
    end,
  })
end

-- ============================================================================
-- GTD QUERIES
-- ============================================================================

--- Get GTD metrics
---@param opts table|nil { use_cache = false, allow_stale = true }
---@return table|nil, string|nil
function M.gtd_metrics(opts)
  opts = opts or {}
  
  -- Try socket first
  local data, err = M.query("gtd", "metrics")
  if data then
    return data, nil
  end
  
  -- Fallback to cache
  if M.config.fallback_to_cache then
    local cache_data, cache_err = read_json_file(cache_path("gtd"))
    if cache_data then
      local age = file_age(cache_path("gtd"))
      if age > M.config.cache_max_age_s and not opts.allow_stale then
        return cache_data, "Cache is stale (" .. age .. "s old)"
      end
      return cache_data, nil
    end
    return nil, cache_err
  end
  
  return nil, err
end

--- Get GTD tasks with optional filtering
---@param opts table|nil { state = "NEXT", limit = 10 }
---@return table|nil, string|nil
function M.gtd_tasks(opts)
  opts = opts or {}
  local params = {}
  
  if opts.state then
    params.state = opts.state
  end
  if opts.limit then
    params.limit = opts.limit
  end
  
  return M.query("gtd", "tasks", params)
end

--- Get overdue tasks
---@return table|nil, string|nil
function M.gtd_overdue()
  return M.query("gtd", "overdue")
end

--- Get NEXT actions
---@param limit number|nil
---@return table|nil, string|nil
function M.gtd_next(limit)
  return M.query("gtd", "tasks", { state = "NEXT", limit = limit })
end

--- Get WAITING items
---@param limit number|nil
---@return table|nil, string|nil
function M.gtd_waiting(limit)
  return M.query("gtd", "tasks", { state = "WAITING", limit = limit })
end

--- Get Inbox items (async for use in pickers)
---@param callback function
function M.gtd_inbox_async(callback)
  M.query_async("gtd", "tasks", { state = "TODO" }, callback)
end

-- ============================================================================
-- CALENDAR QUERIES (Replaces iCalBuddy)
-- ============================================================================

--- Get calendar metrics
---@return table|nil { today_count, upcoming_count, updated_at }
function M.calendar_metrics()
  local data, err = M.query("calendar", "metrics")
  if data then
    return data, nil
  end
  
  -- Fallback to cache
  if M.config.fallback_to_cache then
    local cache_data = read_json_file(cache_path("calendar"))
    if cache_data then
      return cache_data, nil
    end
  end
  
  return nil, err
end

--- Get today's calendar events
---@return table|nil Array of events
function M.calendar_today()
  local data, err = M.query("calendar", "today")
  if data then
    return data, nil
  end
  return nil, err
end

--- Get upcoming calendar events
---@param days number|nil Days ahead (default from Kairos config)
---@return table|nil Array of events
function M.calendar_upcoming(days)
  local params = {}
  if days then
    params.days = days
  end
  return M.query("calendar", "upcoming", params)
end

--- Get next calendar event
---@return table|nil Single event or nil
function M.calendar_next()
  return M.query("calendar", "next")
end

--- Get past calendar events (for weekly review)
---@param days number|nil Days to look back (default 7)
---@return table|nil Array of events
function M.calendar_past(days)
  return M.query("calendar", "past", { days = days or 7 })
end

--- Get calendar events within date range
---@param start_date string Start date (YYYY-MM-DD)
---@param end_date string End date (YYYY-MM-DD)
---@return table|nil Array of events
function M.calendar_range(start_date, end_date)
  return M.query("calendar", "range", { start = start_date, ["end"] = end_date })
end

--- Get calendar week (past 7 + future 7 days)
---@return table|nil Array of events
function M.calendar_week()
  return M.query("calendar", "week")
end

--- Async: Get today's events for agenda display
---@param callback function(events, err)
function M.calendar_today_async(callback)
  M.query_async("calendar", "today", nil, callback)
end

--- Async: Get upcoming events
---@param callback function(events, err)
function M.calendar_upcoming_async(callback)
  M.query_async("calendar", "upcoming", nil, callback)
end

-- ============================================================================
-- REMINDERS QUERIES
-- ============================================================================

--- Get reminders metrics
---@return table|nil { total, incomplete, by_list, updated_at }
function M.reminders_metrics()
  local data, err = M.query("reminders", "metrics")
  if data then
    return data, nil
  end
  
  -- Fallback to cache
  if M.config.fallback_to_cache then
    local cache_data = read_json_file(cache_path("reminders"))
    if cache_data then
      return cache_data, nil
    end
  end
  
  return nil, err
end

--- Get all reminders
---@return table|nil Array of reminders
function M.reminders_all()
  return M.query("reminders", "all")
end

--- Get reminders from a specific list
---@param list_name string List name (e.g., "GTD", "Shopping")
---@return table|nil Array of reminders
function M.reminders_by_list(list_name)
  return M.query("reminders", list_name)
end

--- Async: Get all reminders
---@param callback function(reminders, err)
function M.reminders_all_async(callback)
  M.query_async("reminders", "all", nil, callback)
end

-- ============================================================================
-- MAIL QUERIES (Optional)
-- ============================================================================

--- Get mail unread counts
---@return table|nil { accounts = { [name] = count } }
function M.mail_unread()
  local data, err = M.query("mail", "metrics")
  if data then
    return data, nil
  end
  
  -- Fallback to cache
  if M.config.fallback_to_cache then
    local cache_data = read_json_file(cache_path("mail"))
    if cache_data then
      return cache_data, nil
    end
  end
  
  return nil, err
end

-- ============================================================================
-- SYSTEM COMMANDS
-- ============================================================================

--- Ping daemon
---@return table|nil { status, version, providers }
function M.ping()
  return M.query("", "ping")
end

--- List registered providers
---@return table|nil Array of provider names
function M.providers()
  return M.query("", "providers")
end

--- Refresh a specific provider or all
---@param module string|nil Provider name (nil = all)
---@return boolean, string|nil
function M.refresh(module)
  local data, err = M.query(module or "", "refresh")
  if data then
    return true, nil
  end
  return false, err
end

-- ============================================================================
-- STATUS LINE HELPERS
-- ============================================================================

--- Get compact GTD summary for status line
---@return table { inbox, next, waiting, overdue, projects, available }
function M.summary()
  local metrics = M.gtd_metrics({ allow_stale = true })
  
  if not metrics then
    return {
      inbox = "?",
      next = "?",
      waiting = "?",
      overdue = "?",
      projects = "?",
      available = false,
    }
  end
  
  return {
    inbox = metrics.inbox or 0,
    next = metrics.next or 0,
    todo = metrics.todo or 0,
    waiting = metrics.waiting or 0,
    someday = metrics.someday or 0,
    overdue = metrics.overdue or 0,
    projects = metrics.projects or 0,
    total = metrics.total or 0,
    available = true,
  }
end

--- Format metrics as status line string
---@param opts table|nil { format = "short"|"full", separator = " " }
---@return string
function M.status_line(opts)
  opts = opts or {}
  local sep = opts.separator or " "
  local format = opts.format or "short"
  
  local s = M.summary()
  
  if not s.available then
    return "GTD: offline"
  end
  
  if format == "short" then
    local parts = {}
    local gs = require("gtd-nvim.gtd.shared").glyphs.state
    local gc = require("gtd-nvim.gtd.shared").glyphs.container
    if s.inbox > 0 then table.insert(parts, (gc.inbox or "") .. s.inbox) end
    if s.next > 0 then table.insert(parts, (gs.NEXT or "") .. s.next) end
    if s.waiting > 0 then table.insert(parts, (gs.WAITING or "") .. s.waiting) end
    if s.overdue > 0 then table.insert(parts, (require("gtd-nvim.gtd.shared").glyphs.ui.warning or "") .. s.overdue) end
    return table.concat(parts, sep)
  else
    local gs = require("gtd-nvim.gtd.shared").glyphs.state
    local gc = require("gtd-nvim.gtd.shared").glyphs.container
    return string.format(
      "%s%d %s%d %s%d %s%d %s%d %s%d",
      gc.inbox or "", s.inbox, 
      gs.NEXT or "", s.next, 
      gs.TODO or "", s.todo, 
      gs.WAITING or "", s.waiting, 
      gs.SOMEDAY or "", s.someday, 
      gc.project or "", s.projects
    )
  end
end

-- ============================================================================
-- CALENDAR DISPLAY HELPERS (Replaces icalbuddy functionality)
-- ============================================================================

--- Calculate free time slots from events (replaces icalbuddy.free_slots)
---@param events table Array of calendar events
---@param work_start number Work day start hour (default 9)
---@param work_end number Work day end hour (default 18)
---@param min_slot number Minimum slot duration in minutes (default 30)
---@return table Array of { start_time, end_time, duration_min }
function M.calculate_free_slots(events, work_start, work_end, min_slot)
  work_start = work_start or 9
  work_end = work_end or 18
  min_slot = min_slot or 30
  
  local today = os.date("%Y-%m-%d")
  local slots = {}
  
  -- Filter today's events and sort by start time
  local today_events = {}
  for _, e in ipairs(events or {}) do
    if e.startDate and e.startDate:sub(1, 10) == today and not e.isAllDay then
      table.insert(today_events, e)
    end
  end
  
  table.sort(today_events, function(a, b)
    return (a.startTimestamp or 0) < (b.startTimestamp or 0)
  end)
  
  -- Find gaps between events within work hours
  local current_time = work_start * 60  -- minutes from midnight
  local end_time = work_end * 60
  
  for _, event in ipairs(today_events) do
    local event_start = tonumber(event.startDate:sub(12, 13)) * 60 + tonumber(event.startDate:sub(15, 16) or 0)
    local event_end = tonumber(event.endDate:sub(12, 13)) * 60 + tonumber(event.endDate:sub(15, 16) or 0)
    
    -- Clamp to work hours
    event_start = math.max(event_start, work_start * 60)
    event_end = math.min(event_end, work_end * 60)
    
    -- Gap before this event?
    if event_start > current_time then
      local gap = event_start - current_time
      if gap >= min_slot then
        table.insert(slots, {
          start_time = string.format("%02d:%02d", math.floor(current_time / 60), current_time % 60),
          end_time = string.format("%02d:%02d", math.floor(event_start / 60), event_start % 60),
          duration_min = gap,
        })
      end
    end
    
    current_time = math.max(current_time, event_end)
  end
  
  -- Gap at end of day?
  if current_time < end_time then
    local gap = end_time - current_time
    if gap >= min_slot then
      table.insert(slots, {
        start_time = string.format("%02d:%02d", math.floor(current_time / 60), current_time % 60),
        end_time = string.format("%02d:%02d", work_end, 0),
        duration_min = gap,
      })
    end
  end
  
  return slots
end

--- Build agenda combining calendar events and GTD scheduled tasks
--- (Replaces icalbuddy.agenda functionality)
---@param date string|nil Date in YYYY-MM-DD format (default: today)
---@param callback function(agenda, err) Called with merged agenda
function M.build_agenda_async(date, callback)
  date = date or os.date("%Y-%m-%d")
  
  local agenda = {
    date = date,
    events = {},
    tasks = {},
    merged = {},
  }
  
  local pending = 2
  local function check_done()
    pending = pending - 1
    if pending == 0 then
      -- Merge and sort
      for _, e in ipairs(agenda.events) do
        table.insert(agenda.merged, {
          type = "event",
          time = e.startDate and e.startDate:sub(12, 16) or "00:00",
          title = e.title,
          location = e.location,
          calendar = e.calendar,
          all_day = e.isAllDay,
          data = e,
        })
      end
      
      for _, t in ipairs(agenda.tasks) do
        local time = "00:00"
        if t.scheduled then
          time = t.scheduled:match("(%d%d:%d%d)") or "00:00"
        end
        table.insert(agenda.merged, {
          type = "task",
          time = time,
          title = t.title,
          state = t.state,
          project = t.project,
          data = t,
        })
      end
      
      table.sort(agenda.merged, function(a, b)
        return a.time < b.time
      end)
      
      callback(agenda, nil)
    end
  end
  
  -- Fetch calendar events
  M.calendar_today_async(function(events, err)
    if events then
      agenda.events = events
    end
    check_done()
  end)
  
  -- Fetch scheduled GTD tasks for today
  M.query_async("gtd", "tasks", { scheduled = date }, function(tasks, err)
    if tasks then
      agenda.tasks = tasks
    end
    check_done()
  end)
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Setup function
---@param user_config table|nil Configuration overrides
function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
  
  -- Expand paths
  M.config.socket_path = vim.fn.expand(M.config.socket_path)
  M.config.cache_dir = vim.fn.expand(M.config.cache_dir)
  
  -- Create user commands
  vim.api.nvim_create_user_command("KairosStatus", function()
    local status = M.status()
    local lines = {
      "Kairos Daemon Status",
      "════════════════════",
      "Available: " .. tostring(status.available),
      "Running: " .. tostring(status.running),
      "Socket: " .. status.socket_path,
      "Cache Dir: " .. status.cache_dir,
      "GTD Cache Age: " .. math.floor(status.gtd_cache_age) .. "s",
      "Calendar Cache Age: " .. math.floor(status.calendar_cache_age) .. "s",
      "Cache Fresh: " .. tostring(status.cache_fresh),
    }
    if status.error then
      table.insert(lines, "Error: " .. status.error)
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Show Kairos daemon status" })
  
  vim.api.nvim_create_user_command("KairosMetrics", function()
    local metrics, err = M.gtd_metrics()
    if metrics then
      local lines = {
        "GTD Metrics",
        "═══════════",
        string.format(" Inbox:    %d", metrics.inbox or 0),
        string.format(" Next:     %d", metrics.next or 0),
        string.format(" Todo:     %d", metrics.todo or 0),
        string.format(" Waiting:  %d", metrics.waiting or 0),
        string.format("󰒻 Someday:  %d", metrics.someday or 0),
        string.format(" Projects: %d", metrics.projects or 0),
        string.format(" Overdue:  %d", metrics.overdue or 0),
        string.format(" Total:    %d", metrics.total or 0),
      }
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    else
      vim.notify("Failed to get metrics: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end, { desc = "Show GTD metrics from Kairos" })
  
  vim.api.nvim_create_user_command("KairosCalendar", function()
    local events, err = M.calendar_today()
    if events and #events > 0 then
      local lines = { "Today's Calendar", "════════════════" }
      for _, e in ipairs(events) do
        local time = e.startDate and e.startDate:sub(12, 16) or "All day"
        table.insert(lines, string.format("%s  %s", time, e.title))
      end
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    elseif events then
      vim.notify("No events today", vim.log.levels.INFO)
    else
      vim.notify("Failed to get calendar: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end, { desc = "Show today's calendar from Kairos" })
  
  vim.api.nvim_create_user_command("KairosFreeSlots", function()
    local events, err = M.calendar_today()
    if events then
      local slots = M.calculate_free_slots(events)
      if #slots > 0 then
        local lines = { "Free Time Slots", "═══════════════" }
        for _, slot in ipairs(slots) do
          table.insert(lines, string.format("%s - %s (%d min)", 
            slot.start_time, slot.end_time, slot.duration_min))
        end
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
      else
        vim.notify("No free slots today", vim.log.levels.INFO)
      end
    else
      vim.notify("Failed to get calendar: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end, { desc = "Show free time slots from Kairos" })
  
  vim.api.nvim_create_user_command("KairosRefresh", function(opts)
    local module = opts.args ~= "" and opts.args or nil
    local ok, err = M.refresh(module)
    if ok then
      vim.notify("Kairos refresh triggered" .. (module and (" for " .. module) or " (all)"), vim.log.levels.INFO)
    else
      vim.notify("Refresh failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end, { nargs = "?", desc = "Trigger Kairos refresh (optional: module name)" })
  
  vim.api.nvim_create_user_command("KairosPing", function()
    local data, err = M.ping()
    if data then
      local providers = data.providers or {}
      vim.notify(string.format("Kairos: %s (v%s)\nProviders: %s",
        data.status or "ok",
        data.version or "?",
        table.concat(providers, ", ")),
        vim.log.levels.INFO)
    else
      vim.notify("Ping failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end, { desc = "Ping Kairos daemon" })
end

return M
