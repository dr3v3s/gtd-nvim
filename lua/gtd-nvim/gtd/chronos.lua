-- ============================================================================
-- GTD-NVIM CHRONOS INTEGRATION
-- ============================================================================
-- Integration with Chronos daemon for GTD orchestration, metrics, and sync
-- Provides real-time task data, search, and Apple Reminders bidirectional sync
--
-- @module gtd-nvim.gtd.chronos
-- @version 0.1.0
-- @updated 2025-12-19
-- @see ~/Developer/chronos (daemon source)
-- ============================================================================

local M = {}

M._VERSION = "0.4.0"
M._UPDATED = "2025-12-20"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.config = {
  socket_path = vim.fn.expand("~/.cache/chronos/chronos.sock"),
  cache_dir = vim.fn.expand("~/.cache/chronos"),
  socket_timeout_ms = 1000,
  debug = false,
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function log(msg)
  if M.config.debug then
    vim.notify("[chronos] " .. msg, vim.log.levels.DEBUG)
  end
end

local function file_exists(path)
  return vim.fn.filereadable(path) == 1
end

-- ============================================================================
-- DAEMON STATUS
-- ============================================================================

--- Check if Chronos daemon socket exists
---@return boolean
function M.is_available()
  return file_exists(M.config.socket_path)
end

--- Check if daemon is running
---@return boolean, string|nil
function M.is_running()
  if not M.is_available() then
    return false, "Socket not found"
  end
  
  -- Try a ping to verify it's responsive
  local data, err = M.query(nil, "ping", nil)
  if data then
    return true, nil
  end
  return false, err or "Daemon not responding"
end

-- ============================================================================
-- SOCKET COMMUNICATION
-- ============================================================================

--- Send query to Chronos daemon via Unix socket
---@param module string|nil Provider name (gtd, reminders) or nil for core
---@param cmd string Command to execute
---@param params table|nil Optional parameters
---@return table|nil, string|nil Response data or nil, error message
function M.query(module, cmd, params)
  if not M.is_available() then
    return nil, "Chronos daemon not available"
  end
  
  local request = { cmd = cmd }
  if module then
    request.module = module
  end
  if params and next(params) then
    request.params = params
  end
  
  local json_request = vim.fn.json_encode(request)
  
  local nc_cmd = string.format(
    'echo \'%s\' | nc -U %s 2>/dev/null',
    json_request:gsub("'", "\\'"),
    M.config.socket_path
  )
  
  log("Query: " .. json_request)
  
  local handle = io.popen(nc_cmd)
  if not handle then
    return nil, "Failed to connect to socket"
  end
  
  local response = handle:read("*a")
  handle:close()
  
  if not response or response == "" then
    return nil, "Empty response from daemon"
  end
  
  log("Response: " .. response:sub(1, 200))
  
  local decode_ok, data = pcall(vim.fn.json_decode, response)
  if not decode_ok or not data then
    return nil, "Failed to parse response"
  end
  
  if data.success == false then
    return nil, data.error or "Query failed"
  end
  
  return data.data, nil
end

-- ============================================================================
-- GTD METRICS
-- ============================================================================

--- Get GTD task counts
---@return table|nil {next=n, todo=n, waiting=n, total=n}
function M.metrics()
  local data, err = M.query("gtd", "metrics", nil)
  if not data then
    log("Metrics error: " .. (err or "unknown"))
    return nil
  end
  return data
end

--- Format metrics for status line
---@return string
function M.statusline()
  local m = M.metrics()
  if not m then
    return "󰀦"  -- Error icon
  end
  
  local parts = {}
  if m.next and m.next > 0 then
    table.insert(parts, string.format("󰁔 %d", m.next))
  end
  if m.todo and m.todo > 0 then
    table.insert(parts, string.format("󰄲 %d", m.todo))
  end
  if m.waiting and m.waiting > 0 then
    table.insert(parts, string.format("󰈸 %d", m.waiting))
  end
  
  if #parts == 0 then
    return "󰄳"  -- All done
  end
  
  return table.concat(parts, " ")
end

-- ============================================================================
-- TASK QUERIES
-- ============================================================================

--- Query tasks by state
---@param state string TODO keyword (NEXT, TODO, WAITING, etc.)
---@param limit number|nil Max results (default 50)
---@return table[] Array of task objects
function M.tasks(state, limit)
  local data, err = M.query("gtd", "tasks", {
    state = state,
    limit = limit or 50,
  })
  if not data then
    log("Tasks error: " .. (err or "unknown"))
    return {}
  end
  return data or {}
end

--- Get all NEXT actions
---@return table[]
function M.next_actions()
  return M.tasks("NEXT", 100)
end

--- Get all TODO tasks
---@return table[]
function M.todos()
  return M.tasks("TODO", 100)
end

--- Get all WAITING tasks
---@return table[]
function M.waiting()
  return M.tasks("WAITING", 100)
end

--- Full-text search tasks
---@param query string Search query
---@param limit number|nil Max results
---@return table[]
function M.search(query, limit)
  local data, err = M.query("gtd", "search", {
    query = query,
    limit = limit or 20,
  })
  if not data then
    log("Search error: " .. (err or "unknown"))
    return {}
  end
  return data or {}
end

-- ============================================================================
-- REMINDERS SYNC
-- ============================================================================

--- Get reminders sync status
---@return table|nil
function M.reminders_status()
  local data, err = M.query("reminders", "status", nil)
  if not data then
    log("Reminders status error: " .. (err or "unknown"))
    return nil
  end
  return data
end

--- Get available reminder lists
---@return string[]
function M.reminders_lists()
  local data, err = M.query("reminders", "lists", nil)
  if not data then
    log("Reminders lists error: " .. (err or "unknown"))
    return {}
  end
  return data or {}
end

--- Trigger manual reminders sync
---@return table|nil Sync result with counts
function M.reminders_sync()
  local data, err = M.query("reminders", "sync", nil)
  if not data then
    log("Reminders sync error: " .. (err or "unknown"))
    return nil
  end
  return data
end

--- Get reminders from a specific list
---@param list_name string|nil List name (nil for configured sync list)
---@param include_completed boolean|nil Include completed reminders
---@return table[]
function M.reminders(list_name, include_completed)
  local params = {}
  if list_name then
    params.list = list_name
  end
  if include_completed then
    params.include_completed = true
  end
  
  local data, err = M.query("reminders", "reminders", params)
  if not data then
    log("Reminders error: " .. (err or "unknown"))
    return {}
  end
  
  -- Extract reminders array from nested response
  if data.data and data.data.reminders then
    return data.data.reminders
  end
  return {}
end

-- ============================================================================
-- FZF-LUA INTEGRATION
-- ============================================================================

--- Format task for fzf display
---@param task table Task object
---@return string
local function format_task_for_fzf(task)
  local icon = "󰄲"
  local state = task.state or "TODO"
  if state == "NEXT" then icon = "󰁔"
  elseif state == "WAITING" then icon = "󰈸"
  elseif state == "SOMEDAY" then icon = "󰋚"
  elseif state == "DONE" then icon = "󰄳"
  end
  
  local title = task.title or "Untitled"
  local file = vim.fn.fnamemodify(task.file or "", ":t:r")
  
  return string.format("%s %s  %s", icon, title, file)
end

--- Open fzf picker for tasks
---@param opts table Options: state, title
function M.pick_tasks(opts)
  opts = opts or {}
  local state = opts.state
  local title = opts.title or (state and (state .. " Tasks") or "All Tasks")
  
  local tasks = state and M.tasks(state, 100) or M.tasks(nil, 100)
  
  if #tasks == 0 then
    vim.notify("No tasks found", vim.log.levels.INFO)
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local items = {}
  local task_map = {}
  
  for i, task in ipairs(tasks) do
    local display = format_task_for_fzf(task)
    items[i] = display
    task_map[display] = task
  end
  
  fzf.fzf_exec(items, {
    prompt = title .. " ❯ ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local task = task_map[selected[1]]
          if task and task.file then
            vim.cmd("edit " .. vim.fn.fnameescape(task.file))
            if task.line then
              vim.api.nvim_win_set_cursor(0, {task.line, 0})
              vim.cmd("normal! zz")
            end
          end
        end
      end,
    },
    winopts = {
      height = 0.6,
      width = 0.8,
    },
  })
