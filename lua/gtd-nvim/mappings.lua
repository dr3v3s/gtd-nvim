-- gtd-nvim/mappings.lua
-- GTD Keymaps: Capture, Clarify, Organize, Lists, Manage
-- All mappings under configurable prefix (default: <leader>c)

local M = {}

-- Default keymap configuration
M.defaults = {
  enabled = true,
  prefix = "<leader>c",
  
  -- Individual keymaps (set to false to disable)
  keys = {
    -- Capture
    capture           = "c",    -- <prefix>c  → Capture to Inbox
    
    -- Status
    status            = "s",    -- <prefix>s  → Change task status
    
    -- Clarify / Lists cluster (<prefix>l...)
    clarify_task      = "lt",   -- <prefix>lt → Clarify current task
    clarify_pick      = "ll",   -- <prefix>ll → Clarify from list (fzf)
    link_to_project   = "lp",   -- <prefix>lp → Link task to project
    
    -- Lists
    lists_menu        = "lm",   -- <prefix>lm → Lists menu
    lists_next        = "ln",   -- <prefix>ln → Next Actions
    lists_projects    = "lP",   -- <prefix>lP → Projects (capital P)
    lists_someday     = "ls",   -- <prefix>ls → Someday/Maybe
    lists_waiting     = "lw",   -- <prefix>lw → Waiting For
    lists_stuck       = "lx",   -- <prefix>lx → Stuck Projects
    lists_search      = "la",   -- <prefix>la → Search All
    
    -- Refile / Projects
    refile            = "r",    -- <prefix>r  → Refile current task
    refile_pick       = "R",    -- <prefix>R  → Refile any task (fzf)
    project_new       = "p",    -- <prefix>p  → New project
    project_convert   = "P",    -- <prefix>P  → Convert task to project
    
    -- Manage cluster (<prefix>m...)
    manage_tasks      = "mt",   -- <prefix>mt → Manage tasks
    manage_projects   = "mp",   -- <prefix>mp → Manage projects
    manage_help       = "mh",   -- <prefix>mh → Help menu
    
    -- Health
    health            = "h",    -- <prefix>h  → Health check
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
  local gtd      = safe_require("gtd-nvim.gtd")
  local clarify  = safe_require("gtd-nvim.gtd.clarify")
  local organize = safe_require("gtd-nvim.gtd.organize")
  local lists    = safe_require("gtd-nvim.gtd.lists")
  local manage   = safe_require("gtd-nvim.gtd.manage")
  local status   = safe_require("gtd-nvim.gtd.status")
  
  if not gtd then
    vim.notify("gtd-nvim: GTD module not loaded, keymaps disabled", vim.log.levels.WARN)
    return
  end
  
  ---------------------------------------------------------------------------
  -- Root group for which-key
  ---------------------------------------------------------------------------
  map("n", prefix, function() end, "GTD")
  
  ---------------------------------------------------------------------------
  -- Capture
  ---------------------------------------------------------------------------
  if keys.capture then
    map("n", prefix .. keys.capture, function()
      gtd.capture({})
    end, "GTD: Capture → Inbox")
  end
  
  ---------------------------------------------------------------------------
  -- Status
  ---------------------------------------------------------------------------
  if keys.status and status then
    map("n", prefix .. keys.status, function()
      status.change_status()
    end, "GTD: Change task status")
  end
  
  ---------------------------------------------------------------------------
  -- Clarify
  ---------------------------------------------------------------------------
  if keys.clarify_task then
    map("n", prefix .. keys.clarify_task, function()
      gtd.clarify({ promote_if_needed = true })
    end, "GTD: Clarify current task")
  end
  
  if keys.clarify_pick and clarify then
    map("n", prefix .. keys.clarify_pick, function()
      if clarify.clarify_pick_any then
        clarify.clarify_pick_any({})
      end
    end, "GTD: Clarify from list (fzf)")
  end
  
  if keys.link_to_project then
    map("n", prefix .. keys.link_to_project, function()
      gtd.link_task_to_project({})
    end, "GTD: Link task → project")
  end

  ---------------------------------------------------------------------------
  -- Lists
  ---------------------------------------------------------------------------
  if lists then
    if keys.lists_menu then
      map("n", prefix .. keys.lists_menu, function()
        lists.menu()
      end, "GTD: Lists menu")
    end
    
    if keys.lists_next then
      map("n", prefix .. keys.lists_next, function()
        lists.next_actions()
      end, "GTD: Next Actions")
    end
    
    if keys.lists_projects then
      map("n", prefix .. keys.lists_projects, function()
        lists.projects()
      end, "GTD: Projects")
    end
    
    if keys.lists_someday then
      map("n", prefix .. keys.lists_someday, function()
        lists.someday_maybe()
      end, "GTD: Someday/Maybe")
    end
    
    if keys.lists_waiting then
      map("n", prefix .. keys.lists_waiting, function()
        lists.waiting()
      end, "GTD: Waiting For")
    end
    
    if keys.lists_stuck then
      map("n", prefix .. keys.lists_stuck, function()
        lists.stuck_projects()
      end, "GTD: Stuck Projects")
    end
    
    if keys.lists_search then
      map("n", prefix .. keys.lists_search, function()
        lists.search_all()
      end, "GTD: Search All Items")
    end
  end
  
  ---------------------------------------------------------------------------
  -- Refile / Projects
  ---------------------------------------------------------------------------
  if keys.refile then
    map("n", prefix .. keys.refile, function()
      if organize and organize.refile_to_project then
        organize.refile_to_project()
      elseif gtd.refile_to_project then
        gtd.refile_to_project()
      end
    end, "GTD: Refile current task")
  end
  
  if keys.refile_pick and organize then
    map("n", prefix .. keys.refile_pick, function()
      if organize.refile_pick_any then
        organize.refile_pick_any()
      end
    end, "GTD: Refile any task (fzf)")
  end
  
  if keys.project_new then
    map("n", prefix .. keys.project_new, function()
      gtd.project_new({})
    end, "GTD: New project")
  end
  
  if keys.project_convert then
    map("n", prefix .. keys.project_convert, function()
      gtd.convert_task_to_project({})
    end, "GTD: Convert task → project")
  end
  
  ---------------------------------------------------------------------------
  -- Manage
  ---------------------------------------------------------------------------
  if manage then
    if keys.manage_tasks then
      map("n", prefix .. keys.manage_tasks, function()
        manage.manage_tasks()
      end, "GTD: Manage tasks")
    end
    
    if keys.manage_projects then
      map("n", prefix .. keys.manage_projects, function()
        manage.manage_projects()
      end, "GTD: Manage projects")
    end
    
    if keys.manage_help then
      map("n", prefix .. keys.manage_help, function()
        if manage.help_menu then
          manage.help_menu()
        end
      end, "GTD: Help menu")
    end
  end
  
  ---------------------------------------------------------------------------
  -- Health
  ---------------------------------------------------------------------------
  if keys.health then
    map("n", prefix .. keys.health, function()
      gtd.health()
    end, "GTD: Health check")
  end
  
  ---------------------------------------------------------------------------
  -- which-key integration
  ---------------------------------------------------------------------------
  M.register_which_key(prefix, keys)
end


-- Register with which-key if available
function M.register_which_key(prefix, keys)
  local ok, wk = pcall(require, "which-key")
  if not ok then return end
  
  if wk.add then
    -- New which-key API (v3+)
    local specs = {
      { prefix, group = "GTD" },
      { prefix .. "l", group = "Clarify / Lists" },
      { prefix .. "m", group = "Manage" },
    }
    
    if keys.capture then
      table.insert(specs, { prefix .. keys.capture, desc = "Capture → Inbox" })
    end
    if keys.status then
      table.insert(specs, { prefix .. keys.status, desc = "Change status" })
    end
    if keys.clarify_task then
      table.insert(specs, { prefix .. keys.clarify_task, desc = "Clarify current task" })
    end
    if keys.clarify_pick then
      table.insert(specs, { prefix .. keys.clarify_pick, desc = "Clarify from list" })
    end
    if keys.link_to_project then
      table.insert(specs, { prefix .. keys.link_to_project, desc = "Link task → project" })
    end
    if keys.lists_menu then
      table.insert(specs, { prefix .. keys.lists_menu, desc = "Lists menu" })
    end
    if keys.lists_next then
      table.insert(specs, { prefix .. keys.lists_next, desc = "Next Actions" })
    end
    if keys.lists_projects then
      table.insert(specs, { prefix .. keys.lists_projects, desc = "Projects" })
    end
    if keys.lists_someday then
      table.insert(specs, { prefix .. keys.lists_someday, desc = "Someday/Maybe" })
    end
    if keys.lists_waiting then
      table.insert(specs, { prefix .. keys.lists_waiting, desc = "Waiting For" })
    end
    if keys.lists_stuck then
      table.insert(specs, { prefix .. keys.lists_stuck, desc = "Stuck Projects" })
    end
    if keys.lists_search then
      table.insert(specs, { prefix .. keys.lists_search, desc = "Search All" })
    end
    if keys.refile then
      table.insert(specs, { prefix .. keys.refile, desc = "Refile current task" })
    end
    if keys.refile_pick then
      table.insert(specs, { prefix .. keys.refile_pick, desc = "Refile any task" })
    end
    if keys.project_new then
      table.insert(specs, { prefix .. keys.project_new, desc = "New project" })
    end
    if keys.project_convert then
      table.insert(specs, { prefix .. keys.project_convert, desc = "Convert task → project" })
    end
    if keys.manage_tasks then
      table.insert(specs, { prefix .. keys.manage_tasks, desc = "Manage tasks" })
    end
    if keys.manage_projects then
      table.insert(specs, { prefix .. keys.manage_projects, desc = "Manage projects" })
    end
    if keys.manage_help then
      table.insert(specs, { prefix .. keys.manage_help, desc = "Help menu" })
    end
    if keys.health then
      table.insert(specs, { prefix .. keys.health, desc = "Health check" })
    end
    
    wk.add(specs)
    
  elseif wk.register then
    -- Legacy which-key API (v2)
    wk.register({
      [prefix] = {
        name = "GTD",
        c = keys.capture and "Capture → Inbox" or nil,
        s = keys.status and "Change status" or nil,
        l = {
          name = "Clarify / Lists",
          t = keys.clarify_task and "Clarify current task" or nil,
          l = keys.clarify_pick and "Clarify from list" or nil,
          p = keys.link_to_project and "Link task → project" or nil,
          m = keys.lists_menu and "Lists menu" or nil,
          n = keys.lists_next and "Next Actions" or nil,
          P = keys.lists_projects and "Projects" or nil,
          s = keys.lists_someday and "Someday/Maybe" or nil,
          w = keys.lists_waiting and "Waiting For" or nil,
          x = keys.lists_stuck and "Stuck Projects" or nil,
          a = keys.lists_search and "Search All" or nil,
        },
        r = keys.refile and "Refile current task" or nil,
        R = keys.refile_pick and "Refile any task" or nil,
        p = keys.project_new and "New project" or nil,
        P = keys.project_convert and "Convert task → project" or nil,
        m = {
          name = "Manage",
          t = keys.manage_tasks and "Manage tasks" or nil,
          p = keys.manage_projects and "Manage projects" or nil,
          h = keys.manage_help and "Help menu" or nil,
        },
        h = keys.health and "Health check" or nil,
      },
    })
  end
end

return M
