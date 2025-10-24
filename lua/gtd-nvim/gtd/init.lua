-- ~/.config/nvim/lua/gtd/init.lua
-- GTD glue: capture / clarify / organize / projects / manage / lists (no keymaps here)

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
  return vim.fn.filereadable(p) == 1 and vim.fn.readfile(p) or {}
end
local function writef(p, L)
  ensure_dir(p)
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
local clarifyM = safe_require "gtd.clarify"
local organize = safe_require "gtd.organize"
local projects = safe_require "gtd.projects"
local manage = safe_require "gtd.manage"
local lists = safe_require "gtd.lists"

-- ------------------------ Health ------------------------
function M.health()
  local issues = {}

  if not task_id then
    table.insert(issues, "Missing gtd.utils.task_id")
  end
  if not capture then
    table.insert(issues, "Missing gtd.capture")
  end
  if not clarifyM then
    table.insert(issues, "Missing gtd.clarify")
  end
  if not organize then
    table.insert(issues, "Missing gtd.organize")
  end
  if not projects then
    table.insert(issues, "Missing gtd.projects")
  end
  if not manage then
    table.insert(issues, "Missing gtd.manage")
  end
  if not lists then
    table.insert(issues, "Missing gtd.lists")
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

  if #issues == 0 then
    vim.notify("GTD health: OK", vim.log.levels.INFO)
  else
    for _, e in ipairs(issues) do
      vim.notify("GTD health: " .. e, vim.log.levels.WARN)
    end
  end
  return issues
end

-- ------------------------ Public API ------------------------
function M.capture(opts)
  if capture and capture.capture_quick then
    return capture.capture_quick(opts or {})
  end
  vim.notify("gtd.capture not available", vim.log.levels.WARN)
end

-- Clarify on current heading (promote-if-needed behavior lives in clarify.lua).
function M.clarify(opts)
  if clarifyM and clarifyM.at_cursor then
    return clarifyM.at_cursor(opts or {})
  end
  vim.notify("gtd.clarify not available", vim.log.levels.WARN)
end

-- Clarify: pick any task in GTD (fzf) then run same flow at that task.
function M.clarify_pick_any(opts)
  opts = opts or {}
  local ok_fzf, fzf = pcall(require, "fzf-lua")
  if not ok_fzf then
    vim.notify("fzf-lua not available for task picker", vim.log.levels.WARN)
    return
  end

  local root = xp(M.cfg.gtd_root)
  local files = vim.fn.globpath(root, "**/*.org", false, true)
  table.sort(files)

  local items, meta = {}, {}
  for _, path in ipairs(files) do
    local lines = readf(path)
    for i, line in ipairs(lines) do
      if line:match "^%*+%s+" then
        local display = ("%s:%d: %s"):format(vim.fn.fnamemodify(path, ":."), i, line)
        table.insert(items, display)
        table.insert(meta, { path = path, lnum = i })
      end
    end
  end

  if #items == 0 then
    vim.notify("No org headings found under " .. root, vim.log.levels.WARN)
    return
  end

  fzf.fzf_exec(items, {
    prompt = "Clarify task> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    winopts = { height = 0.55, width = 0.85, row = 0.08 },
    actions = {
      ["default"] = function(sel)
        local choice = sel and sel[1]
        if not choice then
          return
        end
        local idx = vim.fn.index(items, choice) + 1
        local m = meta[idx]
        if not m then
          return
        end
        vim.cmd("edit " .. m.path)
        vim.api.nvim_win_set_cursor(0, { m.lnum, 0 })
        if clarifyM and clarifyM.at_cursor then
          clarifyM.at_cursor(opts)
        end
      end,
    },
  })
end

function M.refile_to_project(opts)
  if organize and organize.refile_at_cursor then
    return organize.refile_at_cursor(opts or {})
  end
  vim.notify("gtd.organize not available", vim.log.levels.WARN)
end

function M.project_new(opts)
  if projects and projects.create then
    return projects.create(opts or {})
  end
  if projects and projects.new_project then
    return projects.new_project(opts or {})
  end
  vim.notify("gtd.projects not available", vim.log.levels.WARN)
end

function M.link_task_to_project(opts)
  if projects and projects.link_task_to_project_at_cursor then
    return projects.link_task_to_project_at_cursor(opts or {})
  end
  vim.notify("gtd.projects link helper not available", vim.log.levels.WARN)
end

-- Lists API wrappers
function M.next_actions()
  if lists and lists.next_actions then
    return lists.next_actions()
  end
  vim.notify("gtd.lists not available", vim.log.levels.WARN)
