-- ============================================================================
-- STEP: AREA
-- ============================================================================
-- Select Area of Responsibility / Area of Focus.
--
-- @module gtd-nvim.capture.steps.area
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

M.name = "area"
M.applies_to = { "task", "project" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  -- Areas of responsibility (can be overridden via setup)
  areas = {
    { name = "10-Work", icon = "󰢱", desc = "Professional responsibilities" },
    { name = "20-Personal", icon = "󰋑", desc = "Personal life" },
    { name = "30-Family", icon = "󰟀", desc = "Family & relationships" },
    { name = "40-Health", icon = "󰊗", desc = "Health & fitness" },
    { name = "50-Finance", icon = "󰗓", desc = "Financial matters" },
    { name = "60-Home", icon = "󰋞", desc = "Home & property" },
    { name = "70-Learning", icon = "󰑴", desc = "Education & growth" },
    { name = "80-Community", icon = "󰏬", desc = "Community & social" },
  },
  
  -- Allow skipping
  allow_skip = true,
  
  -- Prompt
  prompt = "Area ❯ ",
  
  -- Skip icon
  skip_text = "󰜺 (skip - no area)",
}

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Load areas from GTD directory structure
---@return table|nil areas
local function discover_areas()
  local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  if not shared_ok or not shared.gtd_path then
    return nil
  end
  
  local areas_dir = shared.gtd_path("areas")
  if not areas_dir or vim.fn.isdirectory(areas_dir) == 0 then
    return nil
  end
  
  local areas = {}
  local entries = vim.fn.readdir(areas_dir)
  
  for _, entry in ipairs(entries) do
    local path = areas_dir .. "/" .. entry
    if vim.fn.isdirectory(path) == 1 then
      table.insert(areas, {
        name = entry,
        icon = "󰉋",
        desc = entry,
        path = path,
      })
    end
  end
  
  if #areas > 0 then
    table.sort(areas, function(a, b) return a.name < b.name end)
    return areas
  end
  
  return nil
end

-- ============================================================================
-- SHOULD RUN
-- ============================================================================

--- Determine if this step should run
---@param obj table OrgObject
---@param opts table Step options
---@return boolean
function M.should_run(obj, opts)
  opts = opts or {}
  return opts.skip_area ~= true
end

-- ============================================================================
-- RUN
-- ============================================================================

--- Execute the step
---@param obj table OrgObject
---@param opts table Step options
---@param next_step function Callback to continue
function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Try to discover areas from filesystem first
  local areas = discover_areas() or opts.areas
  
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  
  if fzf_ok then
    M._run_fzf(obj, opts, next_step, fzf, areas)
  else
    M._run_select(obj, opts, next_step, areas)
  end
end

--- Run with fzf-lua
function M._run_fzf(obj, opts, next_step, fzf, areas)
  local items = {}
  local lookup = {}
  
  if opts.allow_skip then
    table.insert(items, opts.skip_text)
  end
  
  for _, area in ipairs(areas) do
    local line = string.format("%s %s", area.icon or "󰉋", area.name)
    if area.desc and area.desc ~= area.name then
      line = line .. "  (" .. area.desc .. ")"
    end
    table.insert(items, line)
    lookup[line] = area.name
  end
  
  fzf.fzf_exec(items, {
    prompt = opts.prompt,
    winopts = { height = 0.4, width = 0.45 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then
          vim.schedule(function() next_step(obj) end)
          return
        end
        
        if sel[1]:match("skip") then
          vim.schedule(function() next_step(obj) end)
          return
        end
        
        -- Extract area name
        local area_name = lookup[sel[1]]
        if not area_name then
          -- Try to extract from selection
          area_name = sel[1]:match("^[^%s]+%s+(.+)$")
          if area_name then
            area_name = area_name:match("^([^%(]+)") or area_name
            area_name = vim.trim(area_name)
          end
        end
        
        if area_name then
          obj.area = area_name
        end
        
        vim.schedule(function() next_step(obj) end)
      end,
    },
  })
end

--- Fallback with vim.ui.select
function M._run_select(obj, opts, next_step, areas)
  local items = {}
  local lookup = {}
  
  if opts.allow_skip then
    table.insert(items, "(skip)")
  end
  
  for _, area in ipairs(areas) do
    local line = area.name
    table.insert(items, line)
    lookup[line] = area.name
  end
  
  vim.ui.select(items, { prompt = opts.prompt }, function(choice)
    if choice and choice ~= "(skip)" then
      obj.area = lookup[choice] or choice
    end
    next_step(obj)
  end)
end

return M
