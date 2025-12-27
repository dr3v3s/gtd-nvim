-- ============================================================================
-- ORG OBJECT MODEL
-- ============================================================================
-- Unified data structure for tasks, projects, and headings.
-- Used by capture, edit, refile, and clarify workflows.
--
-- @module gtd-nvim.capture.model.object
-- @version 1.1.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2025-12-27"

-- ============================================================================
-- OBJECT TYPES
-- ============================================================================

M.TYPE = {
  TASK = "task",
  PROJECT = "project",
  HEADING = "heading",
  NOTE = "note",
}

M.STATE = {
  TODO = "TODO",
  NEXT = "NEXT",
  WAITING = "WAITING",
  SOMEDAY = "SOMEDAY",
  PROJECT = "PROJECT",
  DONE = "DONE",
  CANCELLED = "CANCELLED",
}

M.MODE = {
  CREATE = "create",
  EDIT = "edit",
  BATCH = "batch",
  MOVE = "move",
  CLARIFY = "clarify",
}

-- ============================================================================
-- OBJECT CONSTRUCTOR
-- ============================================================================

--- Create a new OrgObject
---@param type string Object type (task, project, heading, note)
---@param opts table|nil Initial values
---@return table OrgObject
function M.new(type, opts)
  opts = opts or {}
  
  local obj = {
    -- Core identity
    type = type or M.TYPE.TASK,
    id = opts.id or nil,  -- TASK_ID, generated on finalize if nil
    
    -- Content
    state = opts.state or nil,
    title = opts.title or "",
    body = opts.body or "",
    
    -- Dates
    scheduled = opts.scheduled or nil,  -- Defer date
    deadline = opts.deadline or nil,    -- Due date
    closed = opts.closed or nil,        -- Completion date
    created = opts.created or nil,      -- Creation timestamp
    
    -- Organization
    tags = opts.tags or {},             -- Array of tags
    level = opts.level or 1,            -- Heading level (stars)
    
    -- Properties drawer
    properties = opts.properties or {},
    
    -- Relationships
    parent = opts.parent or nil,        -- Parent object reference
    children = opts.children or {},     -- Child objects (for projects)
    
    -- Project-specific
    outcome = opts.outcome or nil,      -- Desired outcome
    
    -- WAITING-specific
    waiting_for = opts.waiting_for or nil,
    waiting_since = opts.waiting_since or nil,
    waiting_context = opts.waiting_context or nil,
    
    -- Recurring-specific
    recurring = opts.recurring or false,
    frequency = opts.frequency or nil,
    interval = opts.interval or nil,
    
    -- Communication-specific (from comms integration)
    contact = opts.contact or nil,
    
    -- Reference/attachment
    reference = opts.reference or nil,
    zk_note = opts.zk_note or nil,
    
    -- Source info (for editing existing objects)
    _source = opts._source or nil,
    -- {
    --   file = "/path/to/file.org",
    --   line = 42,
    --   end_line = 55,
    --   level = 2,
    --   raw = "* TODO Original text...",
    -- }
    
    -- Workflow metadata
    _mode = opts._mode or M.MODE.CREATE,
    _workflow = opts._workflow or nil,
    _step_index = opts._step_index or 0,
    _collected = opts._collected or nil,  -- For batch mode
    _target_file = opts._target_file or nil,  -- Pre-set destination file
  }
  
  return setmetatable(obj, { __index = M })
end

-- ============================================================================
-- OBJECT METHODS
-- ============================================================================

--- Check if object is a task (actionable)
---@param obj table OrgObject
---@return boolean
function M.is_task(obj)
  return obj.type == M.TYPE.TASK
end

--- Check if object is a project
---@param obj table OrgObject
---@return boolean
function M.is_project(obj)
  return obj.type == M.TYPE.PROJECT or obj.state == M.STATE.PROJECT
end

--- Check if object is actionable (not SOMEDAY/DONE/CANCELLED)
---@param obj table OrgObject
---@return boolean
function M.is_actionable(obj)
  return obj.state == M.STATE.TODO 
      or obj.state == M.STATE.NEXT 
      or obj.state == M.STATE.WAITING
end

--- Check if object is complete
---@param obj table OrgObject
---@return boolean
function M.is_complete(obj)
  return obj.state == M.STATE.DONE or obj.state == M.STATE.CANCELLED