end

--- Search tasks with fzf
---@param initial_query string|nil Initial search query
function M.pick_search(initial_query)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  fzf.fzf_exec(function(fzf_cb)
    -- This gets called on each keystroke
    -- We'll use fzf's live query feature instead
    fzf_cb()
  end, {
    prompt = "Search Tasks ❯ ",
    query = initial_query or "",
    fn_transform = function(x) return x end,
    actions = {
      ["default"] = function(selected, opts)
        local query = opts.last_query or ""
        if query == "" then return end
        
        local results = M.search(query, 50)
        if #results == 0 then
          vim.notify("No results for: " .. query, vim.log.levels.INFO)
          return
        end
        
        -- Show results in new picker
        local items = {}
        local task_map = {}
        for _, task in ipairs(results) do
          local display = format_task_for_fzf(task)
          table.insert(items, display)
          task_map[display] = task
        end
        
        fzf.fzf_exec(items, {
          prompt = "Results ❯ ",
          actions = {
            ["default"] = function(sel)
              if sel and sel[1] then
                local task = task_map[sel[1]]
                if task and task.file then
                  vim.cmd("edit " .. vim.fn.fnameescape(task.file))
                  if task.line then
                    vim.api.nvim_win_set_cursor(0, {task.line, 0})
                  end
                end
              end
            end,
          },
        })
      end,
    },
  })
