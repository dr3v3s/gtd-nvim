-- ============================================================================
-- CAPTURE STEP: WAITING
-- ============================================================================
-- Collect WAITING FOR metadata when state is WAITING.
--
-- @module gtd-nvim.capture.steps.waiting
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M.name = "waiting"
M.applies_to = { "task" }

local utils = require("gtd-nvim.capture.utils")

-- ============================================================================
-- STEP INTERFACE
-- ============================================================================

function M.should_run(ctx, opts)
  return ctx.state == "WAITING"
end

function M.run(ctx, opts, next_step, cancel)
  -- Step 1: Who are we waiting for?
  vim.ui.input({
    prompt = utils.glyphs.waiting .. " Waiting for (person/org): ",
  }, function(who)
    if not who or who == "" then
      next_step()
      return
    end
    
    ctx.waiting_for = who
    ctx.extra_props = ctx.extra_props or {}
    ctx.extra_props.WAITING_FOR = who
    
    -- Step 2: What are we waiting for?
    vim.ui.input({
      prompt = utils.glyphs.waiting .. " Waiting for what: ",
    }, function(what)
      if what and what ~= "" then
        ctx.extra_props.WAITING_WHAT = what
      end
      
      -- Step 3: Follow-up date
      local help = utils.date_help()
      local suggestion = utils.parse_date("+7d") or ""
      
      vim.ui.input({
        prompt = utils.glyphs.calendar .. " Follow-up [" .. suggestion .. "] (" .. help .. "): ",
      }, function(date)
        if date and date ~= "" then
          ctx.scheduled = utils.parse_date(date) or date
        elseif suggestion ~= "" then
          ctx.scheduled = suggestion
        end
        
        next_step()
      end)
    end)
  end)
end

return M
