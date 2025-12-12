-- gtd/utils/sorting.lua — GTD-focused task sorting
-- Provides structured sorting following GTD methodology:
-- 1. INBOX first (needs processing)
-- 2. AREAS (ongoing responsibilities)
-- 3. PROJECTS (outside areas)
-- 4. OTHER (archive, misc)
--
-- Within each category: State priority → Due date → Scheduled → Title

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.cfg = {
  gtd_root = "~/Documents/GTD",
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  areas_dir = "Areas",
  archive_file = "Archive.org",
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Location categories in GTD priority order
M.LOCATION_PRIORITY = {
  inbox = 1,      -- Needs processing first
  area = 2,       -- Ongoing responsibilities
  project = 3,    -- Active projects
  gtd_root = 4,   -- Other GTD files
  archive = 5,    -- Completed/archived
  other = 6,      -- Everything else
}

-- State priorities (lower = higher priority)
M.STATE_PRIORITY = {
  NEXT = 1,       -- Do it now
  TODO = 2,       -- Do it soon
  WAITING = 3,    -- Blocked, needs follow-up
  SOMEDAY = 4,    -- Maybe later
  PROJECT = 5,    -- Project heading
  DONE = 10,      -- Completed
  CANCELLED = 11, -- Cancelled
}

-- Icons for display
M.LOCATION_ICONS = {
  inbox = "📥",
  area = "🏠",
  project = "g.container.projects",
  gtd_root = "📋",
  archive = "📦",
  other = "📄",
}

M.STATE_ICONS = {
  NEXT = "⚡",
  TODO = "📋",
  WAITING = "⏳",
  SOMEDAY = "💭",
  PROJECT = "g.container.projects",
  DONE = "✅",
  CANCELLED = "❌",
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function xp(p) return vim.fn.expand(p or "") end

--- Parse date string to timestamp for comparison
---@param date_str string|nil Date in YYYY-MM-DD format
---@return number|nil Unix timestamp or nil
local function parse_date(date_str)
  if not date_str or date_str == "" then return nil end
  -- Extract just the date part (handle org dates like "2024-01-15 Mon")
  local clean = date_str:match("(%d%d%d%d%-%d%d%-%d%d)")
  if not clean then return nil end
  
  local y, m, d = clean:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if y and m and d then
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
  end
  return nil
end

--- Get days until a date (negative if past)
---@param date_str string|nil Date string
---@return number|nil Days until date
local function days_until(date_str)
  local target = parse_date(date_str)
  if not target then return nil end
  local today = os.time({ 
    year = tonumber(os.date("%Y")), 
    month = tonumber(os.date("%m")), 
    day = tonumber(os.date("%d")) 
  })
  return math.floor((target - today) / 86400)
end

-- ============================================================================
-- LOCATION CLASSIFICATION
-- ============================================================================

--- Classify a file path into GTD location category
---@param path string File path
---@return string Location category key
---@return string|nil Area/project name
---@return string|nil Parent context
function M.classify_location(path)
  if not path or path == "" then
    return "other", nil, nil
  end

  local expanded_root = xp(M.cfg.gtd_root)
  local path_lower = path:lower()
  local filename = vim.fn.fnamemodify(path, ":t")
  local filename_lower = filename:lower()
  local parent_dir = vim.fn.fnamemodify(path, ":h:t")
  local grandparent = vim.fn.fnamemodify(path, ":h:h:t")

  -- Check for archive first (anywhere in path)
  if filename_lower:match("archive") or path_lower:match("/archive") then
    return "archive", nil, nil
  end

  -- Check for inbox
  if filename_lower == M.cfg.inbox_file:lower() or filename_lower == "inbox.org" then
    -- Could be area inbox or main inbox
    if parent_dir:lower() ~= vim.fn.fnamemodify(expanded_root, ":t"):lower() then
      -- It's an area inbox
      return "area", parent_dir, "inbox"
    end
    return "inbox", nil, nil
  end

  -- Check if in Areas directory
  local areas_path = xp(M.cfg.gtd_root) .. "/" .. M.cfg.areas_dir
  if path:find(areas_path, 1, true) then
    -- Extract area name (parent directory)
    return "area", parent_dir, filename:gsub("%.org$", "")
  end

  -- Check if in Projects directory
  local projects_path = xp(M.cfg.gtd_root) .. "/" .. M.cfg.projects_dir
  if path:find(projects_path, 1, true) then
    return "project", filename:gsub("%.org$", ""), nil
  end

  -- Check if in GTD root (but not in Areas/Projects)
  if path:find(expanded_root, 1, true) then
    return "gtd_root", filename:gsub("%.org$", ""), nil
  end

  return "other", filename:gsub("%.org$", ""), nil
end

--- Get location priority value
---@param location string Location category
---@return number Priority value
function M.get_location_priority(location)
  return M.LOCATION_PRIORITY[location] or M.LOCATION_PRIORITY.other
end

-- ============================================================================
-- TASK ENRICHMENT
-- ============================================================================

--- Enrich task item with sorting metadata
---@param item table Task item with path, state, deadline, scheduled
---@return table Enriched item
function M.enrich_item(item)
  if not item then return item end

  -- Classify location
  local location, context_name, sub_context = M.classify_location(item.path)
  item.location = location
  item.location_priority = M.get_location_priority(location)
  item.context_name = context_name
  item.sub_context = sub_context

  -- State priority
  item.state_priority = M.STATE_PRIORITY[item.state] or 5

  -- Date priorities (days until, nil = no date = lower priority)
  item.deadline_days = days_until(item.deadline)
  item.scheduled_days = days_until(item.scheduled)

  -- Effective due date priority (for sorting)
  -- Overdue items get negative values (higher priority)
  -- No date = 9999 (lowest priority within category)
  if item.deadline_days then
    item.due_priority = item.deadline_days
  elseif item.scheduled_days then
    item.due_priority = item.scheduled_days + 1000  -- Scheduled less urgent than deadline
  else
    item.due_priority = 9999
  end

  -- Location icon
  item.location_icon = M.LOCATION_ICONS[location] or "📄"

  -- State icon
  item.state_icon = M.STATE_ICONS[item.state] or ""

  return item
end

-- ============================================================================
-- SORTING FUNCTIONS
-- ============================================================================

--- Compare two items using GTD hierarchy
---@param a table First item (enriched)
---@param b table Second item (enriched)
---@return boolean True if a should come before b
function M.compare_gtd(a, b)
  -- 1. Location priority (inbox → area → project → other)
  if a.location_priority ~= b.location_priority then
    return a.location_priority < b.location_priority
  end

  -- 2. Within same location category, sort by context name (area/project name)
  if a.context_name and b.context_name and a.context_name ~= b.context_name then
    return a.context_name < b.context_name
  end

  -- 3. State priority (NEXT → TODO → WAITING → SOMEDAY)
  if a.state_priority ~= b.state_priority then
    return a.state_priority < b.state_priority
  end

  -- 4. Due date priority (overdue first, then by date, no date last)
  if a.due_priority ~= b.due_priority then
    return a.due_priority < b.due_priority
  end

  -- 5. Title alphabetically as tiebreaker
  return (a.title or "") < (b.title or "")
end

--- Sort tasks using GTD methodology
---@param items table List of task items
---@return table Sorted items
function M.sort_gtd(items)
  -- Enrich all items
  for _, item in ipairs(items) do
    M.enrich_item(item)
  end

  -- Sort using GTD comparison
  table.sort(items, M.compare_gtd)

  return items
end

-- ============================================================================
-- GROUPING FUNCTIONS
-- ============================================================================

--- Group items by location category
---@param items table List of enriched items
---@return table Groups { inbox = {...}, area = {...}, project = {...}, ... }
function M.group_by_location(items)
  local groups = {
    inbox = {},
    area = {},
    project = {},
    gtd_root = {},
    archive = {},
    other = {},
  }

  for _, item in ipairs(items) do
    M.enrich_item(item)
    local loc = item.location or "other"
    if groups[loc] then
      table.insert(groups[loc], item)
    else
      table.insert(groups.other, item)
    end
  end

  -- Sort within each group
  for _, group in pairs(groups) do
    table.sort(group, function(a, b)
      -- Within group: state → due date → title
      if a.state_priority ~= b.state_priority then
        return a.state_priority < b.state_priority
      end
      if a.due_priority ~= b.due_priority then
        return a.due_priority < b.due_priority
      end
      return (a.title or "") < (b.title or "")
    end)
  end

  return groups
end

--- Group area items by area name
---@param items table List of enriched items (area location only)
---@return table Groups keyed by area name
function M.group_by_area(items)
  local areas = {}

  for _, item in ipairs(items) do
    local area_name = item.context_name or "Unknown"
    if not areas[area_name] then
      areas[area_name] = {}
    end
    table.insert(areas[area_name], item)
  end

  -- Sort within each area
  for _, area_items in pairs(areas) do
    table.sort(area_items, function(a, b)
      if a.state_priority ~= b.state_priority then
        return a.state_priority < b.state_priority
      end
      if a.due_priority ~= b.due_priority then
        return a.due_priority < b.due_priority
      end
      return (a.title or "") < (b.title or "")
    end)
  end

  return areas
end

-- ============================================================================
-- DISPLAY FORMATTING
-- ============================================================================

--- Format item for fzf display with GTD context
---@param item table Enriched task item
---@param opts table|nil Display options
---@return string Formatted display string
function M.format_display(item, opts)
  opts = opts or {}
  local parts = {}

  -- Location indicator
  if opts.show_location ~= false then
    table.insert(parts, item.location_icon or "📄")
  end

  -- State indicator
  if item.state_icon and item.state_icon ~= "" then
    table.insert(parts, item.state_icon)
  elseif item.state then
    table.insert(parts, string.format("[%-7s]", item.state))
  end

  -- Title (truncated if needed)
  local title = item.title or "Untitled"
  local max_title = opts.max_title_length or 50
  if #title > max_title then
    title = title:sub(1, max_title - 3) .. "..."
  end
  table.insert(parts, title)

  -- Context (area/project name)
  if opts.show_context ~= false and item.context_name then
    table.insert(parts, "│")
    table.insert(parts, item.context_name)
  end

  -- Due date indicator
  if item.deadline_days then
    local due_str
    if item.deadline_days < 0 then
      due_str = string.format("g.progress.overdue %dd overdue", math.abs(item.deadline_days))
    elseif item.deadline_days == 0 then
      due_str = "🟠 today"
    elseif item.deadline_days == 1 then
      due_str = "🟡 tomorrow"
    elseif item.deadline_days <= 7 then
      due_str = string.format("g.progress.ontime %dd", item.deadline_days)
    else
      due_str = string.format("%dd", item.deadline_days)
    end
    table.insert(parts, "│")
    table.insert(parts, due_str)
  elseif item.scheduled_days and item.scheduled_days <= 0 then
    table.insert(parts, "│")
    table.insert(parts, "⏰ scheduled")
  end

  return table.concat(parts, " ")
end

--- Format grouped items for display with headers
---@param groups table Groups from group_by_location
---@param opts table|nil Display options
---@return table display_lines, table item_map (display → item)
function M.format_grouped_display(groups, opts)
  opts = opts or {}
  local display_lines = {}
  local item_map = {}

  local order = { "inbox", "area", "project", "gtd_root", "other" }
  local headers = {
    inbox = "📥 INBOX - Needs Processing",
    area = "🏠 AREAS - Ongoing Responsibilities",
    project = "g.container.projects PROJECTS - Active Work",
    gtd_root = "📋 GTD - Other Files",
    other = "📄 OTHER",
  }

  for _, loc in ipairs(order) do
    local items = groups[loc]
    if items and #items > 0 then
      -- Add header (non-selectable, will be filtered or styled)
      if opts.show_headers ~= false then
        local header = string.format("─── %s (%d) ───", headers[loc], #items)
        table.insert(display_lines, header)
        -- Header maps to nil (not selectable)
        item_map[header] = nil
      end

      -- Add items
      for _, item in ipairs(items) do
        local display = M.format_display(item, opts)
        table.insert(display_lines, display)
        item_map[display] = item
      end

      -- Add spacing between groups
      if opts.show_headers ~= false then
        table.insert(display_lines, "")
        item_map[""] = nil
      end
    end
  end

  return display_lines, item_map
end

-- ============================================================================
-- FILTERING
-- ============================================================================

--- Filter items by location
---@param items table List of items
---@param locations table List of location keys to include
---@return table Filtered items
function M.filter_by_location(items, locations)
  local location_set = {}
  for _, loc in ipairs(locations) do
    location_set[loc] = true
  end

  return vim.tbl_filter(function(item)
    M.enrich_item(item)
    return location_set[item.location]
  end, items)
end

--- Filter items by state
---@param items table List of items
---@param states table List of state keywords to include
---@return table Filtered items
function M.filter_by_state(items, states)
  local state_set = {}
  for _, s in ipairs(states) do
    state_set[s] = true
  end

  return vim.tbl_filter(function(item)
    return state_set[item.state]
  end, items)
end

--- Filter to exclude completed/archived items
---@param items table List of items
---@return table Filtered active items
function M.filter_active(items)
  return vim.tbl_filter(function(item)
    M.enrich_item(item)
    -- Exclude DONE, CANCELLED, and archived locations
    if item.state == "DONE" or item.state == "CANCELLED" then
      return false
    end
    if item.location == "archive" then
      return false
    end
    return true
  end, items)
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(user_cfg)
  if user_cfg then
    M.cfg = vim.tbl_deep_extend("force", M.cfg, user_cfg)
  end
end

return M
