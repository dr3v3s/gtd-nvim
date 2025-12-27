-- ============================================================================
-- CAPTURE STEP: REFERENCE
-- ============================================================================
-- Add file or URL reference to task.
--
-- @module gtd-nvim.capture.steps.reference
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M.name = "reference"
M.applies_to = { "task", "project" }

local utils = require("gtd-nvim.capture.utils")

-- ============================================================================
-- STEP INTERFACE
-- ============================================================================

function M.should_run(ctx, opts)
  return true  -- Always offer reference input
end

function M.run(ctx, opts, next_step, cancel)
  vim.ui.input({
    prompt = utils.glyphs.reference .. " Reference (file/URL, optional): ",
  }, function(input)
    if input and input ~= "" then
      -- Format as org link
      if input:match("^[~/]") or input:match("^file:") then
        -- File path
        local expanded = vim.fn.expand(input)
        ctx.reference = "[[file:" .. expanded .. "]]"
      elseif input:match("^https?://") then
        -- URL
        ctx.reference = "[[" .. input .. "]]"
      else
        -- Plain text
        ctx.reference = input
      end
    end
    next_step()
  end)
end

return M
