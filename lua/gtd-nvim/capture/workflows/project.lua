-- ============================================================================
-- WORKFLOW: PROJECT
-- ============================================================================
-- Full GTD project creation workflow.
--
-- Flow: Outcome → Title → Area → Tags → Tasks (multiple) → ZK Note → Finalize
--
-- A project in GTD is any outcome requiring more than one action.
-- This workflow captures the vision first, then the actions to achieve it.
--
-- @module gtd-nvim.capture.workflows.project
-- @version 1.2.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2025-12-23"

local Object = require("gtd-nvim.capture.model.object")

-- ============================================================================
-- TASK COLLECTION FOR PROJECT
-- ============================================================================

--- Collect tasks for the project
---@param project table Project OrgObject
---@param on_complete function Callback when done collecting
function M.collect_tasks(project, on_complete)
  local tasks = {}
  
  local function collect_one()
    local task_num = #tasks + 1
    
    -- Ask for task title
    vim.ui.input({ 
      prompt = string.format("󰐕 Task %d (empty to finish): ", task_num) 
    }, function(title)
      if not title or title == "" then
        -- Done collecting
        on_complete(tasks)
        return
      end
      
      -- Create task object
      local task = Object.task(title, "TODO")
      task.level = 2  -- ** under project
      task.area = project.area  -- Inherit area
      
      -- Ask for state
      vim.schedule(function()
        M._ask_task_state(task, function(task_with_state)
          -- Ask for dates
          vim.schedule(function()
            M._ask_task_dates(task_with_state, function(task_with_dates)
              table.insert(tasks, task_with_dates)
              -- Collect next task
              vim.schedule(function()
                collect_one()
              end)
            end)
          end)
        end)
      end)
    end)
  end
  
  -- Start collecting
  collect_one()
end

--- Ask for task state
function M._ask_task_state(task, callback)
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  
  local states = {
    { state = "NEXT", icon = "󱥦", desc = "ready to do now" },
    { state = "TODO", icon = "󰄲", desc = "not yet ready" },
    { state = "WAITING", icon = "", desc = "delegated/blocked" },
  }
  
  if fzf_ok then
    local items = {}
    local lookup = {}
    for _, s in ipairs(states) do
      local line = string.format("%s %s (%s)", s.icon, s.state, s.desc)
      table.insert(items, line)
      lookup[line] = s.state
    end
    
    fzf.fzf_exec(items, {
      prompt = "State ❯ ",
      winopts = { height = 0.25, width = 0.4 },
      actions = {
        ["default"] = function(sel)
          if sel and sel[1] then
            task.state = lookup[sel[1]] or "TODO"
          else
            task.state = "TODO"
          end
          vim.schedule(function() callback(task) end)
        end,
      },
    })
  else
    -- Fallback
    task.state = "TODO"
    callback(task)
  end
end

--- Ask for task dates (optional, quick)
function M._ask_task_dates(task, callback)
  -- Skip dates for now, keep it fast
  -- User can add dates later during clarify/review
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  
  if fzf_ok then
    fzf.fzf_exec({
      "󰃰 Add dates",
      "󰜺 Skip dates (add later)",
    }, {
      prompt = "Dates? ❯ ",
      winopts = { height = 0.2, width = 0.35 },
      actions = {
        ["default"] = function(sel)
          if sel and sel[1] and sel[1]:match("Add dates") then
            vim.schedule(function()
              M._collect_dates(task, callback)
            end)
          else
            vim.schedule(function() callback(task) end)
          end
        end,
      },
    })
  else
    callback(task)
  end
end

--- Collect defer and due dates
function M._collect_dates(task, callback)
  local today = os.date("%Y-%m-%d")
  
  vim.ui.input({ prompt = "Defer [" .. today .. "]: " }, function(defer)
    if defer and defer ~= "" then
      task.scheduled = defer
    end
    
    vim.schedule(function()
      local due_default = os.date("%Y-%m-%d", os.time() + 7 * 86400)  -- +1 week
      vim.ui.input({ prompt = "Due [" .. due_default .. "]: " }, function(due)
        if due and due ~= "" then
          task.deadline = due
        end
        callback(task)
      end)
    end)
  end)
end

-- ============================================================================
-- WORKFLOW DEFINITION
-- ============================================================================

M.definition = {
  name = "project",
  description = "Full GTD project with outcome, area, tasks, and note",
  object_type = Object.TYPE.PROJECT,
  
  steps = {
    "outcome",    -- First: What does success look like?
    "title",      -- Project name
    "area",       -- Area of responsibility
    "tags",       -- Context tags
    "focus",      -- Is this an Area of Focus?
    "project_tasks",  -- Collect multiple tasks
    "zk_note",    -- Link to Zettelkasten note
  },
  
  opts = {
    -- Outcome is required for projects
    outcome = {
      required_for_projects = true,
      prompt_project = "󰆤 What does success look like? (the outcome): ",
    },
    
    -- Title
    title = {
      prompt_project = "󰷐 Project name: ",
    },
    
    -- Area selection
    skip_area = false,
    
    -- Tags
    multi_select = true,
    
    -- ZK note created by default
    zk_note = {
      auto_create = true,
      template = "project",
    },
  },
  
  -- Custom completion
  on_complete = function(obj)
    local Writer = require("gtd-nvim.capture.model.writer")
    
    -- Ensure project state and level
    obj.state = Object.STATE.PROJECT
    obj.type = Object.TYPE.PROJECT
    obj.level = 1  -- CRITICAL: Projects MUST be level 1 in their own file
    
    -- Determine file path
    local slug = obj.title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
    local target
    
    local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
    if shared_ok and shared.gtd_path then
      if obj.area then
        target = shared.gtd_path("areas") .. "/" .. obj.area .. "/" .. slug .. ".org"
      else
        target = shared.gtd_path("projects") .. "/" .. slug .. ".org"
      end
    else
      target = vim.fn.expand("~/Documents/GTD/Projects/" .. slug .. ".org")
    end
    
    -- Ensure directory exists
    local dir = vim.fn.fnamemodify(target, ":h")
    vim.fn.mkdir(dir, "p")
    
    -- Write project
    local success, err = Writer.write(obj, target, {
      append = false,
      create_if_missing = true,
      include_children = true,
    })
    
    if success then
      local task_count = obj.children and #obj.children or 0
      local note_text = obj.zk_note and " +note" or ""
      vim.notify(
        string.format("󰷐 %s → %s (+%d tasks%s)", 
          obj.title, 
          vim.fn.fnamemodify(target, ":t:r"), 
          task_count,
          note_text
        ),
        vim.log.levels.INFO
      )
      
      -- Refresh daemon
      local chronos_ok, chronos = pcall(require, "gtd-nvim.gtd.chronos")
      if chronos_ok and chronos.is_running and chronos.is_running() then
        chronos.query("gtd", "refresh", nil)
      end
      
      -- Open the project file
      vim.schedule(function()
        vim.cmd("edit " .. target)
      end)
    else
      vim.notify("Failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end,
}

return M.definition
