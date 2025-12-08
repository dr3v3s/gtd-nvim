-- gtd/utils/task_id.lua - IMPROVED VERSION
-- Enhanced task ID with TASK_ID-only approach (no redundant ID property)
-- Strict org-mode compliance and robust validation

local M = {}

-- ============================================================================
-- TASK ID GENERATION - Collision-resistant, UTC-based
-- ============================================================================

local last_ts, last_suffix = nil, ""

--- Generate next suffix in sequence (a -> b -> ... -> z -> aa -> ab -> ...)
local function next_suffix(current_suffix)
  if current_suffix == "" then return "a" end
  
  local bytes = { current_suffix:byte(1, #current_suffix) }
  local i = #bytes
  
  while i >= 0 do
    if i == 0 then
      table.insert(bytes, 1, string.byte("a"))
      break
    end
    
    if bytes[i] < string.byte("z") then
      bytes[i] = bytes[i] + 1
      break
    else
      bytes[i] = string.byte("a")
      i = i - 1
    end
  end
  
  local unpack_fn = table.unpack or unpack
  return string.char(unpack_fn(bytes))
end

--- Generate unique task ID with collision avoidance
--- Format: YYYYMMDDHHMMSS[suffix] where suffix is added for same-second collisions
function M.generate()
  local ts = os.date("!%Y%m%d%H%M%S")
  
  if ts == last_ts then
    last_suffix = next_suffix(last_suffix)
  else
    last_ts, last_suffix = ts, ""
  end
  
  return ts .. last_suffix
end

--- Validate task ID format
function M.is_valid(id)
  if type(id) ~= "string" then return false end
  
  -- Standard format: 14 digits
  if id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d$") then return true end
  
  -- With single letter suffix: 14 digits + [a-z]
  if id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d[a-z]$") then return true end
  
  -- With double letter suffix: 14 digits + [a-z][a-z]
  if id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d[a-z][a-z]$") then return true end
  
  -- Legacy format: 14 digits + dash + 3 characters (for backward compat)
  if id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%-%w%w%w$") then return true end
  
  return false
end

--- Get timestamp portion of task ID
function M.get_timestamp(id)
  if not M.is_valid(id) then return nil end
  return id:match("^(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)")
end

--- Get suffix portion of task ID  
function M.get_suffix(id)
  if not M.is_valid(id) then return "" end
  local ts = M.get_timestamp(id)
  if not ts then return "" end
  return id:sub(#ts + 1)
end

--- Parse task ID into components
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
-- ORG-MODE INTEGRATION - TASK_ID ONLY (no redundant ID property)
-- ============================================================================

--- Find properties drawer within a range of lines
local function find_properties_block(lines, start_line, end_line)
  if not lines or not start_line then return nil, nil end
  
  start_line = math.max(1, start_line)
  end_line = end_line or #lines
  
  local i = start_line + 1
  
  -- Skip empty lines and SCHEDULED/DEADLINE lines
  while i <= end_line do
    local line = lines[i] or ""
    if not line:match("^%s*$") and 
       not line:match("^%s*SCHEDULED:") and 
       not line:match("^%s*DEADLINE:") then
      break
    end
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

--- Extract TASK_ID from properties drawer (TASK_ID only, no ID fallback)
function M.extract_from_properties(lines, heading_line)
  if not lines or not heading_line then return nil end
  
  local p_start, p_end = find_properties_block(lines, heading_line)
  if not p_start or not p_end then return nil end
  
  -- Search for TASK_ID property ONLY
  for i = p_start + 1, p_end - 1 do
    local line = lines[i] or ""
    local key, value = line:match("^%s*:(%u[%u_]*):%s*(.-)%s*$")
    if key == "TASK_ID" and value ~= "" then
      return value
    end
  end
  
  return nil
end

--- Ensure TASK_ID exists in properties drawer (creates if missing)
--- IMPORTANT: Uses TASK_ID only, does NOT create :ID: property
function M.ensure_in_properties(lines, heading_line)
  if not lines or not heading_line then
    local new_id = M.generate()
    return lines or {}, new_id
  end
  
  -- Check for existing valid TASK_ID
  local existing = M.extract_from_properties(lines, heading_line)
  if existing and M.is_valid(existing) then
    return lines, existing
  end
  
  -- Generate new ID
  local new_id = M.generate()
  
  -- Find or create properties drawer
  local p_start, p_end = find_properties_block(lines, heading_line)
  
  if not p_start then
    -- No properties drawer - create new one with TASK_ID only
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
-- ENHANCED UTILITIES
-- ============================================================================

--- Generate multiple unique IDs at once
function M.generate_batch(count)
  local ids = {}
  for i = 1, (count or 1) do
    table.insert(ids, M.generate())
  end
  return ids
end

--- Normalize legacy task IDs to current format
function M.normalize_id(id)
  if not id or not M.is_valid(id) then
    return M.generate()
  end
  
  -- Handle legacy format (YYYYMMDDHHMMSS-XXX)
  local ts = id:match("^(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)%-.+$")
  if ts and #ts == 14 then
    return ts
  end
  
  return id
end

--- Extract all TASK_IDs from org file content
function M.find_all_ids(lines)
  if not lines then return {} end
  
  local ids = {}
  
  for i, line in ipairs(lines) do
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

--- Validate and report on TASK_IDs in file content
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
-- DUPLICATE DETECTION ACROSS GTD FILES
-- ============================================================================

--- Scan all GTD org files and build index of TASK_IDs
--- Returns: { [task_id] = { file = path, line = num, title = heading } }
function M.scan_all_task_ids(gtd_root)
  local xp = vim.fn.expand
  local root = xp(gtd_root or "~/Documents/GTD")
  local index = {}
  
  -- Find all .org files recursively
  local find_cmd = string.format("find %q -type f -name '*.org' 2>/dev/null", root)
  local handle = io.popen(find_cmd)
  if not handle then return index end
  
  local files = {}
  for line in handle:lines() do
    table.insert(files, line)
  end
  handle:close()
  
  -- Scan each file for TASK_IDs
  for _, filepath in ipairs(files) do
    local lines = vim.fn.readfile(filepath)
    local current_heading = nil
    local current_heading_line = nil
    
    for i, line in ipairs(lines) do
      -- Track current heading
      local heading_match = line:match("^%*+%s+(.+)")
      if heading_match then
        current_heading = heading_match
        current_heading_line = i
      end
      
      -- Check for TASK_ID property
      local task_id = line:match("^%s*:TASK_ID:%s*(.-)%s*$")
      if task_id and task_id ~= "" then
        if not index[task_id] then
          index[task_id] = {}
        end
        table.insert(index[task_id], {
          file = filepath,
          line = i,
          heading_line = current_heading_line,
          title = current_heading or "(unknown)"
        })
      end
    end
  end
  
  return index
end

--- Check if a TASK_ID already exists in GTD system
--- Returns: nil if unique, or { file, line, title } of existing task
function M.find_duplicate(task_id, gtd_root)
  if not task_id or task_id == "" then return nil end
  
  local index = M.scan_all_task_ids(gtd_root)
  local existing = index[task_id]
  
  if existing and #existing > 0 then
    return existing[1]  -- Return first occurrence
  end
  
  return nil
end

--- Find all duplicates across GTD system
--- Returns: { [task_id] = { {file, line, title}, ... } } for IDs with >1 occurrence
function M.find_all_duplicates(gtd_root)
  local index = M.scan_all_task_ids(gtd_root)
  local duplicates = {}
  
  for task_id, locations in pairs(index) do
    if #locations > 1 then
      duplicates[task_id] = locations
    end
  end
  
  return duplicates
end

--- Check if a title+date combination already exists (fuzzy duplicate detection)
--- Returns: nil if unique, or { file, line, title, task_id } of similar task
function M.find_similar_task(title, gtd_root, opts)
  opts = opts or {}
  local xp = vim.fn.expand
  local root = xp(gtd_root or "~/Documents/GTD")
  
  -- Normalize title for comparison
  local norm_title = title:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  
  -- Find all .org files
  local find_cmd = string.format("find %q -type f -name '*.org' 2>/dev/null", root)
  local handle = io.popen(find_cmd)
  if not handle then return nil end
  
  local files = {}
  for line in handle:lines() do
    -- Optionally skip Archive.org
    if not opts.include_archive and not line:match("Archive%.org$") then
      table.insert(files, line)
    elseif opts.include_archive then
      table.insert(files, line)
    end
  end
  handle:close()
  
  -- Scan for matching titles
  for _, filepath in ipairs(files) do
    local lines = vim.fn.readfile(filepath)
    local current_task_id = nil
    
    for i, line in ipairs(lines) do
      -- Extract heading
      local state, htitle = line:match("^%*+%s+([A-Z]+)%s+(.*)")
      if htitle then
        -- Normalize and compare
        local norm_htitle = htitle:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        -- Remove trailing tags
        norm_htitle = norm_htitle:gsub("%s*:[%w,_@:-]+:%s*$", "")
        
        if norm_htitle == norm_title then
          -- Found matching title - get its TASK_ID if any
          for j = i + 1, math.min(i + 10, #lines) do
            local tid = lines[j]:match("^%s*:TASK_ID:%s*(.-)%s*$")
            if tid then
              current_task_id = tid
              break
            end
            -- Stop at next heading
            if lines[j]:match("^%*+%s") then break end
          end
          
          return {
            file = filepath,
            line = i,
            title = htitle,
            state = state,
            task_id = current_task_id
          }
        end
      end
    end
  end
  
  return nil
end

-- ============================================================================
-- MODULE CONFIGURATION
-- ============================================================================

M.config = {
  generation = {
    use_utc = true,
    collision_avoidance = true,
  },
  validation = {
    allow_legacy = true,
    strict_format = false,
  },
  integration = {
    auto_normalize = false,
    validate_on_extract = true,
    use_task_id_only = true,  -- NEW: Only use TASK_ID, not ID
  }
}

function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
end

-- Backward compatibility verification
assert(type(M.generate) == "function", "Missing M.generate function")
assert(type(M.is_valid) == "function", "Missing M.is_valid function") 
assert(type(M.extract_from_properties) == "function", "Missing M.extract_from_properties function")
assert(type(M.ensure_in_properties) == "function", "Missing M.ensure_in_properties function")

return M
