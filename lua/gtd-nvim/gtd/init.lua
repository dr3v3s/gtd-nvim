-- ~/.config/nvim/lua/gtd/init.lua
-- GTD glue: delegates to capture / clarify / organize / projects.
-- Keeps config minimal and stable. Safe requires; friendly health checks.
-- ENHANCED: Added convert task to project command

local M = {}

-- ------------------------ Config ------------------------
M.cfg = {
  gtd_root = "~/Documents/GTD",
  zk_root = "~/Documents/Notes",
  inbox_file = "Inbox.org",
  projects_dir = "Projects", -- under gtd_root
  zk_projects = "Projects", -- under zk_root
}

-- ------------------------ Helpers ------------------------
local function xp(p)
  return vim.fn.expand(p)
end
local function j(a, b)
  return (a:gsub("/+$", "")) .. "/" .. (b:gsub("^/+", ""))
end
local function ensure_dir(p)
  vim.fn.mkdir(vim.fn.fnamemodify(p, ":h"), "p")
end
local function readf(p)
  return vim.fn.readfile(p)
end
local function writef(p, L)
  return vim.fn.writefile(L, p) == 0
end

local function inbox_path()
  return j(xp(M.cfg.gtd_root), M.cfg.inbox_file)
end
local function projects_org_dir()
  return j(xp(M.cfg.gtd_root), M.cfg.projects_dir)
end
local function projects_note_dir()
  return j(xp(M.cfg.zk_root), M.cfg.zk_projects)
end

-- Safe require (don't explode on startup)
local function safe_require(name)
  local ok, mod = pcall(require, name)
  if not ok then
    vim.notify("gtd: require('" .. name .. "') failed: " .. tostring(mod), vim.log.levels.WARN)
    return nil
  end
  return mod
end

-- Backing modules (namespace style)
local task_id = safe_require "gtd.utils.task_id"
local capture = safe_require "gtd.capture"
local clarify = safe_require "gtd.clarify"
local organize = safe_require "gtd.organize"
local projects = safe_require "gtd.projects"

-- ------------------------ Health ------------------------
function M.health()
  local issues = {}

  if not task_id then
    table.insert(issues, "Missing gtd.utils.task_id")
  end
  if not capture then
    table.insert(issues, "Missing gtd.capture")
  end
  if not clarify then
    table.insert(issues, "Missing gtd.clarify")
  end
  if not organize then
    table.insert(issues, "Missing gtd.organize")
  end
  if not projects then
    table.insert(issues, "Missing gtd.projects")
  end

  local gtd = xp(M.cfg.gtd_root)
  local zk = xp(M.cfg.zk_root)

  if vim.fn.isdirectory(gtd) == 0 then
    table.insert(issues, "GTD root not found: " .. gtd)
  end
  if vim.fn.isdirectory(zk) == 0 then
    table.insert(issues, "ZK root not found: " .. zk)
  end

  local pod = projects_org_dir()
  if vim.fn.isdirectory(pod) == 0 then
    vim.fn.mkdir(pod, "p")
  end
  local pzd = projects_note_dir()
  if vim.fn.isdirectory(pzd) == 0 then
    vim.fn.mkdir(pzd, "p")
  end

  local inb = inbox_path()
  if vim.fn.filereadable(inb) == 0 then
    ensure_dir(inb)
    writef(inb, { "#+TITLE: Inbox", "" })
  end

  if #issues > 0 then
    for _, e in ipairs(issues) do
      vim.notify("GTD health: " .. e, vim.log.levels.WARN)
    end
  end
  return issues
end

-- ------------------------ Public API ------------------------
function M.capture(opts)
  if not capture then
    return
  end
  return capture.capture_quick(opts or {})
end

function M.clarify(opts)
  if not clarify then
    return
  end
  return clarify.at_cursor(opts or {})
end

function M.refile_to_project(opts)
  if not organize then
    return
  end
  if organize.refile_to_project then
    return organize.refile_to_project(opts or {})
  else
    vim.notify("gtd.organize.refile_to_project() not found", vim.log.levels.ERROR)
  end
end

function M.project_new(opts)
  if not projects then
    return
  end
  return projects.create(opts or {})
end

function M.convert_task_to_project(opts)
  if not projects then
    vim.notify("gtd.projects not loaded", vim.log.levels.ERROR)
    return
  end
  if not projects.create_from_task_at_cursor then
    vim.notify("gtd.projects.create_from_task_at_cursor() not found", vim.log.levels.ERROR)
    return
  end
  return projects.create_from_task_at_cursor(opts or {})
end

function M.link_task_to_project(opts)
  if not projects then
    return
  end
  return projects.link_task_to_project_at_cursor(opts or {})
end

-- ------------------------ Setup & Commands ------------------------
function M.setup(user_cfg)
  if user_cfg then
    for k, v in pairs(user_cfg) do
      M.cfg[k] = v
    end
  end

  pcall(function()
    if clarify and clarify.setup then
      clarify.setup { gtd_root = M.cfg.gtd_root, inbox_file = M.cfg.inbox_file, projects_dir = M.cfg.projects_dir }
    end
  end)

  M.health()

  vim.api.nvim_create_user_command("GtdCapture", function()
    M.capture {}
  end, { desc = "Capture new task to Inbox" })

  vim.api.nvim_create_user_command("GtdClarify", function(opts)
    local status = opts.args ~= "" and opts.args or nil
    M.clarify { status = status }
  end, { nargs = "?", desc = "Clarify task at cursor" })

  vim.api.nvim_create_user_command("GtdClarifyPromote", function(opts)
    local status = opts.args ~= "" and opts.args or nil
    M.clarify { status = status, promote_if_needed = true }
  end, { nargs = "?", desc = "Clarify and promote line to task" })

  vim.api.nvim_create_user_command("GtdRefile", function()
    M.refile_to_project {}
  end, { desc = "Refile task to project" })

  vim.api.nvim_create_user_command("GtdProjectNew", function()
    M.project_new {}
  end, { desc = "Create new project" })

  vim.api.nvim_create_user_command("GtdConvertToProject", function()
    M.convert_task_to_project {}
  end, { desc = "Convert task at cursor to project" })

  vim.api.nvim_create_user_command("GtdLinkToProject", function()
    M.link_task_to_project {}
  end, { desc = "Link task to project" })

  vim.api.nvim_create_user_command("GtdHealth", function()
    M.health()
  end, { desc = "Check GTD system health" })
end

local manage = safe_require "gtd.manage"

pcall(function()
  if manage and manage.setup then
    manage.setup {
      gtd_root = M.cfg.gtd_root,
      zk_root = M.cfg.zk_root,
      projects_dir = M.cfg.projects_dir,
      inbox_file = M.cfg.inbox_file,
    }
  end
end)

return M
