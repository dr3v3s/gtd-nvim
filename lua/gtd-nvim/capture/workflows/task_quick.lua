-- ============================================================================
-- WORKFLOW: TASK_QUICK
-- ============================================================================
-- Minimal task capture: Title → State → Finalize
--
-- @module gtd-nvim.capture.workflows.task_quick
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local Object = require("gtd-nvim.capture.model.object")

return {
  name = "task_quick",
  description = "Quick task capture (minimal steps)",
  object_type = Object.TYPE.TASK,
  
  steps = {
    "title",
    "state",
  },
  
  opts = {
    -- Skip optional steps
    skip_tags = true,
    ask_defer = false,
    ask_due = false,
  },
}
