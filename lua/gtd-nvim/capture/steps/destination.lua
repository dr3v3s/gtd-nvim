-- ============================================================================
-- CAPTURE STEP: DESTINATION
-- ============================================================================
-- Select where to save the task (Inbox, Project, or Area).
--
-- @module gtd-nvim.capture.steps.destination
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M.name = "destination"
M.applies_to = { "task" }  -- Projects have fixed destination

local utils = require("gtd-nvim.capture.utils")

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Scan for project files
local function get_projects()
  local projects = {}
  local projects_dir = utils.projects_dir()
  local areas_dir = utils.areas_dir()
  
  -- Scan Projects directory
  local handle = vim.loop.fs_scandir(projects_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if type == "file" and name:match("%.org$") then
        table.insert(projects, {
          name = name:gsub("%.org$", ""),
          path = projects_dir .. "/" .. name,
          area = nil,
        })
      end
    end
  end
  
  -- Scan Areas subdirectories
  handle = vim.loop.fs_scandir(areas_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if type == "directory" then
        local area_path = areas_dir .. "/" .. name
        local area_handle = vim.loop.fs_scandir(area_path)
        if area_handle then
          while true do
            local fname, ftype = vim.loop.fs_scandir_next(area_handle)
            if not fname then break end
            if ftype == "file" and fname:match("%.org$") then
              table.insert(projects, {
                name = fname:gsub("%.org$", ""),
                path = area_path .. "/" .. fname,
                area = name,
              })
            end
          end
        end
      end
    end
  end
  
  table.sort(projects, function(a, b) return a.name < b.name end)
  return projects
end

-- ============================================================================
-- STEP INTERFACE
-- ============================================================================

function M.should_run(ctx, opts)
  -- Skip if destination already set
  if ctx.path then return false end
  -- Skip if inbox-only mode
  if opts.inbox_only then
    ctx.path = utils.inbox_path()
    ctx.level = 1
    return false
  end
  return true
end

function M.run(ctx, opts, next_step, cancel)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    -- Fallback to inbox
    ctx.path = utils.inbox_path()
    ctx.level = 1
    next_step()
    return
  end
  
  -- Build destination list
  local items = {
    utils.glyphs.inbox .. " Inbox (process later)",
  }
  
  local projects = get_projects()
  local meta = { { type = "inbox" } }
  
  for _, proj in ipairs(projects) do
    local label = proj.area 
      and string.format("%s %s  [%s]", utils.glyphs.project, proj.name, proj.area)
      or string.format("%s %s", utils.glyphs.project, proj.name)
    table.insert(items, label)
    table.insert(meta, { type = "project", project = proj })
  end
  
  fzf.fzf_exec(items, {
    prompt = "Destination ❯ ",
    winopts = { height = 0.5, width = 0.5, row = 0.3 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then
          cancel()
          return
        end
        
        -- Find selected item
        for i, item in ipairs(items) do
          if item == sel[1] then
            if meta[i].type == "inbox" then
              ctx.path = utils.inbox_path()
              ctx.level = 1
            else
              local proj = meta[i].project
              ctx.path = proj.path
              ctx.level = 2  -- Tasks in projects are level 2
              ctx.area = proj.area
              ctx.project_name = proj.name
            end
            break
          end
        end
        
        next_step()
      end,
    },
  })
end

return M
