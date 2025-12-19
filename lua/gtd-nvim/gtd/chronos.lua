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

M._VERSION = "0.2.0"
M._UPDATED = "2025-12-19"

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
  vim.api.nvim_create_user_command("ChronosCapture", function()
    M.capture_full()
  end, { desc = "Full GTD capture wizard" })
  
  vim.api.nvim_create_user_command("ChronosCaptureQuick", function(opts)
    M.capture_quick(opts.args ~= "" and opts.args or nil)
  end, { desc = "Quick capture to inbox", nargs = "?" })
  
  vim.api.nvim_create_user_command("ChronosCaptureNext", function()
    M.capture_next()
  end, { desc = "Capture NEXT action" })
  
  vim.api.nvim_create_user_command("ChronosCaptureReminder", function()
    M.capture_with_reminder()
  end, { desc = "Capture with Reminders sync" })
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
  map("n", prefix .. "c", "<cmd>ChronosCapture<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos full capture" }))
  map("n", prefix .. "q", "<cmd>ChronosCaptureQuick<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos quick capture" }))
  map("n", prefix .. "a", "<cmd>ChronosCaptureNext<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos NEXT action" }))
  map("n", prefix .. "R", "<cmd>ChronosCaptureReminder<cr>",
    vim.tbl_extend("force", opts, { desc = "Chronos capture + reminder" }))
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

-- Glyphs for capture UI
local capture_glyphs = {
  inbox = "󰇮",
  project = "󰷐",
  next = "󰁔",
  todo = "󰄲",
  waiting = "󰈸",
  someday = "󰋚",
  calendar = "󰃭",
  tag = "󰓹",
  check = "󰄳",
  reminder = "󰂚",
}

--- Generate TASK_ID (YYYYMMDDHHmmss format)
---@return string
local function generate_task_id()
  return os.date("%Y%m%d%H%M%S")
end

--- Format org-mode inactive timestamp [YYYY-MM-DD Day HH:MM]
---@return string
local function format_inactive_timestamp()
  return os.date("[%Y-%m-%d %a %H:%M]")
end

--- Format org-mode active timestamp <YYYY-MM-DD Day>
---@param date_str string|nil YYYY-MM-DD format, nil for today
---@return string
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

--- Calculate future date
---@param days number Days from now
---@return string YYYY-MM-DD format
local function future_date(days)
  local t = os.time() + (days * 24 * 60 * 60)
  return os.date("%Y-%m-%d", t)
end

--- Get GTD home directory
---@return string
local function gtd_home()
  local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  if shared_ok and shared.gtd_home then
    return shared.gtd_home()
  end
  return vim.fn.expand("~/Documents/GTD")
end

--- Get inbox path
---@return string
local function inbox_path()
  return gtd_home() .. "/Inbox.org"
end

--- Ensure file exists with header
---@param path string
---@param title string
local function ensure_file(path, title)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile({ "#+TITLE: " .. title, "" }, path)
  end
end

