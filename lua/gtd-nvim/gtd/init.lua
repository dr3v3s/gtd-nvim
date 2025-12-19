-- ============================================================================
-- GTD-NVIM MAIN ENTRY POINT
-- ============================================================================
-- GTD glue: delegates to capture / clarify / organize / projects
-- Keeps config minimal and stable. Safe requires; friendly health checks.
--
-- @module gtd-nvim.gtd
-- @version 1.2.0
-- @see 202512181430-Kairos-Integration
-- ============================================================================

local M = {}

-- Version information
M._VERSION = "1.3.0"
M._UPDATED = "2024-12-19"

-- ------------------------ Config ------------------------
-- NOTE: These are fallback defaults. Use config module for user settings!
-- Access via shared.gtd_home(), shared.notes_home(), etc.
M.cfg = {
  gtd_root = "~/Documents/GTD",
  zk_root = "~/Documents/Notes",
  inbox_file = "Inbox.org",
  projects_dir = "Projects", -- under gtd_root
  zk_projects = "Projects", -- under zk_root
}

-- Load config module (lazy)
local _config = nil
local function get_config()
  if not _config then
    local ok, cfg = pcall(require, "gtd-nvim.config")
    if ok then _config = cfg end
  end
  return _config
end

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
local function writef(p, L)
  return vim.fn.writefile(L, p) == 0
end

-- Path helpers using config
local function gtd_root()
  local cfg = get_config()
  if cfg then return cfg.gtd_home() end
  return xp(M.cfg.gtd_root)
end

local function zk_root()
  local cfg = get_config()
  if cfg then return cfg.notes_home() end
  return xp(M.cfg.zk_root)
end

local function inbox_path()
  return j(gtd_root(), M.cfg.inbox_file)
end
local function projects_org_dir()
  return j(gtd_root(), M.cfg.projects_dir)
end
local function projects_note_dir()
  return j(zk_root(), M.cfg.zk_projects)
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

-- ============================================================================
-- MODULE LOADING
-- ============================================================================

-- Core modules
local task_id = safe_require "gtd-nvim.gtd.utils.task_id"
local capture = safe_require "gtd-nvim.gtd.capture"
local clarify = safe_require "gtd-nvim.gtd.clarify"
local organize = safe_require "gtd-nvim.gtd.organize"
local projects = safe_require "gtd-nvim.gtd.projects"
local manage = safe_require "gtd-nvim.gtd.manage"
local review = safe_require "gtd-nvim.gtd.review"
local editor = safe_require "gtd-nvim.gtd.editor"
local lists = safe_require "gtd-nvim.gtd.lists"
local areas = safe_require "gtd-nvim.gtd.areas"
local reminders = safe_require "gtd-nvim.gtd.reminders"
local status = safe_require "gtd-nvim.gtd.status"

-- Kairos daemon integration (calendar/reminders via EventKit)
local kairos = safe_require "gtd-nvim.gtd.kairos"

-- Chronos daemon integration (GTD orchestration engine)
local chronos = safe_require "gtd-nvim.gtd.chronos"

-- ============================================================================
-- HEALTH CHECK
-- ============================================================================

