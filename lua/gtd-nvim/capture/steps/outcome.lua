-- ============================================================================
-- STEP: OUTCOME
-- ============================================================================
-- Capture desired outcome - the "why" behind the action.
-- 
-- GTD principle: Every action should have a clear outcome.
-- Bad:  "Call mom"
-- Good: "Call mom" → Outcome: "Mom agrees to babysit Friday evening"
--
-- @module gtd-nvim.capture.steps.outcome
-- @version 1.1.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2025-12-23"

M.name = "outcome"
M.applies_to = { "task", "project" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  -- Prompts
  prompt_first = "󰆤 What outcome do you want? ",
  prompt_task = "󰆤 What does DONE look like? ",
  prompt_project = "󰆤 Desired outcome (success vision): ",
  prompt_short = "󰆤 Outcome: ",
  
  -- Help text shown below prompt
  help_text = "e.g., 'Mom agrees to babysit Friday' or 'Contract signed by client'",
  
  -- Required for projects, encouraged for tasks
  required_for_projects = true,
  required_for_tasks = false,
  
  -- Skip entirely?
  skip_outcome = false,
  
  -- Show examples based on task title patterns
  show_examples = true,
}

-- ============================================================================
-- EXAMPLES
-- ============================================================================

-- Context-aware outcome suggestions based on action verbs
local outcome_examples = {
  -- Communication
  { pattern = "^[Cc]all", example = "Person agrees to X / Person confirms Y" },
  { pattern = "^[Rr]ing", example = "Person agrees to X / Person confirms Y" },
  { pattern = "^[Ee]mail", example = "Response received / Information sent" },
  { pattern = "^[Mm]essage", example = "Reply received / Request acknowledged" },
  { pattern = "^[Tt]ext", example = "Response received with answer" },
  { pattern = "^[Aa]sk", example = "Got answer/decision on X" },
  { pattern = "^[Dd]iscuss", example = "Reached agreement on X" },
  { pattern = "^[Mm]eet", example = "Decisions made / Next steps clear" },
  
  -- Planning/Research
  { pattern = "^[Rr]esearch", example = "Have enough info to decide on X" },
  { pattern = "^[Ff]ind", example = "Located X / Have options for Y" },
  { pattern = "^[Ll]ook", example = "Know what/where/how X" },
  { pattern = "^[Dd]ecide", example = "Decision made on X" },
  { pattern = "^[Pp]lan", example = "Clear plan for X with next actions" },
  { pattern = "^[Rr]eview", example = "X reviewed, issues identified" },
  
  -- Creation/Completion
  { pattern = "^[Ww]rite", example = "Draft complete / Document ready for review" },
  { pattern = "^[Cc]reate", example = "X exists and works" },
  { pattern = "^[Bb]uild", example = "X functional and tested" },
  { pattern = "^[Ff]inish", example = "X 100% complete" },
  { pattern = "^[Cc]omplete", example = "X done and delivered" },
  { pattern = "^[Pp]repare", example = "X ready for Y" },
  { pattern = "^[Ss]etup", example = "X configured and working" },
  { pattern = "^[Ff]ix", example = "X working correctly again" },
  
  -- Purchasing/Acquisition
  { pattern = "^[Bb]uy", example = "X purchased and in hand" },
  { pattern = "^[Oo]rder", example = "Order placed, delivery confirmed" },
  { pattern = "^[Gg]et", example = "Have X in possession" },
  { pattern = "^[Pp]ick", example = "X collected/retrieved" },
  
  -- Scheduling
  { pattern = "^[Ss]chedule", example = "Meeting booked for X date" },
  { pattern = "^[Bb]ook", example = "Reservation confirmed" },
  { pattern = "^[Aa]rrange", example = "X organized and confirmed" },
  
  -- Danish patterns
  { pattern = "^[Rr]inge?%s+til", example = "Person siger ja til X" },
  { pattern = "^[Ss]kriv%s+til", example = "Svar modtaget / Info sendt" },
  { pattern = "^[Kk]øb", example = "X købt og modtaget" },
  { pattern = "^[Bb]estil", example = "Ordre bekræftet" },
  { pattern = "^[Ff]ind", example = "Ved hvad/hvor/hvordan X" },
}

--- Get example based on task title
---@param title string Task title
---@return string|nil example
local function get_example_for_title(title)
  if not title then return nil end
  
  for _, item in ipairs(outcome_examples) do
    if title:match(item.pattern) then
      return item.example
    end
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
  
  if opts.skip_outcome then
    return false
  end
  
  -- In edit mode with existing outcome, optionally skip
  if obj._mode == "edit" and obj.outcome and opts.always_ask ~= true then
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
---@param next_step function Callback to continue to next step
function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Determine prompt based on context
  local prompt
  if obj.type == "project" then
    prompt = opts.prompt_project
  elseif not obj.title or obj.title == "" then
    -- Outcome first (before title)
    prompt = opts.prompt_first
  else
    prompt = opts.prompt_task
  end
  
  -- Add contextual example if we have a title
  local example = nil
  if opts.show_examples and obj.title and obj.title ~= "" then
    example = get_example_for_title(obj.title)
  end
  
  -- Build full prompt with help
  local full_prompt = prompt
  if example then
    full_prompt = prompt .. "\n  (e.g., '" .. example .. "')\n  > "
  end
  
  local input_opts = {
    prompt = full_prompt,
  }
  
  -- Pre-fill in edit mode
  if obj._mode == "edit" and obj.outcome then
    input_opts.default = obj.outcome
  end
  
  -- Show notification with context if we have an example
  if example and opts.show_examples then
    vim.notify("💡 Example: " .. example, vim.log.levels.INFO)
  end
  
  vim.ui.input(input_opts, function(outcome)
    -- Handle cancel (nil = Escape pressed)
    if outcome == nil then
      next_step(nil)
      return
    end
    
    -- Handle empty
    if outcome == "" then
      local required = (obj.type == "project" and opts.required_for_projects)
                    or (obj.type == "task" and opts.required_for_tasks)
      
      if required then
        vim.notify("󰀨 Outcome helps clarify why this matters", vim.log.levels.WARN)
        -- Re-run this step
        vim.schedule(function()
          M.run(obj, opts, next_step)
        end)
        return
      end
      
      -- Empty is OK, continue
      next_step(obj)
      return
    end
    
    -- Set outcome
    obj.outcome = outcome
    
    -- Also set as property for org file
    obj.properties = obj.properties or {}
    obj.properties.OUTCOME = outcome
    
    next_step(obj)
  end)
end

return M
