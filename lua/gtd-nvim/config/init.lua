-- gtd-nvim/config/init.lua
-- Configuration loader with user override support
-- Loads defaults, then merges user config from ~/.config/gtd-nvim/config.lua

local M = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERNAL STATE
-- ═══════════════════════════════════════════════════════════════════════════

local _config = nil
local _config_loaded = false

local USER_CONFIG_PATH = "~/.config/gtd-nvim/config.lua"

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function expand(path)
  return vim.fn.expand(path)
end

local function file_exists(path)
  return vim.fn.filereadable(expand(path)) == 1
end

local function notify(msg, level)
  vim.notify("[gtd-config] " .. msg, level or vim.log.levels.INFO)
end

-- Deep merge tables (b overrides a)
local function deep_merge(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return b
  end
  
  local result = vim.deepcopy(a)
  for k, v in pairs(b) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIG LOADING
-- ═══════════════════════════════════════════════════════════════════════════

--- Load configuration (defaults + user overrides)
---@param force boolean|nil Force reload even if already loaded
---@return table config The merged configuration
function M.load(force)
  if _config_loaded and not force then
    return _config
  end
  
  -- Load defaults
  local defaults = require("gtd-nvim.config.defaults")
  _config = vim.deepcopy(defaults.config)
  
  -- Load user config if exists
  local user_path = expand(USER_CONFIG_PATH)
  if file_exists(user_path) then
    local ok, user_config = pcall(dofile, user_path)
    if ok and type(user_config) == "table" then
      _config = deep_merge(_config, user_config)
    else
      notify("Error loading user config: " .. tostring(user_config), vim.log.levels.WARN)
    end
  end
  
  _config_loaded = true
  return _config
end

--- Get the current configuration
---@return table config
function M.get()
  if not _config_loaded then
    return M.load()
  end
  return _config
end

--- Reload configuration from disk
---@return table config
function M.reload()
  _config = nil
  _config_loaded = false
  notify("Configuration reloaded")
  return M.load(true)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PATH ACCESSORS (convenience functions)
-- ═══════════════════════════════════════════════════════════════════════════

--- Get expanded GTD home directory
---@return string
function M.gtd_home()
  return expand(M.get().gtd_home)
end

--- Get expanded Notes home directory
---@return string
function M.notes_home()
  return expand(M.get().notes_home)
end

--- Get full path to a GTD subdirectory or file
---@param key string Key from gtd_dirs (inbox, projects, areas, etc.)
---@return string
function M.gtd_path(key)
  local cfg = M.get()
  local subpath = cfg.gtd_dirs[key]
  if not subpath then return M.gtd_home() end
  return expand(cfg.gtd_home .. "/" .. subpath)
end

--- Get full path to a Notes subdirectory
---@param key string Key from notes_dirs (daily, quick, projects, etc.)
---@return string
function M.notes_path(key)
  local cfg = M.get()
  local subpath = cfg.notes_dirs[key]
  if not subpath then return M.notes_home() end
  return expand(cfg.notes_home .. "/" .. subpath)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DATA ACCESSORS
-- ═══════════════════════════════════════════════════════════════════════════

--- Get user info
---@return table {name, email, timezone, language}
function M.user()
  return M.get().user or {}
end

--- Get areas of focus
---@return table[] Array of area definitions
function M.areas()
  return M.get().areas or {}
end

--- Get area by ID
---@param id string Area ID
---@return table|nil Area definition or nil
function M.area(id)
  for _, area in ipairs(M.areas()) do
    if area.id == id then return area end
  end
  return nil
end

--- Get contexts
---@return table[] Array of context definitions
function M.contexts()
  return M.get().contexts or {}
end

--- Get context by tag
---@param tag string Context tag (e.g., "@computer")
---@return table|nil Context definition or nil
function M.context(tag)
  for _, ctx in ipairs(M.contexts()) do
    if ctx.tag == tag then return ctx end
  end
  return nil
end

--- Get energy levels
---@return table[] Array of energy level definitions
function M.energy_levels()
  return M.get().energy or {}
end

--- Get effort options
---@return table[] Array of effort options
function M.effort_options()
  return M.get().effort_options or {}
end

--- Get priorities
---@return table[] Array of priority definitions
function M.priorities()
  return M.get().priorities or {}
end

--- Get people
---@return table[] Array of people definitions
function M.people()
  return M.get().people or {}
end

--- Get person by ID
---@param id string Person ID
---@return table|nil Person definition or nil
function M.person(id)
  for _, p in ipairs(M.people()) do
    if p.id == id then return p end
  end
  return nil
end

--- Get waiting contexts
---@return table[] Array of waiting context definitions
function M.waiting_contexts()
  return M.get().waiting_contexts or {}
end

--- Get review settings
---@return table Review configuration
function M.review()
  return M.get().review or {}
end

--- Get integration settings
---@param name string|nil Integration name (kairos, calendar, etc.)
---@return table Integration configuration
function M.integrations(name)
  local int = M.get().integrations or {}
  if name then return int[name] or {} end
  return int
end

--- Get capture settings
---@return table Capture configuration
function M.capture()
  return M.get().capture or {}
end

--- Get UI settings
---@return table UI configuration
function M.ui()
  return M.get().ui or {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- GLYPH & COLOR ACCESSORS
-- ═══════════════════════════════════════════════════════════════════════════

--- Get all glyphs
---@return table Glyph definitions
function M.glyphs()
  return M.get().glyphs or {}
end

--- Get state glyph
---@param state string TODO keyword (TODO, NEXT, etc.)
---@return string Icon character
function M.state_glyph(state)
  local g = M.glyphs()
  return (g.state and g.state[state]) or "•"
end

--- Get container glyph
---@param container string Container type (inbox, project, etc.)
---@return string Icon character
function M.container_glyph(container)
  local g = M.glyphs()
  return (g.container and g.container[container]) or "󰉋"
end

--- Get UI glyph
---@param name string UI element name
---@return string Icon character
function M.ui_glyph(name)
  local g = M.glyphs()
  return (g.ui and g.ui[name]) or "•"
end

--- Get phase glyph
---@param phase string GTD phase (capture, clarify, etc.)
---@return string Icon character
function M.phase_glyph(phase)
  local g = M.glyphs()
  return (g.phase and g.phase[phase]) or "•"
end

--- Get all colors
---@return table Color definitions
function M.colors()
  return M.get().colors or {}
end

--- Get specific color
---@param name string Color name
---@return string Hex color code
function M.color(name)
  local c = M.colors()
  return c[name] or "#ffffff"
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYWORDS
-- ═══════════════════════════════════════════════════════════════════════════

--- Get active keywords (TODO, NEXT, WAITING, SOMEDAY)
---@return string[] Array of active keywords
function M.active_keywords()
  local kw = M.get().keywords or {}
  return kw.active or { "TODO", "NEXT", "WAITING", "SOMEDAY" }
end

--- Get done keywords (DONE, CANCELLED)
---@return string[] Array of done keywords
function M.done_keywords()
  local kw = M.get().keywords or {}
  return kw.done or { "DONE", "CANCELLED" }
end

--- Get all keywords (active + done + special)
---@return string[] Array of all keywords
function M.all_keywords()
  local kw = M.get().keywords or {}
  local all = {}
  for _, k in ipairs(kw.active or {}) do table.insert(all, k) end
  for _, k in ipairs(kw.done or {}) do table.insert(all, k) end
  for _, k in ipairs(kw.special or {}) do table.insert(all, k) end
  return all
end

--- Check if keyword is active
---@param keyword string Keyword to check
---@return boolean
function M.is_active_keyword(keyword)
  return vim.tbl_contains(M.active_keywords(), keyword)
end

--- Check if keyword is done
---@param keyword string Keyword to check
---@return boolean
function M.is_done_keyword(keyword)
  return vim.tbl_contains(M.done_keywords(), keyword)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════

--- Validate configuration and return issues
---@return table[] Array of {level, message} issues
function M.validate()
  local issues = {}
  local cfg = M.get()
  
  -- Check paths exist
  if vim.fn.isdirectory(expand(cfg.gtd_home)) ~= 1 then
    table.insert(issues, { level = "warn", message = "GTD home does not exist: " .. cfg.gtd_home })
  end
  if vim.fn.isdirectory(expand(cfg.notes_home)) ~= 1 then
    table.insert(issues, { level = "warn", message = "Notes home does not exist: " .. cfg.notes_home })
  end
  
  -- Check Kairos socket if enabled
  if cfg.integrations.kairos.enabled then
    local socket = expand(cfg.integrations.kairos.socket)
    if vim.fn.filereadable(socket) ~= 1 then
      table.insert(issues, { level = "warn", message = "Kairos socket not found: " .. socket })
    end
  end
  
  -- Check areas have required fields
  for i, area in ipairs(cfg.areas or {}) do
    if not area.id then
      table.insert(issues, { level = "error", message = "Area " .. i .. " missing 'id'" })
    end
    if not area.name then
      table.insert(issues, { level = "error", message = "Area " .. i .. " missing 'name'" })
    end
  end
  
  return issues
end

--- Print configuration health check
function M.health()
  local issues = M.validate()
  
  if #issues == 0 then
    notify("Configuration OK", vim.log.levels.INFO)
    return true
  end
  
  for _, issue in ipairs(issues) do
    local level = issue.level == "error" and vim.log.levels.ERROR or vim.log.levels.WARN
    notify(issue.message, level)
  end
  
  return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- USER CONFIG GENERATION
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate example user config file
---@param path string|nil Output path (default: ~/.config/gtd-nvim/config.lua)
---@return boolean success
function M.generate_user_config(path)
  path = expand(path or USER_CONFIG_PATH)
  
  if file_exists(path) then
    notify("User config already exists: " .. path, vim.log.levels.WARN)
    return false
  end
  
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  
  local example = require("gtd-nvim.config.example")
  local ok = pcall(vim.fn.writefile, vim.split(example.content, "\n"), path)
  
  if ok then
    notify("Created user config: " .. path, vim.log.levels.INFO)
    return true
  else
    notify("Failed to create user config", vim.log.levels.ERROR)
    return false
  end
end

--- Open user config in editor
function M.edit()
  local path = expand(USER_CONFIG_PATH)
  
  if not file_exists(path) then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "User config not found. Create it?",
    }, function(choice)
      if choice == "Yes" then
        M.generate_user_config()
        vim.cmd("edit " .. path)
      end
    end)
    return
  end
  
  vim.cmd("edit " .. path)
end

return M
