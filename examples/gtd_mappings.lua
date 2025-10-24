-- ~/.config/nvim/lua/mappings/gtd.lua
-- GTD keymaps: capture, clarify (task/list), refile, projects, linking,
-- lists (Next/Projects/Someday/Waiting/Stuck/Search), and manager pickers — all under <leader>c.

local M = {}

-- helper to require modules safely
local function safe_require(name)
  local ok, mod = pcall(require, name)
  if not ok then
    vim.notify("mappings.gtd: require('" .. name .. "') failed:\n" .. tostring(mod), vim.log.levels.WARN)
    return nil
  end
  return mod
end

function M.setup()
  -- Core glue + submodules
  local gtd     = safe_require("gtd")          -- lua/gtd/init.lua
  local manager = safe_require("gtd.manage")   -- lua/gtd/manage.lua
  local lists   = safe_require("gtd.lists")    -- lua/gtd/lists.lua
  local organize = safe_require("gtd.organize") -- lua/gtd/organize.lua
  if not gtd then return end

  local map  = vim.keymap.set
  local base = { noremap = true, silent = true }

  ---------------------------------------------------------------------------
  -- Root label so which-key shows a clean group even without plugin
  ---------------------------------------------------------------------------
  map("n", "<leader>c", function() end, vim.tbl_extend("force", base, { desc = "GTD" }))

  ---------------------------------------------------------------------------
  -- Capture
  ---------------------------------------------------------------------------
  map("n", "<leader>cc", function() gtd.capture({}) end,
    vim.tbl_extend("force", base, { desc = "GTD: Capture → Inbox" }))

  ---------------------------------------------------------------------------
  -- Clarify (as agreed)
  --   <leader>clt : clarify task at cursor (promote if needed)
  --   <leader>cll : pick any task (fzf) and run clarify on it
  --   <leader>clp : link task → project note  (kept; do not reuse for lists)
  ---------------------------------------------------------------------------
  map("n", "<leader>clt", function() gtd.clarify({ promote_if_needed = true }) end,
    vim.tbl_extend("force", base, { desc = "GTD: Clarify current task" }))

  -- Call gtd.clarify module directly instead of going through gtd/init.lua
  map("n", "<leader>cll", function()
      local clarify = require("gtd.clarify")
      if clarify and clarify.clarify_pick_any then 
        clarify.clarify_pick_any({})
      else 
        vim.notify("gtd.clarify.clarify_pick_any() not found", vim.log.levels.WARN) 
      end
    end,
    vim.tbl_extend("force", base, { desc = "GTD: Clarify from list (fzf)" }))

  map("n", "<leader>clp", function() gtd.link_task_to_project({}) end,
    vim.tbl_extend("force", base, { desc = "GTD: Link task → project note" }))

  ---------------------------------------------------------------------------
  -- Enhanced GTD Lists - under <leader>cl
  ---------------------------------------------------------------------------
  if lists then
    -- Main Lists Menu
    map("n", "<leader>clm", function() lists.menu() end,
      vim.tbl_extend("force", base, { desc = "GTD Lists: Menu (all lists)" }))

    -- Core GTD Lists  
    map("n", "<leader>cln", function() lists.next_actions() end,
      vim.tbl_extend("force", base, { desc = "GTD Lists: Next Actions" }))

    -- Capital P to avoid clp collision with "link task → project note"
    map("n", "<leader>clP", function() lists.projects() end,
      vim.tbl_extend("force", base, { desc = "GTD Lists: Projects" }))

    map("n", "<leader>cls", function() lists.someday_maybe() end,
      vim.tbl_extend("force", base, { desc = "GTD Lists: Someday/Maybe" }))

    map("n", "<leader>clw", function() lists.waiting() end,
      vim.tbl_extend("force", base, { desc = "GTD Lists: Waiting For" }))

    map("n", "<leader>clx", function() lists.stuck_projects() end,
      vim.tbl_extend("force", base, { desc = "GTD Lists: Stuck Projects" }))

    map("n", "<leader>cla", function() lists.search_all() end,
      vim.tbl_extend("force", base, { desc = "GTD Lists: Search All Items" }))
  end

  ---------------------------------------------------------------------------
  -- Refile / Projects
  ---------------------------------------------------------------------------
  
  -- Simple refile (current task at cursor)
  map("n", "<leader>cr", function() 
    if organize and organize.refile_to_project then
      organize.refile_to_project()
    else
      gtd.refile_to_project()
    end
  end, vim.tbl_extend("force", base, { desc = "GTD: Refile current task" }))

  -- Enhanced refile with fzf task picker
  map("n", "<leader>cR", function() 
    if organize and organize.refile_pick_any then
      organize.refile_pick_any()
    else
      vim.notify("Enhanced refile picker not available. Use <leader>cr instead.", vim.log.levels.WARN)
    end
  end, vim.tbl_extend("force", base, { desc = "GTD: Refile any task (fzf picker)" }))

  map("n", "<leader>cp", function() gtd.project_new({}) end,
    vim.tbl_extend("force", base, { desc = "GTD: New project (org + ZK)" }))

  ---------------------------------------------------------------------------
  -- Manager (tasks & projects admin pickers + help)
  ---------------------------------------------------------------------------
  if manager then
    map("n", "<leader>cmt", function() manager.manage_tasks() end,
      vim.tbl_extend("force", base, { desc = "GTD: Manage → Tasks" }))

    map("n", "<leader>cmp", function() manager.manage_projects() end,
      vim.tbl_extend("force", base, { desc = "GTD: Manage → Projects" }))

    map("n", "<leader>cmh", function() 
      if manager.help_menu then 
        manager.help_menu() 
      else 
        vim.notify("Use :GtdManage, :GtdManageTasks, :GtdManageProjects", vim.log.levels.INFO)
      end
    end, vim.tbl_extend("force", base, { desc = "GTD: Manage → Help" }))
  end

  ---------------------------------------------------------------------------
  -- Health
  ---------------------------------------------------------------------------
  map("n", "<leader>ch", function() gtd.health() end,
    vim.tbl_extend("force", base, { desc = "GTD: Health check" }))

  ---------------------------------------------------------------------------
  -- which-key labels (new API: wk.add; legacy API: wk.register)
  ---------------------------------------------------------------------------
  local ok_wk, wk = pcall(require, "which-key")
  if ok_wk then
    if wk.add then
      -- New which-key API
      wk.add({
        -- Root GTD
        { "<leader>c",   group = "GTD" },
        { "<leader>cc",  desc  = "Capture → Inbox" },

        -- Clarify cluster with enhanced lists
        { "<leader>cl",  group = "Clarify / Lists" },
        { "<leader>clt", desc  = "Clarify current task" },
        { "<leader>cll", desc  = "Clarify from list (fzf)" },
        { "<leader>clp", desc  = "Link task → project note" },
        
        -- Lists submenu
        { "<leader>clm", desc  = "Lists → Menu (all lists)" },
        { "<leader>cln", desc  = "Lists → Next Actions" },
        { "<leader>clP", desc  = "Lists → Projects" },
        { "<leader>cls", desc  = "Lists → Someday/Maybe" },
        { "<leader>clw", desc  = "Lists → Waiting For" },
        { "<leader>clx", desc  = "Lists → Stuck Projects" },
        { "<leader>cla", desc  = "Lists → Search All Items" },

        -- Refile / Projects
        { "<leader>cr",  desc  = "Refile current task" },
        { "<leader>cR",  desc  = "Refile any task (fzf picker)" },
        { "<leader>cp",  desc  = "New project (org + ZK)" },

        -- Manager cluster
        { "<leader>cm",  group = "Manage" },
        { "<leader>cmt", desc  = "Manage → Tasks" },
        { "<leader>cmp", desc  = "Manage → Projects" },
        { "<leader>cmh", desc  = "Manage → Help" },

        { "<leader>ch",  desc  = "Health check" },
      })
    elseif wk.register then
      -- Legacy which-key API
      wk.register({
        c = {
          name = "GTD",
          c = "Capture → Inbox",
          l = { 
            name = "Clarify / Lists",
            t = "Clarify current task",
            l = "Clarify from list (fzf)",
            p = "Link task → project note",
            
            -- Enhanced lists integration
            m = "Lists → Menu (all lists)",
            n = "Lists → Next Actions",
            P = "Lists → Projects",
            s = "Lists → Someday/Maybe",
            w = "Lists → Waiting For",
            x = "Lists → Stuck Projects",
            a = "Lists → Search All Items",
          },
          r = "Refile current task",
          R = "Refile any task (fzf picker)",
          p = "New project (org + ZK)",
          m = {
            name = "Manage",
            t = "Manage → Tasks",
            p = "Manage → Projects",
            h = "Manage → Help",
          },
          h = "Health check",
        },
      }, { prefix = "<leader>" })
    end
  end

  -- Confirm successful setup
--  vim.notify("GTD mappings configured successfully", vim.log.levels.INFO, { title = "GTD" })
--end

return M