end

-- ============================================================================
-- COMMANDS & KEYMAPS
-- ============================================================================

--- Setup user commands
function M.setup_commands()
  vim.api.nvim_create_user_command("ChronosStatus", function()
    local running, err = M.is_running()
    if running then
      local m = M.metrics()
      if m then
        vim.notify(string.format(
          "Chronos: 󰁔 %d NEXT  󰄲 %d TODO  󰈸 %d WAITING",
          m.next or 0, m.todo or 0, m.waiting or 0
        ), vim.log.levels.INFO)
      else
        vim.notify("Chronos: Running (metrics unavailable)", vim.log.levels.INFO)
      end
    else
      vim.notify("Chronos: Not running - " .. (err or ""), vim.log.levels.WARN)
    end
  end, { desc = "Show Chronos daemon status" })
  
  vim.api.nvim_create_user_command("ChronosNext", function()
    M.pick_tasks({ state = "NEXT", title = "NEXT Actions" })
  end, { desc = "Pick NEXT actions via Chronos" })
  
  vim.api.nvim_create_user_command("ChronosTodo", function()
    M.pick_tasks({ state = "TODO", title = "TODO Tasks" })
  end, { desc = "Pick TODO tasks via Chronos" })
  
  vim.api.nvim_create_user_command("ChronosWaiting", function()
    M.pick_tasks({ state = "WAITING", title = "WAITING Tasks" })
  end, { desc = "Pick WAITING tasks via Chronos" })
  
  vim.api.nvim_create_user_command("ChronosSearch", function(opts)
    M.pick_search(opts.args ~= "" and opts.args or nil)
  end, { desc = "Search tasks via Chronos", nargs = "?" })
  
  vim.api.nvim_create_user_command("ChronosRemindersSync", function()
    local result = M.reminders_sync()
    if result then
      vim.notify(string.format(
        "Reminders sync: %d created, %d updated (%s)",
        result.inbound_created or 0,
        result.outbound_updated or 0,
        result.duration or "?"
      ), vim.log.levels.INFO)
    else
      vim.notify("Reminders sync failed", vim.log.levels.ERROR)
    end
  end, { desc = "Trigger Reminders sync" })
  
  -- Capture commands
  vim.api.nvim_create_user_command("ChronosQuick", function(opts)
    M.capture_quick(opts.args ~= "" and opts.args or nil)
  end, { desc = "Quick capture to inbox", nargs = "?" })
  
  vim.api.nvim_create_user_command("ChronosCapture", function()
    M.capture_task()
  end, { desc = "Full task capture wizard" })
  
  vim.api.nvim_create_user_command("ChronosProject", function()
    M.create_project()
  end, { desc = "Create new project" })
end

