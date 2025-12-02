-- gtd-nvim/init.lua
-- GTD-Nvim: Complete Getting Things Done system for Neovim
-- Integrated with Zettelkasten for knowledge management
-- https://github.com/dr3v3s/gtd-nvim

local M = {}

M._VERSION = "2.0.0"

-- Default configuration
M.config = {
  -- GTD directories
  gtd_root = vim.fn.expand("~/Documents/GTD"),
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  areas_dir = "Areas",
  archive_file = "Archive.org",
  
  -- Zettelkasten directories
  zk_root = vim.fn.expand("~/Documents/Notes"),
  zk_projects = "Projects",
  
  -- UI settings
  border = "rounded",
  
  -- Behavior
  auto_save = true,
  quiet_capture = true,
}

-- Safe require helper
local function safe_require(name)
  local ok, mod = pcall(require, name)
  if not ok then
    return nil, mod
  end
  return mod
end

-- Setup function
function M.setup(opts)
  -- Merge user config
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  -- Setup GTD system
  local gtd = safe_require("gtd-nvim.gtd")
  if gtd and gtd.setup then
    gtd.setup({
      gtd_root = M.config.gtd_root,
      zk_root = M.config.zk_root,
      inbox_file = M.config.inbox_file,
      projects_dir = M.config.projects_dir,
    })
  end
  
  -- Setup Zettelkasten
  local zk = safe_require("gtd-nvim.zettelkasten")
  if zk and zk.setup then
    zk.setup({
      notes_dir = M.config.zk_root,
      keymaps = false, -- User sets their own keymaps
    })
  end
  
  -- Setup Audit
  local audit = safe_require("gtd-nvim.audit")
  if audit and audit.setup then
    audit.setup({
      gtd_root = M.config.gtd_root,
    })
  end
end

-- Export modules for direct access
M.gtd = safe_require("gtd-nvim.gtd")
M.zettelkasten = safe_require("gtd-nvim.zettelkasten")
M.audit = safe_require("gtd-nvim.audit")
M.utils = {
  link_insert = safe_require("gtd-nvim.utils.link_insert"),
  link_open = safe_require("gtd-nvim.utils.link_open"),
}

-- Convenience shortcuts
function M.capture(opts)
  if M.gtd and M.gtd.capture then
    return M.gtd.capture(opts or {})
  end
end

function M.clarify(opts)
  if M.gtd and M.gtd.clarify then
    return M.gtd.clarify(opts or {})
  end
end

function M.refile(opts)
  if M.gtd and M.gtd.refile_to_project then
    return M.gtd.refile_to_project(opts or {})
  end
end

function M.health()
  if M.gtd and M.gtd.health then
    return M.gtd.health()
  end
end

return M
