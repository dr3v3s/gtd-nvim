-- ============================================================================
-- STEP: SCHEDULE
-- ============================================================================
-- Set defer (scheduled) and due (deadline) dates with time using visual picker.
-- Optionally create a calendar event.
--
-- @module gtd-nvim.capture.steps.schedule
-- @version 1.2.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.2.0"
M._UPDATED = "2025-12-23"

M.name = "schedule"
M.applies_to = { "task", "project" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  use_picker = true,
  fallback_to_text = true,
  ask_defer = true,
  ask_due = true,
  due_days_after_defer = 3,
  date_help = "+1d, +2w, +1m, mon, fri, tomorrow",
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function parse_smart_date(input, base)
  if not input or input == "" then return nil end
  if input:match("^%d%d%d%d%-%d%d%-%d%d$") then return input end
  
  local base_time = os.time()
  if base then
    local y, m, d = base:match("(%d+)-(%d+)-(%d+)")
    if y then base_time = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) }) end
  end
  
  local num, unit = input:match("^%+(%d+)([dwm])$")
  if num and unit then
    num = tonumber(num)
    local secs = unit == "d" and num * 86400 or unit == "w" and num * 7 * 86400 or num * 30 * 86400
    return os.date("%Y-%m-%d", base_time + secs)
  end
  
  if input:lower() == "today" then return os.date("%Y-%m-%d", base_time) end
  if input:lower() == "tomorrow" then return os.date("%Y-%m-%d", base_time + 86400) end
  
  local day_map = { monday = 1, mon = 1, tuesday = 2, tue = 2, wednesday = 3, wed = 3,
                    thursday = 4, thu = 4, friday = 5, fri = 5, saturday = 6, sat = 6, sunday = 0, sun = 0 }
  local target = day_map[input:lower()]
  if target then
    local current = tonumber(os.date("%w", base_time))
    local days_ahead = (target - current) % 7
    if days_ahead == 0 then days_ahead = 7 end
    return os.date("%Y-%m-%d", base_time + days_ahead * 86400)
  end
  
  return nil
end

local function today() return os.date("%Y-%m-%d") end

local function future_date(days, base)
  local base_time = os.time()
  if base then
    local y, m, d = base:match("(%d+)-(%d+)-(%d+)")
    if y then base_time = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) }) end
  end
  return os.date("%Y-%m-%d", base_time + days * 86400)
end

-- ============================================================================
-- CALENDAR EVENT CREATION
-- ============================================================================

local function create_calendar_event(obj)
  -- Try chronos-bridge for calendar creation
  local chronos_ok, chronos = pcall(require, "gtd-nvim.gtd.chronos")
  if not chronos_ok or not chronos.is_running or not chronos.is_running() then
    vim.notify("Chronos not running - cannot create calendar event", vim.log.levels.WARN)
    return
  end
  
  -- Build event data
  local start_date = obj.scheduled or obj.deadline or today()
  local start_time = obj.scheduled_time or "09:00"
  local end_time = obj.deadline_time or nil
  
  -- Calculate end time (1 hour after start if not specified)
  if not end_time then
    local h, m = start_time:match("(%d+):(%d+)")
    if h then
      local end_h = tonumber(h) + 1
      if end_h > 23 then end_h = 23 end
      end_time = string.format("%02d:%s", end_h, m)
    else
      end_time = "10:00"
    end
  end
  
  local event = {
    title = obj.title,
    start_date = start_date,
    start_time = start_time,
    end_date = obj.deadline or start_date,
    end_time = end_time,
    notes = obj.outcome or "",
  }
  
  chronos.query("calendar", "create_event", event, function(response)
    if response and response.success then
      vim.notify("󰃰 Calendar event created", vim.log.levels.INFO)
      -- Store event ID if returned
      if response.event_id then
        obj.calendar_event_id = response.event_id
      end
    else
      vim.notify("Failed to create calendar event", vim.log.levels.WARN)
    end
  end)
end

-- ============================================================================
-- SHOULD RUN
-- ============================================================================

function M.should_run(obj, opts)
  opts = opts or {}
  -- SOMEDAY tasks don't have dates
  if obj.state == "SOMEDAY" then return false end
  if not opts.ask_defer and not opts.ask_due then return false end
  return true
end

-- ============================================================================
-- RUN
-- ============================================================================

function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Try visual picker first
  if opts.use_picker then
    local picker_ok, picker = pcall(require, "gtd-nvim.capture.ui.datepicker")
    if picker_ok then
      picker.open({
        defer = obj.scheduled,
        due = obj.deadline,
        defer_time = obj.scheduled_time,
        due_time = obj.deadline_time,
        on_complete = function(defer, due, defer_time, due_time, create_event)
          if defer then obj.scheduled = defer end
          if due then obj.deadline = due end
          if defer_time then obj.scheduled_time = defer_time end
          if due_time then obj.deadline_time = due_time end
          
          -- Create calendar event if requested
          if create_event and (obj.scheduled or obj.deadline) then
            create_calendar_event(obj)
          end
          
          vim.schedule(function() next_step(obj) end)
        end,
      })
      return
    end
  end
  
  -- Fallback to text input
  if opts.fallback_to_text then
    M._text_input(obj, opts, next_step)
  else
    next_step(obj)
  end
end

-- ============================================================================
-- TEXT INPUT FALLBACK
-- ============================================================================

function M._text_input(obj, opts, next_step)
  if opts.ask_defer then
    local default = obj.scheduled or today()
    vim.ui.input({ prompt = string.format("Defer [%s] (%s): ", default, opts.date_help) }, function(input)
      if input == nil then next_step(nil); return end
      if input ~= "" then
        obj.scheduled = parse_smart_date(input, today()) or input
      else
        obj.scheduled = default
      end
      
      if opts.ask_due then
        vim.schedule(function() M._ask_due(obj, opts, next_step) end)
      else
        next_step(obj)
      end
    end)
  elseif opts.ask_due then
    M._ask_due(obj, opts, next_step)
  else
    next_step(obj)
  end
end

function M._ask_due(obj, opts, next_step)
  local base = obj.scheduled or today()
  local default = future_date(opts.due_days_after_defer, base)
  
  vim.ui.input({ prompt = string.format("Due [%s] (%s): ", default, opts.date_help) }, function(input)
    if input == nil then next_step(nil); return end
    if input ~= "" then
      obj.deadline = parse_smart_date(input, base) or input
    else
      obj.deadline = default
    end
    next_step(obj)
  end)
end

return M
