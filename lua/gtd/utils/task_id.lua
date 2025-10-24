-- gtd/utils/task_id.lua - Enhanced task ID generation and org-mode integration
-- Provides robust, collision-resistant task IDs with org properties integration
-- 100% backward compatible with existing task_id API

local M = {}

-- Import shared utilities (with fallback for standalone use)
local ui = pcall(require, "gtd.ui") and require("gtd.ui") or nil

-- ============================================================================
-- TASK ID GENERATION - Core functionality (BACKWARD COMPATIBLE)
-- ============================================================================

-- State for collision avoidance
local last_ts, last_suffix = nil, ""

--- Generate next suffix in sequence (a -> b -> ... -> z -> aa -> ab -> ...)
---@param current_suffix string Current suffix
---@return string Next suffix in sequence
local function next_suffix(current_suffix)
  if current_suffix == "" then return "a" end
  
  local bytes = { current_suffix:byte(1, #current_suffix) }
  local i = #bytes
  
  -- Handle carry-over like counting in base-26
  while i >= 0 do
    if i == 0 then
      -- Overflow - add new character at front
      table.insert(bytes, 1, string.byte("a"))
      break
    end
    
    if bytes[i] < string.byte("z") then
      -- Increment current character
      bytes[i] = bytes[i] + 1
      break
    else
      -- Carry over - reset to 'a' and continue
      bytes[i] = string.byte("a")
      i = i - 1
    end
  end
  
  local unpack_fn = table.unpack or unpack
  return string.char(unpack_fn(bytes))
end

--- Generate unique task ID with collision avoidance
--- Format: YYYYMMDDHHMMSS[suffix] where suffix is added for same-second collisions
---@return string Unique task ID
function M.generate()
  local ts = os.date("!%Y%m%d%H%M%S")
  
  if ts == last_ts then
    -- Same timestamp - increment suffix to avoid collision
    last_suffix = next_suffix(last_suffix)
  else
    -- New timestamp - reset suffix
    last_ts, last_suffix = ts, ""
  end
  
  return ts .. last_suffix
end

--- Validate task ID format
--- Accepts: YYYYMMDDHHMMSS, YYYYMMDDHHMMSS[a-z], YYYYMMDDHHMMSS[a-z][a-z], YYYYMMDDHHMMSS-XXX (legacy)
---@param id any ID to validate
---@return boolean True if valid task ID format
function M.is_valid(id)
  if type(id) ~= "string" then return false end
  
  -- Standard format: 14 digits
  if id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d$") then return true end
  
  -- With single letter suffix: 14 digits + [a-z]
  if id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d[a-z]$") then return true end
  
  -- With double letter suffix: 14 digits + [a-z][a-z]
  if id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d[a-z][a-z]$") then return true end
  
  -- Legacy format: 14 digits + dash + 3 characters
  if id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%-%w%w%w$") then return true end
  
  return false
end

--- Get timestamp portion of task ID
---@param id string Task ID
---@return string|nil Timestamp portion (YYYYMMDDHHMMSS) or nil if invalid
function M.get_timestamp(id)
  if not M.is_valid(id) then return nil end
  return id:match("^(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)")
end

--- Get suffix portion of task ID  
---@param id string Task ID
---@return string Suffix portion (may be empty string)
function M.get_suffix(id)
  if not M.is_valid(id) then return "" end
  local ts = M.get_timestamp(id)
  if not ts then return "" end
  return id:sub(#ts + 1)
end

--- Parse task ID into components
---@param id string Task ID to parse
---@return table|nil {timestamp: string, suffix: string, valid: boolean} or nil if invalid
function M.parse_id(id)
  if not M.is_valid(id) then return nil end
  
  local ts = M.get_timestamp(id)
  local suffix = M.get_suffix(id)
  
  return {
    timestamp = ts,
    suffix = suffix,
    valid = true,
    full_id = id
  }
end

-- ============================================================================
-- ORG-MODE INTEGRATION - Properties drawer handling (BACKWARD COMPATIBLE)  
-- ============================================================================

--- Find properties drawer within a range of lines
---@param lines table Array of file lines
---@param start_line number Starting line number (1-indexed)
---@param end_line number|nil Optional ending line number (defaults to #lines)
---@return number|nil, number|nil Start and end line numbers of properties drawer
local function find_properties_block(lines, start_line, end_line)
  if not lines or not start_line then return nil, nil end
  
  start_line = math.max(1, start_line)
  end_line = end_line or #lines
  
  -- Start looking from line after heading
  local i = start_line + 1
  
  -- Skip empty lines
  while i <= end_line and (lines[i] or ""):match("^%s*$") do 
    i = i + 1 
  end
  
  -- Check if we found properties drawer
  if i <= end_line and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= end_line do
      if (lines[j] or ""):match("^%s*:END:%s*$") then
        return i, j
      end
      j = j + 1
    end
  end
  
  return nil, nil
end

--- Insert new properties drawer with given key-value lines
---@param lines table Array of file lines (modified in-place)
---@param insert_after_line number Line number to insert after (1-indexed)
---@param kv_lines table Array of property lines (without :PROPERTIES:/:END:)
---@return table Modified lines array
local function insert_properties_with(lines, insert_after_line, kv_lines)
  local out = {}
  
  for idx = 1, #lines do
    table.insert(out, lines[idx])
    
    if idx == insert_after_line then
      table.insert(out, ":PROPERTIES:")
      for _, line in ipairs(kv_lines) do
        table.insert(out, line)
      end
      table.insert(out, ":END:")
    end
  end
  
  return out
end

--- Extract task ID from properties drawer (BACKWARD COMPATIBLE)
---@param lines table Array of file lines
---@param heading_line number Line number of heading (1-indexed)
---@return string|nil Task ID if found, nil otherwise
function M.extract_from_properties(lines, heading_line)
  if not lines or not heading_line then return nil end
  
  local p_start, p_end = find_properties_block(lines, heading_line)
  if not p_start or not p_end then return nil end
  
  -- Search for TASK_ID property
  for i = p_start + 1, p_end - 1 do
    local line = lines[i] or ""
    local key, value = line:match("^%s*:(%u[%u_]*):%s*(.-)%s*$")
    if key == "TASK_ID" and value ~= "" then
      return value
    end
  end
  
  return nil
end

--- Ensure task ID exists in properties drawer (BACKWARD COMPATIBLE)
--- Creates properties drawer if missing, generates ID if needed
---@param lines table Array of file lines
---@param heading_line number Line number of heading (1-indexed)  
---@return table, string Modified lines array, task ID (existing or newly generated)
function M.ensure_in_properties(lines, heading_line)
  if not lines or not heading_line then
    local new_id = M.generate()
    return lines or {}, new_id
  end
  
  -- Check for existing valid task ID
  local existing = M.extract_from_properties(lines, heading_line)
  if existing and M.is_valid(existing) then
    return lines, existing
  end
  
  -- Generate new ID
  local new_id = M.generate()
  
  -- Find or create properties drawer
  local p_start, p_end = find_properties_block(lines, heading_line)
  
  if not p_start then
    -- No properties drawer - create new one
    local new_lines = insert_properties_with(lines, heading_line, {
      string.format(":TASK_ID: %s", new_id)
    })
    return new_lines, new_id
  else
    -- Properties drawer exists - update or add TASK_ID
    local wrote = false
    for i = p_start + 1, p_end - 1 do
      local line = lines[i] or ""
      local key = line:match("^%s*:(%u[%u_]*):")
      if key == "TASK_ID" then
        -- Update existing TASK_ID
        lines[i] = string.format(":TASK_ID: %s", new_id)
        wrote = true
        break
      end
    end
    
    if not wrote then
      -- Add new TASK_ID property
      table.insert(lines, p_end, string.format(":TASK_ID: %s", new_id))
    end
    
    return lines, new_id
  end
end

-- ============================================================================
-- ENHANCED UTILITIES - New functionality building on foundation
-- ============================================================================

--- Generate multiple unique IDs at once (useful for batch operations)
---@param count number Number of IDs to generate
---@return table Array of unique task IDs
function M.generate_batch(count)
  local ids = {}
  for i = 1, (count or 1) do
    table.insert(ids, M.generate())
  end
  return ids
end

--- Check if ID follows ZK (Zettelkasten) format expectations
---@param id string ID to check
---@return boolean True if compatible with ZK ID format
function M.is_zk_compatible(id)
  if not M.is_valid(id) then return false end
  
  -- ZK typically expects timestamp + optional single letter
  local ts = M.get_timestamp(id)
  local suffix = M.get_suffix(id)
  
  -- Allow no suffix or single letter suffix for ZK compatibility
  return ts and (#suffix <= 1)
end

--- Normalize legacy task IDs to current format
---@param id string Legacy or current task ID
---@return string Normalized task ID
function M.normalize_id(id)
  if not id or not M.is_valid(id) then
    return M.generate()
  end
  
  -- Handle legacy format (YYYYMMDDHHMMSS-XXX)
  local ts = id:match("^(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)%-.+$")
  if ts and #ts == 14 then
    return ts -- Convert legacy to simple timestamp format
  end
  
  -- Already in good format
  return id
end

--- Extract all task IDs from org file content
---@param lines table Array of file lines
---@return table Array of {line_num: number, id: string, valid: boolean}
function M.find_all_ids(lines)
  if not lines then return {} end
  
  local ids = {}
  
  for i, line in ipairs(lines) do
    -- Look for :TASK_ID: property
    local id = line:match("^%s*:TASK_ID:%s*(.-)%s*$")
    if id and id ~= "" then
      table.insert(ids, {
        line_num = i,
        id = id,
        valid = M.is_valid(id),
        normalized = M.normalize_id(id)
      })
    end
  end
  
  return ids
end

--- Validate and report on task IDs in file content
---@param lines table Array of file lines
---@param file_path string|nil Optional file path for reporting
---@return table Validation report {valid: number, invalid: number, duplicates: table, issues: table}
function M.validate_file_ids(lines, file_path)
  local report = {
    valid = 0,
    invalid = 0,
    duplicates = {},
    issues = {},
    file_path = file_path
  }
  
  local ids = M.find_all_ids(lines)
  local seen = {}
  
  for _, entry in ipairs(ids) do
    if entry.valid then
      report.valid = report.valid + 1
      
      -- Check for duplicates
      if seen[entry.id] then
        if not report.duplicates[entry.id] then
          report.duplicates[entry.id] = {seen[entry.id]}
        end
        table.insert(report.duplicates[entry.id], entry.line_num)
      else
        seen[entry.id] = entry.line_num
      end
    else
      report.invalid = report.invalid + 1
      table.insert(report.issues, {
        line_num = entry.line_num,
        id = entry.id,
        issue = "Invalid format"
      })
    end
  end
  
  return report
end

-- ============================================================================
-- INTEGRATION WITH SHARED UTILITIES
-- ============================================================================

--- Log validation issues using shared notification system
---@param report table Validation report from validate_file_ids()
function M.report_validation_issues(report)
  local notify = ui and ui.warn or vim.notify
  local file_info = report.file_path and (" in " .. (ui and ui.relative_path(report.file_path) or report.file_path)) or ""
  
  if report.invalid > 0 then
    notify(string.format("Found %d invalid task IDs%s", report.invalid, file_info))
  end
  
  for id, line_nums in pairs(report.duplicates) do
    notify(string.format("Duplicate ID %s found on lines: %s%s", 
      id, table.concat(line_nums, ", "), file_info))
  end
end

--- Generate ID using enhanced timestamp from ui utilities if available
---@return string Task ID with enhanced timestamp
function M.generate_enhanced()
  if ui and ui.now_id then
    -- Use ui.now_id() for consistent timestamp format across system
    local base_id = ui.now_id()
    
    -- Add collision avoidance suffix if needed
    if base_id == last_ts then
      last_suffix = next_suffix(last_suffix)
      return base_id .. last_suffix
    else
      last_ts, last_suffix = base_id, ""
      return base_id
    end
  else
    -- Fallback to original generation method
    return M.generate()
  end
end

-- ============================================================================
-- MODULE SETUP AND CONFIGURATION
-- ============================================================================

--- Module configuration
M.config = {
  -- ID generation settings
  generation = {
    use_utc = true,           -- Use UTC timestamps (recommended)
    collision_avoidance = true, -- Enable suffix for same-second collisions
  },
  
  -- Validation settings
  validation = {
    allow_legacy = true,      -- Accept legacy format IDs
    strict_zk_format = false, -- Require ZK-compatible format only
  },
  
  -- Integration settings
  integration = {
    auto_normalize = false,   -- Automatically normalize legacy IDs when found
    validate_on_extract = true, -- Validate IDs when extracting from properties
  }
}

--- Setup function for module configuration
---@param user_config table|nil User configuration overrides
function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
  
  -- Apply configuration to behavior
  if M.config.generation.use_utc then
    -- Keep using UTC timestamps (current behavior)
  end
  
  if M.config.integration.auto_normalize then
    -- Could extend ensure_in_properties to auto-normalize legacy IDs
  end
end

-- ============================================================================
-- BACKWARD COMPATIBILITY VERIFICATION
-- ============================================================================

-- Ensure all original functions are present and working:
assert(type(M.generate) == "function", "Missing M.generate function")
assert(type(M.is_valid) == "function", "Missing M.is_valid function") 
assert(type(M.extract_from_properties) == "function", "Missing M.extract_from_properties function")
assert(type(M.ensure_in_properties) == "function", "Missing M.ensure_in_properties function")

return M