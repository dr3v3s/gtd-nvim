-- ============================================================================
-- WORKFLOW ENGINE
-- ============================================================================
-- Chains capture steps together, handles batch mode and project conversion.
--
-- @module gtd-nvim.capture.engine
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

local Object = require("gtd-nvim.capture.model.object")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.config = {
  -- Default workflows
  workflows = {
    task_quick = "task_quick",
    task_full = "task_full",
    project = "project",
    batch = "batch",
    clarify = "clarify",
  },
  
  -- Step-level options (passed to each step)
  step_opts = {},
  
  -- Callbacks
  on_complete = nil,
  on_cancel = nil,
  on_error = nil,
}

-- ============================================================================
-- STEP REGISTRY
-- ============================================================================

local step_cache = {}

--- Load a step module
---@param name string Step name
---@return table|nil Step module
local function load_step(name)
  if step_cache[name] then
    return step_cache[name]
  end
  
  local ok, step = pcall(require, "gtd-nvim.capture.steps." .. name)
  if ok and step then
    step_cache[name] = step
    return step
  end
  
  vim.notify("Failed to load step: " .. name, vim.log.levels.ERROR)
  return nil
end

-- ============================================================================
-- WORKFLOW REGISTRY
-- ============================================================================

local workflow_cache = {}

--- Load a workflow definition
---@param name string Workflow name
---@return table|nil Workflow definition
local function load_workflow(name)
  if workflow_cache[name] then
    return workflow_cache[name]
  end
  
  local ok, workflow = pcall(require, "gtd-nvim.capture.workflows." .. name)
  if ok and workflow then
    -- Handle both direct definition and module.definition patterns
    if workflow.definition then
      workflow_cache[name] = workflow.definition
      return workflow.definition
    elseif workflow.steps then
      workflow_cache[name] = workflow
      return workflow
    end
  end
  
  vim.notify("Failed to load workflow: " .. name, vim.log.levels.ERROR)
  return nil
end

-- ============================================================================
-- ENGINE
-- ============================================================================

--- Run a workflow
---@param workflow_or_name string|table Workflow name or definition
---@param obj_or_opts table|nil OrgObject or options { mode, object, on_complete, on_cancel }
---@param on_complete function|nil Completion callback (when passing definition directly)
function M.run(workflow_or_name, obj_or_opts, on_complete)
  local workflow
  local opts = {}
  local obj = nil
  
  -- Handle different call signatures
  if type(workflow_or_name) == "string" then
    -- M.run("workflow_name", opts)
    workflow = load_workflow(workflow_or_name)
    opts = obj_or_opts or {}
  elseif type(workflow_or_name) == "table" and workflow_or_name.steps then
    -- M.run(definition, obj, on_complete)
    workflow = workflow_or_name
    if obj_or_opts and obj_or_opts._mode then
      -- It's an OrgObject
      obj = obj_or_opts
    else
      opts = obj_or_opts or {}
    end
    if on_complete then
      opts.on_complete = on_complete
    end
  end
  
  if not workflow then
    vim.notify("Unknown or invalid workflow", vim.log.levels.ERROR)
    return
  end
  
  -- Create or use provided object
  if not obj then
    if opts.object then
      obj = opts.object
    else
      local obj_type = workflow.object_type or Object.TYPE.TASK
      obj = Object.new(obj_type, {
        _mode = opts.mode or Object.MODE.CREATE,
        _workflow = workflow.name or "custom",
      })
    end
  end
  
  -- Store workflow metadata
  obj._workflow = workflow.name or "custom"
  obj._step_index = 0
  obj._steps = workflow.steps
  obj._workflow_opts = vim.tbl_extend("force", workflow.opts or {}, opts)
  
  -- For batch mode
  if opts.mode == Object.MODE.BATCH then
    obj._collected = {}
  end
  
  -- Store callbacks
  obj._on_complete = opts.on_complete or workflow.on_complete
  obj._on_cancel = opts.on_cancel or workflow.on_cancel
  
  -- Start the workflow
  M._run_next_step(obj)
end

--- Run the next step in the workflow
---@param obj table OrgObject with workflow metadata
function M._run_next_step(obj)
  obj._step_index = obj._step_index + 1
  
  local step_def = obj._steps[obj._step_index]
  
  -- No more steps - finalize
  if not step_def then
    M._finalize(obj)
    return
  end
  
  -- Check for skip flag (e.g., from actionable = trash/reference)
  if obj._skip_remaining then
    M._finalize(obj)
    return
  end
  
  -- Handle both string names and inline step tables
  local step
  local step_name
  
  if type(step_def) == "string" then
    -- Load step by name
    step_name = step_def
    step = load_step(step_name)
    if not step then
      vim.notify("Skipping unknown step: " .. step_name, vim.log.levels.WARN)
      M._run_next_step(obj)
      return
    end
  elseif type(step_def) == "table" and step_def.run then
    -- Inline step definition
    step = step_def
    step_name = step_def.name or ("inline_" .. obj._step_index)
  else
    vim.notify("Invalid step definition at index " .. obj._step_index, vim.log.levels.ERROR)
    M._run_next_step(obj)
    return
  end
  
  -- Ensure workflow_opts exists
  obj._workflow_opts = obj._workflow_opts or {}
  
  -- Check if step should run
  if step.should_run then
    local should = step.should_run(obj, obj._workflow_opts)
    if not should then
      M._run_next_step(obj)
      return
    end
  end
  
  -- Check if step applies to this object type
  if step.applies_to then
    local applies = vim.tbl_contains(step.applies_to, obj.type)
    if not applies then
      M._run_next_step(obj)
      return
    end
  end
  
  -- Get step-specific options
  local workflow_opts = obj._workflow_opts or {}
  local step_opts = vim.tbl_extend(
    "force",
    M.config.step_opts[step_name] or {},
    workflow_opts[step_name] or {},
    workflow_opts  -- Also include top-level opts
  )
  
  -- Run the step
  step.run(obj, step_opts, function(result_obj)
    -- Step can return nil to cancel
    if not result_obj then
      M._cancel(obj)
      return
    end
    
    -- Continue to next step
    vim.schedule(function()
      M._run_next_step(result_obj)
    end)
  end)