function M.health()
  local issues = {}
  local warnings = {}

  -- Core modules
  if not task_id then table.insert(issues, "Missing gtd.utils.task_id") end
  if not capture then table.insert(issues, "Missing gtd.capture") end
  if not clarify then table.insert(issues, "Missing gtd.clarify") end
  if not organize then table.insert(issues, "Missing gtd.organize") end
  if not projects then table.insert(issues, "Missing gtd.projects") end
  if not manage then table.insert(warnings, "Missing gtd.manage") end
  if not lists then table.insert(warnings, "Missing gtd.lists") end
  if not review then table.insert(warnings, "Missing gtd.review") end
  if not editor then table.insert(warnings, "Missing gtd.editor") end
  if not areas then table.insert(warnings, "Missing gtd.areas") end
  if not reminders then table.insert(warnings, "Missing gtd.reminders") end
  if not status then table.insert(warnings, "Missing gtd.status") end

  -- Kairos daemon
  if not kairos then
    table.insert(warnings, "Missing gtd.kairos (calendar/reminders unavailable)")
  else
    local kairos_status = kairos.status()
    if not kairos_status.available then
      table.insert(warnings, "Kairos daemon not available (socket missing)")
    elseif not kairos_status.running then
      table.insert(warnings, "Kairos daemon not running")
    end
  end

  -- Chronos daemon
  if not chronos then
    table.insert(warnings, "Missing gtd.chronos (GTD orchestration unavailable)")
  else
    if not chronos.is_available() then
      table.insert(warnings, "Chronos daemon not available (socket missing)")
    else
      local running, err = chronos.is_running()
      if not running then
        table.insert(warnings, "Chronos daemon not running: " .. (err or ""))
      end
    end
  end

  -- Directories
  local gtd = xp(M.cfg.gtd_root)
  local zk = xp(M.cfg.zk_root)

  if vim.fn.isdirectory(gtd) == 0 then
    table.insert(issues, "GTD root not found: " .. gtd)
  end
  if vim.fn.isdirectory(zk) == 0 then
    table.insert(issues, "ZK root not found: " .. zk)
  end

  -- Ensure directories exist
  local pod = projects_org_dir()
  if vim.fn.isdirectory(pod) == 0 then
    vim.fn.mkdir(pod, "p")
  end
  local pzd = projects_note_dir()
  if vim.fn.isdirectory(pzd) == 0 then
    vim.fn.mkdir(pzd, "p")
  end

  -- Ensure inbox exists
  local inb = inbox_path()
  if vim.fn.filereadable(inb) == 0 then
    ensure_dir(inb)
    writef(inb, { "#+TITLE: Inbox", "" })
  end

  -- Report
  if #issues > 0 then
    for _, e in ipairs(issues) do
      vim.notify("GTD ERROR: " .. e, vim.log.levels.ERROR)
    end
  end
  if #warnings > 0 then
    for _, w in ipairs(warnings) do
      vim.notify("GTD WARN: " .. w, vim.log.levels.WARN)
    end
  end
  if #issues == 0 and #warnings == 0 then
    vim.notify("GTD: All systems healthy ✓", vim.log.levels.INFO)
  end

  return issues, warnings
end

-- ============================================================================
-- PUBLIC API - Core GTD
-- ============================================================================

function M.capture(opts)
  if not capture then return end
  return capture.capture_quick(opts or {})
end

function M.clarify(opts)
  if not clarify then return end
  return clarify.at_cursor(opts or {})
end

--- Clarify with fzf-lua task picker
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
  if not organize then return end
  if organize.refile_to_project then
    return organize.refile_to_project(opts or {})
  else
    vim.notify("gtd.organize.refile_to_project() not found", vim.log.levels.ERROR)
  end
end

function M.project_new(opts)
  if not projects then return end
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
  if not projects then return end
  return projects.link_task_to_project_at_cursor(opts or {})
end

-- ============================================================================
-- PUBLIC API - Calendar (via Kairos)
-- ============================================================================

--- Show today's agenda (calendar events + GTD scheduled tasks)
--- Delegates to lists.agenda() for comprehensive GTD agenda view
---@param date string|nil Optional date in YYYY-MM-DD format (default: today)
function M.agenda(date)
  if not lists then
    vim.notify("gtd.lists not loaded", vim.log.levels.ERROR)
    return
  end
  return lists.agenda(date)
end

--- Find free time slots for scheduling
--- Delegates to lists.free_slots() for fzf-based view
---@param date string|nil Optional date in YYYY-MM-DD format (default: today)
function M.free_slots(date)
  if not lists then
    vim.notify("gtd.lists not loaded", vim.log.levels.ERROR)
    return
  end
  return lists.free_slots(date)
end

-- ============================================================================
-- WEEKLY REVIEW
-- ============================================================================

--- Start GTD Weekly Review
function M.weekly_review()
  if not review then
    vim.notify("gtd.review not loaded", vim.log.levels.ERROR)
    return
  end
  if review.start then
    return review.start()
  elseif review.weekly then
    return review.weekly()
  end
  vim.notify("gtd.review.start() not found", vim.log.levels.ERROR)
end

--- Resume incomplete weekly review
function M.review_resume()
  if not review then
    vim.notify("gtd.review not loaded", vim.log.levels.ERROR)
    return
  end
  if review.resume then
    return review.resume()
  end
  vim.notify("gtd.review.resume() not found", vim.log.levels.ERROR)
end

