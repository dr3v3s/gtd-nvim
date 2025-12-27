-- ============================================================================
-- GTD-NVIM CAPTURE UTILITIES
-- ============================================================================
-- Shared utilities for capture steps.
--
-- @module gtd-nvim.capture.utils
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local shared = safe_require("gtd-nvim.gtd.shared")

-- ============================================================================
-- GLYPHS
-- ============================================================================

M.glyphs = {
  -- States
  next = "󰁔",
  todo = "󰄲",
  waiting = "󰈸",
  someday = "󰋚",
  done = "󰄳",
  cancelled = "󰜺",
  project = "󰷐",
  
  -- UI
  capture = "",
  tag = "",
  calendar = "󰃭",
  reference = "󰈙",
  note = "󰎞",
  inbox = "󰮤",
  area = "󰉋",
  phone = "󰏲",
  email = "󰇮",
  person = "󰀄",
  outcome = "󰓾",
  recurring = "󰑐",
  
  -- Actions
  skip = "󰜺",
  check = "󰄬",
  cross = "󰅖",
  arrow = "→",
}

-- ============================================================================
-- PATH UTILITIES
-- ============================================================================

--- Get GTD home directory
function M.gtd_home()
  if shared and shared.gtd_home then
    return shared.gtd_home()
  end
  return vim.fn.expand("~/Documents/GTD")
end

--- Get inbox path
function M.inbox_path()
  return M.gtd_home() .. "/Inbox.org"
end

--- Get recurring path
function M.recurring_path()
  return M.gtd_home() .. "/Recurring.org"
end

--- Get projects directory
function M.projects_dir()
  return M.gtd_home() .. "/Projects"
end

--- Get areas directory
function M.areas_dir()
  return M.gtd_home() .. "/Areas"
end

-- ============================================================================
-- DATE UTILITIES
-- ============================================================================

--- Parse smart date string
---@param input string Date input (e.g., "+1d", "tomorrow", "2025-12-25")
---@param base string|nil Base date for relative calculations
---@return string|nil YYYY-MM-DD formatted date
function M.parse_date(input, base)
  if not input or input == "" then return nil end
  
  -- Use shared parser if available
  if shared and shared.parse_smart_date then
    return shared.parse_smart_date(input, base)
  end
  
  -- Simple fallback parsing
  local today = os.date("*t")
  
  -- Relative dates: +1d, +2w, +3m
  local num, unit = input:match("^%+(%d+)([dwmDWM])$")
  if num and unit then
    num = tonumber(num)
    unit = unit:lower()
    local t = os.time(today)
    if unit == "d" then
      t = t + (num * 86400)
    elseif unit == "w" then
      t = t + (num * 7 * 86400)
    elseif unit == "m" then
      today.month = today.month + num
      t = os.time(today)
    end
    return os.date("%Y-%m-%d", t)
  end
  
  -- Named dates
  local named = {
    today = 0,
    tomorrow = 1,
    imorgen = 1,  -- Danish
    monday = nil, tuesday = nil, wednesday = nil,
    thursday = nil, friday = nil, saturday = nil, sunday = nil,
  }
  
  local lower = input:lower()
  if named[lower] then
    local t = os.time(today) + (named[lower] * 86400)
    return os.date("%Y-%m-%d", t)
  end
  
  -- ISO format passthrough
  if input:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return input
  end
  
  return nil
end

--- Format date as org-mode active timestamp
---@param date string YYYY-MM-DD
---@return string org timestamp
function M.format_active_date(date)
  if not date then return "" end
  
  -- Parse date
  local y, m, d = date:match("^(%d+)%-(%d+)%-(%d+)$")
  if not y then return "<" .. date .. ">" end
  
  -- Get day name
  local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
  local day_name = os.date("%a", t)
  
  return string.format("<%s %s>", date, day_name)
end

--- Format inactive timestamp (now)
---@return string org inactive timestamp
function M.format_inactive_timestamp()
  return os.date("[%Y-%m-%d %a %H:%M]")
end

--- Get smart date help text
---@return string help text
function M.date_help()
  return "+1d, +2w, +3m, tomorrow, YYYY-MM-DD"
end

-- ============================================================================
-- TASK ID
-- ============================================================================

--- Generate a new task ID
---@return string 14-digit timestamp ID
function M.generate_task_id()
  return os.date("%Y%m%d%H%M%S")
end

-- ============================================================================
-- FILE UTILITIES
-- ============================================================================

--- Ensure a file exists with header
---@param path string File path
---@param title string|nil Title for header
function M.ensure_file(path, title)
  local f = io.open(vim.fn.expand(path), "r")
  if f then
    f:close()
    return
  end
  
  title = title or vim.fn.fnamemodify(path, ":t:r")
  local header = {
    "#+TITLE: " .. title,
    "#+FILETAGS: :gtd:",
    "",
  }
  
  M.write_file(path, header)
end

--- Write lines to file
---@param path string File path
---@param lines table Array of lines
---@return boolean success
function M.write_file(path, lines)
  local expanded = vim.fn.expand(path)
  local dir = vim.fn.fnamemodify(expanded, ":h")
  vim.fn.mkdir(dir, "p")
  
  local f = io.open(expanded, "w")
  if not f then return false end
  
  for _, line in ipairs(lines) do
    f:write(line .. "\n")
  end
  f:close()
  return true
