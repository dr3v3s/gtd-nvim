-- ============================================================================
-- ORG OBJECT WRITER
-- ============================================================================
-- Converts OrgObject to GTD-SPEC compliant org-mode text.
--
-- @module gtd-nvim.capture.model.writer
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Generate TASK_ID (timestamp-based)
---@return string
local function generate_id()
  return os.date("%Y%m%d%H%M%S")
end

--- Format active timestamp <YYYY-MM-DD Day> or <YYYY-MM-DD Day HH:MM>
---@param date string|table Date string or table
---@param time string|nil Optional time "HH:MM"
---@return string
local function format_active_date(date, time)
  if not date then return nil end
  if type(date) == "table" then
    date = string.format("%04d-%02d-%02d", date.year, date.month, date.day)
  end
  -- Parse date
  local y, m, d = date:match("(%d+)-(%d+)-(%d+)")
  if y and m and d then
    local ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
    local day = os.date("%a", ts)
    if time and time:match("^%d%d:%d%d$") then
      return string.format("<%s %s %s>", date, day, time)
    else
      return string.format("<%s %s>", date, day)
    end
  end
  -- Fallback
  if not date:match("^<") then
    return "<" .. date .. ">"
  end
  return date
end

--- Format inactive timestamp [YYYY-MM-DD Day HH:MM]
---@return string
local function format_inactive_timestamp()
  return os.date("[%Y-%m-%d %a %H:%M]")
end

--- Format ZK note property value
---@param path string Path to ZK note
---@return string
local function format_zk_note(path)
  if not path then return nil end
  local filename = vim.fn.fnamemodify(path, ":t")
  return string.format("[[file:%s][%s]]", path, filename)
end

-- ============================================================================
-- WRITER
-- ============================================================================

