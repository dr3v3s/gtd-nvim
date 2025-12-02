-- gtd/utils/org_dates.lua - STRICT ORG-MODE DATE COMPLIANCE
-- Handles org-mode timestamps with proper day-of-week formatting
-- Format: <YYYY-MM-DD Day> or <YYYY-MM-DD Day HH:MM>

local M = {}

-- Day of week names (org-mode uses English abbreviated day names)
local WEEKDAYS = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

-- ============================================================================
-- DATE VALIDATION
-- ============================================================================

--- Validate date string format (YYYY-MM-DD)
---@param date_str string Date string to validate
---@return boolean True if valid format
function M.is_valid_date_format(date_str)
  if not date_str or date_str == "" then return false end
  
  local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not year or not month or not day then return false end
  
  year = tonumber(year)
  month = tonumber(month)
  day = tonumber(day)
  
  -- Basic range validation
  if year < 1900 or year > 2100 then return false end
  if month < 1 or month > 12 then return false end
  if day < 1 or day > 31 then return false end
  
  -- Days in month validation
  local days_in_month = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
  
  -- Leap year calculation
  if month == 2 then
    local is_leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
    days_in_month[2] = is_leap and 29 or 28
  end
  
  if day > days_in_month[month] then return false end
  
  return true
end

--- Validate org-mode timestamp format
---@param timestamp string Org timestamp to validate
---@return boolean True if valid org-mode format
function M.is_valid_org_timestamp(timestamp)
  if not timestamp or timestamp == "" then return false end
  
  -- Remove angle brackets if present
  local content = timestamp:match("^<(.+)>$") or timestamp
  
  -- Match date with day of week: YYYY-MM-DD Day
  local date_part, day_part = content:match("^(%d%d%d%d%-%d%d%-%d%d)%s+(%a%a%a)$")
  if date_part and day_part then
    return M.is_valid_date_format(date_part) and vim.tbl_contains(WEEKDAYS, day_part)
  end
  
  -- Match date with day and time: YYYY-MM-DD Day HH:MM
  date_part, day_part = content:match("^(%d%d%d%d%-%d%d%-%d%d)%s+(%a%a%a)%s+%d%d:%d%d$")
  if date_part and day_part then
    return M.is_valid_date_format(date_part) and vim.tbl_contains(WEEKDAYS, day_part)
  end
  
  return false
end

-- ============================================================================
-- DATE FORMATTING - ORG-MODE COMPLIANCE
-- ============================================================================

--- Get day of week for a given date
---@param year number Year
---@param month number Month (1-12)
---@param day number Day (1-31)
---@return string Day name (Sun, Mon, etc.)
local function get_day_of_week(year, month, day)
  local t = os.time({year = year, month = month, day = day, hour = 12})
  local wday = tonumber(os.date("%w", t)) + 1  -- os.date %w is 0-6, we want 1-7
  return WEEKDAYS[wday]
end

--- Format date as org-mode timestamp: <YYYY-MM-DD Day>
---@param date_str string Date in YYYY-MM-DD format
---@return string|nil Org-mode timestamp or nil if invalid
function M.format_org_date(date_str)
  if not M.is_valid_date_format(date_str) then
    return nil
  end
  
  local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  
  local weekday = get_day_of_week(year, month, day)
  return string.format("<%s %s>", date_str, weekday)
end

--- Format date with time as org-mode timestamp: <YYYY-MM-DD Day HH:MM>
---@param date_str string Date in YYYY-MM-DD format
---@param time_str string Time in HH:MM format
---@return string|nil Org-mode timestamp or nil if invalid
function M.format_org_datetime(date_str, time_str)
  if not M.is_valid_date_format(date_str) then
    return nil
  end
  
  if not time_str or not time_str:match("^%d%d:%d%d$") then
    return nil
  end
  
  local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  
  local weekday = get_day_of_week(year, month, day)
  return string.format("<%s %s %s>", date_str, weekday, time_str)
end

-- ============================================================================
-- DATE UTILITIES
-- ============================================================================

--- Get today's date in YYYY-MM-DD format
---@param offset_days number|nil Days to offset from today (default 0)
---@return string Date string
function M.today(offset_days)
  local time = os.time() + ((offset_days or 0) * 24 * 3600)
  return os.date("%Y-%m-%d", time)
end

--- Get today's date as org-mode timestamp
---@param offset_days number|nil Days to offset from today (default 0)
---@return string Org-mode timestamp
function M.today_org(offset_days)
  local date_str = M.today(offset_days)
  return M.format_org_date(date_str)
end

--- Get current date and time as org-mode timestamp
---@return string Org-mode datetime timestamp
function M.now_org()
  local date_str = os.date("%Y-%m-%d")
  local time_str = os.date("%H:%M")
  return M.format_org_datetime(date_str, time_str)
end

