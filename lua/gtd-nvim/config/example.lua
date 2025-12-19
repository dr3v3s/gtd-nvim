-- gtd-nvim/config/example.lua
-- Example user configuration template
-- This is used by M.generate_user_config() to create ~/.config/gtd-nvim/config.lua

local M = {}

M.content = [[
-- ~/.config/gtd-nvim/config.lua
-- GTD-Neovim User Configuration
-- Copy this file to ~/.config/gtd-nvim/config.lua and customize

return {
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PATHS
  -- ═══════════════════════════════════════════════════════════════════════════
  gtd_home = "~/Documents/GTD",
  notes_home = "~/Documents/Notes",

  -- ═══════════════════════════════════════════════════════════════════════════
  -- USER IDENTITY
  -- ═══════════════════════════════════════════════════════════════════════════
  user = {
    name = "Your Name",
    email = "you@example.com",
    timezone = "Europe/Copenhagen",  -- Your timezone
    language = "en",                 -- "en", "da", etc.
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- AREAS OF FOCUS (GTD Horizons of Focus - Level 2)
  -- These become subdirectories under GTD/Areas/
  -- ═══════════════════════════════════════════════════════════════════════════
  areas = {
    { id = "work",     name = "Work",         icon = "󰊕", color = "#89b4fa", dir = "Work" },
    { id = "family",   name = "Family",       icon = "󰋑", color = "#f5c2e7", dir = "Family" },
    { id = "health",   name = "Health",       icon = "󰊗", color = "#a6e3a1", dir = "Health" },
    { id = "finance",  name = "Finance",      icon = "󰗃", color = "#f9e2af", dir = "Finance" },
    { id = "home",     name = "Home",         icon = "󰋞", color = "#fab387", dir = "Home" },
    { id = "personal", name = "Personal Dev", icon = "󰛕", color = "#cba6f7", dir = "Personal" },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- CONTEXTS (GTD @contexts for NEXT actions)
  -- Used in capture, clarify, and filtering
  -- ═══════════════════════════════════════════════════════════════════════════
  contexts = {
    { tag = "@computer",  name = "Computer",     icon = "󰌢" },
    { tag = "@phone",     name = "Phone",        icon = "󰏲" },
    { tag = "@errands",   name = "Errands",      icon = "󰒍" },
    { tag = "@home",      name = "Home",         icon = "󰋞" },
    { tag = "@office",    name = "Office",       icon = "󰢱" },
    { tag = "@anywhere",  name = "Anywhere",     icon = "󰖟" },
    { tag = "@agenda",    name = "Meeting/Call", icon = "󰃰" },
    { tag = "@read",      name = "Read/Review",  icon = "󰋽" },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- PEOPLE (for WAITING, delegation, meetings)
  -- Used in WAITING clarification and meeting notes
  -- ═══════════════════════════════════════════════════════════════════════════
  people = {
    -- Work
    { id = "boss",    name = "Boss Name",    email = "boss@work.com",    tags = { "work" } },
    { id = "team",    name = "Dev Team",     email = "team@work.com",    tags = { "work" } },
    -- Family
    { id = "spouse",  name = "Spouse Name",  email = "spouse@home.com",  tags = { "family" } },
    -- Add more people as needed
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- REVIEW SCHEDULE
  -- ═══════════════════════════════════════════════════════════════════════════
  review = {
    weekly = {
      enabled = true,
      day = "Sunday",
      time = "10:00",
    },
    daily = {
      enabled = true,
      time = "08:00",
    },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- INTEGRATIONS
  -- ═══════════════════════════════════════════════════════════════════════════
  integrations = {
    kairos = {
      enabled = true,  -- Set to true if using Kairos daemon
      socket = "~/.cache/kairos/kairos.sock",
    },
    calendar = {
      enabled = true,  -- Set to true for calendar integration
      provider = "apple",
      default_calendar = "Work",
    },
    reminders = {
      enabled = true,  -- Set to true for Apple Reminders
      provider = "apple",
      default_list = "GTD",
    },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- CAPTURE DEFAULTS
  -- ═══════════════════════════════════════════════════════════════════════════
  capture = {
    default_state = "TODO",
    add_created_property = true,
    add_task_id = true,
    ask_for_context = false,   -- Set true to prompt for @context on capture
    ask_for_effort = false,    -- Set true to prompt for effort on capture
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- UI PREFERENCES
  -- ═══════════════════════════════════════════════════════════════════════════
  ui = {
    icons = "nerd",              -- "nerd", "emoji", "ascii"
    date_format = "%Y-%m-%d",
    time_format = "%H:%M",
    first_day_of_week = "monday",
    
    fzf = {
      height = 0.80,
      width = 0.90,
    },
  },
}
]]

return M
