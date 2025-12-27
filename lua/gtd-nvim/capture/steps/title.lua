-- ============================================================================
-- STEP: TITLE
-- ============================================================================
-- Capture task/project title.
--
-- @module gtd-nvim.capture.steps.title
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

M.name = "title"
M.applies_to = { "task", "project", "heading", "note" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  prompt_task = "󰄲 Task: ",
  prompt_project = "󰷐 Project: ",
  prompt_edit = "✏ Title: ",
  allow_empty = false,
}

-- ============================================================================
-- SHOULD RUN
-- ============================================================================

--- Determine if this step should run
---@param obj table OrgObject
---@param opts table Step options
---@return boolean
function M.should_run(obj, opts)
  -- Always run unless we already have a title in edit mode
  if obj._mode == "edit" and obj.title and obj.title ~= "" then
    return opts.always_ask_title == true
  end
  return true
end

-- ============================================================================
-- RUN
-- ============================================================================

--- Execute the step
---@param obj table OrgObject
---@param opts table Step options
---@param next_step function Callback to continue to next step
function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Determine prompt
  local prompt
  if obj._mode == "edit" then
    prompt = opts.prompt_edit
  elseif obj.type == "project" then
    prompt = opts.prompt_project
  else
    prompt = opts.prompt_task
  end
  
  -- Input options
  local input_opts = {
    prompt = prompt,
  }
  
  -- Pre-fill in edit mode OR if title exists
  if obj.title and obj.title ~= "" then
    input_opts.default = obj.title
  end
  
  vim.ui.input(input_opts, function(title)
    -- Handle cancel
    if title == nil then
      next_step(nil)  -- Signal cancel
      return
    end
    
    -- Handle empty
    if title == "" then
      if opts.allow_empty then
        next_step(obj)
      else
        if obj._mode == "edit" then
          -- Keep original title in edit mode
          next_step(obj)
        else
          vim.notify("Title is required", vim.log.levels.WARN)
          next_step(nil)  -- Cancel
        end
      end
      return
    end
    
    -- Set title
    obj.title = title
    next_step(obj)
  end)
end

return M