--- Convert OrgObject to org-mode text lines
---@param obj table OrgObject
---@param opts table|nil Options { include_children = true }
---@return table lines Array of text lines
---@return string id Generated/existing TASK_ID
function M.to_lines(obj, opts)
  opts = opts or {}
  local lines = {}
  
  -- Ensure ID exists
  local id = obj.id or generate_id()
  obj.id = id
  
  -- ─────────────────────────────────────────────────────────────
  -- HEADING LINE
  -- ─────────────────────────────────────────────────────────────
  local stars = string.rep("*", obj.level or 1)
  local state = obj.state or ""
  local title = obj.title or ""
  
  local heading = string.format("%s %s %s", stars, state, title)
  
  -- Tags
  if obj.tags and #obj.tags > 0 then
    local tag_str = ":" .. table.concat(obj.tags, ":") .. ":"
    heading = heading .. "  " .. tag_str
  end
  
  table.insert(lines, heading)
  
  -- ─────────────────────────────────────────────────────────────
  -- DATES (before PROPERTIES per GTD-SPEC)
  -- ─────────────────────────────────────────────────────────────
  if obj.scheduled then
    table.insert(lines, "SCHEDULED: " .. format_active_date(obj.scheduled, obj.scheduled_time))
  end
  if obj.deadline then
    table.insert(lines, "DEADLINE: " .. format_active_date(obj.deadline, obj.deadline_time))
  end
  if obj.closed then
    table.insert(lines, "CLOSED: " .. format_active_date(obj.closed))
  end
  
  -- ─────────────────────────────────────────────────────────────
  -- PROPERTIES DRAWER
  -- ─────────────────────────────────────────────────────────────
  table.insert(lines, ":PROPERTIES:")
  
  -- Required properties
  table.insert(lines, ":TASK_ID:   " .. id)
  table.insert(lines, ":ID:        " .. id)
  table.insert(lines, ":ZK_LINK:   " .. id)
  table.insert(lines, ":CREATED:   " .. (obj.created or format_inactive_timestamp()))
  
  -- Optional standard properties
  if obj.zk_note then
    table.insert(lines, ":ZK_NOTE:   " .. format_zk_note(obj.zk_note))
  end
  if obj.reference then
    table.insert(lines, ":REFERENCE: " .. obj.reference)
  end
  if obj.outcome then
    table.insert(lines, ":OUTCOME:   " .. obj.outcome)
  end
  
  -- Area
  if obj.area then
    table.insert(lines, ":AREA:      " .. obj.area)
  end
  
  -- Focus Area (for projects)
  if obj.focus then
    table.insert(lines, ":FOCUS:     t")
  end
  
  -- WAITING properties
  if obj.state == "WAITING" then
    if obj.waiting_for then
      table.insert(lines, ":WAITING_FOR: " .. obj.waiting_for)
    end
    table.insert(lines, ":WAITING_SINCE: " .. (obj.waiting_since or format_inactive_timestamp()))
    if obj.waiting_context then
      table.insert(lines, ":WAITING_CONTEXT: " .. obj.waiting_context)
    end
  end
  
  -- Recurring properties
  if obj.recurring then
    table.insert(lines, ":RECURRING: t")
    if obj.frequency then
      table.insert(lines, ":FREQUENCY: " .. obj.frequency)
    end
    if obj.interval then
      table.insert(lines, ":INTERVAL:  " .. tostring(obj.interval))
    end
  end
  
  -- Contact properties (from comms integration)
  if obj.contact then
    if obj.contact.id then
      table.insert(lines, ":CONTACT_ID: " .. obj.contact.id)
    end
    if obj.contact.name then
      table.insert(lines, ":CONTACT_NAME: " .. obj.contact.name)
    end
    if obj.contact.phone then
      table.insert(lines, ":PHONE:     " .. obj.contact.phone)
    end
    if obj.contact.email then
      table.insert(lines, ":EMAIL:     " .. obj.contact.email)
    end
  end
  
  -- Custom properties
  if obj.properties then
    for key, value in pairs(obj.properties) do
      -- Skip already-handled properties
      local skip = { TASK_ID=1, ID=1, ZK_LINK=1, CREATED=1, ZK_NOTE=1, 
                     REFERENCE=1, OUTCOME=1, AREA=1, WAITING_FOR=1,
                     WAITING_SINCE=1, WAITING_CONTEXT=1, RECURRING=1,
                     FREQUENCY=1, INTERVAL=1, CONTACT_ID=1, CONTACT_NAME=1,
                     PHONE=1, EMAIL=1 }
      if not skip[key] and value and value ~= "" then
        local padded = key .. string.rep(" ", math.max(0, 10 - #key))
        table.insert(lines, ":" .. padded .. " " .. tostring(value))
      end
    end
  end
  
  table.insert(lines, ":END:")
  
  -- ─────────────────────────────────────────────────────────────
  -- BODY
  -- ─────────────────────────────────────────────────────────────
  if obj.body and obj.body ~= "" then
    table.insert(lines, "")
    for line in obj.body:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
  end
  
  -- ─────────────────────────────────────────────────────────────
  -- CHILDREN (for projects)
  -- ─────────────────────────────────────────────────────────────
  if opts.include_children ~= false and obj.children and #obj.children > 0 then
    table.insert(lines, "")
    for _, child in ipairs(obj.children) do
      -- Ensure child level is correct
      child.level = (obj.level or 1) + 1
      local child_lines = M.to_lines(child, opts)
      for _, line in ipairs(child_lines) do
        table.insert(lines, line)
      end
      table.insert(lines, "")
    end
  end
  
  return lines, id
end

--- Write object to file
---@param obj table OrgObject
---@param file string Target file path
---@param opts table|nil { append = true, create_if_missing = true }
---@return boolean success
---@return string|nil error
function M.write(obj, file, opts)
  opts = opts or { append = true, create_if_missing = true }
  
  -- Validate
  local valid, err = obj:validate()
  if not valid then
    return false, err
  end
  
  -- Generate lines
  local lines, id = M.to_lines(obj, opts)
  obj.id = id
  
  -- Ensure file exists
  if opts.create_if_missing then
    local expanded = vim.fn.expand(file)
    if vim.fn.filereadable(expanded) == 0 then
      local title = vim.fn.fnamemodify(file, ":t:r")
      local header = { "#+TITLE: " .. title, "" }
      vim.fn.writefile(header, expanded)
    end
  end
  
  -- Write
  local expanded = vim.fn.expand(file)
  if opts.append then
    -- Append to file
    local ok = vim.fn.writefile(lines, expanded, "a")
    return ok == 0, ok ~= 0 and "Failed to append to file" or nil
  else
    -- Overwrite (for editing)
    local ok = vim.fn.writefile(lines, expanded)
    return ok == 0, ok ~= 0 and "Failed to write file" or nil
  end
end

return M
