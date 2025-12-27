-- ============================================================================
-- GTD-NVIM KAIROS COMPATIBILITY SHIM
-- ============================================================================
-- This file exists for backward compatibility only.
-- All functionality has been moved to daemon.lua (Chronos integration).
--
-- @module gtd-nvim.gtd.kairos
-- @deprecated Use require("gtd-nvim.gtd.daemon") instead
-- @version 1.1.0
-- @updated 2025-12-22
-- ============================================================================

-- Redirect all calls to the new daemon module
local daemon = require("gtd-nvim.gtd.daemon")

-- Log deprecation warning once
local warned = false
local function warn_deprecation()
  if not warned then
    vim.schedule(function()
      vim.notify(
        "[gtd-nvim] kairos.lua is deprecated. Use daemon.lua instead.\n" ..
        "Update: require('gtd-nvim.gtd.kairos') → require('gtd-nvim.gtd.daemon')",
        vim.log.levels.WARN
      )
    end)
    warned = true
  end
end

-- Create a proxy that warns on first use
local M = setmetatable({}, {
  __index = function(_, key)
    warn_deprecation()
    return daemon[key]
  end,
  __newindex = function(_, key, value)
    warn_deprecation()
    daemon[key] = value
  end,
})

return M