--- Browse past reviews
function M.review_history()
  if not review then
    vim.notify("gtd.review not loaded", vim.log.levels.ERROR)
    return
  end
  if review.index then
    return review.index()
  elseif review.history then
    return review.history()
  end
  vim.notify("gtd.review.index() not found", vim.log.levels.ERROR)
end

-- ============================================================================
-- STATUS CHANGES
-- ============================================================================

--- Change task status with fzf picker
function M.change_status()
  if not status then
    vim.notify("gtd.status not loaded", vim.log.levels.ERROR)
    return
  end
  if status.change_status then
    return status.change_status()
  end
  vim.notify("gtd.status.change_status() not found", vim.log.levels.ERROR)
end

--- Cycle task status forward or backward
---@param direction number 1 for forward, -1 for backward
function M.cycle_status(direction)
  if not status then
    vim.notify("gtd.status not loaded", vim.log.levels.ERROR)
    return
  end
  if status.cycle_status then
    return status.cycle_status(direction or 1)
  end
  vim.notify("gtd.status.cycle_status() not found", vim.log.levels.ERROR)
end

-- ============================================================================
-- AREAS OF RESPONSIBILITY
-- ============================================================================

--- Browse Areas of Responsibility
function M.browse_areas()
  if not areas then
    vim.notify("gtd.areas not loaded", vim.log.levels.ERROR)
    return
  end
  if areas.browse then
    return areas.browse()
  elseif areas.pick_area then
    return areas.pick_area(function(area)
      if area and area.dir then
        vim.cmd("edit " .. vim.fn.fnameescape(area.dir))
      end
    end)
  end
  vim.notify("gtd.areas.browse() not found", vim.log.levels.ERROR)
end

--- Check if calendar is available (Kairos daemon running)
function M.calendar_available()
  return kairos and kairos.is_available() and kairos.is_running()
end

-- ============================================================================
-- PUBLIC API - Lists (fzf pickers)
-- ============================================================================

--- Open lists menu (NEXT, Projects, Waiting, etc.)
function M.lists_menu()
  if not lists then
    vim.notify("gtd.lists not loaded", vim.log.levels.ERROR)
    return
  end
  if lists.menu then
    return lists.menu()
  end
end

--- Show NEXT actions
function M.list_next()
  if not lists then return end
  if lists.show_next then
    return lists.show_next()
  end
end

--- Show projects
function M.list_projects()
  if not lists then return end
  if lists.show_projects then
    return lists.show_projects()
  end
end

--- Show WAITING items
function M.list_waiting()
  if not lists then return end
  if lists.show_waiting then
    return lists.show_waiting()
  end
end

-- ============================================================================
-- DUPLICATE DETECTION
-- ============================================================================

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
    vim.notify(" No duplicate TASK_IDs found", vim.log.levels.INFO)
    return
  end
  
  local report = { "  Found " .. count .. " duplicate TASK_ID(s):", "" }
  
  for task_id_val, locations in pairs(duplicates) do
    table.insert(report, "TASK_ID: " .. task_id_val)
    for _, loc in ipairs(locations) do
      local short_file = vim.fn.fnamemodify(loc.file, ":t")
      table.insert(report, string.format("  - %s (line %d): %s", short_file, loc.heading_line or loc.line, loc.title or "?"))
    end
    table.insert(report, "")
  end
  
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
  
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
end

-- ============================================================================
-- VERSION INFORMATION
-- ============================================================================

