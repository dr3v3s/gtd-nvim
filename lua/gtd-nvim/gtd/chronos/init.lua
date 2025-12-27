-- ============================================================================
-- GTD-NVIM CHRONOS MODULE INDEX
-- ============================================================================
-- Entry point for the chronos submodule system.
-- Provides access to utils, actions, and delegates to main chronos.lua.
--
-- Usage:
--   local chronos = require("gtd-nvim.gtd.chronos")  -- Main API (legacy)
--   local utils = require("gtd-nvim.gtd.chronos.utils")  -- Utilities
--   local actions = require("gtd-nvim.gtd.chronos.actions")  -- Task operations
--
-- @module gtd-nvim.gtd.chronos
-- @version 1.0.0
-- @updated 2025-12-27
-- ============================================================================

-- This init.lua is part of the gtd/chronos/ directory.
-- The main chronos.lua is at gtd/chronos.lua (parent directory).
-- 
-- When you require("gtd-nvim.gtd.chronos"), Lua first looks for:
--   1. gtd/chronos.lua (file) - FOUND, this is the main module
--   2. gtd/chronos/init.lua (directory) - this file
--
-- Since gtd/chronos.lua exists, THIS FILE IS NOT LOADED by default.
-- The submodules (utils, actions) are accessed directly:
--   require("gtd-nvim.gtd.chronos.utils")
--   require("gtd-nvim.gtd.chronos.actions")

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-27"

-- Direct re-exports of submodules
M.utils = require("gtd-nvim.gtd.chronos.utils")
M.actions = require("gtd-nvim.gtd.chronos.actions")

return M