--- Setup keymaps (optional, call separately)
---@param prefix string|nil Keymap prefix (default: <leader>x)
function M.setup_keymaps(prefix)
  prefix = prefix or "<leader>x"
  local map = vim.keymap.set
  local opts = { silent = true }
  
  map("n", prefix .. "s", "<cmd>ChronosStatus<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos status" }))
  map("n", prefix .. "n", "<cmd>ChronosNext<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos NEXT actions" }))
  map("n", prefix .. "t", "<cmd>ChronosTodo<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos TODO tasks" }))
  map("n", prefix .. "w", "<cmd>ChronosWaiting<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos WAITING tasks" }))
  map("n", prefix .. "/", "<cmd>ChronosSearch<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos search" }))
  map("n", prefix .. "r", "<cmd>ChronosRemindersSync<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos reminders sync" }))
  
  -- Capture keymaps
  map("n", prefix .. "q", "<cmd>ChronosQuick<cr>",
    vim.tbl_extend("force", opts, { desc = "Quick capture to inbox" }))
  map("n", prefix .. "c", "<cmd>ChronosCapture<cr>",
    vim.tbl_extend("force", opts, { desc = "Full task capture" }))
  map("n", prefix .. "p", "<cmd>ChronosProject<cr>",
    vim.tbl_extend("force", opts, { desc = "Create project" }))
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Initialize Chronos integration
---@param opts table|nil Configuration overrides
---  opts.keymaps = true|string  Enable keymaps (true = default prefix, string = custom prefix)
function M.setup(opts)
  opts = opts or {}
  
  -- Apply config overrides
  for k, v in pairs(opts) do
    if k ~= "keymaps" and M.config[k] ~= nil then
      M.config[k] = v
    end
  end
  
  M.setup_commands()
  
  -- Setup keymaps if requested
  if opts.keymaps then
    local prefix = type(opts.keymaps) == "string" and opts.keymaps or nil
    M.setup_keymaps(prefix)
  end
  
  log("Chronos integration initialized")
  
  -- Check daemon on setup
  if M.is_available() then
    local running = M.is_running()
    if running then
      log("Daemon running")
    else
      log("Daemon socket exists but not responding")
    end
  else
    log("Daemon not available")
  end
end

-- ============================================================================
-- CAPTURE SYSTEM
-- ============================================================================
-- 1. Quick capture → Inbox dump (one prompt)
-- 2. Full task capture → Wizard with all GTD options
-- 3. Project creation → New project file with structure

local capture_glyphs = {
  inbox = "󰇮",
  project = "󰷐",
  next = "󰁔",
  todo = "󰄲",
  waiting = "󰈸",
  someday = "󰋚",
  calendar = "󰃭",
  area = "󰀼",
}

-- Helpers
local function generate_task_id()
  return os.date("%Y%m%d%H%M%S")
end

local function format_inactive_timestamp()
  return os.date("[%Y-%m-%d %a %H:%M]")
end

local function format_active_date(date_str)
  if date_str then
    local y, m, d = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y then
      local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
      return os.date("<%Y-%m-%d %a>", t)
    end
  end
  return os.date("<%Y-%m-%d %a>")
end

local function future_date(days, from_date)
  local base_time
  if from_date and from_date:match("^%d%d%d%d%-%d%d%-%d%d$") then
    local y, m, d = from_date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    base_time = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
  else
    base_time = os.time()
  end
  return os.date("%Y-%m-%d", base_time + (days * 24 * 60 * 60))
end

