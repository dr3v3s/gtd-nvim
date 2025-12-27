-- ============================================================================
-- STEP: ANOTHER
-- ============================================================================
-- Ask if user wants to capture another task (batch mode).
--
-- @module gtd-nvim.capture.steps.another
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

M.name = "another"
M.applies_to = { "task" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  prompt = "Capture another task?",
  max_batch = 10,  -- Maximum tasks in a batch
}

-- ============================================================================
-- SHOULD RUN
-- ============================================================================

--- Determine if this step should run
---@param obj table OrgObject
---@param opts table Step options
---@return boolean
function M.should_run(obj, opts)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Only run in batch-enabled workflows
  if not obj._workflow_opts or not obj._workflow_opts.batch_enabled then
    return false
  end
  
  -- Check max batch size
  local collected = obj._collected or {}
  if #collected >= opts.max_batch then
    vim.notify("Maximum batch size reached", vim.log.levels.INFO)
    return false
  end
  
  return true
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
  
  -- Initialize collected array if needed
  obj._collected = obj._collected or {}
  
  -- Clone current object and add to collected
  local Object = require("gtd-nvim.capture.model.object")
  local clone = Object.clone(obj)
  clone._collected = nil  -- Don't include collection in clone
  clone._workflow_opts = nil
  table.insert(obj._collected, clone)
  
  local count = #obj._collected
  
  -- Ask if they want another
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  
  if fzf_ok then
    M._run_fzf(obj, opts, next_step, fzf, count)
  else
    M._run_select(obj, opts, next_step, count)
  end
end

--- Run with fzf-lua
function M._run_fzf(obj, opts, next_step, fzf, count)
  fzf.fzf_exec({
    string.format("󰐕 Yes, capture another (%d so far)", count),
    "󰄲 No, I'm done",
    "󰜺 Cancel all",
  }, {
    prompt = opts.prompt .. " ❯ ",
    winopts = { height = 0.25, width = 0.45 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then
          vim.schedule(function() next_step(obj) end)
          return
        end
        
        if sel[1]:match("Yes") then
          -- Restart workflow for another task
          vim.schedule(function()
            M._capture_another(obj, opts, next_step)
          end)
        elseif sel[1]:match("Cancel") then
          -- Cancel everything
          obj._collected = {}
          vim.schedule(function() next_step(nil) end)
        else
          -- Done - continue to finalize
          vim.schedule(function() next_step(obj) end)
        end
      end,
    },
  })
end

--- Capture another task
function M._capture_another(obj, opts, next_step)
  local Object = require("gtd-nvim.capture.model.object")
  
  -- Preserve workflow metadata
  local workflow_opts = obj._workflow_opts or opts or {}
  
  -- Create fresh object but keep collection and workflow metadata
  local new_obj = Object.new(Object.TYPE.TASK, {
    _mode = obj._mode,
    _workflow = obj._workflow,
    _workflow_opts = workflow_opts,
    _collected = obj._collected,
    _on_complete = obj._on_complete,
    _on_cancel = obj._on_cancel,
  })
  
  -- Restart from first step
  new_obj._step_index = 0
  new_obj._steps = obj._steps
  
  -- Run the engine from step 1
  local Engine = require("gtd-nvim.capture.engine")
  Engine._run_next_step(new_obj)
end

--- Fallback with vim.ui.select
function M._run_select(obj, opts, next_step, count)
  vim.ui.select({
    string.format("Yes, capture another (%d so far)", count),
    "No, I'm done",
    "Cancel all",
  }, {
    prompt = opts.prompt,
  }, function(choice)
    if not choice then
      next_step(obj)
      return
    end
    
    if choice:match("Yes") then
      vim.schedule(function()
        M._capture_another(obj, opts, next_step)
      end)
    elseif choice:match("Cancel") then
      obj._collected = {}
      next_step(nil)
    else
      next_step(obj)
    end
  end)
end

return M
