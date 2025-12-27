-- ~/.config/nvim/lua/gtd/validate.lua
-- Comprehensive input validation for GTD-nvim
--
-- File:    lua/gtd/validate.lua
-- Version: 0.1.0
-- Updated: 2025-12-22
--
-- This module mirrors pkg/validate in Go, providing:
--   - Presence and shape validation
--   - Type correctness
--   - Range and bounds checking
--   - Format and structure validation
--   - Semantic/GTD-specific rules
--   - Contextual safety checks
--   - Cross-field validation

local M = {}
M._VERSION = "0.1.0"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Check if value is empty (nil, empty string, empty table)
---@param value any
---@return boolean
function M.is_empty(value)
  if value == nil then return true end
  if type(value) == "string" then return value == "" end
  if type(value) == "table" then return next(value) == nil end
  return false
end

--- Get length of string or table
---@param value string|table|nil
---@return number
function M.get_length(value)
  if value == nil then return 0 end
  if type(value) == "string" then return #value end
  if type(value) == "table" then return #value end
  return 0
end

--- Trim whitespace from string
---@param s string
---@return string
function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

--------------------------------------------------------------------------------
-- Pattern Definitions
--------------------------------------------------------------------------------

M.patterns = {
  -- TASK_ID: YYYYMMDDHHmmss (14 digits)
  task_id = "^%d%d%d%d%d%d%d%d%d%d%d%d%d%d$",
  
  -- ISO date: YYYY-MM-DD
  iso_date = "^%d%d%d%d%-%d%d%-%d%d$",
  
  -- Org date: <YYYY-MM-DD Day HH:MM>
  org_date = "^<[^>]+>$",
  
  -- Repeater: +1w, .+2d, ++1m
  repeater = "^[.+]+%d*[dwmy]$",
  
  -- Org tag: alphanumeric, underscore, @
  org_tag = "^[%w_@]+$",
  
  -- Slug: lowercase, hyphens
  slug = "^[a-z0-9]+[a-z0-9%-]*$",
  
  -- Safe filename: no path separators
  safe_filename = "^[%w][%w%.%-_]*$",
  
  -- Email (simplified)
  email = "^[%w%.%%%+%-]+@[%w%.%-]+%.[%a][%a]+$",
}

--- GTD states
M.gtd_states = {
  active = { "TODO", "NEXT", "WAITING", "SOMEDAY" },
  complete = { "DONE", "CANCELLED" },
  all = { "TODO", "NEXT", "WAITING", "SOMEDAY", "DONE", "CANCELLED", "PROJECT" },
}

--- Standalone GTD files
M.standalone_files = { "Inbox.org", "Recurring.org", "Tickler.org" }

--------------------------------------------------------------------------------
-- Validator Class
--------------------------------------------------------------------------------

---@class Validator
---@field issues table[]
---@field field string
local Validator = {}
Validator.__index = Validator

--- Create a new validator
---@return Validator
function M.new()
  return setmetatable({
    issues = {},
    field = "",
  }, Validator)
end

--- Set current field context
---@param name string
---@return Validator
function Validator:set_field(name)
  self.field = name
  return self
end

--- Append to current field path
---@param name string
---@return Validator
function Validator:sub_field(name)
  if self.field == "" then
    self.field = name
  else
    self.field = self.field .. "." .. name
  end
  return self
end

--- Add an issue
---@param code string
---@param message string
---@param severity "error"|"warning"|"info"
---@param value any
---@param expected any
---@return Validator
function Validator:add_issue(code, message, severity, value, expected)
  table.insert(self.issues, {
    field = self.field,
    code = code,
    message = message,
    severity = severity,
    value = value,
    expected = expected,
  })
  return self
end

function Validator:error(code, message, value, expected)
  return self:add_issue(code, message, "error", value, expected)
end

function Validator:warning(code, message, value, expected)
  return self:add_issue(code, message, "warning", value, expected)
end

function Validator:info(code, message, value, expected)
  return self:add_issue(code, message, "info", value, expected)
end

