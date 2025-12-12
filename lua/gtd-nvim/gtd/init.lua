-- ============================================================================
-- GTD-NVIM MAIN ENTRY POINT
-- ============================================================================
-- GTD glue: delegates to capture / clarify / organize / projects
-- Keeps config minimal and stable. Safe requires; friendly health checks.
--
-- @module gtd-nvim.gtd
-- @version 1.0.0-alpha
-- @see 202512081430-GTD-Nvim-Shared-Module-Audit
-- ============================================================================

local M = {}

-- Version information (canonical source: shared.lua)
M._VERSION = "1.0.0-alpha"
M._UPDATED = "2024-12-08"

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
local task_id = safe_require "gtd-nvim.gtd.utils.task_id"
local capture = safe_require "gtd-nvim.gtd.capture"
local clarify = safe_require "gtd-nvim.gtd.clarify"
local organize = safe_require "gtd-nvim.gtd.organize"
local projects = safe_require "gtd-nvim.gtd.projects"

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

--- Clarify with fzf-lua task picker
--- Opens picker to select any task, then runs full GTD clarification workflow
--- including Expected Outcome, Next Action, dates, and more
---@param opts table|nil Options passed to clarify_pick_any
function M.clarify_pick(opts)
  if not clarify then
    vim.notify("gtd.clarify not loaded", vim.log.levels.ERROR)
    return
  end
  if not clarify.clarify_pick_any then
    vim.notify("gtd.clarify.clarify_pick_any() not found", vim.log.levels.ERROR)
    return
  end
  return clarify.clarify_pick_any(opts or {})
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

  -- Setup GTD highlight groups for colored glyphs
  local shared = safe_require("gtd-nvim.gtd.shared")
  if shared and shared.setup_highlights then
    shared.setup_highlights()
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

  vim.api.nvim_create_user_command("GtdClarifyPick", function()
    M.clarify_pick {}
  end, { desc = "Pick task with fzf and run GTD clarification (Expected Outcome, Next Action, etc.)" })

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
  
  vim.api.nvim_create_user_command("GtdVersion", function()
    M.version()
  end, { desc = "Show GTD-Nvim version information" })
  
  vim.api.nvim_create_user_command("GtdFindDuplicates", function()
    M.find_duplicates()
  end, { desc = "Find duplicate TASK_IDs in GTD system" })
end

-- ------------------------ Duplicate Detection ------------------------
function M.find_duplicates()
  if not task_id or not task_id.find_all_duplicates then
    vim.notify("task_id.find_all_duplicates not available", vim.log.levels.ERROR)
    return
  end
  
  local duplicates = task_id.find_all_duplicates(M.cfg.gtd_root)
  local count = 0
  
  for _ in pairs(duplicates) do
    count = count + 1
  end
  
  if count == 0 then
    vim.notify("✅ No duplicate TASK_IDs found", vim.log.levels.INFO)
    return
  end
  
  -- Build report
  local report = { "⚠️  Found " .. count .. " duplicate TASK_ID(s):", "" }
  
  for task_id_val, locations in pairs(duplicates) do
    table.insert(report, "TASK_ID: " .. task_id_val)
    for _, loc in ipairs(locations) do
      local short_file = vim.fn.fnamemodify(loc.file, ":t")
      table.insert(report, string.format("  - %s (line %d): %s", short_file, loc.heading_line or loc.line, loc.title or "?"))
    end
    table.insert(report, "")
  end
  
  -- Show in floating window or quickfix
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, report)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#report + 2, vim.o.lines - 4)
  
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " GTD Duplicate Report ",
    title_pos = "center",
  })
  
  -- Press q to close
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
end

local manage = safe_require "gtd-nvim.gtd.manage"

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

-- Setup Weekly Review module
local review = safe_require "gtd-nvim.gtd.review"

pcall(function()
  if review and review.setup then
    review.setup {
      gtd_root = M.cfg.gtd_root,
    }
  end
end)

-- Setup Task Editor module
local editor = safe_require "gtd-nvim.gtd.editor"

pcall(function()
  if editor and editor.setup then
    editor.setup {
      gtd_root = M.cfg.gtd_root,
      zk_root = M.cfg.zk_root,
    }
  end
end)

-- ============================================================================
-- VERSION INFORMATION
-- ============================================================================

-- Show version info for all modules
function M.version()
  local shared = safe_require("gtd-nvim.gtd.shared")
  if not shared or not shared.VERSION then
    vim.notify("GTD-Nvim " .. M._VERSION, vim.log.levels.INFO)
    return
  end
  
  local g = shared.glyphs or {}
  local lines = {
    "╔══════════════════════════════════════════════════════╗",
    "║             GTD-NVIM VERSION INFORMATION             ║",
    "╠══════════════════════════════════════════════════════╣",
    string.format("║  Plugin Version: %-35s ║", shared.VERSION.string),
    string.format("║  Release Date:   %-35s ║", shared.VERSION.date),
    "╠══════════════════════════════════════════════════════╣",
    "║  MODULE VERSIONS                                     ║",
    "╠══════════════════════════════════════════════════════╣",
  }
  
  for module, version in pairs(shared.MODULE_VERSIONS) do
    local status = version:match("^1%.") and "✓" or "○"
    table.insert(lines, string.format("║  %s %-12s  %s", status, module, string.rep(" ", 35 - #module) .. version .. " ║"))
  end
  
  table.insert(lines, "╠══════════════════════════════════════════════════════╣")
  table.insert(lines, "║  Legend: ✓ = 1.0 ready  ○ = needs update             ║")
  table.insert(lines, "╚══════════════════════════════════════════════════════╝")
  
  -- Show in floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  
  local width = 58
  local height = #lines
  
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  })
  
  -- Press q to close
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })
end

return M