--- Build GTD-SPEC compliant org entry
---@param opts table Task options
---@return string[] Lines to append
local function build_org_entry(opts)
  local lines = {}
  local task_id = opts.task_id or generate_task_id()
  
  -- Heading line: * STATE Title  :tags:
  local heading = string.format("* %s %s", opts.state or "TODO", opts.title)
  if opts.tags and #opts.tags > 0 then
    heading = heading .. "  :" .. table.concat(opts.tags, ":") .. ":"
  end
  table.insert(lines, heading)
  
  -- SCHEDULED/DEADLINE (before PROPERTIES per GTD-SPEC)
  if opts.scheduled then
    table.insert(lines, "SCHEDULED: " .. format_active_date(opts.scheduled))
  end
  if opts.deadline then
    table.insert(lines, "DEADLINE: " .. format_active_date(opts.deadline))
  end
  
  -- PROPERTIES drawer
  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":TASK_ID:   " .. task_id)
  table.insert(lines, ":ID:        " .. task_id)
  table.insert(lines, ":ZK_LINK:   [[zk:" .. task_id .. "]]")
  table.insert(lines, ":CREATED:   " .. format_inactive_timestamp())
  
  -- Optional properties
  if opts.area then
    table.insert(lines, ":AREA:      " .. opts.area)
  end
  if opts.effort then
    table.insert(lines, ":Effort:    " .. opts.effort)
  end
  if opts.apple_id then
    table.insert(lines, ":APPLE_ID:  " .. opts.apple_id)
  end
  if opts.state == "WAITING" then
    if opts.waiting_for then
      table.insert(lines, ":WAITING_FOR: " .. opts.waiting_for)
    end
    table.insert(lines, ":WAITING_SINCE: " .. format_inactive_timestamp())
    if opts.waiting_context then
      table.insert(lines, ":WAITING_CONTEXT: " .. opts.waiting_context)
    end
  end
  
  table.insert(lines, ":END:")
  
  -- Body text
  if opts.body and opts.body ~= "" then
    table.insert(lines, "")
    table.insert(lines, opts.body)
  end
  
  return lines
end

--- Append lines to file
---@param path string
---@param lines string[]
---@return boolean
local function append_to_file(path, lines)
  local file = io.open(path, "a")
  if not file then return false end
  file:write("\n" .. table.concat(lines, "\n") .. "\n")
  file:close()
  return true
end

--- Get all project files for picker
---@return table[]
local function get_projects()
  local projects = {}
  local root = gtd_home()
  
  -- Standalone projects
  local proj_dir = root .. "/Projects"
  if vim.fn.isdirectory(proj_dir) == 1 then
    for _, f in ipairs(vim.fn.glob(proj_dir .. "/*.org", false, true)) do
      local name = vim.fn.fnamemodify(f, ":t:r")
      table.insert(projects, {
        name = name,
        path = f,
        display = capture_glyphs.project .. " " .. name,
      })
    end
  end
  
  -- Area projects
  local areas_dir = root .. "/Areas"
  if vim.fn.isdirectory(areas_dir) == 1 then
    for _, area_path in ipairs(vim.fn.glob(areas_dir .. "/*", false, true)) do
      if vim.fn.isdirectory(area_path) == 1 then
        local area_name = vim.fn.fnamemodify(area_path, ":t")
        for _, f in ipairs(vim.fn.glob(area_path .. "/*.org", false, true)) do
          local name = vim.fn.fnamemodify(f, ":t:r")
          table.insert(projects, {
            name = name,
            path = f,
            area = area_name,
            display = capture_glyphs.project .. " " .. area_name .. "/" .. name,
          })
        end
      end
    end
  end
  
  return projects
end

--- Quick capture - minimal prompts, straight to inbox
---@param title string|nil Pre-filled title
function M.capture_quick(title)
  local do_capture = function(t)
    if not t or t == "" then return end
    
    local lines = build_org_entry({
      title = t,
      state = "TODO",
    })
    
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
    vim.ui.input({ prompt = capture_glyphs.inbox .. " Quick capture: " }, do_capture)
  end
end

--- NEXT action capture - ready-to-do task
---@param opts table|nil Options: title, scheduled, project
function M.capture_next(opts)
  opts = opts or {}
  
  local function do_capture(title)
    if not title or title == "" then return end
    
    local entry_opts = {
      title = title,
      state = "NEXT",
      scheduled = opts.scheduled or os.date("%Y-%m-%d"),
    }
    
    local target_path = inbox_path()
    local level = "*"
    
    if opts.project_path then
      target_path = opts.project_path
      level = "**"  -- Level 2 for project tasks
    end
    
    local lines = build_org_entry(entry_opts)
    -- Adjust level if needed
    if level == "**" then
      lines[1] = "*" .. lines[1]
    end
    
    ensure_file(target_path, vim.fn.fnamemodify(target_path, ":t:r"))
    if append_to_file(target_path, lines) then
      vim.notify(capture_glyphs.next .. " " .. title, vim.log.levels.INFO)
    else
      vim.notify("Capture failed", vim.log.levels.ERROR)
    end
  end
  
  if opts.title then
    do_capture(opts.title)
  else
    vim.ui.input({ prompt = capture_glyphs.next .. " NEXT action: " }, do_capture)
  end
