-- ============================================================================
-- WORKFLOW: TASK_FULL
-- ============================================================================
-- Full task capture with all options.
-- Title → Outcome → State → Area → Tags → Comms → Schedule → Finalize
--
-- @module gtd-nvim.capture.workflows.task_full
-- @version 1.1.0
-- @updated 2025-12-23
-- ============================================================================

local Object = require("gtd-nvim.capture.model.object")

return {
  name = "task_full",
  description = "Full task capture with all options",
  object_type = Object.TYPE.TASK,
  
  steps = {
    "outcome",  -- First: What does done look like?
    "title",    -- Then: What action achieves that?
    "state",
    "area",
    "tags",
    "comms",
    "schedule",
  },
  
  opts = {
    -- Outcome is optional for tasks but encouraged
    outcome = {
      skip_for_tasks = false,
    },
    
    -- Area selection
    skip_area = false,
    
    -- Tags multi-select
    multi_select = true,
    
    -- Full date options
    ask_defer = true,
    ask_due = true,
  },
}
