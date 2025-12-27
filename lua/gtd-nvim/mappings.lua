-- gtd-nvim/mappings.lua
-- GTD Keymaps: Clean, organized structure
--
-- Structure:
--   <prefix>c/i/v  - Capture (quick access)
--   <prefix>s      - Status change
--   <prefix>t      - Clarify current Task
--   <prefix>r/R    - Refile
--   <prefix>p/P    - Projects
--   <prefix>l...   - Lists (agenda, next, projects, waiting, etc.)
--   <prefix>m...   - Manage (bulk operations)
--   <prefix>S...   - System (backup, config, sync, daemon)
--   <prefix>h      - Health
--
-- File:    lua/gtd-nvim/mappings.lua
-- Version: 0.11.0
-- Updated: 2025-12-23

local M = {}

local FileVersion = "0.11.0"

-- Default keymap configuration
M.defaults = {
  enabled = true,
  prefix = "<leader>x",
  
  keys = {
    -- ═══════════════════════════════════════════════════════════════════════
    -- CAPTURE (quick access at root level)
    -- ═══════════════════════════════════════════════════════════════════════
    capture           = "c",    -- <prefix>c  → Capture to Inbox
    capture_instant   = "i",    -- <prefix>i  → Instant capture (quick brain dump)
    capture_clipboard = "v",    -- <prefix>v  → Capture from clipboard
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- TASK OPERATIONS (quick access at root level)
    -- ═══════════════════════════════════════════════════════════════════════
    status            = "s",    -- <prefix>s  → Change task status
    clarify_task      = "t",    -- <prefix>t  → Clarify current task
    clarify_pick      = "T",    -- <prefix>T  → Clarify any task (fzf picker)
    refile            = "r",    -- <prefix>r  → Refile current task
    refile_pick       = "R",    -- <prefix>R  → Refile any task (fzf)
    project_new       = "p",    -- <prefix>p  → New project
    project_convert   = "P",    -- <prefix>P  → Convert task to project
    link_to_project   = "k",    -- <prefix>k  → linK task to project
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- LISTS <prefix>l... (Views and pickers)
    -- ═══════════════════════════════════════════════════════════════════════
    lists_agenda      = "la",   -- <prefix>la → Agenda (today)
    lists_next        = "ln",   -- <prefix>ln → Next actions
    lists_projects    = "lp",   -- <prefix>lp → Projects
    lists_waiting     = "lw",   -- <prefix>lw → Waiting for
    lists_someday     = "ls",   -- <prefix>ls → Someday/Maybe
    lists_stuck       = "lx",   -- <prefix>lx → Stuck projects (no NEXT)
    lists_overdue     = "lo",   -- <prefix>lo → Overdue tasks
    lists_inbox       = "li",   -- <prefix>li → Inbox items
    lists_search      = "l/",   -- <prefix>l/ → Search all
    lists_menu        = "ll",   -- <prefix>ll → Lists menu (all options)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- MANAGE <prefix>m... (Bulk operations)
    -- ═══════════════════════════════════════════════════════════════════════
    manage_tasks      = "mt",   -- <prefix>mt → Manage tasks
    manage_projects   = "mp",   -- <prefix>mp → Manage projects
    manage_areas      = "ma",   -- <prefix>ma → Manage areas
    manage_help       = "m?",   -- <prefix>m? → Help menu
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- SYSTEM <prefix>S... (Config, backup, sync, daemon)
    -- ═══════════════════════════════════════════════════════════════════════
    system_menu       = "SS",   -- <prefix>SS → System menu
    system_config     = "Sc",   -- <prefix>Sc → Configuration
    system_wizard     = "Sw",   -- <prefix>Sw → Setup wizard
    system_backup     = "Sb",   -- <prefix>Sb → Backup menu
    system_backup_now = "SB",   -- <prefix>SB → Quick backup (no prompts)
    system_sync       = "Ss",   -- <prefix>Ss → Sync reminders
    system_daemon     = "Sd",   -- <prefix>Sd → Daemon status
    system_refresh    = "Sr",   -- <prefix>Sr → Refresh daemon index
    system_calendars  = "SC",   -- <prefix>SC → Select calendars
    system_reminders  = "SR",   -- <prefix>SR → Select reminder lists
    system_mail       = "SM",   -- <prefix>SM → Select mail accounts
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- MISC
    -- ═══════════════════════════════════════════════════════════════════════
    health            = "h",    -- <prefix>h  → Health check
    review            = "w",    -- <prefix>w  → Weekly review
  },
}

