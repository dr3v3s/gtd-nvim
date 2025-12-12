-- ============================================================================
-- ZETTELKASTEN INIT MODULE
-- ============================================================================
-- Module loader and unified interface for Zettelkasten system
--
-- @module gtd-nvim.zettelkasten
-- @version 1.0.0
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-11"

-- ============================================================================
-- LOAD CORE MODULES
-- ============================================================================

local core = require("gtd-nvim.zettelkasten.core")
local notes_mod = require("gtd-nvim.zettelkasten.notes")
local search_mod = require("gtd-nvim.zettelkasten.search")
local gtd_mod = require("gtd-nvim.zettelkasten.gtd")
local file_manage_mod = require("gtd-nvim.zettelkasten.file_manage")

-- Export glyphs for external use
M.glyphs = core.glyphs
M.colors = core.colors

-- ============================================================================
-- LOAD LEGACY SUBMODULES (optional - may fail if not present)
-- ============================================================================

local legacy_modules = {}

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(opts)
  opts = opts or {}

  -- Setup core configuration
  core.setup_config(opts)

  -- Setup highlight groups (from shared)
  core.shared.setup_highlights()

  -- Write initial index
  notes_mod.write_index()

  -- Focus-mode integration
  local focus_mode = (function()
    local ok, mod = pcall(require, "utils.focus_mode")
    if ok and mod and type(mod.set) == "function" then
      return mod
    end
    return nil
  end)()

  if focus_mode then
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*.md",
      callback = function(args)
        local path = vim.fn.fnamemodify(args.file or vim.fn.expand("<afile>:p"), ":p")
        if path:sub(1, #core.cfg.notes_dir) == core.cfg.notes_dir then
          pcall(focus_mode.set, "zk")
        end
      end,
    })
  end

  -- ========================================================================
  -- USER COMMANDS
  -- ========================================================================

  local g = core.glyphs

  -- Note creation
  vim.api.nvim_create_user_command("ZettelNew", function(c)
    notes_mod.new_note({ title = (c.args ~= "" and c.args or nil) })
  end, { nargs = "?", desc = g.note.zettel .. " Create new note" })

  vim.api.nvim_create_user_command("ZettelDaily", function()
    gtd_mod.daily_note_with_gtd()
  end, { desc = g.note.daily .. " Open/create daily note" })

  vim.api.nvim_create_user_command("ZettelQuick", function(c)
    notes_mod.quick_note(c.args ~= "" and c.args or nil)
  end, { nargs = "?", desc = g.note.quick .. " Quick capture" })

  vim.api.nvim_create_user_command("ZettelProject", function(c)
    notes_mod.new_project(c.args ~= "" and c.args or nil)
  end, { nargs = "?", desc = g.note.project .. " Create project note" })

  vim.api.nvim_create_user_command("ZettelReading", function(c)
    notes_mod.new_reading({ title = (c.args ~= "" and c.args or nil) })
  end, { nargs = "?", desc = g.note.reading .. " Create reading note" })

  -- ZettelPerson and ZettelPeople are defined in people.lua's setup_commands()

  vim.api.nvim_create_user_command("ZettelMeeting", function(c)
    notes_mod.new_meeting({ title = (c.args ~= "" and c.args or nil) })
  end, { nargs = "?", desc = g.note.meeting .. " Create meeting note" })

  -- Search & navigation
  vim.api.nvim_create_user_command("ZettelFind", search_mod.find_notes,
    { desc = g.workflow.search .. " Find notes" })

  vim.api.nvim_create_user_command("ZettelSearch", search_mod.search_notes,
    { desc = g.workflow.search .. " Search note contents" })

  vim.api.nvim_create_user_command("ZettelSearchAll", search_mod.search_all,
    { desc = g.workflow.search .. " Search notes + GTD" })

  vim.api.nvim_create_user_command("ZettelRecent", search_mod.recent_notes,
    { desc = g.ui.clock .. " Recent notes" })

  vim.api.nvim_create_user_command("ZettelBacklinks", function()
    search_mod.show_backlinks()
  end, { desc = g.workflow.backlink .. " Show backlinks" })

  vim.api.nvim_create_user_command("ZettelTags", search_mod.browse_tags,
    { desc = g.workflow.tag .. " Browse tags" })

  -- GTD integration
  vim.api.nvim_create_user_command("ZettelGTD", gtd_mod.browse_tasks,
    { desc = core.g.container.inbox .. " Browse GTD tasks" })

  -- Management
  vim.api.nvim_create_user_command("ZettelManage", file_manage_mod.manage_notes,
    { desc = g.ui.brain .. " Manage notes" })

  vim.api.nvim_create_user_command("ZettelStats", search_mod.show_stats,
    { desc = g.ui.stats .. " Show statistics" })

  vim.api.nvim_create_user_command("ZettelClearCache", function()
    core.clear_cache()
    core.notify(g.ui.sync .. " Cache cleared")
  end, { desc = g.ui.sync .. " Clear cache" })

  vim.api.nvim_create_user_command("ZettelUpdateBacklinks", notes_mod.update_backlinks_in_buffer,
    { desc = g.workflow.backlink .. " Update backlinks in buffer" })

  vim.api.nvim_create_user_command("ZettelIndex", function()
    notes_mod.write_index()
    core.notify(g.workflow.index .. " Index updated")
  end, { desc = g.workflow.index .. " Rebuild index" })

  -- ========================================================================
  -- LEGACY SUBMODULES (if available)
  -- ========================================================================

  legacy_modules.capture = safe_require("gtd-nvim.zettelkasten.capture")
  legacy_modules.project = safe_require("gtd-nvim.zettelkasten.project")
  legacy_modules.manage = safe_require("gtd-nvim.zettelkasten.manage")
  legacy_modules.reading = safe_require("gtd-nvim.zettelkasten.reading")
  legacy_modules.people = safe_require("gtd-nvim.zettelkasten.people")

  -- Setup legacy submodule commands
  for name, mod in pairs(legacy_modules) do
    if mod and type(mod.setup_commands) == "function" then
      pcall(mod.setup_commands)
    end
  end

  -- ========================================================================
  -- KEYMAPS
  -- ========================================================================
  
  -- Setup keymaps if enabled
  -- opts.keymaps can be:
  --   false      = no keymaps
  --   true/nil   = default keymaps with <leader>z prefix
  --   { ... }    = custom keymap config (merged with defaults)
  if opts.keymaps ~= false then
    local keymap_opts = type(opts.keymaps) == "table" and opts.keymaps or {}
    M.setup_keymaps(keymap_opts)
  end

  -- ========================================================================
  -- AUTO COMMANDS
  -- ========================================================================

  -- Auto-update backlinks on save
  if core.cfg.backlinks.show_in_buffer then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = "*.md",
      callback = function()
        if vim.fn.expand("%:p"):match("^" .. vim.pesc(core.cfg.notes_dir)) then
          vim.defer_fn(notes_mod.update_backlinks_in_buffer, 100)
        end
      end,
    })
  end

  core.notify(g.ui.brain .. " Zettelkasten v" .. M._VERSION .. " ready")
