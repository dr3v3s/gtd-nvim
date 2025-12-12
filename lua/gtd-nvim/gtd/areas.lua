-- ============================================================================
-- GTD-NVIM AREAS MODULE
-- ============================================================================
-- Areas of Responsibility management
-- Tags tasks with :AREA: property during capture
--
-- @module gtd-nvim.gtd.areas
-- @version 0.8.0
-- @requires shared (>= 1.0.0)
-- @todo Use shared.colorize() for fzf displays
-- ============================================================================

local M = {}

M._VERSION = "0.8.0"
M._UPDATED = "2024-12-08"

-- Load shared utilities with glyph system
local shared = require("gtd-nvim.gtd.shared")
local g = shared.glyphs  -- Glyph shortcuts

-- ------------------------------------------------------------
-- Areas Configuration
-- ------------------------------------------------------------
-- Each area has:
--   name: Display name (used in :AREA: property)
--   dir:  Directory path for area-specific files
--   icon: Optional emoji for display
-- ------------------------------------------------------------

M.areas = {
  {
    name = "Personal",
    dir  = "~/Documents/GTD/Areas/10-Personal",
    icon = "👤",
  },
  {
    name = "Ditte",
    dir  = "~/Documents/GTD/Areas/11-Ditte",
    icon = "❤️",
  },
  {
    name = "Household",
    dir  = "~/Documents/GTD/Areas/20-Household",
    icon = "🏠",
  },
  {
    name = "Kids",
    dir  = "~/Documents/GTD/Areas/30-Kids",
    icon = "👨‍👩‍👧‍👦",
  },
  {
    name = "Friends",
    dir  = "~/Documents/GTD/Areas/40-Friends",
    icon = "🤝",
  },
  {
    name = "GTD",
    dir  = "~/Documents/GTD/Areas/50-GTD",
    icon = "✅",
  },
  {
    name = "DDS",
    dir  = "~/Documents/GTD/Areas/80-DDS",
    icon = "🏢",
  },
  {
    name = "Work",
    dir  = "~/Documents/GTD/Areas/90-Work",
    icon = "💼",
  },
}

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function xp(p) return vim.fn.expand(p) end

--- Get area by name
---@param name string Area name to find
---@return table|nil Area table or nil if not found
function M.get_area(name)
  if not name then return nil end
  for _, area in ipairs(M.areas) do
    if area.name == name then
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
  
  for _, area in ipairs(M.areas) do
    local area_dir = xp(area.dir)
    if expanded:find(area_dir, 1, true) then
      return area
    end
  end
  return nil
end

--- Get all area names
---@return table List of area names
function M.get_area_names()
  local names = {}
  for _, area in ipairs(M.areas) do
    table.insert(names, area.name)
  end
  return names
end

--- Get all area names with icons
---@return table List of "icon name" strings
function M.get_area_display_names()
  local names = {}
  for _, area in ipairs(M.areas) do
    local display = area.icon and (area.icon .. " " .. area.name) or area.name
    table.insert(names, display)
  end
  return names
end

--- List .org files in an area directory (excluding Inbox.org)
---@param area table Area configuration
---@return table List of file paths
function M.list_area_files(area)
  if not area or not area.dir then return {} end
  
  local dir = xp(area.dir)
  local files = vim.fn.glob(dir .. "/*.org", false, true)
  
  -- Filter out Inbox.org (deprecated)
  local result = {}
  for _, f in ipairs(files) do
    local name = vim.fn.fnamemodify(f, ":t"):lower()
    if name ~= "inbox.org" then
      table.insert(result, f)
    end
  end
  
  return result
end

--- Recursively list all .org files in an area (excluding Inbox.org)
---@param area table Area configuration
---@return table List of file paths
function M.list_area_files_recursive(area)
  if not area or not area.dir then return {} end
  
  local uv = vim.loop
  local results = {}
  
  local function scan(path)
    local fs = uv.fs_scandir(path)
    if not fs then return end
    
    while true do
      local name, t = uv.fs_scandir_next(fs)
      if not name then break end
      local full = path .. "/" .. name
      
      if t == "file" then
        if name:sub(-4) == ".org" and name:lower() ~= "inbox.org" then
          table.insert(results, full)
        end
      elseif t == "directory" then
        if name ~= ".git" and name:sub(1, 1) ~= "." then
          scan(full)
        end
      end
    end
  end
  
  scan(xp(area.dir))
  return results
end

-- ------------------------------------------------------------
-- fzf-lua Area Picker
-- ------------------------------------------------------------

local function safe_require(mod)
  local ok, m = pcall(require, mod)
  return ok and m or nil
end

--- Pick an area using fzf-lua
---@param callback function Called with selected area table or nil
function M.pick_area(callback)
  if not callback then return end
  
  local fzf = safe_require("fzf-lua")
  
  local items = { "No specific area" }
  for _, area in ipairs(M.areas) do
    local display = area.icon and (area.icon .. " " .. area.name) or area.name
    table.insert(items, display)
  end
  
  if fzf then
    fzf.fzf_exec(items, {
      prompt = shared.colorize(g.container.areas, "areas") .. " Area of Responsibility> ",
      actions = {
        ["default"] = function(sel)
          local choice = sel and sel[1]
          if not choice or choice == "No specific area" then
            callback(nil)
            return
          end
          
          -- Extract name (remove icon if present)
          local name = choice:match("[%a]+.*$") or choice
          name = name:gsub("^%s+", "") -- trim leading space after icon
          
          for _, area in ipairs(M.areas) do
            if area.name == name then
              callback(area)
              return
            end
          end
          callback(nil)
        end,
      },
      fzf_opts = { ["--no-info"] = true, ["--ansi"] = true },
      winopts = { height = 0.35, width = 0.50, row = 0.15 },
    })
  else
    vim.ui.select(items, { prompt = "Area of Responsibility" }, function(choice)
      if not choice or choice == "No specific area" then
        callback(nil)
        return
      end
      
      local name = choice:match("[%a]+.*$") or choice
      name = name:gsub("^%s+", "")
      
      for _, area in ipairs(M.areas) do
        if area.name == name then
          callback(area)
          return
        end
      end
      callback(nil)
    end)
  end
end

-- ------------------------------------------------------------
-- Setup
-- ------------------------------------------------------------

function M.setup(opts)
  if opts and opts.areas then
    M.areas = opts.areas
  end
end

return M
