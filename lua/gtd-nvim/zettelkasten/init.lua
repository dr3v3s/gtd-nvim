-- ~/.config/nvim/lua/utils/zettelkasten/init.lua
-- Module loader and integration point

local M = {}

-- Load core module
local core = require("gtd-nvim.zettelkasten.zettelkasten")

-- Load submodules
local capture = require("gtd-nvim.zettelkasten.capture")
local project = require("gtd-nvim.zettelkasten.project")
local manage = require("gtd-nvim.zettelkasten.manage")
local reading = require("gtd-nvim.zettelkasten.reading")
local people = require("gtd-nvim.zettelkasten.people")

----------------------------------------------------------------------
-- Unified Setup
----------------------------------------------------------------------
function M.setup(opts)
  -- Setup core
  core.setup(opts)
  
  -- Setup submodules
  capture.setup_commands()
  project.setup_commands()
  manage.setup_commands()
  reading.setup_commands()
  people.setup_commands()
  
  -- Setup keymaps (optional)
  if opts and opts.keymaps ~= false then
    capture.setup_keymaps()
    project.setup_keymaps()
    manage.setup_keymaps()
    reading.setup_keymaps()
    people.setup_keymaps()
  end
  
  -- Notify user
  core.notify("Zettelkasten system initialized (capture, project, manage, reading, people)")
end

----------------------------------------------------------------------
-- Export everything
----------------------------------------------------------------------
-- Re-export core functions
M.new_note = core.new_note
M.find_notes = core.find_notes
M.search_notes = core.search_notes
M.recent_notes = core.recent_notes
M.search_all = core.search_all
M.show_backlinks = core.show_backlinks
M.browse_tags = core.browse_tags
M.show_stats = core.show_stats
M.get_paths = core.get_paths
M.get_config = core.get_config
M.write_index = core.write_index

-- Export capture functions
M.quick_note = capture.quick_note
M.daily_note = capture.daily_note
M.meeting_note = capture.meeting_note

-- Export project functions
M.new_project = project.new_project
M.list_projects = project.list_projects
M.project_dashboard = project.dashboard

-- Export manage functions
M.manage_notes = manage.manage_notes
M.bulk_tag_add = manage.bulk_tag_add
M.bulk_tag_remove = manage.bulk_tag_remove

-- Export reading functions
M.new_book = reading.new_book
M.list_books = reading.list_books
M.reading_dashboard = reading.dashboard
M.capture_quote = reading.capture_quote

-- Export people functions
M.new_person = people.new_person
M.list_people = people.list_people
M.people_directory = people.directory
M.recent_interactions = people.recent_interactions
M.birthdays = people.birthdays

return M
