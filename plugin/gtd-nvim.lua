-- plugin/gtd-nvim.lua
-- Autoload entry point for GTD-Nvim
-- This file is automatically loaded by Neovim when the plugin is installed

if vim.g.loaded_gtd_nvim then
  return
end
vim.g.loaded_gtd_nvim = true

-- Minimum Neovim version check
if vim.fn.has("nvim-0.9.0") ~= 1 then
  vim.api.nvim_echo({
    { "GTD-Nvim requires Neovim >= 0.9.0\n", "ErrorMsg" },
    { "Please upgrade your Neovim installation", "WarningMsg" },
  }, true, {})
  return
end

-- Create user commands
-- ============================================================================
-- GTD Commands
-- ============================================================================

vim.api.nvim_create_user_command("GtdCapture", function()
  local ok, gtd = pcall(require, "gtd-nvim.gtd")
  if ok and gtd.capture then
    gtd.capture({})
  else
    vim.notify("GTD capture module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Capture new item to inbox" })

vim.api.nvim_create_user_command("GtdClarify", function(opts)
  local ok, gtd = pcall(require, "gtd-nvim.gtd")
  if ok and gtd.clarify then
    local status = opts.args ~= "" and opts.args or nil
    gtd.clarify({ status = status })
  else
    vim.notify("GTD clarify module not available", vim.log.levels.ERROR)
  end
end, { nargs = "?", desc = "GTD: Clarify item at cursor" })

vim.api.nvim_create_user_command("GtdRefile", function()
  local ok, gtd = pcall(require, "gtd-nvim.gtd")
  if ok and gtd.refile_to_project then
    gtd.refile_to_project({})
  else
    vim.notify("GTD organize module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Refile item to project" })

vim.api.nvim_create_user_command("GtdProjectNew", function()
  local ok, gtd = pcall(require, "gtd-nvim.gtd")
  if ok and gtd.project_new then
    gtd.project_new({})
  else
    vim.notify("GTD projects module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Create new project" })

vim.api.nvim_create_user_command("GtdHealth", function()
  local ok, gtd = pcall(require, "gtd-nvim.gtd")
  if ok and gtd.health then
    gtd.health()
  else
    vim.notify("Running :checkhealth gtd-nvim instead", vim.log.levels.INFO)
    vim.cmd("checkhealth gtd-nvim")
  end
end, { desc = "GTD: Run health check" })

-- ============================================================================
-- GTD List Commands
-- ============================================================================

vim.api.nvim_create_user_command("GtdNextActions", function()
  local ok, lists = pcall(require, "gtd-nvim.gtd.lists")
  if ok and lists.next_actions then
    lists.next_actions()
  else
    vim.notify("GTD lists module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Show next actions" })

vim.api.nvim_create_user_command("GtdProjects", function()
  local ok, lists = pcall(require, "gtd-nvim.gtd.lists")
  if ok and lists.projects then
    lists.projects()
  else
    vim.notify("GTD lists module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Show projects" })

vim.api.nvim_create_user_command("GtdWaiting", function()
  local ok, lists = pcall(require, "gtd-nvim.gtd.lists")
  if ok and lists.waiting then
    lists.waiting()
  else
    vim.notify("GTD lists module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Show waiting for" })

vim.api.nvim_create_user_command("GtdSomedayMaybe", function()
  local ok, lists = pcall(require, "gtd-nvim.gtd.lists")
  if ok and lists.someday_maybe then
    lists.someday_maybe()
  else
    vim.notify("GTD lists module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Show someday/maybe" })

vim.api.nvim_create_user_command("GtdStuckProjects", function()
  local ok, lists = pcall(require, "gtd-nvim.gtd.lists")
  if ok and lists.stuck_projects then
    lists.stuck_projects()
  else
    vim.notify("GTD lists module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Show stuck projects" })

vim.api.nvim_create_user_command("GtdMenu", function()
  local ok, lists = pcall(require, "gtd-nvim.gtd.lists")
  if ok and lists.menu then
    lists.menu()
  else
    vim.notify("GTD lists module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Show lists menu" })

-- ============================================================================
-- GTD Management Commands
-- ============================================================================

vim.api.nvim_create_user_command("GtdManageTasks", function()
  local ok, manage = pcall(require, "gtd-nvim.gtd.manage")
  if ok and manage.manage_tasks then
    manage.manage_tasks()
  else
    vim.notify("GTD manage module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Manage tasks" })

vim.api.nvim_create_user_command("GtdManageProjects", function()
  local ok, manage = pcall(require, "gtd-nvim.gtd.manage")
  if ok and manage.manage_projects then
    manage.manage_projects()
  else
    vim.notify("GTD manage module not available", vim.log.levels.ERROR)
  end
end, { desc = "GTD: Manage projects" })

-- ============================================================================
-- GTD Audit Commands
-- ============================================================================

vim.api.nvim_create_user_command("GtdAudit", function()
  local ok, audit = pcall(require, "gtd-nvim.audit")
  if ok and audit.audit then
    audit.audit()
  else
    vim.notify("GTD audit module not available", vim.log.levels.WARN)
  end
end, { desc = "GTD: Audit current org file" })

vim.api.nvim_create_user_command("GtdAuditAll", function()
  local ok, audit = pcall(require, "gtd-nvim.audit")
  if ok and audit.audit_all then
    audit.audit_all()
  else
    vim.notify("GTD audit module not available", vim.log.levels.WARN)
  end
end, { desc = "GTD: Audit all GTD files" })

-- ============================================================================
-- Zettelkasten Commands
-- ============================================================================

vim.api.nvim_create_user_command("ZkNew", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.new_note then
    zk.new_note()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: New note" })

vim.api.nvim_create_user_command("ZkFind", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.find_notes then
    zk.find_notes()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: Find notes" })

vim.api.nvim_create_user_command("ZkSearch", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.search_notes then
    zk.search_notes()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: Search notes" })

vim.api.nvim_create_user_command("ZkRecent", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.recent_notes then
    zk.recent_notes()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: Recent notes" })

vim.api.nvim_create_user_command("ZkBacklinks", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.show_backlinks then
    zk.show_backlinks()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: Show backlinks" })

vim.api.nvim_create_user_command("ZkDaily", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.daily_note then
    zk.daily_note()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: Daily note" })

vim.api.nvim_create_user_command("ZkProject", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.new_project then
    zk.new_project()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: New project note" })

vim.api.nvim_create_user_command("ZkPerson", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.new_person then
    zk.new_person()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: New person note" })

vim.api.nvim_create_user_command("ZkBook", function()
  local ok, zk = pcall(require, "gtd-nvim.zettelkasten")
  if ok and zk.new_book then
    zk.new_book()
  else
    vim.notify("Zettelkasten module not available", vim.log.levels.ERROR)
  end
end, { desc = "ZK: New book note" })

-- ============================================================================
-- Link Commands
-- ============================================================================

vim.api.nvim_create_user_command("LinkInsert", function()
  local ok, link = pcall(require, "gtd-nvim.utils.link_insert")
  if ok and link.insert_link then
    link.insert_link()
  else
    vim.notify("Link insert module not available", vim.log.levels.ERROR)
  end
end, { desc = "Insert link" })

vim.api.nvim_create_user_command("LinkOpen", function()
  local ok, link = pcall(require, "gtd-nvim.utils.link_open")
  if ok and link.open_link then
    link.open_link()
  else
    vim.notify("Link open module not available", vim.log.levels.ERROR)
  end
end, { desc = "Open link under cursor" })