--- Parse smart date input: +1d, +2w, +3m, 25, 12-25, 2025-12-25
local function parse_smart_date(input, base_date)
  if not input or input == "" then return nil end
  input = input:gsub("^%s+", ""):gsub("%s+$", "")
  if input == "" then return nil end
  
  local base_time
  if base_date and base_date:match("^%d%d%d%d%-%d%d%-%d%d$") then
    local y, m, d = base_date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    base_time = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
  else
    base_time = os.time()
  end
  local base = os.date("*t", base_time)
  
  -- Full date YYYY-MM-DD
  if input:match("^%d%d%d%d%-%d%d%-%d%d$") then return input end
  
  -- Relative days +Nd or +N
  local rel_days = input:match("^%+(%d+)d?$")
  if rel_days then
    return os.date("%Y-%m-%d", base_time + (tonumber(rel_days) * 86400))
  end
  
  -- Relative weeks +Nw
  local rel_weeks = input:match("^%+(%d+)w$")
  if rel_weeks then
    return os.date("%Y-%m-%d", base_time + (tonumber(rel_weeks) * 7 * 86400))
  end
  
  -- Relative months +Nm
  local rel_months = input:match("^%+(%d+)m$")
  if rel_months then
    local months = tonumber(rel_months)
    local new_month = base.month + months
    local new_year = base.year
    while new_month > 12 do
      new_month = new_month - 12
      new_year = new_year + 1
    end
    local max_day = ({ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[new_month]
    if new_month == 2 and ((new_year % 4 == 0 and new_year % 100 ~= 0) or (new_year % 400 == 0)) then
      max_day = 29
    end
    return string.format("%04d-%02d-%02d", new_year, new_month, math.min(base.day, max_day))
  end
  
  -- Month-day MM-DD
  local mm, dd = input:match("^(%d%d?)%-(%d%d?)$")
  if mm and dd then
    local month, day = tonumber(mm), tonumber(dd)
    if month >= 1 and month <= 12 and day >= 1 and day <= 31 then
      return string.format("%04d-%02d-%02d", base.year, month, day)
    end
  end
  
  -- Day only D or DD
  local day_only = input:match("^(%d%d?)$")
  if day_only then
    local day = tonumber(day_only)
    if day >= 1 and day <= 31 then
      return string.format("%04d-%02d-%02d", base.year, base.month, day)
    end
  end
  
  return nil
end

local DATE_HINT = "+1d, +2w, +3m, 25, 12-25"
local DEFAULT_DUE_DAYS = 3  -- DUE = DEFER + 3 days

local function gtd_home()
  local ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  return (ok and shared.gtd_home) and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
end

local function inbox_path()
  return gtd_home() .. "/Inbox.org"
end

local function ensure_file(path, title)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({ "#+TITLE: " .. title, "" }, path)
  end
end

local function slugify(title)
  local s = title:lower()
  s = s:gsub("[æ]", "ae"):gsub("[ø]", "oe"):gsub("[å]", "aa")
  s = s:gsub("[^%w%s-]", ""):gsub("%s+", "-"):gsub("%-+", "-")
  return s:gsub("^%-", ""):gsub("%-$", "")
end

local function append_to_file(path, lines)
  local f = io.open(path, "a")
  if not f then return false end
  f:write("\n" .. table.concat(lines, "\n") .. "\n")
  f:close()
  return true
end

local function write_file(path, lines)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
  return true
end

--- Build GTD-SPEC compliant task entry
local function build_task_entry(opts)
  local lines = {}
  local id = opts.task_id or generate_task_id()
  local stars = string.rep("*", opts.level or 1)
  
  -- Heading
  local heading = string.format("%s %s %s", stars, opts.state or "TODO", opts.title)
  if opts.tags and #opts.tags > 0 then
    heading = heading .. "  :" .. table.concat(opts.tags, ":") .. ":"
  end
  table.insert(lines, heading)
  
  -- Dates (before PROPERTIES per GTD-SPEC)
  if opts.scheduled then
    table.insert(lines, "SCHEDULED: " .. format_active_date(opts.scheduled))
  end
  if opts.deadline then
    table.insert(lines, "DEADLINE: " .. format_active_date(opts.deadline))
  end
  
  -- PROPERTIES
  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":TASK_ID:   " .. id)
  table.insert(lines, ":ID:        " .. id)
  table.insert(lines, ":ZK_LINK:   [[zk:" .. id .. "]]")
  table.insert(lines, ":CREATED:   " .. format_inactive_timestamp())
  if opts.area then table.insert(lines, ":AREA:      " .. opts.area) end
  if opts.effort then table.insert(lines, ":Effort:    " .. opts.effort) end
  if opts.state == "WAITING" then
    if opts.waiting_for then table.insert(lines, ":WAITING_FOR: " .. opts.waiting_for) end
    table.insert(lines, ":WAITING_SINCE: " .. format_inactive_timestamp())
  end
  table.insert(lines, ":END:")
  
  return lines, id
end

--- Build GTD-SPEC compliant project entry
local function build_project_entry(opts)
  local lines = {}
  local id = opts.task_id or generate_task_id()
  
  local heading = "* PROJECT " .. opts.title
  if opts.tags and #opts.tags > 0 then
    heading = heading .. "  :" .. table.concat(opts.tags, ":") .. ":"
  end
  table.insert(lines, heading)
  
  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":ID:        " .. id)
  table.insert(lines, ":TASK_ID:   " .. id)
  table.insert(lines, ":ZK_LINK:   [[zk:" .. id .. "]]")
  table.insert(lines, ":CREATED:   " .. format_inactive_timestamp())
  if opts.description then table.insert(lines, ":DESCRIPTION: " .. opts.description) end
  if opts.area then table.insert(lines, ":AREA:      " .. opts.area) end
  table.insert(lines, ":END:")
  
  if opts.outcome then
    table.insert(lines, "")
    table.insert(lines, "** Outcome")
    table.insert(lines, opts.outcome)
  end
  
  return lines, id
