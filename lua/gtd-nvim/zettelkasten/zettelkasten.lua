-- ============================================================================
-- ZETTELKASTEN BACKWARD COMPATIBILITY WRAPPER
-- ============================================================================
-- This file exists for backward compatibility with old require paths.
-- All functionality has been moved to modular structure:
--   core.lua      - Config, cache, utilities
--   notes.lua     - Note creation, templates
--   search.lua    - Find, search, browse
--   gtd.lua       - GTD integration
--   file_manage.lua - Delete, archive, move
--   init.lua      - Main entry point
--
-- Use: require("gtd-nvim.zettelkasten") instead
-- ============================================================================

-- Just re-export the main init module
return require("gtd-nvim.zettelkasten.init")