end

-- ============================================================================
-- EXPORTED API
-- ============================================================================

-- Core
M.get_paths = function()
  return {
    notes_dir = core.cfg.notes_dir,
    daily_dir = core.cfg.daily_dir,
    quick_dir = core.cfg.quick_dir,
    templates_dir = core.cfg.templates_dir,
    archive_dir = core.cfg.archive_dir,
    gtd_dir = core.cfg.gtd_dir,
    file_ext = core.cfg.file_ext,
  }
end
M.get_config = function() return vim.deepcopy(core.cfg) end
M.get_stats = function()
  return {
    notes_count = #core.get_all_notes(),
    tags_count = vim.tbl_count(core.get_all_tags()),
    gtd_tasks_count = #gtd_mod.get_tasks(),
    cache_enabled = core.cfg.cache.enabled,
  }
end
M.clear_cache = core.clear_cache
M.clear_all_cache = core.clear_cache  -- Alias for backward compatibility
M.notify = core.notify

-- Notes
M.new_note = notes_mod.new_note
M.quick_note = notes_mod.quick_note
M.daily_note = gtd_mod.daily_note_with_gtd
M.new_project = notes_mod.new_project
M.new_reading = notes_mod.new_reading
M.new_person = notes_mod.new_person
M.new_meeting = notes_mod.new_meeting
M.write_index = notes_mod.write_index
M.update_backlinks_in_buffer = notes_mod.update_backlinks_in_buffer
M.create_note_file = notes_mod.create_note_file

-- Search
M.find_notes = search_mod.find_notes
M.search_notes = search_mod.search_notes
M.search_all = search_mod.search_all
M.recent_notes = search_mod.recent_notes
M.show_backlinks = search_mod.show_backlinks
M.browse_tags = search_mod.browse_tags
M.show_stats = search_mod.show_stats

-- GTD
M.browse_gtd_tasks = gtd_mod.browse_tasks
M.get_gtd_tasks = gtd_mod.get_tasks