end

--- Get all project files for picker
local function get_projects()
  local projects = {}
  local root = gtd_home()
  
  -- Standalone projects
  local pdir = root .. "/Projects"
  if vim.fn.isdirectory(pdir) == 1 then
    for _, f in ipairs(vim.fn.glob(pdir .. "/*.org", false, true)) do
      local name = vim.fn.fnamemodify(f, ":t:r")
      table.insert(projects, { name = name, path = f, display = capture_glyphs.project .. " " .. name })
    end
  end
  
  -- Area projects
  local adir = root .. "/Areas"
  if vim.fn.isdirectory(adir) == 1 then
    for _, ap in ipairs(vim.fn.glob(adir .. "/*", false, true)) do
      if vim.fn.isdirectory(ap) == 1 then
        local aname = vim.fn.fnamemodify(ap, ":t")
        for _, f in ipairs(vim.fn.glob(ap .. "/*.org", false, true)) do
          local name = vim.fn.fnamemodify(f, ":t:r")
          table.insert(projects, {
            name = name, path = f, area = aname,
            display = capture_glyphs.area .. " " .. aname .. "/" .. name
          })
        end
      end
    end
  end
  
  return projects
end

--- Get areas
local function get_areas()
  local areas = {}
  local adir = gtd_home() .. "/Areas"
  if vim.fn.isdirectory(adir) == 1 then
    for _, p in ipairs(vim.fn.glob(adir .. "/*", false, true)) do
      if vim.fn.isdirectory(p) == 1 then
        table.insert(areas, { name = vim.fn.fnamemodify(p, ":t"), path = p })
      end
    end
  end
  return areas
end

-- ============================================================================
-- 1. QUICK CAPTURE (Inbox dump)
-- ============================================================================

--- Quick capture - one prompt, straight to Inbox as TODO
---@param title string|nil Pre-filled title
function M.capture_quick(title)
  local do_capture = function(t)
    if not t or t == "" then return end
    
    local lines = build_task_entry({ title = t, state = "TODO", level = 1 })
    ensure_file(inbox_path(), "Inbox")
    
    if append_to_file(inbox_path(), lines) then
      vim.notify(capture_glyphs.inbox .. " " .. t, vim.log.levels.INFO)
    else
      vim.notify("Capture failed", vim.log.levels.ERROR)
    end
  end
  
  if title then
    do_capture(title)
  else
    vim.ui.input({ prompt = capture_glyphs.inbox .. " Capture: " }, do_capture)
  end
end

-- ============================================================================
-- 2. FULL TASK CAPTURE (Wizard)
-- ============================================================================

--- Full task capture wizard
--- Flow: Title → State → Destination → Schedule → (Extras) → Create
function M.capture_task()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local data = {}
  
  -- Step 1: Title
  vim.ui.input({ prompt = capture_glyphs.todo .. " Task: " }, function(title)
    if not title or title == "" then return end
    data.title = title
    
    -- Step 2: State
    vim.schedule(function()
      fzf.fzf_exec({
        capture_glyphs.next .. " NEXT  (ready to do)",
        capture_glyphs.todo .. " TODO  (not yet ready)",
        capture_glyphs.waiting .. " WAITING (delegated/blocked)",
        capture_glyphs.someday .. " SOMEDAY (maybe later)",
      }, {
        prompt = "State ❯ ",
        winopts = { height = 0.3, width = 0.4 },
        actions = {
          ["default"] = function(sel)
            if not sel or not sel[1] then return end
            data.state = sel[1]:match("(%u+)%s") or "TODO"
            vim.schedule(function() M._task_step_dest(data) end)
          end,
        },
      })
    end)
  end)