--- Check if there are any errors
---@return boolean
function Validator:has_errors()
  for _, issue in ipairs(self.issues) do
    if issue.severity == "error" then
      return true
    end
  end
  return false
end

--- Get validation result
---@return table
function Validator:result()
  return {
    valid = not self:has_errors(),
    issues = self.issues,
  }
end

--------------------------------------------------------------------------------
-- Presence Validators
--------------------------------------------------------------------------------

--- Check value is present (non-nil, non-empty)
function Validator:required(value)
  if M.is_empty(value) then
    self:error("REQUIRED", "field is required", value, "non-empty value")
  end
  return self
end

--- Check presence only when condition is true
function Validator:required_if(value, condition, reason)
  if condition and M.is_empty(value) then
    self:error("REQUIRED_IF", "field is required when " .. reason, value, "non-empty value")
  end
  return self
end

--- Check value is not nil
function Validator:not_nil(value)
  if value == nil then
    self:error("NOT_NIL", "field must not be nil", nil, "non-nil value")
  end
  return self
end

--------------------------------------------------------------------------------
-- Type Validators
--------------------------------------------------------------------------------

function Validator:is_type(value, expected_type)
  if value ~= nil and type(value) ~= expected_type then
    self:error("TYPE_MISMATCH", "expected " .. expected_type .. ", got " .. type(value), value, expected_type)
  end
  return self
end

function Validator:is_string(value) return self:is_type(value, "string") end
function Validator:is_number(value) return self:is_type(value, "number") end
function Validator:is_table(value) return self:is_type(value, "table") end
function Validator:is_boolean(value) return self:is_type(value, "boolean") end

function Validator:has_key(tbl, key)
  if tbl == nil then return self end
  if tbl[key] == nil then
    self:error("MISSING_KEY", "missing required key: " .. key, tbl, key)
  end
  return self
end

function Validator:has_keys(tbl, keys)
  if tbl == nil then return self end
  for _, key in ipairs(keys) do
    self:set_field(key):has_key(tbl, key)
  end
  return self
end

--------------------------------------------------------------------------------
-- Range and Bounds
--------------------------------------------------------------------------------

function Validator:min(value, min_val)
  if type(value) == "number" and value < min_val then
    self:error("MIN_VALUE", "value must be at least " .. min_val, value, min_val)
  end
  return self
end

function Validator:max(value, max_val)
  if type(value) == "number" and value > max_val then
    self:error("MAX_VALUE", "value must be at most " .. max_val, value, max_val)
  end
  return self
end

function Validator:range(value, min_val, max_val)
  if type(value) == "number" and (value < min_val or value > max_val) then
    self:error("OUT_OF_RANGE", "value must be between " .. min_val .. " and " .. max_val, value, { min_val, max_val })
  end
  return self
end

function Validator:positive(value)
  if type(value) == "number" and value <= 0 then
    self:error("NOT_POSITIVE", "value must be positive", value, "> 0")
  end
  return self
end

function Validator:non_negative(value)
  if type(value) == "number" and value < 0 then
    self:error("NEGATIVE", "value must not be negative", value, ">= 0")
  end
  return self
end

function Validator:min_len(value, min_val)
  local len = M.get_length(value)
  if len < min_val then
    self:error("MIN_LENGTH", "length must be at least " .. min_val, len, min_val)
  end
  return self
end

function Validator:max_len(value, max_val)
  local len = M.get_length(value)
  if len > max_val then
    self:error("MAX_LENGTH", "length must be at most " .. max_val, len, max_val)
  end
  return self
end

function Validator:len_range(value, min_val, max_val)
  local len = M.get_length(value)
  if len < min_val or len > max_val then
    self:error("LENGTH_OUT_OF_RANGE", "length must be between " .. min_val .. " and " .. max_val, len, { min_val, max_val })
  end
  return self
end

function Validator:exact_len(value, expected)
  local len = M.get_length(value)
  if len ~= expected then
    self:error("LENGTH_MISMATCH", "length must be exactly " .. expected, len, expected)
  end
  return self
end