end

--- Full capture wizard with all options
function M.capture_full()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required for full capture", vim.log.levels.ERROR)
    return
  end
  
  local capture_data = {}
  
  -- Step 1: Title
  vim.ui.input({ prompt = "󰷐 Task title: " }, function(title)
    if not title or title == "" then return end
    capture_data.title = title
    
    -- Step 2: State
    local states = {
      capture_glyphs.next .. " NEXT (ready to do now)",
      capture_glyphs.todo .. " TODO (not yet actionable)",
      capture_glyphs.waiting .. " WAITING (delegated/blocked)",
      capture_glyphs.someday .. " SOMEDAY (maybe later)",
    }
    
    fzf.fzf_exec(states, {
      prompt = "State ❯ ",
      actions = {
        ["default"] = function(selected)
          if not selected or not selected[1] then return end
          local choice = selected[1]
          if choice:match("NEXT") then capture_data.state = "NEXT"
          elseif choice:match("TODO") then capture_data.state = "TODO"
          elseif choice:match("WAITING") then capture_data.state = "WAITING"
          elseif choice:match("SOMEDAY") then capture_data.state = "SOMEDAY"
          else capture_data.state = "TODO" end
          
          vim.schedule(function()
            -- Step 3: Destination
            local destinations = {
              capture_glyphs.inbox .. " Inbox (for later review)",
              capture_glyphs.project .. " Select Project...",
            }
            
            fzf.fzf_exec(destinations, {
              prompt = "Capture to ❯ ",
              actions = {
                ["default"] = function(dest_sel)
                  if not dest_sel or not dest_sel[1] then return end
                  
                  vim.schedule(function()
                    if dest_sel[1]:match("Project") then
                      -- Pick project
                      local projects = get_projects()
                      if #projects == 0 then
                        vim.notify("No projects found", vim.log.levels.WARN)
                        capture_data.path = inbox_path()
                        capture_data.level = 1
                      else
                        local items = {}
                        for _, p in ipairs(projects) do
                          table.insert(items, p.display)
                        end
                        
                        fzf.fzf_exec(items, {
                          prompt = "Project ❯ ",
                          actions = {
                            ["default"] = function(proj_sel)
                              if proj_sel and proj_sel[1] then
                                for _, p in ipairs(projects) do
                                  if p.display == proj_sel[1] then
                                    capture_data.path = p.path
                                    capture_data.level = 2
                                    capture_data.area = p.area
                                    break
                                  end
                                end
                              else
                                capture_data.path = inbox_path()
                                capture_data.level = 1
                              end
                              vim.schedule(function() M._capture_step_date(capture_data) end)
                            end,
                          },
                          winopts = { height = 0.5, width = 0.6 },
                        })
                        return
                      end
                    else
                      capture_data.path = inbox_path()
                      capture_data.level = 1
                    end
                    
                    M._capture_step_date(capture_data)
                  end)
                end,
              },
              winopts = { height = 0.3, width = 0.5 },
            })
          end)
        end,
      },
      winopts = { height = 0.35, width = 0.5 },
    })
  end)
end

