-- GTD-NVIM TASK EDITOR
-- ============================================================================
-- Comprehensive task editor for GTD workflow
-- Edit all task properties in a unified interface
--
-- @module gtd-nvim.gtd.editor
-- @version 1.0.0
-- ============================================================================

local M = {}

M._VERSION = "1.0.2"
M._UPDATED = "2024-12-10"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local function safe_require(mod)
  local ok, m = pcall(require, mod)
  return ok and m or nil
end

local shared = safe_require("gtd-nvim.gtd.shared")
local clarify = safe_require("gtd-nvim.gtd.clarify")
local organize = safe_require("gtd-nvim.gtd.organize")
local projects = safe_require("gtd-nvim.gtd.projects")
local areas_mod = safe_require("gtd-nvim.gtd.areas")

-- Glyphs
local g = shared and shared.glyphs or {}
local gs = g.state or {}
local gc = g.container or {}
local gu = g.ui or {}
local gx = g.checkbox or {}
local gp = g.priority or {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.cfg = {
  gtd_root = "~/Documents/GTD",
  id_cache_file = vim.fn.stdpath("data") .. "/gtd/task_id_cache.json",
  left_panel_width = 45,
  zk_root = "~/Documents/Notes/Zettelkasten",
}

-- ============================================================================
-- STATE
-- ============================================================================

M.state = {
  active = false,
  buffers = {},
  original_win = nil,
  original_buf = nil,
  task_data = nil,
  modified = false,
  cursor_field = 1,
}

-- Field definitions for navigation
M.fields = {
  { id = "title",     label = "Title",     editable = true,  type = "text" },
  { id = "state",     label = "State",     editable = true,  type = "select", options = {"TODO", "NEXT", "WAITING", "SOMEDAY", "DONE"} },
  { id = "priority",  label = "Priority",  editable = true,  type = "select", options = {"A", "B", "C", ""} },
  { id = "separator1", label = "─── Location ───", editable = false, type = "separator" },
  { id = "area",      label = "Area",      editable = true,  type = "picker" },
  { id = "project",   label = "Project",   editable = true,  type = "picker" },
  { id = "file",      label = "File",      editable = true,  type = "refile" },
  { id = "separator2", label = "─── Dates ───", editable = false, type = "separator" },
  { id = "scheduled", label = "Scheduled", editable = true,  type = "date" },
  { id = "deadline",  label = "Deadline",  editable = true,  type = "date" },
  { id = "repeat",    label = "Repeat",    editable = true,  type = "select", options = {"", "+1d", "+1w", "+2w", "+1m", ".+1d", ".+1w", ".+1m"} },
  { id = "separator3", label = "─── Identity ───", editable = false, type = "separator" },
  { id = "task_id",   label = "TASK_ID",   editable = false, type = "readonly" },
  { id = "created",   label = "Created",   editable = false, type = "readonly" },
  { id = "tags",      label = "Tags",      editable = true,  type = "tags" },
  { id = "separator4", label = "─── Resources ───", editable = false, type = "separator" },
  { id = "zk_note",   label = "ZK Note",   editable = true,  type = "zk" },
  { id = "waiting_for", label = "Waiting", editable = true,  type = "text" },
}

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function xp(p)
  return p and vim.fn.expand(p) or ""
end

local function read_json(path)
  local f = io.open(xp(path), "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  return ok and data or {}
end

local function write_json(path, data)
  local dir = vim.fn.fnamemodify(xp(path), ":h")
  vim.fn.mkdir(dir, "p")
  local f = io.open(xp(path), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

local function readf(path)
  local lines = vim.fn.readfile(xp(path))
  return type(lines) == "table" and lines or {}
end

local function writef(path, lines)
  vim.fn.writefile(lines, xp(path))
end

local function trim(s)
  return s and s:match("^%s*(.-)%s*$") or ""
end

-- ============================================================================
-- UNIQUE TASK_ID SYSTEM
-- ============================================================================

-- Generate a new unique ID with random suffix
local function generate_id()
  local timestamp = os.date("%Y%m%d%H%M%S")
  local suffix = string.format("%04x", math.random(0, 65535))
  return timestamp .. "-" .. suffix
end

-- Load ID cache
local function load_id_cache()
  return read_json(M.cfg.id_cache_file)
end

-- Save ID cache
local function save_id_cache(cache)
  write_json(M.cfg.id_cache_file, cache)
end

-- Scan all org files for existing TASK_IDs
local function scan_all_task_ids()
  local gtd_root = xp(M.cfg.gtd_root)
  local files = vim.fn.globpath(gtd_root, "**/*.org", false, true)
  if type(files) == "string" then files = { files } end
  
  local ids = {}
  for _, filepath in ipairs(files) do
    local lines = readf(filepath)
    for lnum, line in ipairs(lines) do
      -- Match :TASK_ID: property
      local id = line:match(":TASK_ID:%s*([%d%-]+[%w]*)")
      if id and id ~= "" then
        ids[id] = filepath .. ":" .. lnum
      end
    end
  end
  
  return ids
end

-- Ensure ID is unique, regenerate if collision
function M.ensure_unique_id(current_id, current_file, current_lnum)
  local cache = load_id_cache()
  local ids = cache.ids or {}
  
  -- If cache is stale (older than 1 hour), rescan
  local last_scan = cache.last_scan or 0
  if os.time() - last_scan > 3600 then
    ids = scan_all_task_ids()
    cache.ids = ids
    cache.last_scan = os.time()
    save_id_cache(cache)
  end
  
  -- Check if current ID exists elsewhere
  if current_id and ids[current_id] then
    local existing_loc = ids[current_id]
    local current_loc = current_file .. ":" .. current_lnum
    if existing_loc ~= current_loc then
      -- Collision! Generate new ID
      local new_id = generate_id()
      while ids[new_id] do
        new_id = generate_id()
      end
      vim.notify((gu.warning or "") .. " ID collision detected, generated new: " .. new_id, vim.log.levels.WARN)
      return new_id, true
    end
  end
  
  -- No ID or no collision
  if not current_id or current_id == "" then
    local new_id = generate_id()
    while ids[new_id] do
      new_id = generate_id()
    end
    return new_id, true
  end
  
  return current_id, false
end

-- Update ID cache with new entry
function M.register_id(id, filepath, lnum)
  local cache = load_id_cache()
  cache.ids = cache.ids or {}
  cache.ids[id] = filepath .. ":" .. lnum
  save_id_cache(cache)
end

-- ============================================================================
-- TASK DATA EXTRACTION
-- ============================================================================

-- Extract all metadata from task at cursor
function M.extract_task_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local filepath = vim.api.nvim_buf_get_name(buf)
  
  -- Find heading line (search upward)
  local h_start = lnum
  while h_start >= 1 do
    if lines[h_start] and lines[h_start]:match("^%*+%s") then
      break
    end
    h_start = h_start - 1
  end
  
  if h_start < 1 or not lines[h_start]:match("^%*+%s") then
    return nil, "Not on an org heading"
  end
  
  -- Parse heading line
  local heading = lines[h_start]
  local stars = heading:match("^(%*+)")
  local level = #stars
  
  -- Find heading end (next same-level or higher heading)
  local h_end = h_start
  for i = h_start + 1, #lines do
    local line = lines[i]
    local next_stars = line:match("^(%*+)")
    if next_stars and #next_stars <= level then
      break
    end
    h_end = i
  end
  
  -- Parse state, priority, title
  local rest = heading:sub(#stars + 1)
  local state = rest:match("^%s+([A-Z]+)%s") or ""
  local priority = rest:match("%[#([ABC])%]") or ""
  local title = rest:gsub("^%s+[A-Z]+%s+", ""):gsub("%s*%[#[ABC]%]%s*", ""):gsub("%s*:.*:%s*$", "")
  title = trim(title)
  
  -- Extract inline tags
  local inline_tags = heading:match(":([%w@:_-]+):%s*$") or ""
  
  -- Find properties drawer
  local props = {}
  local props_start, props_end = nil, nil
  for i = h_start + 1, h_end do
    local line = lines[i]
    if line:match("^%s*:PROPERTIES:%s*$") then
      props_start = i
    elseif props_start and line:match("^%s*:END:%s*$") then
      props_end = i
      break
    elseif props_start and not props_end then
      local key, val = line:match("^%s*:([^:]+):%s*(.*)$")
      if key then
        props[key:upper()] = trim(val)
      end
    end
  end
  
  -- Extract dates from heading or body
  local scheduled, deadline, repeat_str = nil, nil, nil
  for i = h_start, math.min(h_start + 5, h_end) do
    local line = lines[i] or ""
    local sched = line:match("SCHEDULED:%s*<([^>]+)>")
    local dead = line:match("DEADLINE:%s*<([^>]+)>")
    if sched then 
      scheduled = sched:match("^[%d%-]+")
      repeat_str = sched:match("(%+[%d%.]+[dwmy])") or repeat_str
    end
    if dead then 
      deadline = dead:match("^[%d%-]+")
      repeat_str = dead:match("(%+[%d%.]+[dwmy])") or repeat_str
    end
  end
  
  -- Extract ZK note link
  local zk_note = nil
  for i = h_start, h_end do
    local line = lines[i] or ""
    local zk = line:match(":ZK_NOTE:%s*%[%[file:([^]]+)%]%]")
    if not zk then
      zk = line:match(":ZK_NOTE:%s*([^%s]+)")
    end
    if zk then
      zk_note = zk
      break
    end
  end
  
  -- Determine area from file path
  local area = nil
  local areas_root = xp("~/Documents/GTD/Areas")
  if filepath:find(areas_root, 1, true) then
    area = filepath:match("/Areas/([^/]+)/")
  end
  
  -- Determine project from :PROJECT: property or file
  local project = props["PROJECT"] or nil
  if not project and filepath:match("/Projects/") then
    project = vim.fn.fnamemodify(filepath, ":t:r")
  end
  
  return {
    -- Location in file
    filepath = filepath,
    h_start = h_start,
    h_end = h_end,
    level = level,
    props_start = props_start,
    props_end = props_end,
    
    -- Core fields
    title = title,
    state = state,
    priority = priority,
    tags = inline_tags,
    
    -- Dates
    scheduled = scheduled,
    deadline = deadline,
    ["repeat"] = repeat_str or "",
    
    -- Identity
    task_id = props["TASK_ID"] or "",
    created = props["CREATED"] or "",
    
    -- Location
    area = area,
    project = project,
    file = vim.fn.fnamemodify(filepath, ":t"),
    
    -- Resources  
    zk_note = zk_note,
    waiting_for = props["WAITING_FOR"] or "",
    
    -- Raw data
    props = props,
    lines = lines,
    heading = heading,
  }, nil
end

-- ============================================================================
-- TASK DATA SAVING
-- ============================================================================

-- Rebuild the org heading and properties from task_data
function M.save_task_data(data)
  if not data or not data.filepath then
    return false, "No task data"
  end
  
  local lines = readf(data.filepath)
  if #lines == 0 then
    return false, "Cannot read file"
  end
  
  -- Ensure unique TASK_ID
  local new_id, id_changed = M.ensure_unique_id(data.task_id, data.filepath, data.h_start)
  if id_changed then
    data.task_id = new_id
  end
  
  -- Build new heading line
  local stars = string.rep("*", data.level)
  local parts = { stars }
  
  if data.state and data.state ~= "" then
    table.insert(parts, data.state)
  end
  
  if data.priority and data.priority ~= "" then
    table.insert(parts, "[#" .. data.priority .. "]")
  end
  
  table.insert(parts, data.title or "Untitled")
  
  if data.tags and data.tags ~= "" then
    -- Ensure tags are properly formatted
    local tags = data.tags:gsub("^:*", ""):gsub(":*$", "")
    if tags ~= "" then
      table.insert(parts, ":" .. tags .. ":")
    end
  end
  
  local new_heading = table.concat(parts, " ")
  lines[data.h_start] = new_heading
  
  -- Build properties to set
  local new_props = {
    TASK_ID = data.task_id,
  }
  
  if data.created and data.created ~= "" then
    new_props.CREATED = data.created
  else
    new_props.CREATED = os.date("%Y-%m-%d")
  end
  
  if data.waiting_for and data.waiting_for ~= "" then
    new_props.WAITING_FOR = data.waiting_for
  end
  
  if data.zk_note and data.zk_note ~= "" then
    new_props.ZK_NOTE = "[[file:" .. data.zk_note .. "]]"
  end
  
  if data.project and data.project ~= "" then
    new_props.PROJECT = data.project
  end
  
  -- Update or create properties drawer
  if data.props_start and data.props_end then
    -- Update existing drawer
    local new_drawer = { ":PROPERTIES:" }
    
    -- Keep existing props, update with new ones
    for i = data.props_start + 1, data.props_end - 1 do
      local key = lines[i]:match("^%s*:([^:]+):")
      if key and not new_props[key:upper()] then
        table.insert(new_drawer, lines[i])
      end
    end
    
    -- Add new/updated props
    for key, val in pairs(new_props) do
      if val and val ~= "" then
        table.insert(new_drawer, ":" .. key .. ": " .. val)
      end
    end
    
    table.insert(new_drawer, ":END:")
    
    -- Replace drawer lines
    local new_lines = {}
    for i = 1, data.props_start - 1 do
      table.insert(new_lines, lines[i])
    end
    for _, line in ipairs(new_drawer) do
      table.insert(new_lines, line)
    end
    for i = data.props_end + 1, #lines do
      table.insert(new_lines, lines[i])
    end
    lines = new_lines
    
  else
    -- Create new properties drawer after heading
    local insert_at = data.h_start + 1
    
    -- Skip SCHEDULED/DEADLINE lines
    while insert_at <= #lines and (lines[insert_at]:match("^%s*SCHEDULED:") or lines[insert_at]:match("^%s*DEADLINE:")) do
      insert_at = insert_at + 1
    end
    
    local drawer = { ":PROPERTIES:" }
    for key, val in pairs(new_props) do
      if val and val ~= "" then
        table.insert(drawer, ":" .. key .. ": " .. val)
      end
    end
    table.insert(drawer, ":END:")
    
    -- Insert drawer
    local new_lines = {}
    for i = 1, insert_at - 1 do
      table.insert(new_lines, lines[i])
    end
    for _, line in ipairs(drawer) do
      table.insert(new_lines, line)
    end
    for i = insert_at, #lines do
      table.insert(new_lines, lines[i])
    end
    lines = new_lines
  end
  
  -- Handle SCHEDULED/DEADLINE
  -- Find or create the date line after heading
  local date_line_idx = nil
  for i = data.h_start + 1, math.min(data.h_start + 3, #lines) do
    if lines[i]:match("SCHEDULED:") or lines[i]:match("DEADLINE:") then
      date_line_idx = i
      break
    end
  end
  
  local date_parts = {}
  if data.scheduled and data.scheduled ~= "" then
    local sched_str = data.scheduled
    if data["repeat"] and data["repeat"] ~= "" then
      sched_str = sched_str .. " " .. data["repeat"]
    end
    table.insert(date_parts, "SCHEDULED: <" .. sched_str .. ">")
  end
  if data.deadline and data.deadline ~= "" then
    local dead_str = data.deadline
    if data["repeat"] and data["repeat"] ~= "" and not data.scheduled then
      dead_str = dead_str .. " " .. data["repeat"]
    end
    table.insert(date_parts, "DEADLINE: <" .. dead_str .. ">")
  end
  
  if #date_parts > 0 then
    local date_line = table.concat(date_parts, " ")
    if date_line_idx then
      lines[date_line_idx] = date_line
    else
      -- Insert after heading
      table.insert(lines, data.h_start + 1, date_line)
    end
  elseif date_line_idx then
    -- Remove existing date line if no dates
    table.remove(lines, date_line_idx)
  end
  
  -- Write file
  writef(data.filepath, lines)
  
  -- Register ID in cache
  M.register_id(data.task_id, data.filepath, data.h_start)
  
  return true, nil
end

-- ============================================================================
-- UI RENDERING
-- ============================================================================

local function setup_highlights()
  local hl = vim.api.nvim_set_hl
  
  -- Catppuccin Mocha colors
  hl(0, "GtdEditorTitle", { fg = "#cba6f7", bold = true })
  hl(0, "GtdEditorLabel", { fg = "#a6adc8" })
  hl(0, "GtdEditorValue", { fg = "#cdd6f4" })
  hl(0, "GtdEditorSeparator", { fg = "#585b70" })
  hl(0, "GtdEditorCursor", { fg = "#f5c2e7", bold = true })
  hl(0, "GtdEditorReadonly", { fg = "#6c7086", italic = true })
  hl(0, "GtdEditorModified", { fg = "#f9e2af" })
  hl(0, "GtdEditorHint", { fg = "#6c7086", italic = true })
  
  -- State colors
  hl(0, "GtdEditorNEXT", { fg = "#f7c67f", bold = true })
  hl(0, "GtdEditorTODO", { fg = "#89b4fa" })
  hl(0, "GtdEditorWAITING", { fg = "#fab387" })
  hl(0, "GtdEditorSOMEDAY", { fg = "#a6adc8" })
  hl(0, "GtdEditorDONE", { fg = "#a6e3a1" })
  
  -- Priority colors
  hl(0, "GtdEditorPrioA", { fg = "#f38ba8", bold = true })
  hl(0, "GtdEditorPrioB", { fg = "#f9e2af" })
  hl(0, "GtdEditorPrioC", { fg = "#a6e3a1" })
end

local function render_left()
  local buf = M.state.buffers.left
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local data = M.state.task_data
  if not data then return end
  
  local lines = {}
  local highlights = {}
  
  -- Header
  table.insert(lines, "")
  table.insert(lines, "  " .. (gu.edit or "") .. " Task Editor")
  table.insert(highlights, { line = #lines - 1, hl = "GtdEditorTitle" })
  
  if M.state.modified then
    table.insert(lines, "  " .. (gu.warning or "") .. " Modified")
    table.insert(highlights, { line = #lines - 1, hl = "GtdEditorModified" })
  end
  table.insert(lines, "")
  
  -- Fields
  for i, field in ipairs(M.fields) do
    local is_current = i == M.state.cursor_field
    local cursor = is_current and (gu.arrow_right or "▶") or " "
    
    if field.type == "separator" then
      table.insert(lines, "  " .. field.label)
      table.insert(highlights, { line = #lines - 1, hl = "GtdEditorSeparator" })
    else
      local value = data[field.id] or ""
      if value == "" then value = "(none)" end
      
      -- Truncate long values
      if #value > 25 then
        value = value:sub(1, 22) .. "..."
      end
      
      local line = string.format(" %s %-12s %s", cursor, field.label, value)
      table.insert(lines, line)
      
      if is_current then
        table.insert(highlights, { line = #lines - 1, hl = "GtdEditorCursor" })
      elseif not field.editable then
        table.insert(highlights, { line = #lines - 1, hl = "GtdEditorReadonly" })
      elseif field.id == "state" and data.state then
        table.insert(highlights, { line = #lines - 1, hl = "GtdEditor" .. data.state })
      end
    end
  end
  
  -- Footer
  table.insert(lines, "")
  table.insert(lines, "  ─── Shortcuts ───")
  table.insert(highlights, { line = #lines - 1, hl = "GtdEditorSeparator" })
  table.insert(lines, "  j/k     Navigate")
  table.insert(lines, "  Enter   Edit field")
  table.insert(lines, "  s       Save")
  table.insert(lines, "  q       Cancel")
  table.insert(lines, "")
  table.insert(lines, "  Ctrl-Z  Create ZK note")
  table.insert(lines, "  Ctrl-R  Refile")
  table.insert(lines, "  Ctrl-P  Link project")
  table.insert(lines, "  Ctrl-A  Change area")
  
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  
  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("gtd_editor_left")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, h.hl, h.line, 0, -1)
  end
end

local function render_right()
  local buf = M.state.buffers.right
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local data = M.state.task_data
  if not data then return end
  
  local lines = {}
  
  -- Preview header
  table.insert(lines, "")
  table.insert(lines, "  " .. (gu.list or "") .. " Preview")
  table.insert(lines, "")
  
  -- Show the reconstructed org heading
  local stars = string.rep("*", data.level or 1)
  local preview_heading = stars
  if data.state and data.state ~= "" then
    preview_heading = preview_heading .. " " .. data.state
  end
  if data.priority and data.priority ~= "" then
    preview_heading = preview_heading .. " [#" .. data.priority .. "]"
  end
  preview_heading = preview_heading .. " " .. (data.title or "Untitled")
  if data.tags and data.tags ~= "" then
    preview_heading = preview_heading .. " :" .. data.tags:gsub("^:*", ""):gsub(":*$", "") .. ":"
  end
  
  table.insert(lines, "  " .. preview_heading)
  table.insert(lines, "")
  
  -- Dates
  if data.scheduled or data.deadline then
    local date_line = " "
    if data.scheduled then
      date_line = date_line .. " SCHEDULED: <" .. data.scheduled
      if data["repeat"] and data["repeat"] ~= "" then
        date_line = date_line .. " " .. data["repeat"]
      end
      date_line = date_line .. ">"
    end
    if data.deadline then
      date_line = date_line .. " DEADLINE: <" .. data.deadline .. ">"
    end
    table.insert(lines, date_line)
    table.insert(lines, "")
  end
  
  -- Properties preview
  table.insert(lines, "  :PROPERTIES:")
  table.insert(lines, "  :TASK_ID: " .. (data.task_id or "(will generate)"))
  if data.created and data.created ~= "" then
    table.insert(lines, "  :CREATED: " .. data.created)
  end
  if data.waiting_for and data.waiting_for ~= "" then
    table.insert(lines, "  :WAITING_FOR: " .. data.waiting_for)
  end
  if data.zk_note and data.zk_note ~= "" then
    table.insert(lines, "  :ZK_NOTE: [[file:" .. data.zk_note .. "]]")
  end
  if data.project and data.project ~= "" then
    table.insert(lines, "  :PROJECT: " .. data.project)
  end
  table.insert(lines, "  :END:")
  
  -- File info
  table.insert(lines, "")
  table.insert(lines, "  ─── Location ───")
  table.insert(lines, "  File: " .. (data.file or "?"))
  if data.area then
    table.insert(lines, "  Area: " .. data.area)
  end
  if data.h_start then
    table.insert(lines, "  Line: " .. data.h_start .. "-" .. data.h_end)
  end
  
  -- Current field help
  table.insert(lines, "")
  table.insert(lines, "  ─── Help ───")
  local field = M.fields[M.state.cursor_field]
  if field then
    if field.type == "separator" then
      table.insert(lines, "  (section header)")
    elseif field.type == "readonly" then
      table.insert(lines, "  Read-only field")
    elseif field.type == "select" then
      table.insert(lines, "  Options: " .. table.concat(field.options or {}, ", "))
    elseif field.type == "date" then
      table.insert(lines, "  Format: YYYY-MM-DD")
    elseif field.type == "zk" then
      table.insert(lines, "  Ctrl-Z to create/link")
    elseif field.type == "refile" then
      table.insert(lines, "  Ctrl-R to refile")
    elseif field.type == "picker" then
      table.insert(lines, "  Enter to select")
    else
      table.insert(lines, "  Enter to edit")
    end
  end
  
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  
  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("gtd_editor_right")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "GtdEditorTitle", 1, 0, -1)
end

local function refresh_ui()
  render_left()
  render_right()
end

-- ============================================================================
-- NAVIGATION
-- ============================================================================

function M.nav_down()
  local new_pos = M.state.cursor_field + 1
  -- Skip separators
  while new_pos <= #M.fields and M.fields[new_pos].type == "separator" do
    new_pos = new_pos + 1
  end
  if new_pos <= #M.fields then
    M.state.cursor_field = new_pos
    refresh_ui()
  end
end

function M.nav_up()
  local new_pos = M.state.cursor_field - 1
  -- Skip separators
  while new_pos >= 1 and M.fields[new_pos].type == "separator" do
    new_pos = new_pos - 1
  end
  if new_pos >= 1 then
    M.state.cursor_field = new_pos
    refresh_ui()
  end
end

-- ============================================================================
-- FIELD EDITING
-- ============================================================================

function M.edit_current_field()
  local field = M.fields[M.state.cursor_field]
  if not field or not field.editable then
    vim.notify("This field is read-only", vim.log.levels.INFO)
    return
  end
  
  local data = M.state.task_data
  
  if field.type == "text" then
    vim.ui.input({
      prompt = field.label .. ": ",
      default = data[field.id] or "",
    }, function(input)
      if input ~= nil then
        data[field.id] = input
        M.state.modified = true
        refresh_ui()
      end
    end)
    
  elseif field.type == "select" then
    local fzf = safe_require("fzf-lua")
    if fzf then
      fzf.fzf_exec(field.options, {
        prompt = field.label .. "> ",
        winopts = { height = 0.30, width = 0.40, row = 0.20 },
        actions = {
          ["default"] = function(sel)
            if sel and sel[1] then
              data[field.id] = sel[1]
              M.state.modified = true
              refresh_ui()
            end
          end,
        },
      })
    else
      vim.ui.select(field.options, { prompt = field.label }, function(choice)
        if choice then
          data[field.id] = choice
          M.state.modified = true
          refresh_ui()
        end
      end)
    end
    
  elseif field.type == "date" then
    vim.ui.input({
      prompt = field.label .. " (YYYY-MM-DD): ",
      default = data[field.id] or "",
    }, function(input)
      if input ~= nil then
        -- Validate date format
        if input == "" or input:match("^%d%d%d%d%-%d%d%-%d%d$") then
          data[field.id] = input
          M.state.modified = true
          refresh_ui()
        else
          vim.notify("Invalid date format. Use YYYY-MM-DD", vim.log.levels.WARN)
        end
      end
    end)
    
  elseif field.type == "tags" then
    vim.ui.input({
      prompt = "Tags (colon-separated, e.g., @home:@errands): ",
      default = data[field.id] or "",
    }, function(input)
      if input ~= nil then
        data[field.id] = input
        M.state.modified = true
        refresh_ui()
      end
    end)
    
  elseif field.type == "picker" then
    if field.id == "area" then
      M.pick_area()
    elseif field.id == "project" then
      M.pick_project()
    end
    
  elseif field.type == "zk" then
    M.create_or_open_zk()
    
  elseif field.type == "refile" then
    M.refile_task()
  end
end

-- ============================================================================
-- PICKERS
-- ============================================================================

function M.pick_area()
  local areas = areas_mod and areas_mod.areas or {}
  local options = { "(none)" }
  for _, a in ipairs(areas) do
    table.insert(options, a.name)
  end
  
  local fzf = safe_require("fzf-lua")
  if fzf then
    fzf.fzf_exec(options, {
      prompt = "Area> ",
      winopts = { height = 0.40, width = 0.50, row = 0.20 },
      actions = {
        ["default"] = function(sel)
          if sel and sel[1] then
            local choice = sel[1]
            M.state.task_data.area = choice == "(none)" and nil or choice
            M.state.modified = true
            refresh_ui()
          end
        end,
      },
    })
  end
end

function M.pick_project()
  -- Get list of projects
  local gtd_root = xp(M.cfg.gtd_root)
  local project_files = vim.fn.globpath(gtd_root .. "/Projects", "*.org", false, true)
  local area_projects = vim.fn.globpath(gtd_root .. "/Areas", "*/*.org", false, true)
  
  if type(project_files) == "string" then project_files = { project_files } end
  if type(area_projects) == "string" then area_projects = { area_projects } end
  
  local options = { "(none)" }
  for _, f in ipairs(project_files) do
    table.insert(options, vim.fn.fnamemodify(f, ":t:r"))
  end
  for _, f in ipairs(area_projects) do
    table.insert(options, vim.fn.fnamemodify(f, ":t:r"))
  end
  
  local fzf = safe_require("fzf-lua")
  if fzf then
    fzf.fzf_exec(options, {
      prompt = "Project> ",
      winopts = { height = 0.50, width = 0.60, row = 0.15 },
      actions = {
        ["default"] = function(sel)
          if sel and sel[1] then
            local choice = sel[1]
            M.state.task_data.project = choice == "(none)" and nil or choice
            M.state.modified = true
            refresh_ui()
          end
        end,
      },
    })
  end
end

function M.create_or_open_zk()
  local data = M.state.task_data
  
  if data.zk_note and data.zk_note ~= "" then
    -- Open existing
    vim.ui.select({"Open note", "Unlink note", "Cancel"}, {
      prompt = "ZK Note exists",
    }, function(choice)
      if choice == "Open note" then
        M.close()
        vim.cmd("edit " .. xp(data.zk_note))
      elseif choice == "Unlink note" then
        data.zk_note = nil
        M.state.modified = true
        refresh_ui()
      end
    end)
  else
    -- Create new
    vim.ui.select({"Create new ZK note", "Link existing", "Cancel"}, {
      prompt = "ZK Note",
    }, function(choice)
      if choice == "Create new ZK note" then
        local zk_root = xp(M.cfg.zk_root)
        local timestamp = os.date("%Y%m%d%H%M")
        local slug = data.title:lower():gsub("[^%w]+", "-"):sub(1, 30)
        local filename = timestamp .. "-" .. slug .. ".md"
        local filepath = zk_root .. "/" .. filename
        
        -- Create note content
        local content = {
          "# " .. data.title,
          "",
          "Created: " .. os.date("%Y-%m-%d %H:%M"),
          "Task: [[" .. data.filepath .. "]]",
          "",
          "## Notes",
          "",
          "",
        }
        
        vim.fn.mkdir(zk_root, "p")
        vim.fn.writefile(content, filepath)
        
        data.zk_note = filepath
        M.state.modified = true
        refresh_ui()
        vim.notify((gu.note or "󰝗") .. " Created ZK note: " .. filename, vim.log.levels.INFO)
      end
    end)
  end
end

function M.refile_task()
  if not organize then
    vim.notify("Organize module not available", vim.log.levels.WARN)
    return
  end
  
  -- Save changes first
  if M.state.modified then
    local ok, err = M.save_task_data(M.state.task_data)
    if not ok then
      vim.notify("Save failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      return
    end
  end
  
  -- Store task location before closing
  local filepath = M.state.task_data.filepath
  local h_start = M.state.task_data.h_start
  
  -- Close editor
  M.close()
  
  -- Open original file and position cursor
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  pcall(vim.api.nvim_win_set_cursor, 0, { h_start, 0 })
  
  -- Now call refile
  vim.schedule(function()
    if organize.refile_to_project then
      organize.refile_to_project()
    elseif organize.refile_pick_any then
      organize.refile_pick_any()
    else
      vim.notify("No refile function found in organize module", vim.log.levels.WARN)
    end
  end)
end

-- ============================================================================
-- SAVE / CLOSE
-- ============================================================================

function M.save()
  if not M.state.task_data then
    vim.notify("No task data to save", vim.log.levels.WARN)
    return
  end
  
  local ok, err = M.save_task_data(M.state.task_data)
  if ok then
    M.state.modified = false
    vim.notify((gx.checked or "✓") .. " Task saved (ID: " .. M.state.task_data.task_id .. ")", vim.log.levels.INFO)
    refresh_ui()
    
    -- Reload the original buffer (the actual org file) from disk
    if M.state.original_buf and vim.api.nvim_buf_is_valid(M.state.original_buf) then
      -- Check if it's a real file buffer (not scratch)
      local buftype = vim.api.nvim_buf_get_option(M.state.original_buf, "buftype")
      if buftype == "" then
        -- Use checktime to reload if file changed on disk
        vim.api.nvim_buf_call(M.state.original_buf, function()
          vim.cmd("checktime")
        end)
      end
    end
  else
    vim.notify((gu.cross or "✗") .. " Save failed: " .. (err or "unknown"), vim.log.levels.ERROR)
  end
end

function M.close()
  -- Clean up buffers
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  
  M.state.active = false
  M.state.buffers = {}
  M.state.task_data = nil
  M.state.modified = false
  M.state.cursor_field = 1
  
  -- Return to original window
  if M.state.original_win and vim.api.nvim_win_is_valid(M.state.original_win) then
    vim.api.nvim_set_current_win(M.state.original_win)
  end
end

function M.cancel()
  if M.state.modified then
    vim.ui.select({"Discard changes", "Keep editing"}, {
      prompt = "Unsaved changes",
    }, function(choice)
      if choice == "Discard changes" then
        M.close()
      end
    end)
  else
    M.close()
  end
end

function M.save_and_close()
  M.save()
  M.close()
end

-- ============================================================================
-- KEYMAPS
-- ============================================================================

local function setup_keymaps()
  local kopts = { noremap = true, silent = true }
  
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_keymap(buf, "n", "j", ":lua require('gtd-nvim.gtd.editor').nav_down()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "k", ":lua require('gtd-nvim.gtd.editor').nav_up()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<Down>", ":lua require('gtd-nvim.gtd.editor').nav_down()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<Up>", ":lua require('gtd-nvim.gtd.editor').nav_up()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", ":lua require('gtd-nvim.gtd.editor').edit_current_field()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "s", ":lua require('gtd-nvim.gtd.editor').save()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "S", ":lua require('gtd-nvim.gtd.editor').save_and_close()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "q", ":lua require('gtd-nvim.gtd.editor').cancel()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":lua require('gtd-nvim.gtd.editor').cancel()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<C-z>", ":lua require('gtd-nvim.gtd.editor').create_or_open_zk()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<C-r>", ":lua require('gtd-nvim.gtd.editor').refile_task()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<C-p>", ":lua require('gtd-nvim.gtd.editor').pick_project()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<C-a>", ":lua require('gtd-nvim.gtd.editor').pick_area()<CR>", kopts)
    end
  end
end

-- ============================================================================
-- OPEN EDITOR
-- ============================================================================

function M.open()
  if M.state.active then
    vim.notify("Editor already open", vim.log.levels.WARN)
    return
  end
  
  -- Save original position
  M.state.original_win = vim.api.nvim_get_current_win()
  M.state.original_buf = vim.api.nvim_get_current_buf()
  
  -- Extract task data
  local data, err = M.extract_task_at_cursor()
  if not data then
    vim.notify((gu.cross or "✗") .. " " .. (err or "Cannot extract task"), vim.log.levels.ERROR)
    return
  end
  
  M.state.task_data = data
  M.state.active = true
  M.state.modified = false
  M.state.cursor_field = 1
  
  -- Skip to first editable field
  while M.state.cursor_field <= #M.fields and not M.fields[M.state.cursor_field].editable do
    M.state.cursor_field = M.state.cursor_field + 1
  end
  
  -- Setup highlights
  setup_highlights()
  
  -- Create split layout
  vim.cmd("vsplit")
  vim.cmd("wincmd h")
  vim.cmd("vertical resize " .. M.cfg.left_panel_width)
  
  -- Left buffer (editor form)
  local left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(left_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(left_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(left_buf, "GTD-Task-Editor")
  vim.api.nvim_set_current_buf(left_buf)
  M.state.buffers.left = left_buf
  
  -- Right buffer (preview)
  vim.cmd("wincmd l")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(right_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(right_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(right_buf, "GTD-Task-Preview")
  vim.api.nvim_set_current_buf(right_buf)
  M.state.buffers.right = right_buf
  
  -- Setup keymaps and render
  setup_keymaps()
  refresh_ui()
  
  -- Focus left panel
  vim.cmd("wincmd h")
  
  vim.notify((gu.edit or "") .. " Editing: " .. (data.title or "task"), vim.log.levels.INFO)
end

-- ============================================================================
-- SETUP & COMMANDS
-- ============================================================================

function M.setup(user_cfg)
  if user_cfg then
    M.cfg = vim.tbl_deep_extend("force", M.cfg, user_cfg)
  end
  
  -- Ensure cache directory exists
  vim.fn.mkdir(vim.fn.fnamemodify(M.cfg.id_cache_file, ":h"), "p")
  
  -- Create commands
  vim.api.nvim_create_user_command("GtdEdit", function() M.open() end, { desc = "Edit task at cursor" })
  vim.api.nvim_create_user_command("GtdTaskEditor", function() M.open() end, { desc = "Edit task at cursor" })
  vim.api.nvim_create_user_command("GtdEnsureId", function()
    local data, err = M.extract_task_at_cursor()
    if data then
      local new_id, changed = M.ensure_unique_id(data.task_id, data.filepath, data.h_start)
      if changed then
        data.task_id = new_id
        M.save_task_data(data)
        vim.notify("ID assigned: " .. new_id, vim.log.levels.INFO)
      else
        vim.notify("ID already unique: " .. data.task_id, vim.log.levels.INFO)
      end
    else
      vim.notify(err or "No task found", vim.log.levels.WARN)
    end
  end, { desc = "Ensure task has unique ID" })
  
  vim.api.nvim_create_user_command("GtdScanIds", function()
    local ids = scan_all_task_ids()
    local count = vim.tbl_count(ids)
    local cache = { ids = ids, last_scan = os.time() }
    save_id_cache(cache)
    vim.notify("Scanned " .. count .. " task IDs", vim.log.levels.INFO)
  end, { desc = "Scan and cache all task IDs" })
end

return M