end

--- Append lines to file
---@param path string File path
---@param lines table Array of lines
---@return boolean success
function M.append_file(path, lines)
  local expanded = vim.fn.expand(path)
  
  -- Ensure file exists
  M.ensure_file(path)
  
  local f = io.open(expanded, "a")
  if not f then return false end
  
  -- Add blank line before new entry
  f:write("\n")
  for _, line in ipairs(lines) do
    f:write(line .. "\n")
  end
  f:close()
  return true
end

-- ============================================================================
-- TASK BUILDING
-- ============================================================================

--- Build a GTD-SPEC compliant task entry
---@param ctx table Capture context
---@return table lines, string task_id
function M.build_task(ctx)
  local lines = {}
  local id = ctx.task_id or M.generate_task_id()
  local stars = string.rep("*", ctx.level or 1)
  
  -- Heading
  local heading = string.format("%s %s %s", stars, ctx.state or "TODO", ctx.title)
  if ctx.tags and #ctx.tags > 0 then
    -- Clean tags (remove @ prefix for org tags)
    local clean_tags = {}
    for _, tag in ipairs(ctx.tags) do
      table.insert(clean_tags, tag:gsub("^@", ""))
    end
    heading = heading .. "  :" .. table.concat(clean_tags, ":") .. ":"
  end
  table.insert(lines, heading)
  
  -- Dates (before PROPERTIES per GTD-SPEC)
  if ctx.scheduled then
    table.insert(lines, "SCHEDULED: " .. M.format_active_date(ctx.scheduled))
  end
  if ctx.deadline then
    table.insert(lines, "DEADLINE: " .. M.format_active_date(ctx.deadline))
  end
  
  -- PROPERTIES drawer
  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":TASK_ID:   " .. id)
  table.insert(lines, ":ID:        " .. id)
  table.insert(lines, ":ZK_LINK:   " .. id)
  table.insert(lines, ":CREATED:   " .. M.format_inactive_timestamp())
  
  if ctx.zk_note then
    local note_name = vim.fn.fnamemodify(ctx.zk_note, ":t")
    table.insert(lines, ":ZK_NOTE:   [[file:" .. ctx.zk_note .. "][" .. note_name .. "]]")
  end
  if ctx.reference then
    table.insert(lines, ":REFERENCE: " .. ctx.reference)
  end
  if ctx.area then
    table.insert(lines, ":AREA:      " .. ctx.area)
  end
  if ctx.outcome then
    table.insert(lines, ":OUTCOME:   " .. ctx.outcome)
  end
  
  -- WAITING properties
  if ctx.state == "WAITING" then
    if ctx.waiting_for then
      table.insert(lines, ":WAITING_FOR: " .. ctx.waiting_for)
    end
    table.insert(lines, ":WAITING_SINCE: " .. M.format_inactive_timestamp())
  end
  
  -- Extra properties (contact info, etc.)
  if ctx.extra_props then
    for k, v in pairs(ctx.extra_props) do
      if v and v ~= "" then
        table.insert(lines, string.format(":%s: %s", k, v))
      end
    end
  end
  
  table.insert(lines, ":END:")
  
  -- Body content
  if ctx.outcome then
    table.insert(lines, "")
    table.insert(lines, "Desired outcome: " .. ctx.outcome)
  end
  
  return lines, id
end

--- Build a GTD-SPEC compliant project entry
---@param ctx table Capture context
---@return table lines, string project_id
function M.build_project(ctx)
  local lines = {}
  local id = ctx.task_id or M.generate_task_id()
  
  -- Heading
  local heading = "* PROJECT " .. ctx.title
  if ctx.tags and #ctx.tags > 0 then
    local clean_tags = {}
    for _, tag in ipairs(ctx.tags) do
      table.insert(clean_tags, tag:gsub("^@", ""))
    end
    heading = heading .. "  :" .. table.concat(clean_tags, ":") .. ":"
  end
  table.insert(lines, heading)
  
  -- PROPERTIES drawer
  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":ID:        " .. id)
  table.insert(lines, ":TASK_ID:   " .. id)
  table.insert(lines, ":ZK_LINK:   " .. id)
  table.insert(lines, ":CREATED:   " .. M.format_inactive_timestamp())
  
  if ctx.zk_note then
    local note_name = vim.fn.fnamemodify(ctx.zk_note, ":t")
    table.insert(lines, ":ZK_NOTE:   [[file:" .. ctx.zk_note .. "][" .. note_name .. "]]")
  end
  if ctx.outcome then
    table.insert(lines, ":DESCRIPTION: " .. ctx.outcome)
  end
  if ctx.area then
    table.insert(lines, ":AREA:      " .. ctx.area)
  end
  
  table.insert(lines, ":END:")
  
  -- Outcome as body
  if ctx.outcome then
    table.insert(lines, "")
    table.insert(lines, "Desired outcome: " .. ctx.outcome)
  end
  
  return lines, id
end

return M