-- Manage
M.manage_notes = file_manage_mod.manage_notes

-- Legacy module access (for backward compat)
M.legacy = legacy_modules

-- ============================================================================
-- KEYMAPS
-- ============================================================================

-- Default keymap configuration
M.default_keymaps = {
  prefix = "<leader>z",
  
  -- Notes creation
  new_note     = "n",   -- New note
  daily_note   = "d",   -- Daily note with GTD
  quick_note   = "q",   -- Quick capture
  new_project  = "p",   -- New project
  new_meeting  = "M",   -- New meeting
  
  -- People
  new_person   = "o",   -- New person
  list_people  = "O",   -- List/manage people
  interactions = "I",   -- Recent interactions
  
  -- Search & Navigation
  find_notes   = "f",   -- Find notes (files)
  search_notes = "s",   -- Search content
  search_all   = "a",   -- Search all (Notes+GTD)
  recent_notes = "r",   -- Recent notes
  browse_tags  = "t",   -- Browse tags
  backlinks    = "b",   -- Show backlinks
  gtd_tasks    = "g",   -- Browse GTD tasks
  
  -- Management
  manage       = "m",   -- Manage notes (fzf)
  clear_cache  = "c",   -- Clear cache
  stats        = "i",   -- Statistics & info
  update_bl    = "u",   -- Update backlinks
  
  -- Legacy (optional)
  list_books   = "B",   -- List books (reading)
  reading_dash = "R",   -- Reading dashboard
  list_projects= "P",   -- List projects
  project_dash = "D",   -- Project dashboard
}

function M.setup_keymaps(opts)
  opts = opts or {}
  local keys = vim.tbl_deep_extend("force", M.default_keymaps, opts)
  local prefix = keys.prefix
  local g = core.glyphs  -- Local reference to glyphs
  
  local function map(key, cmd, desc)
    if key and key ~= "" then
      vim.keymap.set("n", prefix .. key, cmd, { desc = desc, silent = true })
    end
  end
  
  -- Notes creation
  map(keys.new_note,     M.new_note,     g.note.zettel .. " New note")
  map(keys.daily_note,   M.daily_note,   g.note.daily .. " Daily note")
  map(keys.quick_note,   M.quick_note,   g.note.quick .. " Quick note")
  map(keys.new_project,  M.new_project,  g.note.project .. " New project")
  map(keys.new_meeting,  M.new_meeting,  g.note.meeting .. " New meeting")
  
  -- People
  map(keys.new_person,   M.new_person,   g.note.person .. " New person")
  if legacy_modules.people then
    map(keys.list_people,  legacy_modules.people.list_people, g.note.person .. " List people")
    map(keys.interactions, function() legacy_modules.people.recent_interactions(30) end, g.note.person .. " Recent interactions")
  end
  
  -- Search & Navigation
  map(keys.find_notes,   M.find_notes,   g.workflow.search .. " Find notes")
  map(keys.search_notes, M.search_notes, g.workflow.search .. " Search content")
  map(keys.search_all,   M.search_all,   g.workflow.search .. " Search all")
  map(keys.recent_notes, M.recent_notes, g.ui.clock .. " Recent notes")
  map(keys.browse_tags,  M.browse_tags,  g.workflow.tag .. " Browse tags")
  map(keys.backlinks,    M.show_backlinks, g.workflow.backlink .. " Show backlinks")
  map(keys.gtd_tasks,    M.browse_gtd_tasks, core.shared.glyphs.container.inbox .. " GTD tasks")
  
  -- Management
  map(keys.manage,       M.manage_notes, g.ui.brain .. " Manage notes")
  map(keys.clear_cache,  function() M.clear_cache(); M.notify("Cache cleared") end, g.ui.sync .. " Clear cache")
  map(keys.stats,        M.show_stats,   g.ui.stats .. " Statistics")
  map(keys.update_bl,    M.update_backlinks_in_buffer, g.workflow.backlink .. " Update backlinks")
  
  -- Legacy keymaps (if modules available)
  if legacy_modules.reading then
    map(keys.list_books,   legacy_modules.reading.list_books, g.note.reading .. " List books")
    map(keys.reading_dash, legacy_modules.reading.dashboard,  g.note.reading .. " Reading dashboard")
  end
  if legacy_modules.project then
    map(keys.list_projects, legacy_modules.project.list_projects, g.note.project .. " List projects")
    map(keys.project_dash,  legacy_modules.project.dashboard,     g.note.project .. " Project dashboard")
  end
  
  core.notify(g.ui.brain .. " Keymaps ready (prefix: " .. prefix .. ")")
end

return M
