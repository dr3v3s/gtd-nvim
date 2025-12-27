-- ============================================================================
-- GTD-NVIM CHRONOS PICKERS
-- ============================================================================
-- FZF-based pickers for tasks, projects, areas, and search.
-- 
-- NOTE: Picker implementations remain in the main chronos.lua for now due to
-- their complexity and interdependencies. This module provides the public API.
--
-- @module gtd-nvim.gtd.chronos.pickers
-- @version 1.0.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-27"

-- ============================================================================
-- IMPLEMENTATION NOTE
-- ============================================================================
-- The picker functions are complex with many local helper closures.
-- They remain in gtd/chronos.lua and are accessed via the main module.
-- This file exists for future extraction when time permits.
-- ============================================================================

-- Pickers are accessed via require("gtd-nvim.gtd.chronos"):
-- - pick_tasks(opts)
-- - pick_archive()
-- - pick_all()
-- - pick_projects()
-- - pick_all_projects()
-- - pick_areas()
-- - pick_convert_to_project()
-- - pick_search(initial_query)

return M