-- Safe require helper
local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

-- Create a keymap
local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
end

-- Setup keymaps
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", M.defaults, opts or {})
  
  if not opts.enabled then
    return
  end
  
  local prefix = opts.prefix
  local keys = opts.keys
  
  -- Load modules
  local gtd            = safe_require("gtd-nvim.gtd")
  local organize       = safe_require("gtd-nvim.gtd.organize")
  local lists          = safe_require("gtd-nvim.gtd.lists")
  local agenda         = safe_require("gtd-nvim.gtd.agenda")
  local manage         = safe_require("gtd-nvim.gtd.manage")
  local areas          = safe_require("gtd-nvim.gtd.areas")
  local review         = safe_require("gtd-nvim.gtd.review")
  local configurator   = safe_require("gtd-nvim.configurator")
  local backup         = safe_require("gtd-nvim.configurator.backup")
  local chronos_client = safe_require("gtd-nvim.gtd.chronos-client")
  local reminders      = safe_require("gtd-nvim.gtd.reminders")
  
  -- V2 modules
  local capture_v2     = safe_require("gtd-nvim.capture")
  local clarify_v2     = safe_require("gtd-nvim.capture.workflows.clarify")
  local status_v2      = safe_require("gtd-nvim.capture.workflows.status")
  
  if not gtd then
    vim.notify("gtd-nvim: GTD module not loaded, keymaps disabled", vim.log.levels.WARN)
    return
  end
  
  ---------------------------------------------------------------------------
  -- Root group for which-key
  ---------------------------------------------------------------------------
  map("n", prefix, function() end, "GTD")
  
  ---------------------------------------------------------------------------
  -- CAPTURE
  ---------------------------------------------------------------------------
  if keys.capture then
    map("n", prefix .. keys.capture, function()
      if capture and capture.capture_quick then
        capture.capture_quick({})
      elseif gtd.capture then
        gtd.capture({})
      end
    end, "GTD: Capture → Inbox")
  end
  
  if keys.capture_instant then
    map("n", prefix .. keys.capture_instant, function()
      if capture and capture.capture_instant then
        capture.capture_instant()
      end
    end, "GTD: Instant capture")
  end
  
  if keys.capture_clipboard then
    map("n", prefix .. keys.capture_clipboard, function()
      if capture and capture.capture_clipboard then
        capture.capture_clipboard()
      end
    end, "GTD: Capture clipboard")
  end
  
  ---------------------------------------------------------------------------
  -- TASK OPERATIONS
  ---------------------------------------------------------------------------
  if keys.status and status_v2 then
    map("n", prefix .. keys.status, function()
      status_v2.change_status()
    end, "GTD: Change status")
  end
  
  if keys.clarify_task then
    map("n", prefix .. keys.clarify_task, function()
      if clarify and clarify.at_cursor then
        clarify.at_cursor({ promote_if_needed = true })
      elseif gtd.clarify then
        gtd.clarify({ promote_if_needed = true })
      end
    end, "GTD: Clarify task")
  end
  
  if keys.clarify_pick and clarify then
    map("n", prefix .. keys.clarify_pick, function()
      if clarify.clarify_pick_any then
        clarify.clarify_pick_any({})
      end
    end, "GTD: Clarify (pick)")
  end
  
  if keys.refile then
    map("n", prefix .. keys.refile, function()
      if organize and organize.refile_to_project then
        organize.refile_to_project()
      elseif gtd.refile_to_project then
        gtd.refile_to_project()
      end
    end, "GTD: Refile task")
  end
  
  if keys.refile_pick and organize then
    map("n", prefix .. keys.refile_pick, function()
      if organize.refile_pick_any then
        organize.refile_pick_any()
      end
    end, "GTD: Refile (pick)")
  end
  
  if keys.project_new then
    map("n", prefix .. keys.project_new, function()
      gtd.project_new({})
    end, "GTD: New project")
  end
  
  if keys.project_convert then
    map("n", prefix .. keys.project_convert, function()
      gtd.convert_task_to_project({})
    end, "GTD: Task → Project")
  end
  
  if keys.link_to_project then
    map("n", prefix .. keys.link_to_project, function()
      gtd.link_task_to_project({})
    end, "GTD: Link to project")
  end
  
  ---------------------------------------------------------------------------
  -- LISTS <prefix>l...
  ---------------------------------------------------------------------------
  -- Group marker
  map("n", prefix .. "l", function() end, "GTD Lists")
  
  if keys.lists_agenda then
    map("n", prefix .. keys.lists_agenda, function()
      if agenda and agenda.show then
        agenda.show()
      elseif gtd.agenda then
        gtd.agenda()
      elseif lists and lists.agenda then
        lists.agenda()
      end
    end, "GTD: Agenda")
  end
  
  if keys.lists_next and lists then
    map("n", prefix .. keys.lists_next, function()
      lists.next_actions()
    end, "GTD: Next actions")
  end
  
  if keys.lists_projects and lists then
    map("n", prefix .. keys.lists_projects, function()
      lists.projects()
    end, "GTD: Projects")
  end
  
  if keys.lists_waiting and lists then
    map("n", prefix .. keys.lists_waiting, function()
      lists.waiting()
    end, "GTD: Waiting for")
  end
  
  if keys.lists_someday and lists then
    map("n", prefix .. keys.lists_someday, function()
      lists.someday_maybe()
    end, "GTD: Someday/Maybe")
  end
  
  if keys.lists_stuck and lists then
    map("n", prefix .. keys.lists_stuck, function()
      lists.stuck_projects()
    end, "GTD: Stuck projects")
  end
  
  if keys.lists_overdue and lists then
    map("n", prefix .. keys.lists_overdue, function()
      if lists.overdue then
        lists.overdue()
      end
    end, "GTD: Overdue")
  end
  
  if keys.lists_inbox and lists then
    map("n", prefix .. keys.lists_inbox, function()
      if lists.inbox then
        lists.inbox()
      end
    end, "GTD: Inbox")
  end
  
  if keys.lists_search and lists then
    map("n", prefix .. keys.lists_search, function()
      if lists.search_all then
        lists.search_all()
      end
    end, "GTD: Search all")
  end
  
  if keys.lists_menu and lists then
    map("n", prefix .. keys.lists_menu, function()
      lists.menu()
    end, "GTD: Lists menu")
  end
  
  ---------------------------------------------------------------------------
  -- MANAGE <prefix>m...
  ---------------------------------------------------------------------------
  -- Group marker
  map("n", prefix .. "m", function() end, "GTD Manage")
  
  if keys.manage_tasks and manage then
    map("n", prefix .. keys.manage_tasks, function()
      manage.manage_tasks()
    end, "GTD: Manage tasks")
  end
  
  if keys.manage_projects and manage then
    map("n", prefix .. keys.manage_projects, function()
      manage.manage_projects()
    end, "GTD: Manage projects")
  end
  
  if keys.manage_areas and areas then
    map("n", prefix .. keys.manage_areas, function()
      if areas.browse then
        areas.browse()
      end
    end, "GTD: Manage areas")
  end
  
  if keys.manage_help and manage then
    map("n", prefix .. keys.manage_help, function()
      if manage.help_menu then
        manage.help_menu()
      end
    end, "GTD: Help")
  end
  
  ---------------------------------------------------------------------------
  -- SYSTEM <prefix>S...
  ---------------------------------------------------------------------------
  -- Group marker
  map("n", prefix .. "S", function() end, "GTD System")
  
  if keys.system_menu then
    map("n", prefix .. keys.system_menu, function()
      -- Show system menu via fzf
      local fzf = safe_require("fzf-lua")
      if not fzf then
        vim.notify("fzf-lua required", vim.log.levels.ERROR)
        return
      end
      
      local items = {
        "  Configuration",
        "  Setup Wizard",
        "󰁯  Backup Menu",
        "󰑓  Sync Reminders",
        "  Daemon Status",
        "󰑐  Refresh Index",
        "  Select Calendars",
        "  Select Reminders",
      }
      
      fzf.fzf_exec(items, {
        prompt = "System> ",
        actions = {
          ["default"] = function(sel)
            if not sel or not sel[1] then return end
            local choice = sel[1]
            if choice:match("Configuration") then
              if configurator then configurator.open() end
            elseif choice:match("Setup Wizard") then
              if configurator then configurator.wizard() end
            elseif choice:match("Backup") then
              if backup then backup.menu() end
            elseif choice:match("Sync Reminders") then
              if reminders and reminders.sync then reminders.sync() end
            elseif choice:match("Daemon Status") then
              if chronos_client then chronos_client.show_status() end
            elseif choice:match("Refresh") then
              if chronos_client then chronos_client.refresh() end
            elseif choice:match("Select Calendars") then
              if configurator then configurator.select_calendars() end
            elseif choice:match("Select Reminders") then
              if configurator then configurator.select_reminders() end
            end
          end,
        },
        winopts = { height = 0.4, width = 0.4 },
      })
    end, "GTD: System menu")
  end
  
  if keys.system_config and configurator then
    map("n", prefix .. keys.system_config, function()
      configurator.open()
    end, "GTD: Configuration")
  end
  
  if keys.system_wizard and configurator then
    map("n", prefix .. keys.system_wizard, function()
      configurator.wizard()
    end, "GTD: Setup wizard")
  end
  
  if keys.system_backup and backup then
    map("n", prefix .. keys.system_backup, function()
      backup.menu()
    end, "GTD: Backup menu")
  end
  
  if keys.system_backup_now and backup then
    map("n", prefix .. keys.system_backup_now, function()
      if backup.quick then
        backup.quick()
      elseif backup.create then
        backup.create()
      end
    end, "GTD: Backup now")
  end
  
  if keys.system_sync then
    map("n", prefix .. keys.system_sync, function()
      if reminders and reminders.sync then
        reminders.sync()
      else
        vim.notify("Reminders sync not available", vim.log.levels.WARN)
      end
    end, "GTD: Sync reminders")
  end
  
  if keys.system_daemon and chronos_client then
    map("n", prefix .. keys.system_daemon, function()
      if chronos_client.show_status then
        chronos_client.show_status()
      else
        vim.cmd("ChronosStatus")
      end
    end, "GTD: Daemon status")
  end
  
  if keys.system_refresh and chronos_client then
    map("n", prefix .. keys.system_refresh, function()
      local ok, err = chronos_client.refresh()
      if ok then
        vim.notify("Index refresh triggered", vim.log.levels.INFO)
      else
        vim.notify("Refresh failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      end
    end, "GTD: Refresh index")
  end
  
  if keys.system_calendars and configurator then
    map("n", prefix .. keys.system_calendars, function()
      configurator.select_calendars()
    end, "GTD: Select calendars")
  end
  
  if keys.system_reminders and configurator then
    map("n", prefix .. keys.system_reminders, function()
      configurator.select_reminders()
    end, "GTD: Select reminders")
  end
  
  if keys.system_mail and configurator then
    map("n", prefix .. keys.system_mail, function()
      configurator.select_mail_accounts()
    end, "GTD: Select mail accounts")
  end
  
  ---------------------------------------------------------------------------
  -- MISC
  ---------------------------------------------------------------------------
  if keys.health then
    map("n", prefix .. keys.health, function()
      gtd.health()
    end, "GTD: Health check")
  end
  
  if keys.review and review then
    map("n", prefix .. keys.review, function()
      if review.start then
        review.start()
      elseif review.weekly then
        review.weekly()
      end
    end, "GTD: Weekly review")
  end
  
  ---------------------------------------------------------------------------
  -- Register which-key
  ---------------------------------------------------------------------------
  M.register_which_key(prefix, keys)
end


-- Register with which-key if available
function M.register_which_key(prefix, keys)
  local ok, wk = pcall(require, "which-key")
  if not ok then return end
  
  if wk.add then
    -- which-key v3+ API
    local specs = {
      -- Root group
      { prefix, group = "GTD", icon = "󰄲" },
      
      -- Subgroups
      { prefix .. "l", group = "Lists", icon = "" },
      { prefix .. "m", group = "Manage", icon = "" },
      { prefix .. "S", group = "System", icon = "" },
      
      -- Capture
      { prefix .. "c", desc = "Capture", icon = "" },
      { prefix .. "i", desc = "Instant capture", icon = "󰈸" },
      { prefix .. "v", desc = "From clipboard", icon = "󰅌" },
      
      -- Task ops
      { prefix .. "s", desc = "Change status", icon = "󰑐" },
      { prefix .. "t", desc = "Clarify task", icon = "" },
      { prefix .. "T", desc = "Clarify (pick)", icon = "" },
      { prefix .. "r", desc = "Refile", icon = "󰁕" },
      { prefix .. "R", desc = "Refile (pick)", icon = "󰁕" },
      { prefix .. "p", desc = "New project", icon = "" },
      { prefix .. "P", desc = "Task → Project", icon = "" },
      { prefix .. "k", desc = "Link to project", icon = "󰌷" },
      
      -- Lists
      { prefix .. "la", desc = "Agenda", icon = "󰃰" },
      { prefix .. "ln", desc = "Next actions", icon = "󱥦" },
      { prefix .. "lp", desc = "Projects", icon = "" },
      { prefix .. "lw", desc = "Waiting for", icon = "" },
      { prefix .. "ls", desc = "Someday/Maybe", icon = "󰋊" },
      { prefix .. "lx", desc = "Stuck projects", icon = "" },
      { prefix .. "lo", desc = "Overdue", icon = "" },
      { prefix .. "li", desc = "Inbox", icon = "" },
      { prefix .. "l/", desc = "Search all", icon = "" },
      { prefix .. "ll", desc = "Lists menu", icon = "" },
      
      -- Manage
      { prefix .. "mt", desc = "Tasks", icon = "󰄲" },
      { prefix .. "mp", desc = "Projects", icon = "" },
      { prefix .. "ma", desc = "Areas", icon = "󰕰" },
      { prefix .. "m?", desc = "Help", icon = "" },
      
      -- System
      { prefix .. "SS", desc = "System menu", icon = "" },
      { prefix .. "Sc", desc = "Configuration", icon = "" },
      { prefix .. "Sw", desc = "Setup wizard", icon = "" },
      { prefix .. "Sb", desc = "Backup menu", icon = "󰁯" },
      { prefix .. "SB", desc = "Backup now", icon = "󰁯" },
      { prefix .. "Ss", desc = "Sync reminders", icon = "󰑓" },
      { prefix .. "Sd", desc = "Daemon status", icon = "" },
      { prefix .. "Sr", desc = "Refresh index", icon = "󰑐" },
      { prefix .. "SC", desc = "Select calendars", icon = "" },
      { prefix .. "SR", desc = "Select reminders", icon = "" },
      
      -- Misc
      { prefix .. "h", desc = "Health check", icon = "󰓙" },
      { prefix .. "w", desc = "Weekly review", icon = "󰬓" },
    }
    
    wk.add(specs)
    
  elseif wk.register then
    -- which-key v2 (legacy)
    wk.register({
      [prefix] = {
        name = "GTD",
        c = "Capture",
        i = "Instant capture",
        v = "From clipboard",
        s = "Change status",
        t = "Clarify task",
        T = "Clarify (pick)",
        r = "Refile",
        R = "Refile (pick)",
        p = "New project",
        P = "Task → Project",
        k = "Link to project",
        h = "Health check",
        w = "Weekly review",
        l = {
          name = "Lists",
          a = "Agenda",
          n = "Next actions",
          p = "Projects",
          w = "Waiting for",
          s = "Someday/Maybe",
          x = "Stuck projects",
          o = "Overdue",
          i = "Inbox",
          ["/"] = "Search all",
          l = "Lists menu",
        },
        m = {
          name = "Manage",
          t = "Tasks",
          p = "Projects",
          a = "Areas",
          ["?"] = "Help",
        },
        S = {
          name = "System",
          S = "System menu",
          c = "Configuration",
          w = "Setup wizard",
          b = "Backup menu",
          B = "Backup now",
          s = "Sync reminders",
          d = "Daemon status",
          r = "Refresh index",
          C = "Select calendars",
          R = "Select reminders",
        },
      },
    })
  end
end

-- Module info
function M.version()
  return FileVersion
end

return M