end

--- Task wizard: Destination step
function M._task_step_dest(data)
  local fzf = require("fzf-lua")
  
  fzf.fzf_exec({
    capture_glyphs.inbox .. " Inbox (review later)",
    capture_glyphs.project .. " Project...",
  }, {
    prompt = "To ❯ ",
    winopts = { height = 0.25, width = 0.35 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        
        if sel[1]:match("Project") then
          vim.schedule(function()
            local projects = get_projects()
            if #projects == 0 then
              vim.notify("No projects found", vim.log.levels.WARN)
              data.path, data.level = inbox_path(), 1
              vim.schedule(function() M._task_step_schedule(data) end)
              return
            end
            
            local items = {}
            for _, p in ipairs(projects) do table.insert(items, p.display) end
            
            fzf.fzf_exec(items, {
              prompt = "Project ❯ ",
              winopts = { height = 0.5, width = 0.5 },
              actions = {
                ["default"] = function(proj)
                  if proj and proj[1] then
                    for _, p in ipairs(projects) do
                      if p.display == proj[1] then
                        data.path, data.level, data.area = p.path, 2, p.area
                        break
                      end
                    end
                  else
                    data.path, data.level = inbox_path(), 1
                  end
                  vim.schedule(function() M._task_step_schedule(data) end)
                end,
              },
            })
          end)
        else
          data.path, data.level = inbox_path(), 1
          vim.schedule(function() M._task_step_schedule(data) end)
        end
      end,
    },
  })
end

--- Task wizard: Schedule step (DEFER and DUE dates)
function M._task_step_schedule(data)
  local today = os.date("%Y-%m-%d")
  
  if data.state == "WAITING" then
    -- WAITING: Ask for follow-up date and who/what we're waiting for
    vim.ui.input({ prompt = "Waiting for (person/thing): " }, function(wf)
      if not wf or wf == "" then
        vim.schedule(function() M._task_finalize(data) end)
        return
      end
      data.waiting_for = wf
      
      vim.schedule(function()
        local follow_default = future_date(7)  -- 1 week follow-up
        vim.ui.input({
          prompt = string.format("Follow-up [%s] (%s): ", follow_default, DATE_HINT)
        }, function(f)
          local follow_up = parse_smart_date(f) or follow_default
          data.scheduled = follow_up
          
          -- DUE date
          vim.schedule(function()
            local due_default = future_date(DEFAULT_DUE_DAYS, follow_up)
            vim.ui.input({
              prompt = string.format("Due [%s] (%s): ", due_default, DATE_HINT)
            }, function(d)
              data.deadline = parse_smart_date(d, follow_up) or due_default
              M._task_finalize(data)
            end)
          end)
        end)
      end)
    end)
  elseif data.state == "SOMEDAY" then
    -- SOMEDAY: No dates needed
    vim.schedule(function() M._task_finalize(data) end)
  else
    -- NEXT/TODO: Ask for DEFER and DUE
    vim.ui.input({
      prompt = string.format("Defer [%s] (%s): ", today, DATE_HINT)
    }, function(s)
      local defer_date = parse_smart_date(s) or today
      data.scheduled = defer_date
      
      vim.schedule(function()
        local due_default = future_date(DEFAULT_DUE_DAYS, defer_date)
        vim.ui.input({
          prompt = string.format("Due [%s] (%s): ", due_default, DATE_HINT)
        }, function(d)
          if d and d ~= "" then
            data.deadline = parse_smart_date(d, defer_date) or due_default
          end
          -- DUE is optional - empty means no deadline
          M._task_finalize(data)
        end)
      end)
    end)
  end
end

--- Task wizard: Create task
function M._task_finalize(data)
  local lines = build_task_entry({
    title = data.title,
    state = data.state,
    level = data.level or 1,
    scheduled = data.scheduled,
    deadline = data.deadline,
    area = data.area,
    waiting_for = data.waiting_for,
  })
  
  local target = data.path or inbox_path()
  ensure_file(target, vim.fn.fnamemodify(target, ":t:r"))
  
  if append_to_file(target, lines) then
    local icon = capture_glyphs[data.state:lower()] or capture_glyphs.todo
    local dest = vim.fn.fnamemodify(target, ":t:r")
    vim.notify(string.format("%s %s → %s", icon, data.title, dest), vim.log.levels.INFO)
    
    if M.is_running() then M.query("gtd", "refresh", nil) end
  else
    vim.notify("Capture failed", vim.log.levels.ERROR)
  end
