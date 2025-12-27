-- ============================================================================
-- CAPTURE STEP: FINALIZE
-- ============================================================================
-- Write the task/project to file and handle post-creation actions.
--
-- @module gtd-nvim.capture.steps.finalize
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M.name = "finalize"
M.applies_to = { "task", "project" }

local utils = require("gtd-nvim.capture.utils")

-- ============================================================================
-- STEP INTERFACE
-- ============================================================================

function M.should_run(ctx, opts)
  return true  -- Always run
end

function M.run(ctx, opts, next_step, cancel)
  -- Generate task ID
  ctx.task_id = ctx.task_id or utils.generate_task_id()
  
  -- Create ZK note if requested
  if ctx._create_zk_note then
    local zk_step = require("gtd-nvim.capture.steps.zk_note")
    ctx.zk_note = zk_step.create_note(ctx)
  end
  
  -- Build entry
  local lines, id
  if ctx._type == "project" then
    lines, id = utils.build_project(ctx)
  else
    lines, id = utils.build_task(ctx)
  end
  
  -- Determine target file
  local target = ctx.path
  if not target then
    if ctx._type == "project" then
      local slug = ctx.title:gsub("%s+", "-"):gsub("[^%w%-]", "")
      target = utils.projects_dir() .. "/" .. slug .. ".org"
    else
      target = utils.inbox_path()
    end
  end
  
  -- Ensure file exists
  local title = vim.fn.fnamemodify(target, ":t:r")
  utils.ensure_file(target, title)
  
  -- Write to file
  local success
  if ctx._type == "project" then
    -- Projects are new files - write fresh
    success = utils.write_file(target, lines)
  else
    -- Tasks are appended
    success = utils.append_file(target, lines)
  end
  
  if success then
    -- Notify
    if opts.notify ~= false then
      local icon = ctx._type == "project" and utils.glyphs.project or utils.glyphs[ctx.state:lower()] or utils.glyphs.todo
      local dest = vim.fn.fnamemodify(target, ":t:r")
      local msg = string.format("%s %s → %s", icon, ctx.title, dest)
      if ctx.zk_note then
        msg = msg .. " +note"
      end
      vim.notify(msg, vim.log.levels.INFO)
    end
    
    -- Refresh daemon
    if opts.refresh_daemon ~= false then
      local chronos_ok, chronos = pcall(require, "gtd-nvim.gtd.chronos")
      if chronos_ok and chronos and chronos.is_running and chronos.is_running() then
        chronos.query("gtd", "refresh", nil)
      end
    end
    
    -- Prompt for communication action
    M._maybe_prompt_action(ctx, opts)
  else
    vim.notify("Failed to create " .. ctx._type, vim.log.levels.ERROR)
  end
  
  -- Workflow complete
  next_step()
end

--- Prompt for immediate communication action
function M._maybe_prompt_action(ctx, opts)
  if not ctx.contact or not ctx.contact.info then
    return
  end
  
  if opts.prompt_action == false then
    return
  end
  
  vim.schedule(function()
    local comms_ok, comms = pcall(require, "gtd-nvim.gtd.comms")
    if comms_ok and comms then
      comms.prompt_action(
        function() return comms.open_url(ctx.contact.info.url) end,
        { full_name = ctx.contact.name },
        ctx.contact.context_type,
        nil
      )
    end
  end)
end

return M
