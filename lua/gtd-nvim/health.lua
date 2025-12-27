-- gtd-nvim/health.lua
-- Health checks for :checkhealth gtd-nvim

local M = {}

local function check_file_exists(path, label)
  local expanded = vim.fn.expand(path)
  if vim.fn.filereadable(expanded) == 1 then
    vim.health.ok(label .. " found: " .. expanded)
    return true
  elseif vim.fn.isdirectory(expanded) == 1 then
    vim.health.ok(label .. " directory found: " .. expanded)
    return true
  else
    vim.health.warn(label .. " not found: " .. expanded)
    return false
  end
end

local function check_dir_exists(path, label)
  local expanded = vim.fn.expand(path)
  if vim.fn.isdirectory(expanded) == 1 then
    vim.health.ok(label .. " found: " .. expanded)
    return true
  else
    vim.health.warn(label .. " not found: " .. expanded)
    return false
  end
end

local function check_plugin(name, required)
  local ok = pcall(require, name)
  if ok then
    vim.health.ok(name .. " is installed")
    return true
  elseif required then
    vim.health.error(name .. " is required but not installed")
    return false
  else
    vim.health.warn(name .. " is not installed (optional)")
    return false
  end
end

local function check_executable(name, required)
  if vim.fn.executable(name) == 1 then
    vim.health.ok(name .. " is installed")
    return true
  elseif required then
    vim.health.error(name .. " is required but not installed")
    return false
  else
    vim.health.warn(name .. " is not installed (recommended)")
    return false
  end
end

function M.check()
  vim.health.start("GTD-Nvim")
  
  -- Check Neovim version
  if vim.fn.has("nvim-0.9.0") == 1 then
    vim.health.ok("Neovim >= 0.9.0")
  else
    vim.health.error("Neovim >= 0.9.0 is required")
  end
  
  -- Check required plugins
  vim.health.start("Required Dependencies")
  check_plugin("plenary", true)
  
  -- Check fuzzy finder (one of them required)
  local has_fzf = check_plugin("fzf-lua", false)
  local has_telescope = check_plugin("telescope", false)
  
  if has_fzf or has_telescope then
    vim.health.ok("Fuzzy finder available")
  else
    vim.health.error("Either fzf-lua or telescope.nvim is required")
  end
  
  -- Check optional plugins
  vim.health.start("Optional Dependencies")
  check_plugin("which-key", false)
  check_plugin("orgmode", false)
  check_plugin("nvim-treesitter", false)
  
  -- Check system tools
  vim.health.start("System Tools")
  check_executable("fzf", false)
  check_executable("rg", false)
  check_executable("fd", false)
  
  -- Check GTD directories
  vim.health.start("GTD System")
  
  -- Try to use config module first
  local cfg_ok, cfg = pcall(require, "gtd-nvim.config")
  local gtd_root, zk_root
  
  if cfg_ok then
    gtd_root = cfg.gtd_home()
    zk_root = cfg.notes_home()
    vim.health.ok("Config module loaded")
  else
    -- Fallback to gtd module config
    local gtd_ok, gtd = pcall(require, "gtd-nvim.gtd")
    gtd_root = (gtd_ok and gtd.cfg and gtd.cfg.gtd_root) or "~/Documents/GTD"
    zk_root = "~/Documents/Notes"
  end
  
  check_dir_exists(gtd_root, "GTD root")
  check_file_exists(gtd_root .. "/Inbox.org", "Inbox file")
  check_dir_exists(gtd_root .. "/Projects", "Projects directory")
  check_dir_exists(gtd_root .. "/Areas", "Areas directory")
  
  -- Check Zettelkasten directories
  vim.health.start("Zettelkasten System")
  check_dir_exists(zk_root, "Zettelkasten root")
  
  -- Check GTD modules
  vim.health.start("GTD Modules")
  local modules = {
    -- V2 Capture system
    "gtd-nvim.capture",
    "gtd-nvim.capture.workflows.clarify",
    "gtd-nvim.capture.workflows.status",
    "gtd-nvim.capture.workflows.edit",
    -- Core modules
    "gtd-nvim.gtd.organize",
    "gtd-nvim.gtd.manage",
    "gtd-nvim.gtd.lists",
    "gtd-nvim.gtd.projects",
    "gtd-nvim.gtd.areas",
    "gtd-nvim.gtd.agenda",
    "gtd-nvim.gtd.shared",
    "gtd-nvim.gtd.chronos",
    "gtd-nvim.gtd.utils.task_id",
  }
  
  local loaded = 0
  for _, mod in ipairs(modules) do
    local ok = pcall(require, mod)
    if ok then
      loaded = loaded + 1
    else
      vim.health.warn("Module not loaded: " .. mod)
    end
  end
  
  if loaded == #modules then
    vim.health.ok("All GTD modules loaded successfully (" .. loaded .. "/" .. #modules .. ")")
  elseif loaded > 0 then
    vim.health.warn("Partial GTD modules loaded (" .. loaded .. "/" .. #modules .. ")")
  else
    vim.health.error("No GTD modules could be loaded")
  end
  
  -- Check Zettelkasten modules
  vim.health.start("Zettelkasten Modules")
  local zk_modules = {
    "gtd-nvim.zettelkasten",
    "gtd-nvim.zettelkasten.zettelkasten",
    "gtd-nvim.zettelkasten.capture",
    "gtd-nvim.zettelkasten.manage",
    "gtd-nvim.zettelkasten.project",
    "gtd-nvim.zettelkasten.reading",
    "gtd-nvim.zettelkasten.people",
  }
  
  local zk_loaded = 0
  for _, mod in ipairs(zk_modules) do
    local ok = pcall(require, mod)
    if ok then
      zk_loaded = zk_loaded + 1
    else
      vim.health.warn("Module not loaded: " .. mod)
    end
  end
  
  if zk_loaded == #zk_modules then
    vim.health.ok("All Zettelkasten modules loaded successfully (" .. zk_loaded .. "/" .. #zk_modules .. ")")
  elseif zk_loaded > 0 then
    vim.health.warn("Partial Zettelkasten modules loaded (" .. zk_loaded .. "/" .. #zk_modules .. ")")
  else
    vim.health.error("No Zettelkasten modules could be loaded")
  end
  
  -- Check GTD Audit module
  vim.health.start("GTD Audit")
  local audit_ok = pcall(require, "gtd-nvim.audit")
  if audit_ok then
    vim.health.ok("GTD Audit module available")
  else
    vim.health.warn("GTD Audit module not available (optional)")
  end
end

return M