function M.version()
  local shared = safe_require("gtd-nvim.gtd.shared")
  if not shared or not shared.VERSION then
    vim.notify("GTD-Nvim " .. M._VERSION, vim.log.levels.INFO)
    return
  end
  
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
  
  for module, version in pairs(shared.MODULE_VERSIONS or {}) do
    local status = version:match("^1%.") and "✓" or "○"
    table.insert(lines, string.format("║  %s %-12s  %s", status, module, string.rep(" ", 35 - #module) .. version .. " ║"))
  end
  
  table.insert(lines, "╠══════════════════════════════════════════════════════╣")
  table.insert(lines, "║  Legend: ✓ = 1.0 ready  ○ = needs update             ║")
  table.insert(lines, "╚══════════════════════════════════════════════════════╝")
  
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
  
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(user_cfg)
  if user_cfg then
    for k, v in pairs(user_cfg) do
      M.cfg[k] = v
    end
  end

  -- Setup GTD highlight groups
  local shared = safe_require("gtd-nvim.gtd.shared")
  if shared and shared.setup_highlights then
    shared.setup_highlights()
  end

  -- Setup submodules
  pcall(function()
    if clarify and clarify.setup then
      clarify.setup { 
        gtd_root = M.cfg.gtd_root, 
        inbox_file = M.cfg.inbox_file, 
        projects_dir = M.cfg.projects_dir 
      }
    end
  end)

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

  pcall(function()
    if review and review.setup then
      review.setup { gtd_root = M.cfg.gtd_root }
    end
  end)

  pcall(function()
    if editor and editor.setup then
      editor.setup {
        gtd_root = M.cfg.gtd_root,
        zk_root = M.cfg.zk_root,
      }
    end
  end)

  pcall(function()
    if lists and lists.setup then
      lists.setup { gtd_root = M.cfg.gtd_root }
    end
  end)

  -- Setup Projects
  pcall(function()
    if projects and projects.setup then
      projects.setup {
        projects_dir = xp(M.cfg.gtd_root) .. "/" .. M.cfg.projects_dir,
        zk_project_root = xp(M.cfg.zk_root) .. "/" .. M.cfg.zk_projects,
      }
    end
  end)

  -- Setup Areas
  pcall(function()
    if areas and areas.setup then
      areas.setup {}
    end
  end)

  -- Setup Reminders (Apple Reminders integration)
  pcall(function()
    if reminders and reminders.setup then
      reminders.setup {
        gtd_root = M.cfg.gtd_root,
        inbox_file = M.cfg.inbox_file,
        projects_dir = M.cfg.projects_dir,
      }
    end
  end)

  -- Setup Status (org-mode status changes)
  -- Note: status.lua doesn't have setup(), just uses shared.glyphs

  -- Setup UI utilities
  pcall(function()
    local ui = safe_require "gtd-nvim.gtd.ui"
    if ui and ui.setup then
      ui.setup {}
    end
  end)

  -- Setup Kairos daemon integration
  pcall(function()
    if kairos and kairos.setup then
      kairos.setup {}
    end
  end)

  -- Setup Chronos daemon integration (GTD orchestration engine)
  pcall(function()
    if chronos and chronos.setup then
      chronos.setup { keymaps = "<leader>C" }
    end
  end)

  -- Run health check
  M.health()

  -- ========================================================================
  -- USER COMMANDS
  -- ========================================================================
  
  -- Core GTD
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
  end, { desc = "Pick task with fzf and run GTD clarification" })

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

  -- Lists (shortcuts - main definitions in lists.lua)
  vim.api.nvim_create_user_command("GtdNext", function()
    M.list_next()
  end, { desc = "Show NEXT actions" })

  -- Calendar (Kairos)
  vim.api.nvim_create_user_command("GtdAgenda", function(opts)
    M.agenda(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Show agenda (calendar + scheduled tasks)" })

  vim.api.nvim_create_user_command("GtdFreeSlots", function()
    M.free_slots()
  end, { desc = "Show free time slots" })

  -- Utilities
  vim.api.nvim_create_user_command("GtdHealth", function()
    M.health()
  end, { desc = "Check GTD system health" })
  
  vim.api.nvim_create_user_command("GtdVersion", function()
    M.version()
  end, { desc = "Show GTD-Nvim version information" })
  
  vim.api.nvim_create_user_command("GtdFindDuplicates", function()
    M.find_duplicates()
  end, { desc = "Find duplicate TASK_IDs" })

  -- Weekly Review (main definitions in review.lua)
  -- Commands: GtdReview, GtdReviewResume, GtdReviewHistory, GtdReviewChecklists

  -- Status changes
  vim.api.nvim_create_user_command("GtdStatus", function()
    M.change_status()
  end, { desc = "Change task status with fzf picker" })

  vim.api.nvim_create_user_command("GtdCycleStatus", function(opts)
    local dir = opts.args == "prev" and -1 or 1
    M.cycle_status(dir)
  end, { nargs = "?", desc = "Cycle task status (next/prev)" })

  -- Areas
  vim.api.nvim_create_user_command("GtdAreas", function()
    M.browse_areas()
  end, { desc = "Browse Areas of Responsibility" })
end

return M