end

-- ============================================================================
-- 3. PROJECT CREATION
-- ============================================================================

--- Create new project
--- Flow: Name → Area → Outcome → First action → Create file
function M.create_project()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local data = {}
  
  -- Step 1: Name
  vim.ui.input({ prompt = capture_glyphs.project .. " Project name: " }, function(name)
    if not name or name == "" then return end
    data.name = name
    data.slug = slugify(name)
    
    -- Step 2: Area
    vim.schedule(function()
      local areas = get_areas()
      local items = { capture_glyphs.project .. " Standalone (no area)" }
      for _, a in ipairs(areas) do
        table.insert(items, capture_glyphs.area .. " " .. a.name)
      end
      table.insert(items, capture_glyphs.area .. " + New area...")
      
      fzf.fzf_exec(items, {
        prompt = "Area ❯ ",
        winopts = { height = 0.4, width = 0.4 },
        actions = {
          ["default"] = function(sel)
            if not sel or not sel[1] then return end
            
            if sel[1]:match("New area") then
              vim.schedule(function()
                vim.ui.input({ prompt = "New area: " }, function(aname)
                  if aname and aname ~= "" then
                    data.area = aname
                    vim.fn.mkdir(gtd_home() .. "/Areas/" .. aname, "p")
                  end
                  vim.schedule(function() M._project_step_outcome(data) end)
                end)
              end)
            elseif sel[1]:match("Standalone") then
              data.area = nil
              vim.schedule(function() M._project_step_outcome(data) end)
            else
              data.area = sel[1]:match(capture_glyphs.area .. " (.+)")
              vim.schedule(function() M._project_step_outcome(data) end)
            end
          end,
        },
      })
    end)
  end)
end

--- Project wizard: Outcome step
function M._project_step_outcome(data)
  vim.ui.input({ prompt = "Desired outcome (optional): " }, function(outcome)
    data.outcome = (outcome and outcome ~= "") and outcome or nil
    vim.schedule(function() M._project_step_action(data) end)
  end)
end

--- Project wizard: First action step
function M._project_step_action(data)
  vim.ui.input({ prompt = capture_glyphs.next .. " First action (optional): " }, function(action)
    data.first_action = (action and action ~= "") and action or nil
    vim.schedule(function() M._project_finalize(data) end)
  end)
end

--- Project wizard: Create file
function M._project_finalize(data)
  local path
  if data.area then
    path = gtd_home() .. "/Areas/" .. data.area .. "/" .. data.slug .. ".org"
  else
    path = gtd_home() .. "/Projects/" .. data.slug .. ".org"
  end
  
  if vim.fn.filereadable(path) == 1 then
    vim.notify("Project exists: " .. path, vim.log.levels.ERROR)
    return
  end
  
  local id = generate_task_id()
  local file_lines = { "#+TITLE: " .. data.name, "#+FILETAGS: :project:", "" }
  
  local proj_lines = build_project_entry({
    title = data.name,
    task_id = id,
    area = data.area,
    outcome = data.outcome,
  })
  for _, l in ipairs(proj_lines) do table.insert(file_lines, l) end
  
  if data.first_action then
    table.insert(file_lines, "")
    local action_lines = build_task_entry({
      title = data.first_action,
      state = "NEXT",
      level = 2,
      scheduled = os.date("%Y-%m-%d"),
    })
    for _, l in ipairs(action_lines) do table.insert(file_lines, l) end
  end
  
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  if write_file(path, file_lines) then
    local loc = data.area and (data.area .. "/") or "Projects/"
    vim.notify(capture_glyphs.project .. " " .. data.name .. " → " .. loc .. data.slug .. ".org", vim.log.levels.INFO)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    if M.is_running() then M.query("gtd", "refresh", nil) end
  else
    vim.notify("Failed to create project", vim.log.levels.ERROR)
  end
end

return M