--- Internal: Date selection step
function M._capture_step_date(data)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    M._capture_finalize(data)
    return
  end
  
  local date_opts = {
    capture_glyphs.calendar .. " Today (" .. os.date("%Y-%m-%d") .. ")",
    capture_glyphs.calendar .. " Tomorrow (" .. future_date(1) .. ")",
    capture_glyphs.calendar .. " Next week (" .. future_date(7) .. ")",
    capture_glyphs.calendar .. " No date",
    capture_glyphs.calendar .. " Custom date...",
  }
  
  fzf.fzf_exec(date_opts, {
    prompt = "Schedule ❯ ",
    actions = {
      ["default"] = function(selected)
        if not selected or not selected[1] then
          vim.schedule(function() M._capture_finalize(data) end)
          return
        end
        
        local choice = selected[1]
        if choice:match("Today") then
          data.scheduled = os.date("%Y-%m-%d")
        elseif choice:match("Tomorrow") then
          data.scheduled = future_date(1)
        elseif choice:match("Next week") then
          data.scheduled = future_date(7)
        elseif choice:match("Custom") then
          vim.schedule(function()
            vim.ui.input({ prompt = "Date (YYYY-MM-DD): " }, function(d)
              if d and d:match("^%d%d%d%d%-%d%d%-%d%d$") then
                data.scheduled = d
              end
              M._capture_finalize(data)
            end)
          end)
          return
        end
        -- No date selected = nil scheduled
        
        vim.schedule(function() M._capture_finalize(data) end)
      end,
    },
    winopts = { height = 0.35, width = 0.5 },
  })
end

--- Internal: Final capture step
function M._capture_finalize(data)
  -- Handle WAITING state extras
  if data.state == "WAITING" then
    vim.ui.input({ prompt = "Waiting for (person/thing): " }, function(wf)
      data.waiting_for = wf
      M._do_capture(data)
    end)
  else
    M._do_capture(data)
  end
end

--- Internal: Execute capture
function M._do_capture(data)
  local entry_opts = {
    title = data.title,
    state = data.state,
    scheduled = data.scheduled,
    area = data.area,
    waiting_for = data.waiting_for,
  }
  
  local lines = build_org_entry(entry_opts)
  
  -- Adjust heading level for project files
  if data.level == 2 then
    lines[1] = "*" .. lines[1]
  end
  
  local target = data.path or inbox_path()
  ensure_file(target, vim.fn.fnamemodify(target, ":t:r"))
  
  if append_to_file(target, lines) then
    local icon = capture_glyphs[data.state:lower()] or capture_glyphs.todo
    local dest = vim.fn.fnamemodify(target, ":t:r")
    vim.notify(string.format("%s %s → %s", icon, data.title, dest), vim.log.levels.INFO)
    
    -- Refresh Chronos index if running
    if M.is_running() then
      -- The file watcher will auto-update, but we can force it
      M.query("gtd", "refresh", nil)
    end
  else
    vim.notify("Capture failed", vim.log.levels.ERROR)
  end
end

--- Capture with Apple Reminders sync
---@param opts table|nil Options
function M.capture_with_reminder(opts)
  opts = opts or {}
  
  vim.ui.input({ prompt = capture_glyphs.reminder .. " Task (syncs to Reminders): " }, function(title)
    if not title or title == "" then return end
    
    -- Create the reminder first via bridge, get APPLE_ID
    -- For now, just capture to org - reminder sync will pick it up
    local entry_opts = {
      title = title,
      state = opts.state or "NEXT",
      scheduled = opts.scheduled or os.date("%Y-%m-%d"),
    }
    
    local lines = build_org_entry(entry_opts)
    ensure_file(inbox_path(), "Inbox")
    
    if append_to_file(inbox_path(), lines) then
      vim.notify(capture_glyphs.reminder .. " " .. title .. " (sync pending)", vim.log.levels.INFO)
      
      -- Trigger immediate sync to create the reminder
      if M.is_running() then
        vim.defer_fn(function()
          local result = M.reminders_sync()
          if result and result.outbound_updated and result.outbound_updated > 0 then
            vim.notify("Synced to Apple Reminders", vim.log.levels.INFO)
          end
        end, 500)
      end
    else
      vim.notify("Capture failed", vim.log.levels.ERROR)
    end
  end)
end

return M