function Validator:not_empty(value)
  if M.get_length(value) == 0 then
    self:error("EMPTY", "value must not be empty", value, "non-empty")
  end
  return self
end

--------------------------------------------------------------------------------
-- Format and Pattern Validators
--------------------------------------------------------------------------------

function Validator:matches(value, pattern)
  if type(value) ~= "string" then return self end
  if not value:match(pattern) then
    self:error("PATTERN_MISMATCH", "value does not match pattern", value, pattern)
  end
  return self
end

function Validator:not_matches(value, pattern)
  if type(value) ~= "string" then return self end
  if value:match(pattern) then
    self:error("FORBIDDEN_PATTERN", "value must not match pattern", value, "not " .. pattern)
  end
  return self
end

function Validator:task_id(value)
  if type(value) ~= "string" then return self end
  if not value:match(M.patterns.task_id) then
    self:error("INVALID_TASK_ID", "TASK_ID must be 14 digits (YYYYMMDDHHmmss)", value, "14-digit timestamp")
    return self
  end
  -- Check year range
  local year = tonumber(value:sub(1, 4))
  if year and (year < 2000 or year > 2100) then
    self:warning("TASK_ID_YEAR_RANGE", "TASK_ID year seems unusual", value, "year 2000-2100")
  end
  return self
end

function Validator:iso_date(value)
  if type(value) ~= "string" then return self end
  if not value:match(M.patterns.iso_date) then
    self:error("INVALID_ISO_DATE", "date must be YYYY-MM-DD format", value, "YYYY-MM-DD")
  end
  return self
end

function Validator:org_date(value)
  if type(value) ~= "string" then return self end
  if not value:match(M.patterns.org_date) then
    self:error("INVALID_ORG_DATE", "date must be org-mode format <YYYY-MM-DD>", value, "<YYYY-MM-DD>")
  end
  return self
end

function Validator:org_tag(value)
  if type(value) ~= "string" then return self end
  if not value:match(M.patterns.org_tag) then
    self:error("INVALID_ORG_TAG", "tag must be alphanumeric, underscores, or @", value, "valid org tag")
  end
  return self
end

function Validator:slug(value)
  if type(value) ~= "string" then return self end
  if not value:match(M.patterns.slug) then
    self:error("INVALID_SLUG", "invalid slug format (lowercase, hyphens only)", value, "valid slug")
  end
  return self
end

function Validator:safe_filename(value)
  if type(value) ~= "string" then return self end
  if not value:match(M.patterns.safe_filename) then
    self:error("UNSAFE_FILENAME", "filename contains invalid characters", value, "safe filename")
  end
  return self
end

function Validator:repeater(value)
  if type(value) ~= "string" or value == "" then return self end
  if not value:match(M.patterns.repeater) then
    self:error("INVALID_REPEATER", "repeater must be format like +1w, .+2d", value, "+Xd/w/m/y")
  end
  return self
end

function Validator:one_of(value, allowed)
  for _, a in ipairs(allowed) do
    if value == a then return self end
  end
  self:error("NOT_IN_ENUM", "value must be one of: " .. table.concat(allowed, ", "), value, allowed)
  return self
end

function Validator:not_one_of(value, forbidden)
  for _, f in ipairs(forbidden) do
    if value == f then
      self:error("FORBIDDEN_VALUE", "value must not be: " .. f, value, "not " .. f)
      return self
    end
  end
  return self
end

--------------------------------------------------------------------------------
-- String Content Validators
--------------------------------------------------------------------------------

function Validator:no_whitespace(value)
  if type(value) ~= "string" then return self end
  if value:match("%s") then
    self:error("CONTAINS_WHITESPACE", "value must not contain whitespace", value, "no whitespace")
  end
  return self
end

function Validator:trimmed(value)
  if type(value) ~= "string" then return self end
  if M.trim(value) ~= value then
    self:error("NOT_TRIMMED", "value has leading or trailing whitespace", value, "trimmed string")
  end
  return self
end

