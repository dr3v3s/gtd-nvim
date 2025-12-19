-- ============================================================================
-- GTD-NVIM AREAS MODULE
-- ============================================================================
-- Areas of Responsibility management
-- Tags tasks with :AREA: property during capture
-- Reads areas from user config (~/.config/gtd-nvim/config.lua)
--
-- @module gtd-nvim.gtd.areas
-- @version 1.0.0
-- @requires shared (>= 1.1.0)
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2024-12-19"

-- Load shared utilities
local shared = require("gtd-nvim.gtd.shared")
local g = shared.glyphs

-- ------------------------------------------------------------
-- Areas Access (from config)
-- ------------------------------------------------------------

--- Get all areas from config
---@return table[] Array of area definitions
function M.get_areas()
  local config_areas = shared.get_areas()
  local areas = {}
  
  -- Build full paths from config
  local gtd_home = shared.gtd_home()
  local areas_root = gtd_home .. "/Areas"
  
  for _, area in ipairs(config_areas) do
    local full_dir = area.dir
    -- If dir is relative (no ~/), prepend areas_root
    if not full_dir:match("^[~/]") then
      full_dir = areas_root .. "/" .. area.dir
    end
    
    table.insert(areas, {
      id = area.id,
      name = area.name,
      icon = area.icon or g.container.area,
      color = area.color,
      dir = full_dir,
    })
  end
  
  return areas
end

-- Legacy compatibility: M.areas property
-- Returns areas from config (for modules that access M.areas directly)
setmetatable(M, {
  __index = function(_, key)
    if key == "areas" then
      return M.get_areas()
    end
    return nil
  end
})

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function xp(p) return vim.fn.expand(p) end

--- Get area by name
---@param name string Area name to find
---@return table|nil Area table or nil if not found
function M.get_area(name)
  if not name then return nil end
  for _, area in ipairs(M.get_areas()) do
    if area.name == name then
      return area
    end
  end
  return nil
end

--- Get area by ID
---@param id string Area ID to find
---@return table|nil Area table or nil if not found
function M.get_area_by_id(id)
  if not id then return nil end
  for _, area in ipairs(M.get_areas()) do
    if area.id == id then
      return area
    end
  end
  return nil
end

--- Get area by directory path
---@param path string File path to check
---@return table|nil Area table or nil if not in an area
function M.get_area_for_path(path)
  if not path then return nil end
  local expanded = xp(path)
  
  for _, area in ipairs(M.get_areas()) do
    local area_dir = xp(area.dir)
    if expanded:find(area_dir, 1, true) then
      return area
    end
  end
  return nil
end

--- Get list of area names
---@return string[] List of area names
function M.list_names()
  local names = {}
  for _, area in ipairs(M.get_areas()) do
    table.insert(names, area.name)
  end
  return names
end

--- Get areas root directory
---@return string Expanded path to Areas directory
function M.get_root()
  return xp(shared.gtd_path("areas"))
end

-- ------------------------------------------------------------
-- Picker: fzf-lua area selection
-- ------------------------------------------------------------

--- Present area picker and execute callback with selection
---@param callback function Callback receiving selected area table
---@param opts table|nil Options: { prompt = "...", include_none = bool }
function M.pick(callback, opts)
  opts = opts or {}
  
  local areas = M.get_areas()
  if #areas == 0 then
    shared.notify("No areas configured. Add areas to ~/.config/gtd-nvim/config.lua", "WARN")
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    shared.notify("fzf-lua not available", "WARN")
    return
  end
  
  local display = {}
  local lookup = {}
  
  -- Optionally include "No Area" option
  if opts.include_none then
    table.insert(display, g.ui.folder .. " (No Area)")
    lookup["(No Area)"] = nil
  end
  
  for _, area in ipairs(areas) do
    local icon = area.icon or g.container.area
    local label = icon .. " " .. area.name
    table.insert(display, label)
    lookup[area.name] = area
  end
  
  fzf.fzf_exec(display, {
    prompt = opts.prompt or "Area> ",
    winopts = {
      height = 0.40,
      width = 0.50,
      row = 0.30,
      title = " " .. g.container.area .. " Areas ",
      title_pos = "center",
    },
    fzf_opts = {
      ["--no-info"] = true,
    },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        -- Extract area name from selection (remove icon prefix)
        local name = sel[1]:match("%s(.+)$") or sel[1]
        local area = lookup[name]
        if callback then callback(area) end
      end,
    },
  })
end

-- ------------------------------------------------------------
-- Browse: Open area directory in fzf-lua
-- ------------------------------------------------------------

--- Browse all areas with fzf-lua picker
function M.browse()
  local areas = M.get_areas()
  if #areas == 0 then
    shared.notify("No areas configured", "WARN")
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    shared.notify("fzf-lua not available", "WARN")
    return
  end
  
  local display = {}
  local meta = {}
  
  for _, area in ipairs(areas) do
    local icon = area.icon or g.container.area
    local dir = xp(area.dir)
    local file_count = 0
    
    if vim.fn.isdirectory(dir) == 1 then
      local files = vim.fn.glob(dir .. "/*.org", false, true)
      file_count = #files
    end
    
    local label = string.format("%s %s (%d files)", icon, area.name, file_count)
    table.insert(display, label)
    table.insert(meta, area)
  end
  
  fzf.fzf_exec(display, {
    prompt = "Areas> ",
    winopts = {
      height = 0.50,
      width = 0.60,
      row = 0.25,
      title = " " .. g.container.area .. " Areas of Focus ",
      title_pos = "center",
    },
    fzf_opts = {
      ["--no-info"] = true,
      ["--header"] = "Enter: Browse files │ Ctrl-N: New project",
    },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local area = meta[idx]
        if area then
          local dir = xp(area.dir)
          if vim.fn.isdirectory(dir) == 1 then
            fzf.files({ cwd = dir })
          else
            shared.notify("Area directory not found: " .. dir, "WARN")
          end
        end
      end,
      ["ctrl-n"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local area = meta[idx]
        if area then
          -- Create new project in this area
          local projects = require("gtd-nvim.gtd.projects")
          if projects and projects.create then
            projects.create({ area = area })
          end
        end
      end,
    },
  })
end

-- ------------------------------------------------------------
-- Setup (optional - for custom configuration)
-- ------------------------------------------------------------

function M.setup(opts)
  -- No-op: areas now come from user config
  -- Kept for backwards compatibility
  if opts and opts.areas then
    shared.notify("areas.setup() is deprecated. Use ~/.config/gtd-nvim/config.lua", "WARN")
  end
end

return M
