-- ============================================================================
-- GTD-NVIM CAPTURE V2
-- ============================================================================
-- Composable capture system with workflow engine.
--
-- Usage:
--   local capture = require("gtd-nvim.capture")
--   capture.task()        -- Full task capture
--   capture.quick()       -- Quick task capture  
--   capture.batch()       -- Multi-task batch capture
--   capture.project()     -- Project creation
--
-- @module gtd-nvim.capture
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

local Engine = require("gtd-nvim.capture.engine")
local Object = require("gtd-nvim.capture.model.object")

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Full task capture
---@param opts table|nil Options to pass to workflow
function M.task(opts)
  Engine.run("task_full", opts)
end

--- Quick task capture (minimal)
---@param opts table|nil Options
function M.quick(opts)
  Engine.run("task_quick", opts)
end

--- Batch task capture (multiple tasks, project offer)
---@param opts table|nil Options
function M.batch(opts)
  Engine.run("batch", opts)
end

--- Project creation
---@param opts table|nil Options
function M.project(opts)
  Engine.run("project", opts)
end

--- Capture from clipboard
--- Reads clipboard content and pre-fills task title
function M.clipboard()
  local clipboard = vim.fn.getreg("+")
  if not clipboard or clipboard == "" then
    clipboard = vim.fn.getreg("*")
  end
  
  if not clipboard or clipboard == "" then
    vim.notify("Clipboard is empty", vim.log.levels.WARN)
    return
  end
  
  -- Clean up clipboard content for title
  local title = clipboard:gsub("[\r\n]+", " "):gsub("%s+", " ")
  title = vim.trim(title)
  
  -- Truncate if too long
  if #title > 100 then
    title = title:sub(1, 97) .. "..."
  end
  
  -- Run quick capture with pre-filled title
  local obj = Object.new(Object.TYPE.TASK, {
    title = title,
    state = "TODO",
    _mode = Object.MODE.CREATE,
  })
  
  -- If clipboard looks like a URL, store it
  if clipboard:match("^https?://") then
    obj.url = vim.trim(clipboard)
  end
  
  Engine.run("task_quick", { object = obj })
end

--- Clarify task (at cursor or pick)
---@param opts table|nil Options
function M.clarify(opts)
  local clarify_wf = require("gtd-nvim.capture.workflows.clarify")
  clarify_wf.clarify()
end

--- Run a named workflow
---@param name string Workflow name
---@param opts table|nil Options
function M.run(name, opts)
  Engine.run(name, opts)
end

--- Edit an existing object
---@param obj table OrgObject or source info
function M.edit(obj)
  local edit_wf = require("gtd-nvim.capture.workflows.edit")
  if obj then
    edit_wf.full_edit(obj)
  else
    edit_wf.full_edit()  -- Parse from cursor
  end
end

--- Quick edit - pick single field to edit
function M.quick_edit()
  local edit_wf = require("gtd-nvim.capture.workflows.edit")
  edit_wf.quick_edit()
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Configure capture system
---@param opts table Configuration
--   opts.workflows - Custom workflow definitions
--   opts.steps - Step-specific options
function M.setup(opts)
  Engine.setup(opts)
  
  -- Register commands
  vim.api.nvim_create_user_command("CaptureTask", function()
    M.task()
  end, { desc = "Full task capture" })
  
  vim.api.nvim_create_user_command("CaptureQuick", function()
    M.quick()
  end, { desc = "Quick task capture" })
  
  vim.api.nvim_create_user_command("CaptureBatch", function()
    M.batch()
  end, { desc = "Batch task capture" })
  
  vim.api.nvim_create_user_command("CaptureProject", function()
    M.project()
  end, { desc = "Create project" })
end

-- ============================================================================
-- RE-EXPORTS
-- ============================================================================

M.Engine = Engine
M.Object = Object
M.Writer = require("gtd-nvim.capture.model.writer")

return M