--- Parse org-mode timestamp back to date string
---@param org_timestamp string Org-mode timestamp
---@return string|nil Date in YYYY-MM-DD format or nil if invalid
function M.parse_org_date(org_timestamp)
  if not org_timestamp then return nil end
  
  -- Remove angle brackets if present
  local content = org_timestamp:match("^<(.+)>$") or org_timestamp
  
  -- Extract date part (before day name)
  local date_part = content:match("^(%d%d%d%d%-%d%d%-%d%d)")
  
  if date_part and M.is_valid_date_format(date_part) then
    return date_part
  end
  
  return nil
end

--- Calculate days between two dates
---@param date1 string First date (YYYY-MM-DD)
---@param date2 string Second date (YYYY-MM-DD)
---@return number|nil Days between dates (positive if date2 is after date1)
function M.days_between(date1, date2)
  if not M.is_valid_date_format(date1) or not M.is_valid_date_format(date2) then
    return nil
  end
  
  local function date_to_time(date_str)
    local y, m, d = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    return os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12})
  end
  
  local t1 = date_to_time(date1)
  local t2 = date_to_time(date2)
  
  return math.floor((t2 - t1) / (24 * 3600))
end

--- Check if date1 is before date2
---@param date1 string First date (YYYY-MM-DD)
---@param date2 string Second date (YYYY-MM-DD)
---@return boolean True if date1 is before date2
function M.is_before(date1, date2)
  local days = M.days_between(date1, date2)
  return days and days > 0 or false
end

--- Check if date is overdue (before today)
---@param date_str string Date to check (YYYY-MM-DD)
---@param grace_days number|nil Grace period in days (default 0)
---@return boolean True if overdue
function M.is_overdue(date_str, grace_days)
  if not M.is_valid_date_format(date_str) then return false end
  
  local today = M.today()
  local days = M.days_between(date_str, today)
  
  return days and days > (grace_days or 0) or false
end

-- ============================================================================
-- INTERACTIVE DATE PROMPTS
-- ============================================================================

--- Prompt user for date with validation and org-mode formatting
---@param opts table Options table with prompt, default, allow_empty
---@param callback function Callback receives org-mode timestamp or empty string
function M.prompt_org_date(opts, callback)
  opts = opts or {}
  local prompt = opts.prompt or "Date (YYYY-MM-DD): "
  local default = opts.default or M.today()
  
  if default and M.is_valid_date_format(default) then
    prompt = prompt .. "[" .. default .. "] "
  end
  
  vim.ui.input({ prompt = prompt, default = opts.default }, function(input)
    if not input or input == "" then
      if opts.allow_empty then
        callback("")
      else
        callback(M.format_org_date(default))
      end
      return
    end
    
    local date_str = input:gsub("^%s+", ""):gsub("%s+$", "")
    
    if not M.is_valid_date_format(date_str) then
      vim.notify(
        string.format("Invalid date format: '%s'. Expected YYYY-MM-DD", date_str),
        vim.log.levels.ERROR
      )
      callback("")
      return
    end
    
    local org_timestamp = M.format_org_date(date_str)
    callback(org_timestamp)
  end)
end

--- Prompt user for date+time with validation
---@param opts table Options table
---@param callback function Callback receives org-mode datetime timestamp
function M.prompt_org_datetime(opts, callback)
  opts = opts or {}
  
  M.prompt_org_date(opts, function(org_date)
    if not org_date or org_date == "" then
      callback("")
      return
    end
    
    local date_str = M.parse_org_date(org_date)
    
    vim.ui.input({ prompt = "Time (HH:MM): [12:00] ", default = "12:00" }, function(time_input)
      local time_str = time_input or "12:00"
      time_str = time_str:gsub("^%s+", ""):gsub("%s+$", "")
      
      if not time_str:match("^%d%d:%d%d$") then
        vim.notify("Invalid time format. Expected HH:MM", vim.log.levels.ERROR)
        callback(org_date)  -- Fallback to date only
        return
      end
      
      local org_datetime = M.format_org_datetime(date_str, time_str)
      callback(org_datetime or org_date)
    end)
  end)
end

-- ============================================================================
-- CONVERSION UTILITIES
-- ============================================================================

--- Convert non-org date format to org-mode timestamp
---@param date_str string Date in YYYY-MM-DD format
---@return string Org-mode timestamp or original if invalid
function M.ensure_org_format(date_str)
  if not date_str or date_str == "" then return "" end
  
  -- Already in org format?
  if date_str:match("^<.+>$") and M.is_valid_org_timestamp(date_str) then
    return date_str
  end
  
  -- Try to format as org date
  local formatted = M.format_org_date(date_str)
  return formatted or date_str
end

--- Convert org-mode SCHEDULED/DEADLINE line format
---@param keyword string "SCHEDULED" or "DEADLINE"
---@param date_str string Date in YYYY-MM-DD format
---@return string Org-mode line with keyword and timestamp
function M.format_org_date_line(keyword, date_str)
  local org_timestamp = M.format_org_date(date_str)
  if not org_timestamp then
    return ""
  end
  return string.format("%s: %s", keyword, org_timestamp)
end

-- ============================================================================
-- MODULE CONFIGURATION
-- ============================================================================

M.config = {
  strict_validation = true,
  require_day_of_week = true,
  allow_time = true,
}

function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
end

return M