function Validator:lowercase(value)
  if type(value) ~= "string" then return self end
  if value:lower() ~= value then
    self:error("NOT_LOWERCASE", "value must be lowercase", value, "lowercase string")
  end
  return self
end

function Validator:uppercase(value)
  if type(value) ~= "string" then return self end
  if value:upper() ~= value then
    self:error("NOT_UPPERCASE", "value must be uppercase", value, "uppercase string")
  end
  return self
end

function Validator:starts_with_upper(value)
  if type(value) ~= "string" or value == "" then return self end
  local first = value:sub(1, 1)
  if not first:match("[A-Z]") then
    self:error("NOT_CAPITALIZED", "value must start with uppercase letter", value, "capitalized string")
  end
  return self
end

function Validator:no_control_chars(value)
  if type(value) ~= "string" then return self end
  if value:match("[%c]") and not value:match("^[\n\r\t]*$") then
    self:error("CONTAINS_CONTROL_CHARS", "value contains control characters", value, "no control chars")
  end
  return self
end

function Validator:starts_with(value, prefix)
  if type(value) ~= "string" then return self end
  if value:sub(1, #prefix) ~= prefix then
    self:error("MISSING_PREFIX", "value must start with: " .. prefix, value, prefix .. "...")
  end
  return self
end

function Validator:ends_with(value, suffix)
  if type(value) ~= "string" then return self end
  if value:sub(-#suffix) ~= suffix then
    self:error("MISSING_SUFFIX", "value must end with: " .. suffix, value, "..." .. suffix)
  end
  return self
end

function Validator:contains(value, substr)
  if type(value) ~= "string" then return self end
  if not value:find(substr, 1, true) then
    self:error("MISSING_SUBSTRING", "value must contain: " .. substr, value, "contains " .. substr)
  end
  return self
end

function Validator:not_contains(value, substr)
  if type(value) ~= "string" then return self end
  if value:find(substr, 1, true) then
    self:error("FORBIDDEN_SUBSTRING", "value must not contain: " .. substr, value, "not contain " .. substr)
  end
  return self
end

--------------------------------------------------------------------------------
-- Safety Validators
--------------------------------------------------------------------------------

function Validator:safe_path(value)
  if type(value) ~= "string" then return self end
  if value:find("%.%.") then
    self:error("PATH_TRAVERSAL", "path contains traversal sequence (..)", value, "safe path")
  end
  if value:find("%z") then
    self:error("NULL_BYTE", "path contains null byte", value, "safe path")
  end
  return self
end

function Validator:within_dir(path, allowed_dir)
  if type(path) ~= "string" or type(allowed_dir) ~= "string" then return self end
  -- Normalize paths
  local norm_path = vim.fn.fnamemodify(path, ":p")
  local norm_dir = vim.fn.fnamemodify(allowed_dir, ":p")
  if not vim.startswith(norm_path, norm_dir) then
    self:error("PATH_ESCAPE", "path escapes allowed directory", path, "within " .. allowed_dir)
  end
  return self
end

function Validator:safe_extension(path, allowed)
  if type(path) ~= "string" then return self end
  local ext = vim.fn.fnamemodify(path, ":e")
  ext = "." .. ext:lower()
  for _, a in ipairs(allowed) do
    if ext == a:lower() then return self end
  end
  self:error("UNSAFE_EXTENSION", "file extension not allowed: " .. ext, path, allowed)
  return self
end

function Validator:no_shell_meta(value)
  if type(value) ~= "string" then return self end
  if value:match("[;&|$`\\!#*?~<>^%(%)%[%]{}]") then
    self:error("SHELL_METACHAR", "value contains shell metacharacters", value, "safe shell input")
  end
  return self
end

--------------------------------------------------------------------------------
-- GTD Semantic Validators
--------------------------------------------------------------------------------

function Validator:gtd_state(value)
  if type(value) ~= "string" then return self end
  local upper = value:upper()
  for _, s in ipairs(M.gtd_states.all) do
    if upper == s then return self end
  end
  self:error("INVALID_GTD_STATE", "invalid GTD state: " .. value, value, M.gtd_states.all)
  return self
end

function Validator:gtd_active_state(value)
  if type(value) ~= "string" then return self end
  local upper = value:upper()
  for _, s in ipairs(M.gtd_states.active) do
    if upper == s then return self end
  end
  self:error("NOT_ACTIVE_STATE", "state is not active: " .. value, value, M.gtd_states.active)
  return self
end

function Validator:heading_level(level)
  if type(level) ~= "number" then return self end
  if level < 1 or level > 6 then
    self:error("INVALID_HEADING_LEVEL", "heading level must be 1-6", level, "1-6")
  end
  return self
end

function Validator:project_heading_level(level)
  if type(level) ~= "number" then return self end
  if level ~= 1 then
    self:error("PROJECT_LEVEL", "PROJECT must be heading level 1", level, 1)
  end
  return self
end

function Validator:task_under_project(level)
  if type(level) ~= "number" then return self end
  if level ~= 2 then
    self:error("TASK_LEVEL_UNDER_PROJECT", "task under PROJECT should be level 2", level, 2)
  end
  return self
end

function Validator:standalone_task_level(level)
  if type(level) ~= "number" then return self end
  if level ~= 1 then
    self:error("STANDALONE_TASK_LEVEL", "task in standalone file should be level 1", level, 1)
  end
  return self
end

function Validator:gtd_tags(tags)
  if type(tags) ~= "table" then return self end
  for _, tag in ipairs(tags) do
    if not tag:match(M.patterns.org_tag) then
      self:error("INVALID_TAG", "tag must be alphanumeric/underscore/@: " .. tag, tag, "valid tag")
    end
    if tag:match("%s") then
      self:error("TAG_WHITESPACE", "tag cannot contain whitespace: " .. tag, tag, "no whitespace")
    end
  end
  return self
end

function Validator:waiting_has_context(state, waiting_for)
  if type(state) ~= "string" then return self end
  if state:upper() ~= "WAITING" then return self end
  if M.is_empty(waiting_for) then
    self:info("WAITING_NO_CONTEXT", "WAITING task should have WAITING_FOR property", nil, "WAITING_FOR")
  end
  return self
end

function Validator:project_has_progress(state, title)
  if type(state) ~= "string" then return self end
  if state:upper() ~= "PROJECT" then return self end
  if type(title) ~= "string" then return self end
  if not title:find("%[") or not title:find("/") then
    self:info("PROJECT_NO_PROGRESS", "PROJECT should have progress indicator [n/m]", title, "[0/0]")
  end
  return self
end

--------------------------------------------------------------------------------
-- Cross-Field Validators
--------------------------------------------------------------------------------

function Validator:mutually_exclusive(fields)
  local non_empty = {}
  for name, value in pairs(fields) do
    if not M.is_empty(value) then
      table.insert(non_empty, name)
    end
  end
  if #non_empty > 1 then
    self:error("MUTUALLY_EXCLUSIVE", "only one of these fields can be set: " .. table.concat(non_empty, ", "),
      non_empty, "one field only")
  end
  return self
end

function Validator:requires_together(fields)
  local set, unset = {}, {}
  for name, value in pairs(fields) do
    if M.is_empty(value) then
      table.insert(unset, name)
    else
      table.insert(set, name)
    end
  end
  if #set > 0 and #unset > 0 then
    self:error("REQUIRES_TOGETHER", "if " .. table.concat(set, ", ") .. " are set, " .. table.concat(unset, ", ") .. " must also be set",
      set, "all or none")
  end
  return self
end

function Validator:at_least_one(fields)
  for _, value in pairs(fields) do
    if not M.is_empty(value) then
      return self
    end
  end
  local names = {}
  for name, _ in pairs(fields) do
    table.insert(names, name)
  end
  self:error("AT_LEAST_ONE", "at least one of these must be set: " .. table.concat(names, ", "), nil, "one required")
  return self
end

function Validator:no_duplicates(items)
  if type(items) ~= "table" then return self end
  local seen = {}
  for _, item in ipairs(items) do
    if seen[item] then
      self:error("DUPLICATE_VALUE", "duplicate value: " .. tostring(item), item, "unique values")
      return self
    end
    seen[item] = true
  end
  return self
end

function Validator:all_in(items, allowed)
  if type(items) ~= "table" then return self end
  local allowed_set = {}
  for _, a in ipairs(allowed) do
    allowed_set[a] = true
  end
  for _, item in ipairs(items) do
    if not allowed_set[item] then
      self:error("VALUE_NOT_ALLOWED", "value not in allowed set: " .. tostring(item), item, allowed)
    end
  end
  return self
end

--------------------------------------------------------------------------------
-- High-Level Validators
--------------------------------------------------------------------------------

--- Validate a task creation request
---@param req table { title, state?, body?, tags?, scheduled?, deadline? }
---@return table ValidationResult
function M.validate_task_request(req)
  local v = M.new()
  
  -- Required
  v:set_field("title"):required(req.title)
  
  -- Title
  if req.title then
    v:set_field("title")
      :min_len(req.title, 1)
      :max_len(req.title, 500)
      :trimmed(req.title)
      :no_control_chars(req.title)
  end
  
  -- State
  if req.state then
    v:set_field("state"):gtd_state(req.state)
  end
  
  -- Body
  if req.body then
    v:set_field("body"):max_len(req.body, 100000)
  end
  
  -- Tags
  if req.tags then
    v:set_field("tags")
      :max_len(req.tags, 50)
      :no_duplicates(req.tags)
      :gtd_tags(req.tags)
  end
  
  -- Dates
  if req.scheduled then
    v:set_field("scheduled"):iso_date(req.scheduled)
  end
  if req.deadline then
    v:set_field("deadline"):iso_date(req.deadline)
  end
  
  return v:result()
end

--- Validate a refile request
---@param req table { task_id, destination, position? }
---@param gtd_root string
---@return table ValidationResult
function M.validate_refile_request(req, gtd_root)
  local v = M.new()
  
  -- Required
  v:set_field("task_id"):required(req.task_id)
  v:set_field("destination"):required(req.destination)
  
  -- TaskID format
  if req.task_id then
    v:set_field("task_id"):task_id(req.task_id)
  end
  
  -- Destination
  if req.destination then
    if req.destination:find("/") or req.destination:match("%.org$") then
      v:set_field("destination")
        :safe_path(req.destination)
        :within_dir(req.destination, gtd_root)
    else
      v:set_field("destination"):slug(req.destination)
    end
  end
  
  -- Position
  if req.position then
    v:set_field("position"):one_of(req.position, { "top", "bottom" })
  end
  
  return v:result()
end

--- Validate a search request
---@param req table { query?, state?, states?, project?, tag?, limit?, offset? }
---@return table ValidationResult
function M.validate_search_request(req)
  local v = M.new()
  
  -- At least one criteria
  v:at_least_one({
    query = req.query,
    state = req.state,
    states = req.states,
    project = req.project,
    tag = req.tag,
    file = req.file,
  })
  
  -- Query safety
  if req.query then
    v:set_field("query"):max_len(req.query, 500)
  end
  
  -- State validation
  if req.state then
    v:set_field("state"):gtd_state(req.state)
  end
  if req.states then
    for i, state in ipairs(req.states) do
      v:set_field("states[" .. i .. "]"):gtd_state(state)
    end
  end
  
  -- Pagination
  if req.limit then
    v:set_field("limit"):range(req.limit, 0, 1000)
  end
  if req.offset then
    v:set_field("offset"):non_negative(req.offset)
  end
  
  -- Path validation
  if req.file then
    v:set_field("file"):safe_path(req.file)
  end
  
  return v:result()
end

--- Validate GTD path is within structure
---@param path string
---@param gtd_root string
---@return table ValidationResult
function M.validate_gtd_path(path, gtd_root)
  local v = M.new()
  
  v:set_field("path")
    :required(path)
    :safe_path(path)
    :within_dir(path, gtd_root)
    :safe_extension(path, { ".org" })
  
  return v:result()
end

return M