end

--- Check if object needs dates (actionable, not SOMEDAY)
---@param obj table OrgObject
---@return boolean
function M.wants_dates(obj)
  return M.is_actionable(obj) and obj.state ~= M.STATE.SOMEDAY
end

--- Check if object is in edit mode
---@param obj table OrgObject
---@return boolean
function M.is_editing(obj)
  return obj._mode == M.MODE.EDIT
end

--- Check if object is in create mode
---@param obj table OrgObject
---@return boolean
function M.is_creating(obj)
  return obj._mode == M.MODE.CREATE or obj._mode == M.MODE.BATCH
end

--- Add a tag
---@param obj table OrgObject
---@param tag string Tag to add (with or without @)
function M.add_tag(obj, tag)
  tag = tag:gsub("^@", "")  -- Normalize: remove @ prefix
  if not vim.tbl_contains(obj.tags, tag) then
    table.insert(obj.tags, tag)
  end
end

--- Remove a tag
---@param obj table OrgObject
---@param tag string Tag to remove
function M.remove_tag(obj, tag)
  tag = tag:gsub("^@", "")
  obj.tags = vim.tbl_filter(function(t) return t ~= tag end, obj.tags)
end

--- Has tag?
---@param obj table OrgObject
---@param tag string Tag to check
---@return boolean
function M.has_tag(obj, tag)
  tag = tag:gsub("^@", "")
  return vim.tbl_contains(obj.tags, tag)
end

--- Set a property
---@param obj table OrgObject
---@param key string Property name
---@param value any Property value
function M.set_property(obj, key, value)
  obj.properties[key] = value
end

--- Get a property
---@param obj table OrgObject
---@param key string Property name
---@return any
function M.get_property(obj, key)
  return obj.properties[key]
end

--- Add a child object (for projects)
---@param obj table Parent OrgObject
---@param child table Child OrgObject
function M.add_child(obj, child)
  child.parent = obj
  child.level = (obj.level or 1) + 1
  table.insert(obj.children, child)
end

--- Convert task to project
---@param obj table OrgObject (task)
---@return table OrgObject (project)
function M.to_project(obj)
  obj.type = M.TYPE.PROJECT
  obj.state = M.STATE.PROJECT
  obj.children = obj.children or {}
  return obj
end

--- Clone an object
---@param obj table OrgObject
---@return table New OrgObject
function M.clone(obj)
  local clone = {}
  for k, v in pairs(obj) do
    if type(v) == "table" and k ~= "_source" and k ~= "parent" then
      clone[k] = vim.deepcopy(v)
    else
      clone[k] = v
    end
  end
  clone._source = nil  -- New object, no source
  return setmetatable(clone, { __index = M })
end

--- Validate object has required fields
---@param obj table OrgObject
---@return boolean valid
---@return string|nil error_message
function M.validate(obj)
  if not obj.title or obj.title == "" then
    return false, "Title is required"
  end
  
  if obj.type == M.TYPE.TASK and not obj.state then
    return false, "State is required for tasks"
  end
  
  if obj.state == M.STATE.WAITING and not obj.waiting_for then
    -- Warning but not error
    vim.notify("WAITING task without WAITING_FOR", vim.log.levels.WARN)
  end
  
  return true, nil
end

-- ============================================================================
-- FACTORY METHODS
-- ============================================================================

--- Create a new task object
---@param title string Task title
---@param state string|nil Task state (default: TODO)
---@return table OrgObject
function M.task(title, state)
  return M.new(M.TYPE.TASK, {
    title = title,
    state = state or M.STATE.TODO,
  })
end

--- Create a new project object
---@param title string Project title
---@param outcome string|nil Desired outcome
---@return table OrgObject
function M.project(title, outcome)
  return M.new(M.TYPE.PROJECT, {
    title = title,
    state = M.STATE.PROJECT,
    outcome = outcome,
  })
end

--- Create object from existing org heading (for editing)
---@param source table Source info { file, line, ... }
---@param data table Parsed heading data
---@return table OrgObject
function M.from_source(source, data)
  local obj = M.new(data.type or M.TYPE.TASK, data)
  obj._source = source
  obj._mode = M.MODE.EDIT
  return obj
end

return M
