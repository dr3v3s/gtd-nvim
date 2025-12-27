-- ~/.config/nvim/lua/utils/zettelkasten/init.lua
-- Full Zettelkasten system loader with all submodules
-- 
-- Use: require("utils.zettelkasten.init") for full system
-- Or:  require("utils.zettelkasten") for core only

local M = {}

-- Load core module
local core = require("utils.zettelkasten.core")

-- Safely load submodules
local function safe_require(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
  return nil
end

local capture = safe_require("utils.zettelkasten.capture")
local project = safe_require("utils.zettelkasten.project")
local manage = safe_require("utils.zettelkasten.manage")
local reading = safe_require("utils.zettelkasten.reading")
local people = safe_require("utils.zettelkasten.people")

----------------------------------------------------------------------
-- Unified Setup
----------------------------------------------------------------------
function M.setup(opts)
  -- Setup core first
  core.setup(opts)
  
  -- Setup submodules
  if capture and capture.setup_commands then capture.setup_commands() end
  if project and project.setup_commands then project.setup_commands() end
  if manage and manage.setup_commands then manage.setup_commands() end
  if reading and reading.setup_commands then reading.setup_commands() end
  if people and people.setup_commands then people.setup_commands() end
  
  -- Setup keymaps (optional)
  if opts and opts.keymaps ~= false then
    if capture and capture.setup_keymaps then capture.setup_keymaps() end
    if project and project.setup_keymaps then project.setup_keymaps() end
    if manage and manage.setup_keymaps then manage.setup_keymaps() end
    if reading and reading.setup_keymaps then reading.setup_keymaps() end
    if people and people.setup_keymaps then people.setup_keymaps() end
  end
  
  -- Report loaded modules
  local loaded = { "core" }
  if capture then table.insert(loaded, "capture") end
  if project then table.insert(loaded, "project") end
  if manage then table.insert(loaded, "manage") end
  if reading then table.insert(loaded, "reading") end
  if people then table.insert(loaded, "people") end
  
  core.notify("Zettelkasten loaded: " .. table.concat(loaded, ", "))
end

----------------------------------------------------------------------
-- Re-export Core Functions
----------------------------------------------------------------------
-- Config & paths
M.get_paths = core.get_paths
M.get_config = core.get_config
M.notify = core.notify

-- Note operations
M.new_note = core.new_note
M.quick_note = core.quick_note
M.daily_note = core.daily_note
M.create_note_file = core.create_note_file

-- Search & navigation
M.find_notes = core.find_notes
M.search_notes = core.search_notes
M.search_all = core.search_all
M.recent_notes = core.recent_notes
M.browse_tags = core.browse_tags
M.show_backlinks = core.show_backlinks

-- Data functions
M.get_all_notes = core.get_all_notes
M.get_gtd_tasks = core.get_gtd_tasks
M.get_all_tags = core.get_all_tags
M.get_backlinks = core.get_backlinks
M.extract_tags_from_content = core.extract_tags_from_content

-- Cache & index
M.clear_cache = core.clear_cache
M.write_index = core.write_index
M.show_stats = core.show_stats

-- Utilities for submodules
M.ensure_dir = core.ensure_dir
M.file_exists = core.file_exists
M.join = core.join
M.slugify = core.slugify
M.gen_id = core.gen_id
M.gen_filename = core.gen_filename
M.apply_template = core.apply_template
M.open_and_seed = core.open_and_seed
M.find_content_row = core.find_content_row
M.sel_to_paths_fzf = core.sel_to_paths_fzf
M.have_fzf = core.have_fzf
M.have_telescope = core.have_telescope

----------------------------------------------------------------------
-- Capture Module Functions
----------------------------------------------------------------------
if capture then
  M.capture_daily_note = capture.daily_note
  M.capture_quick_note = capture.quick_note
  M.meeting_note = capture.meeting_note
  M.capture_to_gtd = capture.capture_to_gtd
  M.note_to_gtd_task = capture.note_to_gtd_task
  M.browse_gtd_tasks = capture.browse_gtd_tasks
  M.extract_meeting_actions = capture.extract_meeting_actions
  M.refresh_daily_gtd = capture.refresh_daily_gtd
end

----------------------------------------------------------------------
-- Project Module Functions
----------------------------------------------------------------------
if project then
  M.new_project = project.new_project
  M.list_projects = project.list_projects
  M.toggle_project_status = project.toggle_project_status
  M.archive_project = project.archive_project
  M.project_dashboard = project.dashboard
end

----------------------------------------------------------------------
-- Manage Module Functions
----------------------------------------------------------------------
if manage then
  M.manage_notes = manage.manage_notes
  M.delete_notes = manage.delete_notes
  M.archive_notes = manage.archive_notes
  M.move_notes = manage.move_notes
  M.bulk_tag_add = manage.bulk_tag_add
  M.bulk_tag_remove = manage.bulk_tag_remove
end

----------------------------------------------------------------------
-- Reading Module Functions
----------------------------------------------------------------------
if reading then
  M.new_book = reading.new_book
  M.list_books = reading.list_books
  M.update_reading_status = reading.update_reading_status
  M.update_rating = reading.update_rating
  M.reading_dashboard = reading.dashboard
  M.capture_quote = reading.capture_quote
end

----------------------------------------------------------------------
-- People Module Functions
----------------------------------------------------------------------
if people then
  M.new_person = people.new_person
  M.list_people = people.list_people
  M.add_meeting = people.add_meeting
  M.add_interaction = people.add_interaction
  M.people_directory = people.directory
  M.recent_interactions = people.recent_interactions
  M.birthdays = people.birthdays
end

return M
