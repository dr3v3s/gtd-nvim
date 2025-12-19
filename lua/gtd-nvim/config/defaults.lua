-- gtd-nvim/config/defaults.lua
-- Default configuration values
-- Users override these in ~/.config/gtd-nvim/config.lua

local M = {}

M.config = {
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PATHS
  -- ═══════════════════════════════════════════════════════════════════════════
  gtd_home = "~/Documents/GTD",
  notes_home = "~/Documents/Notes",
  
  -- Subdirectories (relative to gtd_home)
  gtd_dirs = {
    inbox = "Inbox.org",
    recurring = "Recurring.org",
    tickler = "Tickler.org",
    projects = "Projects",
    areas = "Areas",
    archive = "Archive",
  },
  
  -- Subdirectories (relative to notes_home)
  notes_dirs = {
    daily = "Daily",
    quick = "Quick",
    projects = "Projects",
    people = "People",
    reading = "Reading",
    templates = "Templates",
    archive = "Archive",
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- USER IDENTITY
  -- ═══════════════════════════════════════════════════════════════════════════
  user = {
    name = "",
    email = "",
    timezone = "UTC",
    language = "en",  -- "en", "da", etc.
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- TODO KEYWORDS (org-mode states)
  -- ═══════════════════════════════════════════════════════════════════════════
  keywords = {
    active = { "TODO", "NEXT", "WAITING", "SOMEDAY" },
    done = { "DONE", "CANCELLED" },
    special = { "PROJECT", "RECURRING" },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- AREAS OF FOCUS (GTD Horizons of Focus - Level 2)
  -- ═══════════════════════════════════════════════════════════════════════════
  areas = {
    -- { id = "work", name = "Work", icon = "󰊕", color = "#89b4fa", dir = "Work" },
    -- Add your areas here
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- CONTEXTS (GTD @contexts for NEXT actions)
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
  -- ENERGY LEVELS (for task filtering by mental state)
  -- ═══════════════════════════════════════════════════════════════════════════
  energy = {
    { id = "high",   name = "High Focus",   icon = "󱐋", description = "Deep work, complex tasks" },
    { id = "medium", name = "Normal",       icon = "󰾅", description = "Regular tasks" },
    { id = "low",    name = "Low Energy",   icon = "󰒲", description = "Simple, routine tasks" },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- TIME ESTIMATES (Effort property)
  -- ═══════════════════════════════════════════════════════════════════════════
  effort_options = {
    { value = "0:05", label = "5 min",    icon = "󱑀" },
    { value = "0:15", label = "15 min",   icon = "󱑂" },
    { value = "0:30", label = "30 min",   icon = "󱑅" },
    { value = "1:00", label = "1 hour",   icon = "󱑊" },
    { value = "2:00", label = "2 hours",  icon = "󱑎" },
    { value = "4:00", label = "Half day", icon = "󱑖" },
    { value = "8:00", label = "Full day", icon = "󱑡" },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- PRIORITY LEVELS
  -- ═══════════════════════════════════════════════════════════════════════════
  priorities = {
    { id = "A", name = "High",   icon = "󰀦", color = "#f38ba8" },
    { id = "B", name = "Medium", icon = "󰀧", color = "#f9e2af" },
    { id = "C", name = "Low",    icon = "󰀨", color = "#a6e3a1" },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- PEOPLE (for WAITING, delegation, meetings)
  -- ═══════════════════════════════════════════════════════════════════════════
  people = {
    -- { id = "boss", name = "Boss Name", email = "boss@work.com", tags = { "work" } },
    -- Add your people here
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- WAITING CONTEXTS (how you're waiting)
  -- ═══════════════════════════════════════════════════════════════════════════
  waiting_contexts = {
    { id = "email",   name = "Email",        icon = "󰇮" },
    { id = "phone",   name = "Phone",        icon = "󰏲" },
    { id = "meeting", name = "Meeting",      icon = "󰃰" },
    { id = "slack",   name = "Slack/Teams",  icon = "󰒱" },
    { id = "text",    name = "Text/SMS",     icon = "󰍡" },
    { id = "verbal",  name = "Verbal",       icon = "󰔊" },
    { id = "mail",    name = "Physical Mail", icon = "󰊫" },
    { id = "other",   name = "Other",        icon = "󰋗" },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- REVIEW SCHEDULE
  -- ═══════════════════════════════════════════════════════════════════════════
  review = {
    weekly = {
      enabled = true,
      day = "Sunday",       -- Day for weekly review
      time = "10:00",       -- Preferred time
    },
    daily = {
      enabled = true,
      time = "08:00",       -- Morning review time
    },
    monthly = {
      enabled = false,
      day = 1,              -- Day of month
    },
    quarterly = {
      enabled = false,
      months = { 1, 4, 7, 10 },
    },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- INTEGRATIONS
  -- ═══════════════════════════════════════════════════════════════════════════
  integrations = {
    kairos = {
      enabled = false,
      socket = "~/.cache/kairos/kairos.sock",
      cache_dir = "~/.cache/kairos",
    },
    calendar = {
      enabled = false,
      provider = "apple",   -- "apple", "google", "ical"
      default_calendar = "",
    },
    reminders = {
      enabled = false,
      provider = "apple",   -- "apple"
      default_list = "",
    },
    mail = {
      enabled = false,
      accounts = {},        -- IMAP account configs
    },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- CAPTURE DEFAULTS
  -- ═══════════════════════════════════════════════════════════════════════════
  capture = {
    default_state = "TODO",
    add_created_property = true,
    add_task_id = true,
    ask_for_context = false,      -- Prompt for @context on capture
    ask_for_effort = false,       -- Prompt for effort on capture
    ask_for_deadline = false,     -- Prompt for deadline on capture
    templates = {
      task = "* %s %s\n:PROPERTIES:\n:TASK_ID: %s\n:CREATED: [%s]\n:END:\n",
      project = "* PROJECT %s [0/0]\n:PROPERTIES:\n:ID: %s\n:TASK_ID: %s\n:Effort: 2:00\n:END:\n\n** NEXT First action\n",
    },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- UI PREFERENCES
  -- ═══════════════════════════════════════════════════════════════════════════
  ui = {
    icons = "nerd",             -- "nerd", "emoji", "ascii"
    colorscheme = "auto",       -- "auto", "catppuccin", "tokyonight", etc.
    date_format = "%Y-%m-%d",
    time_format = "%H:%M",
    datetime_format = "%Y-%m-%d %H:%M",
    first_day_of_week = "monday",  -- "monday" or "sunday"
    
    -- FZF window settings
    fzf = {
      height = 0.80,
      width = 0.90,
      preview = true,
    },
    
    -- Notification settings
    notifications = {
      enabled = true,
      timeout = 3000,         -- ms
    },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- GLYPHS (icons used throughout the system)
  -- ═══════════════════════════════════════════════════════════════════════════
  glyphs = {
    -- State icons
    state = {
      TODO = "󰄲",
      NEXT = "󰁔",
      WAITING = "󰈸",
      SOMEDAY = "󰋚",
      PROJECT = "󰷐",
      DONE = "󰄳",
      CANCELLED = "󰜺",
      RECURRING = "󰑖",
    },
    -- Container icons
    container = {
      inbox = "󰇮",
      project = "󰷐",
      area = "󰉋",
      recurring = "󰑖",
      archive = "󰀼",
      gtd = "󰄳",
    },
    -- UI icons
    ui = {
      calendar = "󰃭",
      clock = "󰥔",
      tag = "󰓹",
      link = "󰌷",
      note = "󰎞",
      person = "󰏃",
      check = "󰄬",
      warning = "󰀦",
      error = "󰅚",
      info = "󰋽",
      arrow_right = "󰁔",
      arrow_down = "󰁅",
      folder = "󰉋",
      file = "󰈙",
      search = "󰍉",
      filter = "󰈶",
      sort = "󰒺",
      edit = "󰏫",
      delete = "󰆴",
      archive = "󰀼",
      refresh = "󰑓",
    },
    -- GTD phase icons
    phase = {
      capture = "󰄀",
      clarify = "󰔡",
      organize = "󰉋",
      reflect = "󰍉",
      engage = "󰐊",
    },
  },

  -- ═══════════════════════════════════════════════════════════════════════════
  -- COLORS (Catppuccin Mocha as default)
  -- ═══════════════════════════════════════════════════════════════════════════
  colors = {
    -- Base colors
    text = "#cdd6f4",
    subtext = "#a6adc8",
    muted = "#6c7086",
    
    -- State colors
    next = "#a6e3a1",      -- Green
    todo = "#89b4fa",      -- Blue
    waiting = "#f9e2af",   -- Yellow
    someday = "#cba6f7",   -- Mauve
    done = "#6c7086",      -- Gray
    overdue = "#f38ba8",   -- Red
    project = "#89dceb",   -- Cyan
    
    -- Accent colors
    accent = "#cba6f7",    -- Mauve
    success = "#a6e3a1",   -- Green
    warning = "#f9e2af",   -- Yellow
    error = "#f38ba8",     -- Red
    info = "#89b4fa",      -- Blue
  },
}

return M