end

function M.projects_list()
  if lists and lists.projects then
    return lists.projects()
  end
  vim.notify("gtd.lists not available", vim.log.levels.WARN)
end

function M.waiting_list()
  if lists and lists.waiting then
    return lists.waiting()
  end
  vim.notify("gtd.lists not available", vim.log.levels.WARN)
end

function M.someday_maybe()
  if lists and lists.someday_maybe then
    return lists.someday_maybe()
  end
  vim.notify("gtd.lists not available", vim.log.levels.WARN)
end

function M.lists_menu()
  if lists and lists.menu then
    return lists.menu()
  end
  vim.notify("gtd.lists not available", vim.log.levels.WARN)
end

-- ------------------------ Setup & Commands ------------------------
function M.setup(user_cfg)
  if user_cfg then
    for k, v in pairs(user_cfg) do
      M.cfg[k] = v
    end
  end

  -- Pass cfg to submodules that support setup
  pcall(function()
    if clarifyM and clarifyM.setup then
      clarifyM.setup {
        gtd_root = M.cfg.gtd_root,
        inbox_file = M.cfg.inbox_file,
        projects_dir = M.cfg.projects_dir,
      }
    end
  end)

  pcall(function()
    if projects and projects.setup then
      projects.setup {
        gtd_root = M.cfg.gtd_root,
        projects_dir = M.cfg.projects_dir,
        zk_root = M.cfg.zk_root,
      }
    end
  end)

  pcall(function()
    if manage and manage.setup then
      manage.setup {
        gtd_root = M.cfg.gtd_root,
        projects_dir = M.cfg.projects_dir,
        zk_root = M.cfg.zk_root,
      }
    end
  end)

  -- Setup lists module (this is what was missing!)
  pcall(function()
    if lists and lists.setup then
      lists.setup {
        gtd_root = M.cfg.gtd_root,
        inbox_file = M.cfg.inbox_file,
        projects_dir = M.cfg.projects_dir,
        archive_file = "Archive.org",
        zk_root = M.cfg.zk_root,
      }
    end
  end)

  M.health()

  -- Core GTD
  vim.api.nvim_create_user_command("GtdCapture", function()
    M.capture {}
  end, {})
  vim.api.nvim_create_user_command("GtdClarify", function(o)
    M.clarify { status = (o.args ~= "" and o.args or nil) }
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("GtdClarifyPick", function()
    M.clarify_pick_any {}
  end, {})
  vim.api.nvim_create_user_command("GtdRefile", function()
    M.refile_to_project {}
  end, {})
  vim.api.nvim_create_user_command("GtdProjectNew", function()
    M.project_new {}
  end, {})
  vim.api.nvim_create_user_command("GtdLinkToProject", function()
    M.link_task_to_project {}
  end, {})
  vim.api.nvim_create_user_command("GtdHealth", function()
    M.health()
  end, {})

  -- Lists (note: these will also be created by lists.setup(), but we can add convenience aliases here)
  vim.api.nvim_create_user_command("GtdLists", function()
    M.lists_menu()
  end, {})

  -- Manager (tasks/projects archive/delete & ZK handling)
  if manage then
    vim.api.nvim_create_user_command("GtdManage", function()
      manage.help_menu()
    end, {})
    vim.api.nvim_create_user_command("GtdManageTasks", function()
      manage.manage_tasks()
    end, {})
    vim.api.nvim_create_user_command("GtdManageProjects", function()
      manage.manage_projects()
    end, {})
    vim.api.nvim_create_user_command("GtdArchiveTask", function()
      manage.archive_task_at_cursor {}
    end, {})
    vim.api.nvim_create_user_command("GtdDeleteTask", function()
      manage.delete_task_at_cursor {}
    end, {})
  end
end

-- In ~/.config/nvim/lua/gtd/init.lua
local reminders = safe_require "gtd.reminders"

-- Add to your setup function:
function M.setup(user_cfg)
  -- ... existing setup code ...

  -- Setup reminders integration
  pcall(function()
    if reminders and reminders.setup then
      reminders.setup {
        gtd_root = M.cfg.gtd_root,
        inbox_file = M.cfg.inbox_file,
        projects_dir = M.cfg.projects_dir,
      }
    end
  end)

  -- Add commands
  vim.api.nvim_create_user_command("GtdImportReminders", function()
    if reminders then
      reminders.import_all()
    end
  end, {})
  vim.api.nvim_create_user_command("GtdImportRemindersList", function()
    if reminders then
      reminders.import_from_list()
    end
  end, {})
end

return M