end

--- Cancel the workflow
---@param obj table OrgObject
function M._cancel(obj)
  vim.notify("Workflow cancelled", vim.log.levels.INFO)
  
  if obj._on_cancel then
    obj._on_cancel(obj)
  elseif M.config.on_cancel then
    M.config.on_cancel(obj)
  end
end

--- Finalize the workflow
---@param obj table OrgObject
function M._finalize(obj)
  -- Use workflow's on_complete if defined (handles batch logic too)
  if obj._on_complete then
    obj._on_complete(obj)
    return
  end
  
  -- For batch mode with collected objects (fallback)
  if obj._collected and #obj._collected > 0 then
    M._handle_batch_complete(obj)
    return
  end
  
  -- Default completion
  if M.config.on_complete then
    M.config.on_complete(obj)
  else
    -- Default: write the object
    M._default_finalize(obj)
  end
end

--- Handle batch completion (multiple tasks captured)
---@param obj table OrgObject with _collected array
function M._handle_batch_complete(obj)
  local count = #obj._collected
  
  if count == 0 then
    vim.notify("No tasks captured", vim.log.levels.INFO)
    return
  end
  
  if count == 1 then
    -- Single task - just finalize it
    obj._on_complete = obj._on_complete
    M._default_finalize(obj._collected[1])
    return
  end
  
  -- Multiple tasks - offer project conversion
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    -- Fallback: just write as individual tasks
    for _, task in ipairs(obj._collected) do
      M._default_finalize(task)
    end
    return
  end
  
  fzf.fzf_exec({
    "󰷐 Create as PROJECT (group these tasks)",
    "󰄲 Create as individual tasks",
    "󰜺 Cancel (don't create anything)",
  }, {
    prompt = string.format("%d tasks captured ❯ ", count),
    winopts = { height = 0.25, width = 0.5 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        
        if sel[1]:match("PROJECT") then
          -- Convert to project
          vim.schedule(function()
            M._convert_to_project(obj._collected)
          end)
        elseif sel[1]:match("individual") then
          -- Write as individual tasks
          for _, task in ipairs(obj._collected) do
            M._default_finalize(task)
          end
        end
        -- Cancel: do nothing
      end,
    },
  })
end

--- Convert collected tasks to a project
---@param tasks table Array of task objects
function M._convert_to_project(tasks)
  -- Run project workflow with these as children
  M.run("project", {
    mode = Object.MODE.CREATE,
    children = tasks,
    on_complete = function(project)
      -- Add tasks as children
      for _, task in ipairs(tasks) do
        Object.add_child(project, task)
      end
      M._default_finalize(project)
    end,
  })
end

--- Default finalization (write to file)
---@param obj table OrgObject
function M._default_finalize(obj)
  local Writer = require("gtd-nvim.capture.model.writer")
  
  -- Determine target file
  local target = obj._target_file
  if not target then
    if Object.is_project(obj) then
      -- Projects get their own file
      local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
      if shared_ok and shared.gtd_path then
        local slug = obj.title:lower():gsub("%s+", "-"):gsub("[^%w-]", "")
        target = shared.gtd_path("projects") .. "/" .. slug .. ".org"
      else
        target = vim.fn.expand("~/Documents/GTD/Projects/" .. obj.title:gsub("%s+", "-") .. ".org")
      end
    else
      -- Tasks go to inbox by default
      local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
      if shared_ok and shared.gtd_path then
        target = shared.gtd_path("inbox")
      else
        target = vim.fn.expand("~/Documents/GTD/Inbox.org")
      end
    end
  end
  
  -- Write
  local success, err = Writer.write(obj, target, { append = true, create_if_missing = true })
  
  if success then
    local icon = Object.is_project(obj) and "󰷐" or "󰄲"
    local dest = vim.fn.fnamemodify(target, ":t:r")
    vim.notify(string.format("%s %s → %s", icon, obj.title, dest), vim.log.levels.INFO)
    
    -- Refresh daemon if available
    local chronos_ok, chronos = pcall(require, "gtd-nvim.gtd.chronos")
    if chronos_ok and chronos.is_running and chronos.is_running() then
      chronos.query("gtd", "refresh", nil)
    end
  else
    vim.notify("Failed to save: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Configure the workflow engine
---@param opts table Configuration options
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
end

return M
