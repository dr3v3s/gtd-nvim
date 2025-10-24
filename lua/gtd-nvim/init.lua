-- GTD-Nvim: A complete Getting Things Done system for Neovim
-- Integrated with Zettelkasten for knowledge management

local M = {}

-- Default configuration
M.config = {
  -- GTD directories
  gtd_dir = vim.fn.expand("~/.config/kanso/"),
  
  -- Zettelkasten directories
  zk_dir = vim.fn.expand("~/Documents/Notes/"),
  
  -- Auto-save settings
  auto_save = true,
  
  -- UI settings
  border = "rounded",
}

-- Setup function to initialize the plugin
function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  -- Initialize GTD system
  local gtd = require("gtd-nvim.gtd")
  if gtd.setup then
    gtd.setup(M.config)
  end
  
  -- Initialize Zettelkasten if configured
  if M.config.zk_dir then
    local zk = require("gtd-nvim.zettelkasten")
    if zk.setup then
      zk.setup(M.config)
    end
  end
end

-- Export GTD modules for direct access
M.gtd = require("gtd-nvim.gtd")
M.zettelkasten = require("gtd-nvim.zettelkasten")

return M
