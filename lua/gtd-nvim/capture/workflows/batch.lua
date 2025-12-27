-- ============================================================================
-- WORKFLOW: BATCH
-- ============================================================================
-- Batch task capture with automatic project conversion.
-- When multiple tasks are captured (GTD definition of a project),
-- prompts to create a project.
--
-- Flow: Title → State → Area → Tags → Comms → Another? → (repeat or finalize)
--
-- @module gtd-nvim.capture.workflows.batch
-- @version 1.2.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2025-12-23"

-- ============================================================================
-- PROJECT CREATION FROM TASKS
-- ============================================================================

--- Create a project from collected tasks
---@param tasks table Array of task objects
function M.create_project_from_tasks(tasks)
  -- Inherit area from first task if set
  local inherited_area = nil
  for _, t in ipairs(tasks) do
    if t.area then
      inherited_area = t.area
      break
    end
  end
  
  -- Step 1: Project name
  vim.ui.input({ prompt = "󰷐 Project name: " }, function(name)
    if not name or name == "" then
      vim.notify("Project creation cancelled", vim.log.levels.INFO)
      return
    end
    
    -- Step 2: Outcome
    vim.schedule(function()
      vim.ui.input({ prompt = "󰆤 Desired outcome: " }, function(outcome)
        -- Step 3: Create project
        vim.schedule(function()
          local Object = require("gtd-nvim.capture.model.object")
          local Writer = require("gtd-nvim.capture.model.writer")
          
          -- Create project object
          local project = Object.project(name, outcome)
          project.area = inherited_area
          project.level = 1  -- CRITICAL: Projects MUST be level 1 in their own file
          
          -- Add tasks as children
          for _, task in ipairs(tasks) do
            Object.add_child(project, task)
          end
          
          -- Determine file path
          local slug = name:lower():gsub("%s+", "-"):gsub("[^%w-]", "")
          local target
          
          local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
          if shared_ok and shared.gtd_path then
            if inherited_area then
              -- Put in area folder
              target = shared.gtd_path("areas") .. "/" .. inherited_area .. "/" .. slug .. ".org"
            else
              target = shared.gtd_path("projects") .. "/" .. slug .. ".org"
            end
          else
            target = vim.fn.expand("~/Documents/GTD/Projects/" .. slug .. ".org")
          end
          
          -- Write project file
          local success, err = Writer.write(project, target, { 
            append = false,  -- New file
            create_if_missing = true,
            include_children = true,
          })
          
          if success then
            local task_count = #tasks
            vim.notify(
              string.format("󰷐 %s → %s (+%d tasks)", name, vim.fn.fnamemodify(target, ":t:r"), task_count),
              vim.log.levels.INFO
            )
            
            -- Refresh daemon
            local chronos_ok, chronos = pcall(require, "gtd-nvim.gtd.chronos")
            if chronos_ok and chronos.is_running and chronos.is_running() then
              chronos.query("gtd", "refresh", nil)
            end
          else
            vim.notify("Failed to create project: " .. (err or "unknown"), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end)
end

-- ============================================================================
-- WORKFLOW DEFINITION
-- ============================================================================

local Object = require("gtd-nvim.capture.model.object")

M.definition = {
  name = "batch",
  description = "Capture multiple tasks, auto-convert to project if >1",
  object_type = Object.TYPE.TASK,
  
  steps = {
    "outcome",  -- First: What does done look like?
    "title",    -- Then: What action achieves that?
    "state",
    "area",
    "tags",
    "comms",
    "another",
  },
  
  opts = {
    -- Enable batch collection
    batch_enabled = true,
    max_batch = 10,
    
    -- Skip dates in batch mode (can set later on individual tasks)
    ask_defer = false,
    ask_due = false,
    
    -- Multi-select tags
    multi_select = true,
    
    -- Area is important for batch
    skip_area = false,
  },
  
  -- Custom completion handler for batch
  on_complete = function(obj)
    local collected = obj._collected or {}
    
    -- Add current object if not already collected
    if obj.title and obj.title ~= "" then
      local dominated = false
      for _, t in ipairs(collected) do
        if t.title == obj.title then
          dominated = true
          break
        end
      end
      if not dominated then
        local clone = Object.clone(obj)
        clone._collected = nil
        clone._workflow_opts = nil
        table.insert(collected, clone)
      end
    end
    
    local count = #collected
    
    if count == 0 then
      vim.notify("No tasks captured", vim.log.levels.INFO)
      return
    end
    
    if count == 1 then
      -- Single task - just write it
      local Engine = require("gtd-nvim.capture.engine")
      Engine._default_finalize(collected[1])
      return
    end
    
    -- Multiple tasks = GTD project!
    -- Prompt for project creation
    local fzf_ok, fzf = pcall(require, "fzf-lua")
    
    if not fzf_ok then
      -- Fallback: write as individual tasks
      local Engine = require("gtd-nvim.capture.engine")
      for _, task in ipairs(collected) do
        Engine._default_finalize(task)
      end
      vim.notify(string.format("Created %d tasks", count), vim.log.levels.INFO)
      return
    end
    
    -- Show project conversion prompt
    fzf.fzf_exec({
      string.format("󰷐 Create PROJECT with %d tasks", count),
      string.format("󰄲 Create %d individual tasks", count),
      "󰜺 Cancel (don't create)",
    }, {
      prompt = "Multiple tasks captured ❯ ",
      winopts = { height = 0.25, width = 0.5 },
      actions = {
        ["default"] = function(sel)
          if not sel or not sel[1] then return end
          
          if sel[1]:match("PROJECT") then
            -- Convert to project
            vim.schedule(function()
              M.create_project_from_tasks(collected)
            end)
          elseif sel[1]:match("individual") then
            -- Write as individual tasks
            vim.schedule(function()
              local Engine = require("gtd-nvim.capture.engine")
              for _, task in ipairs(collected) do
                Engine._default_finalize(task)
              end
              vim.notify(string.format("󰄲 Created %d tasks in Inbox", count), vim.log.levels.INFO)
            end)
          end
          -- Cancel: do nothing
        end,
      },
    })
  end,
}

-- Return the definition for the engine to load
return M.definition
