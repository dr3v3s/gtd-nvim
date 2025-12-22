-- ============================================================================
-- GTD-NVIM CHRONOS INTEGRATION
-- ============================================================================
-- Integration with Chronos daemon for GTD orchestration, metrics, and sync
-- Provides real-time task data, search, and Apple Reminders bidirectional sync
--
-- @module gtd-nvim.gtd.chronos
-- @version 0.15.0
-- @updated 2025-12-22
-- @see ~/Developer/chronos (daemon source)
-- ============================================================================

local M = {}

M._VERSION = "0.15.0"
M._UPDATED = "2025-12-22"

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

-- Glyphs for GTD display
local capture_glyphs = {
  inbox = "󰇮",
  project = "󰷐",
  next = "󰁔",
  todo = "󰄲",
  waiting = "󰈸",
  someday = "󰋚",
  calendar = "󰃭",
  area = "󰀼",
  tag = "󰓹",
  reference = "󰌷",
}

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
-- SYNC STATUS (for statusline integration)
-- ============================================================================

-- Cache for sync status (updated periodically)
local sync_cache = {
  daemon_ok = false,
  reminders_ok = false,
  last_check = 0,
  last_sync = nil,
  connection_mode = "unknown",
  version = nil,
}
local SYNC_CACHE_TTL = 5000  -- 5 seconds

--- Get comprehensive sync status
---@return table {daemon_ok, reminders_ok, connection_mode, version, last_sync}
function M.sync_status()
  local now = vim.loop.now()
  
  -- Return cached if fresh
  if now - sync_cache.last_check < SYNC_CACHE_TTL then
    return sync_cache
  end
  
  sync_cache.last_check = now
  sync_cache.daemon_ok = false
  sync_cache.reminders_ok = false
  
  -- Check daemon via ping
  local ping_data, ping_err = M.query(nil, "ping", nil)
  if ping_data then
    sync_cache.daemon_ok = true
    if ping_data.version then
      sync_cache.version = ping_data.version
    end
  else
    log("Daemon ping failed: " .. (ping_err or "unknown"))
    return sync_cache
  end
  
  -- Check reminders provider status
  local rem_status, rem_err = M.query("reminders", "status", nil)
  if rem_status then
    sync_cache.reminders_ok = rem_status.bridge_available or false
    sync_cache.connection_mode = rem_status.connection_mode or "unknown"
    if rem_status.last_sync then
      sync_cache.last_sync = rem_status.last_sync
    end
  else
    log("Reminders status failed: " .. (rem_err or "unknown"))
  end
  
  return sync_cache
end

--- Format sync status for statusline (compact)
--- Returns: "󰅟" (synced), "󰅞" (partial), "󰅜" (offline)
---@return string icon, string|nil tooltip
function M.sync_statusline()
  local status = M.sync_status()
  
  if not status.daemon_ok then
    return "󰅜", "Chronos daemon offline"
  end
  
  if status.reminders_ok then
    return "󰅟", "Synced"
  end
  
  return "󰅞", "Daemon OK, Reminders unavailable"
end

--- Quick daemon connection check (cached)
---@return boolean
function M.is_connected()
  local status = M.sync_status()
  return status.daemon_ok
end

--- Get daemon version (cached)
---@return string|nil
function M.daemon_version()
  local status = M.sync_status()
  return status.version
end

--- Get detailed sync status for display (not cached as aggressively)
---@return table Detailed status info
function M.detailed_status()
  local result = {
    daemon = { ok = false, version = nil, providers = {} },
    gtd = { ok = false, task_count = 0, last_refresh = nil },
    reminders = { ok = false, connection = "unknown", lists = 0 },
    bridge = { ok = false, version = nil },
  }
  
  -- Check daemon
  local ping, _ = M.query(nil, "ping", nil)
  if ping then
    result.daemon.ok = true
    result.daemon.version = ping.version
    result.daemon.providers = ping.providers or {}
  else
    return result
  end
  
  -- Check GTD metrics
  local metrics, _ = M.query("gtd", "metrics", nil)
  if metrics then
    result.gtd.ok = true
    result.gtd.task_count = metrics.total or 0
    result.gtd.next_count = metrics.next or 0
    result.gtd.inbox_count = metrics.inbox or 0
  end
  
  -- Check Reminders provider
  local rem_status, _ = M.query("reminders", "status", nil)
  if rem_status then
    result.reminders.ok = rem_status.bridge_available or false
    result.reminders.connection = rem_status.connection_mode or "unknown"
    result.reminders.lists = rem_status.list_count or 0
    result.bridge.ok = rem_status.bridge_available or false
    result.bridge.version = rem_status.bridge_version
  end
  
  return result
end

--- Show comprehensive status in a floating window
function M.show_status()
  local status = M.detailed_status()
  
  local lines = {
    "╭─────────────────────────────────────╮",
    "│        Chronos Sync Status          │",
    "├─────────────────────────────────────┤",
  }
  
  -- Daemon status
  local daemon_icon = status.daemon.ok and "󰄳" or "󰅜"
  local daemon_ver = status.daemon.version or "unknown"
  table.insert(lines, string.format("│ %s Daemon: %s", daemon_icon, daemon_ver))
  
  -- GTD status
  if status.gtd.ok then
    table.insert(lines, string.format("│ 󰄳 GTD: %d tasks (󰁔 %d next, 󰇮 %d inbox)",
      status.gtd.task_count, status.gtd.next_count or 0, status.gtd.inbox_count or 0))
  else
    table.insert(lines, "│ 󰅜 GTD: Not available")
  end
  
  -- Reminders status
  if status.reminders.ok then
    table.insert(lines, string.format("│ 󰄳 Reminders: %s (%d lists)",
      status.reminders.connection, status.reminders.lists))
  else
    table.insert(lines, "│ 󰅞 Reminders: Not available")
  end
  
  -- Bridge status
  if status.bridge.ok then
    local bridge_ver = status.bridge.version or "unknown"
    table.insert(lines, string.format("│ 󰄳 Bridge: %s", bridge_ver))
  else
    table.insert(lines, "│ 󰅜 Bridge: Not running")
  end
  
  table.insert(lines, "╰─────────────────────────────────────╯")
  
  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  
  local width = 39
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "none",
  })
  
  -- Close on any key
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<CR>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
end

-- ============================================================================
-- LUALINE COMPONENTS
-- ============================================================================

--- Lualine component for GTD metrics
--- Usage: require('lualine').setup { sections = { lualine_x = { require('gtd-nvim.gtd.chronos').lualine_gtd } } }
function M.lualine_gtd()
  local m = M.metrics()
  if not m then return "" end
  
  local parts = {}
  if m.next and m.next > 0 then
    table.insert(parts, "󰁔" .. m.next)
  end
  if m.waiting and m.waiting > 0 then
    table.insert(parts, "󰈸" .. m.waiting)
  end
  if m.inbox and m.inbox > 0 then
    table.insert(parts, "󰇮" .. m.inbox)
  end
  
  return table.concat(parts, " ")
end

--- Lualine component for sync status
--- Returns icon only: 󰅟 (all ok), 󰅞 (partial), 󰅜 (offline)
function M.lualine_sync()
  local icon, _ = M.sync_statusline()
  return icon
end

-- ============================================================================
-- TASK WRITE OPERATIONS (via daemon API)
-- ============================================================================

--- Create a new task via daemon
---@param opts table {title, state, dest, scheduled, deadline, tags, props, body}
---@return table|nil {task_id, file, line} or nil on error
function M.create_task(opts)
  if not opts.title or opts.title == "" then
    vim.notify("[chronos] Title required", vim.log.levels.ERROR)
    return nil
  end
  
  local data, err = M.query("gtd", "create", {
    title = opts.title,
    state = opts.state or "TODO",
    dest = opts.dest or "inbox",
    scheduled = opts.scheduled,
    deadline = opts.deadline,
    tags = opts.tags,
    props = opts.props,
    body = opts.body,
  })
  
  if not data then
    vim.notify("[chronos] Create failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return nil
  end
  
  log("Created task: " .. data.task_id)
  return data
end

--- Update an existing task via daemon
---@param task_id string The TASK_ID to update
---@param opts table {title, state, scheduled, deadline, tags, props, body}
---@return table|nil {task_id, file, line, changed} or nil on error
function M.update_task(task_id, opts)
  if not task_id or task_id == "" then
    vim.notify("[chronos] task_id required", vim.log.levels.ERROR)
    return nil
  end
  
  local params = vim.tbl_extend("force", { task_id = task_id }, opts or {})
  local data, err = M.query("gtd", "update", params)
  
  if not data then
    vim.notify("[chronos] Update failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return nil
  end
  
  log("Updated task: " .. task_id .. " changed: " .. table.concat(data.changed or {}, ", "))
  return data
end

--- Complete a task via daemon
---@param task_id string The TASK_ID to complete
---@param note string|nil Optional completion note
---@return table|nil {task_id, file, line, closed_at, recurring} or nil on error
function M.complete_task(task_id, note)
  if not task_id or task_id == "" then
    vim.notify("[chronos] task_id required", vim.log.levels.ERROR)
    return nil
  end
  
  local data, err = M.query("gtd", "complete", {
    task_id = task_id,
    note = note,
  })
  
  if not data then
    vim.notify("[chronos] Complete failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return nil
  end
  
  local msg = "Completed: " .. task_id
  if data.recurring then
    msg = "Advanced recurring: " .. task_id
  end
  log(msg)
  return data
end

--- Refile a task to a different file via daemon
---@param task_id string The TASK_ID to refile
---@param dest string Destination: "inbox", "project:slug", or file path
---@return table|nil {task_id, from_file, from_line, to_file, to_line} or nil on error
function M.refile_task(task_id, dest)
  if not task_id or task_id == "" then
    vim.notify("[chronos] task_id required", vim.log.levels.ERROR)
    return nil
  end
  if not dest or dest == "" then
    vim.notify("[chronos] dest required", vim.log.levels.ERROR)
    return nil
  end
  
  local data, err = M.query("gtd", "refile", {
    task_id = task_id,
    dest = dest,
  })
  
  if not data then
    vim.notify("[chronos] Refile failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return nil
  end
  
  log("Refiled: " .. task_id .. " to " .. data.to_file)
  return data
end

--- Delete a task via daemon
---@param task_id string The TASK_ID to delete
---@param hard boolean|nil True to remove from file, false to mark CANCELLED
---@return table|nil {task_id, file, hard} or nil on error
function M.delete_task(task_id, hard)
  if not task_id or task_id == "" then
    vim.notify("[chronos] task_id required", vim.log.levels.ERROR)
    return nil
  end
  
  local data, err = M.query("gtd", "delete", {
    task_id = task_id,
    hard = hard or false,
  })
  
  if not data then
    vim.notify("[chronos] Delete failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return nil
  end
  
  local action = data.hard and "Deleted" or "Cancelled"
  log(action .. ": " .. task_id)
  return data
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

--- Get all projects with timeline and stats from daemon
---@return table[]
function M.projects_info()
  local data, err = M.query("gtd", "projects_timeline", nil)
  if not data then
    log("Projects timeline error: " .. (err or "unknown"))
    return {}
  end
  return data or {}
end

--- Get single project info by ID
---@param project_id string
---@return table|nil
function M.project_info(project_id)
  local data, err = M.query("gtd", "project_info", { project_id = project_id })
  if not data then
    log("Project info error: " .. (err or "unknown"))
    return nil
  end
  return data
end

-- ============================================================================
-- AREAS (Horizon 2)
-- ============================================================================

--- Get all areas with statistics
---@return table[] Areas array
function M.areas()
  local data, err = M.query("gtd", "areas", nil)
  if not data then
    log("Areas error: " .. (err or "unknown"))
    return {}
  end
  return data
end

--- Get detailed info for a single area
---@param area_id string Area ID (e.g., "10-Personal")
---@return table|nil Area info
function M.area_info(area_id)
  local data, err = M.query("gtd", "area_info", { area_id = area_id })
  if not data then
    log("Area info error: " .. (err or "unknown"))
    return nil
  end
  return data
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

-- ============================================================================
-- PATH HELPERS (needed by task operations)
-- ============================================================================

local function gtd_home()
  local ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  return (ok and shared.gtd_home) and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
end

local function zk_home()
  local ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  return (ok and shared.notes_home) and shared.notes_home() or vim.fn.expand("~/Documents/Notes")
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

--- Check if file has a PROJECT heading
local function has_project_heading(path)
  local f = io.open(path, "r")
  if not f then return false end
  
  -- Check first 15 lines for PROJECT heading
  for i = 1, 15 do
    local line = f:read("*line")
    if not line then break end
    if line:match("^%*+%s+PROJECT%s+") then
      f:close()
      return true
    end
  end
  f:close()
  return false
end

--- Get all project files for picker (only files with PROJECT heading)
local function get_projects()
  local projects = {}
  local root = gtd_home()
  
  -- Standalone projects in Projects/
  local pdir = root .. "/Projects"
  if vim.fn.isdirectory(pdir) == 1 then
    for _, f in ipairs(vim.fn.glob(pdir .. "/*.org", false, true)) do
      if has_project_heading(f) then
        local name = vim.fn.fnamemodify(f, ":t:r")
        table.insert(projects, { name = name, path = f, display = capture_glyphs.project .. " " .. name })
      end
    end
  end
  
  -- Area projects in Areas/*/
  local adir = root .. "/Areas"
  if vim.fn.isdirectory(adir) == 1 then
    for _, ap in ipairs(vim.fn.glob(adir .. "/*", false, true)) do
      if vim.fn.isdirectory(ap) == 1 then
        local aname = vim.fn.fnamemodify(ap, ":t")
        for _, f in ipairs(vim.fn.glob(ap .. "/*.org", false, true)) do
          if has_project_heading(f) then
            local name = vim.fn.fnamemodify(f, ":t:r")
            table.insert(projects, {
              name = name, path = f, area = aname,
              display = capture_glyphs.area .. " " .. aname .. "/" .. name
            })
          end
        end
      end
    end
  end
  
  -- Reminders provider projects in Reminders/
  local rdir = root .. "/Reminders"
  if vim.fn.isdirectory(rdir) == 1 then
    for _, f in ipairs(vim.fn.glob(rdir .. "/*.org", false, true)) do
      if has_project_heading(f) then
        local name = vim.fn.fnamemodify(f, ":t:r")
        table.insert(projects, {
          name = name, path = f, provider = "reminders",
          display = "󰅖 " .. name  -- reminders icon
        })
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

--- Get .org files that are NOT projects (no PROJECT heading)
local function get_non_project_files()
  local files = {}
  local root = gtd_home()
  local skip_files = { "Inbox.org", "Recurring.org", "Tickler.org" }
  
  local function should_skip(name)
    for _, s in ipairs(skip_files) do
      if name == s then return true end
    end
    return false
  end
  
  local function scan_dir(dir, prefix)
    if vim.fn.isdirectory(dir) ~= 1 then return end
    for _, f in ipairs(vim.fn.glob(dir .. "/*.org", false, true)) do
      local name = vim.fn.fnamemodify(f, ":t")
      if not should_skip(name) and not has_project_heading(f) then
        local display_name = vim.fn.fnamemodify(f, ":t:r")
        if prefix then display_name = prefix .. "/" .. display_name end
        table.insert(files, { name = display_name, path = f })
      end
    end
  end
  
  scan_dir(root .. "/Projects", nil)
  scan_dir(root .. "/Reminders", "Reminders")
  
  -- Areas subdirs
  local adir = root .. "/Areas"
  if vim.fn.isdirectory(adir) == 1 then
    for _, ap in ipairs(vim.fn.glob(adir .. "/*", false, true)) do
      if vim.fn.isdirectory(ap) == 1 then
        scan_dir(ap, "Areas/" .. vim.fn.fnamemodify(ap, ":t"))
      end
    end
  end
  
  return files
end

--- Convert a file to a project (add PROJECT heading with PROPERTIES)
local function convert_file_to_project(path, project_name)
  local lines = vim.fn.readfile(path)
  if not lines then return false, "Could not read file" end
  
  -- Generate TASK_ID
  local task_id = os.date("%Y%m%d%H%M%S")
  
  -- Find where to insert (after #+TITLE and #+FILETAGS if present)
  local insert_at = 1
  for i, line in ipairs(lines) do
    if line:match("^#%+") then
      insert_at = i + 1
    else
      break
    end
  end
  
  -- Build PROJECT heading
  local project_lines = {
    "",
    "* PROJECT " .. project_name,
    ":PROPERTIES:",
    ":ID: " .. task_id,
    ":TASK_ID: " .. task_id,
    ":CREATED: [" .. os.date("%Y-%m-%d %a") .. "]",
    ":END:",
    "",
  }
  
  -- Insert project heading
  for i, pl in ipairs(project_lines) do
    table.insert(lines, insert_at + i - 1, pl)
  end
  
  -- Adjust existing headings: * → **
  for i = insert_at + #project_lines, #lines do
    if lines[i]:match("^%* ") then
      lines[i] = "*" .. lines[i]
    end
  end
  
  vim.fn.writefile(lines, path)
  return true
end

-- ============================================================================
-- TASK OPERATIONS (for fzf actions)
-- ============================================================================

--- Delete task(s) from org file
---@param tasks table Array of task objects with file and line
local function delete_tasks(tasks)
  -- Group by file
  local by_file = {}
  for _, task in ipairs(tasks) do
    if task.file and task.line then
      by_file[task.file] = by_file[task.file] or {}
      table.insert(by_file[task.file], task.line)
    end
  end
  
  local deleted = 0
  for file, lines in pairs(by_file) do
    -- Sort lines descending to delete from bottom up
    table.sort(lines, function(a, b) return a > b end)
    
    local content = vim.fn.readfile(file)
    for _, line_num in ipairs(lines) do
      -- Find the subtree extent
      local start_line = line_num
      
      -- Safety check: ensure line exists
      if start_line > #content or not content[start_line] then
        goto continue
      end
      
      local stars = content[start_line]:match("^(%*+)")
      if stars then
        local level = #stars
        local end_line = start_line
        
        -- Find end of subtree
        for i = start_line + 1, #content do
          local s = content[i]:match("^(%*+)")
          if s and #s <= level then break end
          end_line = i
        end
        
        -- Remove lines (from end to start)
        for i = end_line, start_line, -1 do
          table.remove(content, i)
        end
        deleted = deleted + 1
      end
      ::continue::
    end
    vim.fn.writefile(content, file)
  end
  
  return deleted
end

--- Archive task(s) - move to Archive folder
---@param tasks table Array of task objects
local function archive_tasks(tasks)
  local archive_dir = gtd_home() .. "/Archive"
  vim.fn.mkdir(archive_dir, "p")
  
  -- Group tasks by file to handle multiple tasks from same file
  local by_file = {}
  for _, task in ipairs(tasks) do
    if task.file and task.line then
      by_file[task.file] = by_file[task.file] or {}
      table.insert(by_file[task.file], task)
    end
  end
  
  local archived = 0
  
  for file, file_tasks in pairs(by_file) do
    -- Sort by line descending to process from bottom up
    table.sort(file_tasks, function(a, b) return a.line > b.line end)
    
    local content = vim.fn.readfile(file)
    local source_name = vim.fn.fnamemodify(file, ":t")
    local archive_file = archive_dir .. "/" .. source_name
    
    -- Load or create archive content
    local archive_content = {}
    if vim.fn.filereadable(archive_file) == 1 then
      archive_content = vim.fn.readfile(archive_file)
    end
    
    for _, task in ipairs(file_tasks) do
      local start_line = task.line
      
      -- Safety check: ensure line exists
      if start_line > #content or not content[start_line] then
        goto continue
      end
      
      local stars = content[start_line]:match("^(%*+)")
      
      if stars then
        local level = #stars
        local end_line = start_line
        local subtree = {}
        
        -- Extract subtree
        for i = start_line, #content do
          local s = content[i]:match("^(%*+)")
          if i > start_line and s and #s <= level then break end
          table.insert(subtree, content[i])
          end_line = i
        end
        
        -- Append to archive content
        table.insert(archive_content, "")  -- blank line separator
        for _, line in ipairs(subtree) do
          table.insert(archive_content, line)
        end
        
        -- Remove from source content (bottom up)
        for i = end_line, start_line, -1 do
          table.remove(content, i)
        end
        archived = archived + 1
      end
      ::continue::
    end
    
    -- Write modified source file
    vim.fn.writefile(content, file)
    
    -- Write archive file
    vim.fn.writefile(archive_content, archive_file)
  end
  
  return archived
end

--- Scan Archive folder and return archived tasks
---@return table[] Array of archived task objects
local function get_archived_tasks()
  local archive_dir = gtd_home() .. "/Archive"
  local tasks = {}
  
  if vim.fn.isdirectory(archive_dir) == 0 then
    return tasks
  end
  
  -- Scan all .org files in Archive
  local files = vim.fn.glob(archive_dir .. "/*.org", false, true)
  
  for _, file in ipairs(files) do
    local content = vim.fn.readfile(file)
    local source_name = vim.fn.fnamemodify(file, ":t:r")  -- original file name
    
    for i, line in ipairs(content) do
      local stars, state, title = line:match("^(%*+)%s+(NEXT|TODO|WAITING|SOMEDAY|DONE|CANCELLED|PROJECT)%s+(.+)")
      if not stars then
        -- Try individual keywords
        for _, kw in ipairs({"NEXT", "TODO", "WAITING", "SOMEDAY", "DONE", "CANCELLED", "PROJECT"}) do
          stars, title = line:match("^(%*+)%s+" .. kw .. "%s+(.+)")
          if stars then
            state = kw
            break
          end
        end
      end
      
      if stars and state and title then
        -- Clean title (remove tags)
        title = title:gsub("%s+:[%w@:]+:%s*$", "")
        
        table.insert(tasks, {
          title = title,
          state = state,
          file = file,
          line = i,
          level = #stars,
          source = source_name,  -- where it came from
        })
      end
    end
  end
  
  return tasks
end

--- Restore task(s) from archive to production
---@param tasks table Array of archived task objects
---@param target_file string|nil Target file (defaults to Inbox.org)
---@return number Count of restored tasks
local function restore_tasks(tasks, target_file)
  target_file = target_file or inbox_path()
  ensure_file(target_file, vim.fn.fnamemodify(target_file, ":t:r"))
  
  -- Determine target heading level
  local target_level = 1
  local target_content = vim.fn.readfile(target_file)
  for i = 1, math.min(10, #target_content) do
    if target_content[i]:match("^%* PROJECT") then
      target_level = 2
      break
    end
  end
  
  local restored = 0
  
  -- Group by archive file for efficient processing
  local by_file = {}
  for _, task in ipairs(tasks) do
    if task.file and task.line then
      by_file[task.file] = by_file[task.file] or {}
      table.insert(by_file[task.file], task)
    end
  end
  
  for archive_file, file_tasks in pairs(by_file) do
    local content = vim.fn.readfile(archive_file)
    
    -- Sort by line descending to remove from bottom up
    table.sort(file_tasks, function(a, b) return a.line > b.line end)
    
    for _, task in ipairs(file_tasks) do
      local start_line = task.line
      local stars = content[start_line]:match("^(%*+)")
      
      if stars then
        local source_level = #stars
        local end_line = start_line
        local subtree = {}
        
        -- Extract subtree
        for i = start_line, #content do
          local s = content[i]:match("^(%*+)")
          if i > start_line and s and #s <= source_level then break end
          local line = content[i]
          -- Adjust heading levels
          if line:match("^%*+") then
            local level_diff = target_level - source_level
            if level_diff > 0 then
              line = string.rep("*", level_diff) .. line
            elseif level_diff < 0 then
              line = line:sub(1 - level_diff + 1)
            end
          end
          table.insert(subtree, line)
          end_line = i
        end
        
        -- Append to target
        target_content = vim.fn.readfile(target_file)
        table.insert(target_content, "")
        for _, line in ipairs(subtree) do
          table.insert(target_content, line)
        end
        vim.fn.writefile(target_content, target_file)
        
        -- Remove from archive
        for i = end_line, start_line, -1 do
          table.remove(content, i)
        end
        restored = restored + 1
      end
    end
    
    -- Write back archive file (or delete if empty)
    local has_content = false
    for _, line in ipairs(content) do
      if line:match("^%*") then
        has_content = true
        break
      end
    end
    
    if has_content then
      vim.fn.writefile(content, archive_file)
    else
      vim.fn.delete(archive_file)
    end
  end
  
  return restored
end

--- Delete task(s) permanently from archive
---@param tasks table Array of archived task objects
---@return number Count of deleted tasks
local function delete_archived_tasks(tasks)
  -- Group by file
  local by_file = {}
  for _, task in ipairs(tasks) do
    if task.file and task.line then
      by_file[task.file] = by_file[task.file] or {}
      table.insert(by_file[task.file], task.line)
    end
  end
  
  local deleted = 0
  for file, lines in pairs(by_file) do
    table.sort(lines, function(a, b) return a > b end)
    
    local content = vim.fn.readfile(file)
    for _, line_num in ipairs(lines) do
      local start_line = line_num
      local stars = content[start_line]:match("^(%*+)")
      if stars then
        local level = #stars
        local end_line = start_line
        
        for i = start_line + 1, #content do
          local s = content[i]:match("^(%*+)")
          if s and #s <= level then break end
          end_line = i
        end
        
        for i = end_line, start_line, -1 do
          table.remove(content, i)
        end
        deleted = deleted + 1
      end
    end
    
    -- Write back or delete empty file
    local has_content = false
    for _, line in ipairs(content) do
      if line:match("^%*") then
        has_content = true
        break
      end
    end
    
    if has_content then
      vim.fn.writefile(content, file)
    else
      vim.fn.delete(file)
    end
  end
  
  return deleted
end

--- Mark task(s) as DONE
---@param tasks table Array of task objects
local function mark_tasks_done(tasks)
  local done = 0
  for _, task in ipairs(tasks) do
    if task.file and task.line then
      local content = vim.fn.readfile(task.file)
      local line = content[task.line]
      if line then
        -- Replace state keyword with DONE
        local new_line = line
        for _, kw in ipairs({"NEXT", "TODO", "WAITING", "SOMEDAY"}) do
          local pattern = "^(%*+%s+)" .. kw .. "(%s+)"
          if line:match(pattern) then
            new_line = line:gsub(pattern, "%1DONE%2")
            break
          end
        end
        if new_line ~= line then
          content[task.line] = new_line
          vim.fn.writefile(content, task.file)
          done = done + 1
        end
      end
    end
  end
  return done
end

--- Refile task(s) to another file
---@param tasks table Array of task objects
---@param target_file string Target org file path
local function refile_tasks(tasks, target_file)
  if not target_file or target_file == "" then return 0 end
  
  ensure_file(target_file, vim.fn.fnamemodify(target_file, ":t:r"))
  
  -- Determine target heading level (1 for standalone, 2 for project)
  local target_level = 1
  local target_content = vim.fn.readfile(target_file)
  for i = 1, math.min(10, #target_content) do
    if target_content[i]:match("^%* PROJECT") then
      target_level = 2
      break
    end
  end
  
  local refiled = 0
  for _, task in ipairs(tasks) do
    if task.file and task.line then
      local content = vim.fn.readfile(task.file)
      local start_line = task.line
      
      -- Safety check: ensure line exists
      if start_line > #content or not content[start_line] then
        goto continue
      end
      
      local stars = content[start_line]:match("^(%*+)")
      
      if stars then
        local source_level = #stars
        local end_line = start_line
        local subtree = {}
        
        -- Extract subtree
        for i = start_line, #content do
          local s = content[i]:match("^(%*+)")
          if i > start_line and s and #s <= source_level then break end
          local line = content[i]
          -- Adjust heading levels
          if line:match("^%*+") then
            local level_diff = target_level - source_level
            if level_diff > 0 then
              line = string.rep("*", level_diff) .. line
            elseif level_diff < 0 then
              line = line:sub(1 - level_diff + 1)
            end
          end
          table.insert(subtree, line)
          end_line = i
        end
        
        -- Append to target
        target_content = vim.fn.readfile(target_file)
        table.insert(target_content, "")
        for _, line in ipairs(subtree) do
          table.insert(target_content, line)
        end
        vim.fn.writefile(target_content, target_file)
        
        -- Remove from source
        for i = end_line, start_line, -1 do
          table.remove(content, i)
        end
        vim.fn.writefile(content, task.file)
        refiled = refiled + 1
      end
    end
    ::continue::
  end
  
  return refiled
end

-- ============================================================================
-- TASK PICKERS
-- ============================================================================

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
  
  -- Helper to get selected tasks
  local function get_selected_tasks(selected)
    local result = {}
    for _, sel in ipairs(selected or {}) do
      if task_map[sel] then
        table.insert(result, task_map[sel])
      end
    end
    return result
  end
  
  -- Helper to reopen picker after action
  local function reopen()
    vim.schedule(function()
      -- Wait for file system to sync, then refresh daemon index
      vim.defer_fn(function()
        if M.is_running() then M.query("gtd", "refresh", nil) end
        -- Wait for daemon to complete re-indexing before reopening
        vim.defer_fn(function() M.pick_tasks(opts) end, 200)
      end, 50)
    end)
  end
  
  fzf.fzf_exec(items, {
    prompt = title .. " ❯ ",
    fzf_opts = {
      ["--multi"] = true,
      ["--header"] = "󰌌 TAB:select  Enter:open  ^D:done  ^X:delete  ^A:archive  ^R:refile",
    },
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
      ["ctrl-d"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        
        local count = mark_tasks_done(sel_tasks)
        vim.notify(string.format("✓ Marked %d task(s) DONE", count), vim.log.levels.INFO)
        reopen()
      end,
      ["ctrl-x"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        
        vim.ui.select({ "Yes, delete", "Cancel" }, {
          prompt = string.format("Delete %d task(s)?", #sel_tasks),
        }, function(choice)
          if choice == "Yes, delete" then
            local count = delete_tasks(sel_tasks)
            vim.notify(string.format("🗑 Deleted %d task(s)", count), vim.log.levels.INFO)
            reopen()
          else
            reopen()
          end
        end)
      end,
      ["ctrl-a"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        
        local count = archive_tasks(sel_tasks)
        vim.notify(string.format("📦 Archived %d task(s)", count), vim.log.levels.INFO)
        reopen()
      end,
      ["ctrl-r"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        
        -- Show project/file picker for refile target
        local projects = get_projects()
        local refile_items = { "Inbox.org" }
        for _, p in ipairs(projects) do
          table.insert(refile_items, p.name .. " (" .. vim.fn.fnamemodify(p.path, ":h:t") .. ")")
        end
        
        fzf.fzf_exec(refile_items, {
          prompt = "Refile to ❯ ",
          winopts = { height = 0.4, width = 0.5 },
          actions = {
            ["default"] = function(target)
              if target and target[1] then
                local target_path
                if target[1] == "Inbox.org" then
                  target_path = inbox_path()
                else
                  local proj_name = target[1]:match("^([^(]+)")
                  if proj_name then
                    proj_name = vim.trim(proj_name)
                    for _, p in ipairs(projects) do
                      if p.name == proj_name then
                        target_path = p.path
                        break
                      end
                    end
                  end
                end
                
                if target_path then
                  local count = refile_tasks(sel_tasks, target_path)
                  vim.notify(string.format("📁 Refiled %d task(s) → %s", count, vim.fn.fnamemodify(target_path, ":t")), vim.log.levels.INFO)
                  reopen()
                else
                  reopen()
                end
              else
                reopen()
              end
            end,
            ["esc"] = function()
              reopen()
            end,
          },
        })
      end,
      ["esc"] = function()
        -- Just close, don't reopen
      end,
    },
    winopts = {
      height = 0.6,
      width = 0.8,
    },
  })
end

--- Open fzf picker for archived tasks
function M.pick_archive()
  local tasks = get_archived_tasks()
  
  if #tasks == 0 then
    vim.notify("Archive is empty", vim.log.levels.INFO)
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
    local icon = "󰄳"  -- default done icon
    if task.state == "PROJECT" then icon = "󰷐"
    elseif task.state == "CANCELLED" then icon = "󰜺"
    end
    
    local display = string.format("%s %s  %s", icon, task.title, task.source)
    items[i] = display
    task_map[display] = task
  end
  
  local function get_selected_tasks(selected)
    local result = {}
    for _, sel in ipairs(selected or {}) do
      if task_map[sel] then
        table.insert(result, task_map[sel])
      end
    end
    return result
  end
  
  local function reopen()
    vim.schedule(function()
      -- Wait for daemon to complete re-indexing before reopening
      vim.defer_fn(function() M.pick_archive() end, 250)
    end)
  end
  
  fzf.fzf_exec(items, {
    prompt = "Archive ❯ ",
    fzf_opts = {
      ["--multi"] = true,
      ["--header"] = "󰌌 TAB:select  Enter:view  ^R:restore  ^X:delete permanently",
    },
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
      ["ctrl-r"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        
        -- Ask where to restore
        local projects = get_projects()
        local restore_items = { "Inbox.org (default)" }
        for _, p in ipairs(projects) do
          table.insert(restore_items, p.name .. " (" .. vim.fn.fnamemodify(p.path, ":h:t") .. ")")
        end
        
        fzf.fzf_exec(restore_items, {
          prompt = "Restore to ❯ ",
          winopts = { height = 0.4, width = 0.5 },
          actions = {
            ["default"] = function(target)
              local target_path = inbox_path()
              
              if target and target[1] and not target[1]:match("Inbox.org") then
                local proj_name = target[1]:match("^([^(]+)")
                if proj_name then
                  proj_name = vim.trim(proj_name)
                  for _, p in ipairs(projects) do
                    if p.name == proj_name then
                      target_path = p.path
                      break
                    end
                  end
                end
              end
              
              local count = restore_tasks(sel_tasks, target_path)
              vim.notify(string.format("♻ Restored %d task(s) → %s", count, vim.fn.fnamemodify(target_path, ":t")), vim.log.levels.INFO)
              if M.is_running() then M.query("gtd", "refresh", nil) end
              reopen()
            end,
            ["esc"] = function() reopen() end,
          },
        })
      end,
      ["ctrl-x"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        
        vim.ui.select({ "Yes, delete permanently", "Cancel" }, {
          prompt = string.format("Permanently delete %d task(s)?", #sel_tasks),
        }, function(choice)
          if choice == "Yes, delete permanently" then
            local count = delete_archived_tasks(sel_tasks)
            vim.notify(string.format("🗑 Permanently deleted %d task(s)", count), vim.log.levels.INFO)
          end
          reopen()
        end)
      end,
      ["esc"] = function() end,  -- just close
    },
    winopts = {
      height = 0.6,
      width = 0.8,
    },
  })
end

--- Unified task picker with state filtering
--- Shows all active tasks, filterable by state using ctrl keys
function M.pick_all()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  -- Fetch all active states
  local all_tasks = {}
  for _, state in ipairs({"NEXT", "TODO", "WAITING", "SOMEDAY"}) do
    local tasks = M.tasks(state, 100)
    for _, t in ipairs(tasks) do
      table.insert(all_tasks, t)
    end
  end
  
  if #all_tasks == 0 then
    vim.notify("No active tasks found", vim.log.levels.INFO)
    return
  end
  
  -- Build display with state prefix for filtering
  local items = {}
  local task_map = {}
  
  local state_icons = {
    NEXT = "󰁔",
    TODO = "󰄲",
    WAITING = "󰈸",
    SOMEDAY = "󰋚",
  }
  
  for _, task in ipairs(all_tasks) do
    local icon = state_icons[task.state] or "󰄲"
    local file = vim.fn.fnamemodify(task.file or "", ":t:r")
    -- Include state in display for filtering
    local display = string.format("%s %-8s %s  %s", icon, task.state, task.title or "Untitled", file)
    table.insert(items, display)
    task_map[display] = task
  end
  
  local function get_selected_tasks(selected)
    local result = {}
    for _, sel in ipairs(selected or {}) do
      if task_map[sel] then
        table.insert(result, task_map[sel])
      end
    end
    return result
  end
  
  local function reopen()
    vim.schedule(function()
      -- Wait for file system to sync, then refresh daemon index
      vim.defer_fn(function()
        if M.is_running() then M.query("gtd", "refresh", nil) end
        -- Wait for daemon to complete re-indexing before reopening
        vim.defer_fn(function() M.pick_all() end, 200)
      end, 50)
    end)
  end
  
  fzf.fzf_exec(items, {
    prompt = "Tasks ❯ ",
    fzf_opts = {
      ["--multi"] = true,
      ["--header"] = "󰌌 Filter: NEXT/TODO/WAIT/SOME | ^D:done ^X:del ^A:archive ^R:refile",
    },
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
      ["ctrl-d"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        local count = mark_tasks_done(sel_tasks)
        vim.notify(string.format("✓ Marked %d task(s) DONE", count), vim.log.levels.INFO)
        reopen()
      end,
      ["ctrl-x"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        vim.ui.select({ "Yes, delete", "Cancel" }, {
          prompt = string.format("Delete %d task(s)?", #sel_tasks),
        }, function(choice)
          if choice == "Yes, delete" then
            local count = delete_tasks(sel_tasks)
            vim.notify(string.format("🗑 Deleted %d task(s)", count), vim.log.levels.INFO)
          end
          reopen()
        end)
      end,
      ["ctrl-a"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        local count = archive_tasks(sel_tasks)
        vim.notify(string.format("📦 Archived %d task(s)", count), vim.log.levels.INFO)
        reopen()
      end,
      ["ctrl-r"] = function(selected)
        local sel_tasks = get_selected_tasks(selected)
        if #sel_tasks == 0 then return end
        local projects = get_projects()
        local refile_items = { "Inbox.org" }
        for _, p in ipairs(projects) do
          table.insert(refile_items, p.name .. " (" .. vim.fn.fnamemodify(p.path, ":h:t") .. ")")
        end
        fzf.fzf_exec(refile_items, {
          prompt = "Refile to ❯ ",
          winopts = { height = 0.4, width = 0.5 },
          actions = {
            ["default"] = function(target)
              if target and target[1] then
                local target_path = inbox_path()
                if not target[1]:match("Inbox.org") then
                  local proj_name = vim.trim(target[1]:match("^([^(]+)") or "")
                  for _, p in ipairs(projects) do
                    if p.name == proj_name then target_path = p.path break end
                  end
                end
                local count = refile_tasks(sel_tasks, target_path)
                vim.notify(string.format("📁 Refiled %d → %s", count, vim.fn.fnamemodify(target_path, ":t")), vim.log.levels.INFO)
              end
              reopen()
            end,
            ["esc"] = function() reopen() end,
          },
        })
      end,
      ["esc"] = function() end,
    },
    winopts = { height = 0.7, width = 0.85 },
  })
end

--- Archive entire project file
---@param project table Project object with path
local function archive_project(project)
  if not project or not project.path then return false end
  
  local archive_dir = gtd_home() .. "/Archive"
  vim.fn.mkdir(archive_dir, "p")
  
  local source_name = vim.fn.fnamemodify(project.path, ":t")
  local archive_path = archive_dir .. "/" .. source_name
  
  -- If archive already exists, append content
  if vim.fn.filereadable(archive_path) == 1 then
    local archive_content = vim.fn.readfile(archive_path)
    local source_content = vim.fn.readfile(project.path)
    table.insert(archive_content, "")
    table.insert(archive_content, "# Archived: " .. os.date("%Y-%m-%d %H:%M"))
    for _, line in ipairs(source_content) do
      table.insert(archive_content, line)
    end
    vim.fn.writefile(archive_content, archive_path)
  else
    vim.fn.rename(project.path, archive_path)
  end
  
  -- Delete source if it still exists (was appended)
  if vim.fn.filereadable(project.path) == 1 then
    vim.fn.delete(project.path)
  end
  
  return true
end

--- Toggle ONGOING property on a project file
---@param project table Project object with path
---@return boolean success
---@return boolean new_state True if now ongoing, false if now active
local function toggle_ongoing(project)
  if not project or not project.path then return false, false end
  
  local lines = vim.fn.readfile(project.path)
  if #lines == 0 then return false, false end
  
  local in_properties = false
  local has_ongoing = false
  local ongoing_line = nil
  local properties_end = nil
  
  -- Find ONGOING property
  for i, line in ipairs(lines) do
    if line:match("^%s*:PROPERTIES:%s*$") then
      in_properties = true
    elseif line:match("^%s*:END:%s*$") and in_properties then
      properties_end = i
      in_properties = false
      break
    elseif in_properties and line:match("^%s*:ONGOING:%s*") then
      has_ongoing = true
      ongoing_line = i
    end
  end
  
  if has_ongoing and ongoing_line then
    -- Remove ONGOING property
    table.remove(lines, ongoing_line)
    vim.fn.writefile(lines, project.path)
    return true, false
  elseif properties_end then
    -- Add ONGOING property before :END:
    table.insert(lines, properties_end, ":ONGOING: t")
    vim.fn.writefile(lines, project.path)
    return true, true
  end
  
  return false, false
end

--- Toggle ON_HOLD property on a project file
---@param project table Project object with path
---@return boolean success
---@return boolean new_state True if now on hold, false if now active
local function toggle_on_hold(project)
  if not project or not project.path then return false, false end
  
  local lines = vim.fn.readfile(project.path)
  if #lines == 0 then return false, false end
  
  local in_properties = false
  local has_on_hold = false
  local on_hold_line = nil
  local properties_end = nil
  
  -- Find ON_HOLD property
  for i, line in ipairs(lines) do
    if line:match("^%s*:PROPERTIES:%s*$") then
      in_properties = true
    elseif line:match("^%s*:END:%s*$") and in_properties then
      properties_end = i
      in_properties = false
      break
    elseif in_properties and line:match("^%s*:ON_HOLD:%s*") then
      has_on_hold = true
      on_hold_line = i
    end
  end
  
  if has_on_hold and on_hold_line then
    -- Remove ON_HOLD property
    table.remove(lines, on_hold_line)
    vim.fn.writefile(lines, project.path)
    return true, false
  elseif properties_end then
    -- Add ON_HOLD property before :END:
    table.insert(lines, properties_end, ":ON_HOLD: t")
    vim.fn.writefile(lines, project.path)
    return true, true
  end
  
  return false, false
end

--- Project picker with actions
function M.pick_projects()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  -- Get project info from daemon (rich data with timeline and stats)
  local projects_raw = M.projects_info()
  
  -- Filter projects:
  -- 1. Exclude Reminders/ folder (synced lists, not GTD projects)
  -- 2. Exclude projects with <2 tasks (not real projects)
  -- 3. Exclude ONGOING areas (unless user wants all)
  -- 4. Exclude ON_HOLD projects (paused/deferred)
  local projects = {}
  for _, p in ipairs(projects_raw) do
    local is_reminders = p.file and p.file:match("/Reminders/")
    local has_tasks = p.tasks and p.tasks.total >= 1  -- At least 1 child task
    local is_ongoing = p.ongoing
    local is_on_hold = p.on_hold
    
    if not is_reminders and has_tasks and not is_ongoing and not is_on_hold then
      table.insert(projects, p)
    end
  end
  
  if #projects == 0 then
    vim.notify("No active projects found", vim.log.levels.INFO)
    return
  end
  
  local items = {}
  local proj_map = {}
  
  for _, p in ipairs(projects) do
    local tasks = p.tasks or {}
    local timeline = p.timeline or {}
    
    -- Build status indicators
    local parts = {}
    
    -- Task count by state
    local state_parts = {}
    if tasks.by_state then
      if tasks.by_state.NEXT and tasks.by_state.NEXT > 0 then
        table.insert(state_parts, "󰁔" .. tasks.by_state.NEXT)
      end
      if tasks.by_state.TODO and tasks.by_state.TODO > 0 then
        table.insert(state_parts, "󰄲" .. tasks.by_state.TODO)
      end
      if tasks.by_state.WAITING and tasks.by_state.WAITING > 0 then
        table.insert(state_parts, "󰈸" .. tasks.by_state.WAITING)
      end
    end
    if #state_parts > 0 then
      table.insert(parts, table.concat(state_parts, " "))
    else
      table.insert(parts, "(" .. (tasks.total or 0) .. " tasks)")
    end
    
    -- Overdue indicator
    if tasks.overdue and tasks.overdue > 0 then
      table.insert(parts, "⚠️" .. tasks.overdue)
    end
    
    -- Due this week
    if tasks.due_this_week and tasks.due_this_week > 0 then
      table.insert(parts, "📅" .. tasks.due_this_week)
    end
    
    -- Duration if computed
    if timeline.computed and timeline.duration_days then
      table.insert(parts, "📆" .. timeline.duration_days .. "d")
    end
    
    local area_part = p.area and (" [" .. p.area .. "]") or ""
    local stats_part = #parts > 0 and ("  " .. table.concat(parts, " ")) or ""
    
    local display = string.format("%s %s%s%s", capture_glyphs.project, p.title, area_part, stats_part)
    table.insert(items, display)
    
    -- Store full project info for actions
    proj_map[display] = {
      name = p.title,
      path = p.file,
      area = p.area,
      project_id = p.project_id,
      tasks = p.tasks,
      timeline = p.timeline,
    }
  end
  
  local function get_selected_projects(selected)
    local result = {}
    for _, sel in ipairs(selected or {}) do
      if proj_map[sel] then
        table.insert(result, proj_map[sel])
      end
    end
    return result
  end
  
  local function reopen()
    vim.schedule(function()
      -- Wait for file system to sync, then refresh daemon index
      vim.defer_fn(function()
        if M.is_running() then M.query("gtd", "refresh", nil) end
        -- Wait for daemon to complete re-indexing before reopening
        vim.defer_fn(function() M.pick_projects() end, 200)
      end, 50)
    end)
  end
  
  fzf.fzf_exec(items, {
    prompt = "Projects ❯ ",
    fzf_opts = {
      ["--multi"] = true,
      ["--header"] = "Enter:open | ^T:tasks | ^N:new | ^I:info | ^O:ongoing | ^H:hold | ^A:archive",
    },
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local proj = proj_map[selected[1]]
          if proj and proj.path then
            vim.cmd("edit " .. vim.fn.fnameescape(proj.path))
          end
        end
      end,
      ["ctrl-t"] = function(selected)
        -- Show tasks for this project
        if selected and selected[1] then
          local proj = proj_map[selected[1]]
          if proj then
            M.pick_tasks({ 
              filter_file = proj.path, 
              title = proj.name .. " Tasks" 
            })
          end
        end
      end,
      ["ctrl-n"] = function(selected)
        -- Create new task in this project
        if selected and selected[1] then
          local proj = proj_map[selected[1]]
          if proj then
            M.capture_task({ 
              target = proj.path, 
              level = 2,
              area = proj.area,
            })
          end
        end
      end,
      ["ctrl-i"] = function(selected)
        -- Show detailed project info
        if selected and selected[1] then
          local proj = proj_map[selected[1]]
          if proj then
            local info = M.project_info(proj.project_id)
            if info then
              local lines = {
                "󰷐 " .. info.title,
                "",
                "Tasks:",
                "  Total: " .. (info.tasks.total or 0),
              }
              if info.tasks.by_state then
                for state, count in pairs(info.tasks.by_state) do
                  table.insert(lines, "  " .. state .. ": " .. count)
                end
              end
              if info.tasks.overdue and info.tasks.overdue > 0 then
                table.insert(lines, "  ⚠️ Overdue: " .. info.tasks.overdue)
              end
              if info.timeline.computed then
                table.insert(lines, "")
                table.insert(lines, "Timeline:")
                if info.timeline.start then
                  table.insert(lines, "  Start: " .. info.timeline.start:sub(1, 10))
                end
                if info.timeline["end"] then
                  table.insert(lines, "  End: " .. info.timeline["end"]:sub(1, 10))
                end
                if info.timeline.duration_days then
                  table.insert(lines, "  Duration: " .. info.timeline.duration_days .. " days")
                end
              end
              if info.insights then
                if info.insights.tasks_without_dates > 0 or info.insights.tasks_without_deadline > 0 then
                  table.insert(lines, "")
                  table.insert(lines, "Insights:")
                  if info.insights.tasks_without_dates > 0 then
                    table.insert(lines, "  No dates: " .. info.insights.tasks_without_dates)
                  end
                  if info.insights.tasks_without_deadline > 0 then
                    table.insert(lines, "  No deadline: " .. info.insights.tasks_without_deadline)
                  end
                end
              end
              vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Project Info" })
            end
          end
        end
        -- Stay in picker
        vim.schedule(function() M.pick_projects() end)
      end,
      ["ctrl-o"] = function(selected)
        -- Toggle ongoing status (mark as area vs active project)
        local sel_projs = get_selected_projects(selected)
        if #sel_projs == 0 then return end
        
        for _, p in ipairs(sel_projs) do
          local ok, is_ongoing = toggle_ongoing(p)
          if ok then
            local status = is_ongoing and "󰑖 ongoing" or "󰷐 active"
            vim.notify(string.format("%s → %s", p.name, status), vim.log.levels.INFO)
          end
        end
        reopen()
      end,
      ["ctrl-h"] = function(selected)
        -- Toggle on-hold status (pause/defer project)
        local sel_projs = get_selected_projects(selected)
        if #sel_projs == 0 then return end
        
        for _, p in ipairs(sel_projs) do
          local ok, is_on_hold = toggle_on_hold(p)
          if ok then
            local status = is_on_hold and "⏸ on hold" or "󰷐 active"
            vim.notify(string.format("%s → %s", p.name, status), vim.log.levels.INFO)
          end
        end
        reopen()
      end,
      ["ctrl-a"] = function(selected)
        local sel_projs = get_selected_projects(selected)
        if #sel_projs == 0 then return end
        
        local names = {}
        for _, p in ipairs(sel_projs) do table.insert(names, p.name) end
        
        vim.ui.select({ "Yes, archive", "Cancel" }, {
          prompt = string.format("Archive %d project(s)? (%s)", #sel_projs, table.concat(names, ", ")),
        }, function(choice)
          if choice == "Yes, archive" then
            local count = 0
            for _, p in ipairs(sel_projs) do
              if archive_project(p) then count = count + 1 end
            end
            vim.notify(string.format("📦 Archived %d project(s)", count), vim.log.levels.INFO)
          end
          reopen()
        end)
      end,
      ["ctrl-x"] = function(selected)
        local sel_projs = get_selected_projects(selected)
        if #sel_projs == 0 then return end
        
        local names = {}
        for _, p in ipairs(sel_projs) do table.insert(names, p.name) end
        
        vim.ui.select({ "Yes, DELETE permanently", "Cancel" }, {
          prompt = string.format("DELETE %d project(s)? (%s) - THIS CANNOT BE UNDONE!", #sel_projs, table.concat(names, ", ")),
        }, function(choice)
          if choice == "Yes, DELETE permanently" then
            local count = 0
            for _, p in ipairs(sel_projs) do
              if vim.fn.delete(p.path) == 0 then count = count + 1 end
            end
            vim.notify(string.format("🗑 Deleted %d project(s)", count), vim.log.levels.INFO)
          end
          reopen()
        end)
      end,
      ["esc"] = function() end,
    },
    winopts = { height = 0.6, width = 0.8 },
  })
end

--- Pick all projects including ongoing areas and Reminders
--- Sorted: Active projects → Ongoing areas → Reminders
function M.pick_all_projects()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local projects_raw = M.projects_info()
  
  if #projects_raw == 0 then
    vim.notify("No projects found", vim.log.levels.INFO)
    return
  end
  
  -- Categorize projects
  local active = {}
  local on_hold = {}
  local ongoing = {}
  local reminders = {}
  
  for _, p in ipairs(projects_raw) do
    local is_reminders = p.file and p.file:match("/Reminders/")
    local is_ongoing = p.ongoing
    local is_on_hold = p.on_hold
    local has_tasks = p.tasks and p.tasks.total >= 1
    
    if is_reminders then
      table.insert(reminders, p)
    elseif is_on_hold then
      table.insert(on_hold, p)
    elseif is_ongoing then
      table.insert(ongoing, p)
    elseif has_tasks then
      table.insert(active, p)
    else
      -- Empty non-ongoing projects go with active (at end)
      table.insert(active, p)
    end
  end
  
  -- Build sorted list: active → on_hold → ongoing → reminders
  local items = {}
  local proj_map = {}
  
  local function add_projects(list, icon_override)
    for _, p in ipairs(list) do
      local tasks = p.tasks or {}
      local is_reminders = p.file and p.file:match("/Reminders/")
      local is_ongoing = p.ongoing
      local is_on_hold = p.on_hold
      
      -- Build prefix icon
      local icon = icon_override or capture_glyphs.project
      if not icon_override then
        if is_reminders then
          icon = "󰅖"  -- reminders icon
        elseif is_on_hold then
          icon = "⏸"   -- paused icon
        elseif is_ongoing then
          icon = "󰑖"  -- ongoing/refresh icon
        end
      end
      
      -- Task counts
      local task_info = string.format("(%d)", tasks.total or 0)
      
      local area_part = p.area and (" [" .. p.area .. "]") or ""
      local display = string.format("%s %s%s  %s", icon, p.title, area_part, task_info)
      
      table.insert(items, display)
      proj_map[display] = {
        name = p.title,
        path = p.file,
        area = p.area,
        project_id = p.project_id,
      }
    end
  end
  
  add_projects(active)
  add_projects(on_hold)
  add_projects(ongoing)
  add_projects(reminders)
  
  local function reopen()
    vim.schedule(function()
      -- Wait for file system to sync, then refresh daemon index
      vim.defer_fn(function()
        if M.is_running() then M.query("gtd", "refresh", nil) end
        -- Wait for daemon to complete re-indexing before reopening
        vim.defer_fn(function() M.pick_all_projects() end, 200)
      end, 50)
    end)
  end
  
  fzf.fzf_exec(items, {
    prompt = "All Projects ❯ ",
    fzf_opts = {
      ["--multi"] = true,
      ["--header"] = "󰷐 active → ⏸ hold → 󰑖 ongoing → 󰅖 reminders | ^O:ongoing ^H:hold",
    },
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local proj = proj_map[selected[1]]
          if proj and proj.path then
            vim.cmd("edit " .. vim.fn.fnameescape(proj.path))
          end
        end
      end,
      ["ctrl-o"] = function(selected)
        -- Toggle ongoing status
        if not selected or #selected == 0 then return end
        
        for _, sel in ipairs(selected) do
          local proj = proj_map[sel]
          if proj then
            local ok, is_ongoing = toggle_ongoing(proj)
            if ok then
              local status = is_ongoing and "󰑖 ongoing" or "󰷐 active"
              vim.notify(string.format("%s → %s", proj.name, status), vim.log.levels.INFO)
            end
          end
        end
        reopen()
      end,
      ["ctrl-h"] = function(selected)
        -- Toggle on-hold status
        if not selected or #selected == 0 then return end
        
        for _, sel in ipairs(selected) do
          local proj = proj_map[sel]
          if proj then
            local ok, is_on_hold = toggle_on_hold(proj)
            if ok then
              local status = is_on_hold and "⏸ on hold" or "󰷐 active"
              vim.notify(string.format("%s → %s", proj.name, status), vim.log.levels.INFO)
            end
          end
        end
        reopen()
      end,
      ["esc"] = function() end,
    },
    winopts = { height = 0.6, width = 0.8 },
  })
end

--- Areas of Responsibility picker (Horizon 2)
function M.pick_areas()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local areas_raw = M.areas()
  
  local items = {}
  local area_map = {}
  
  for _, a in ipairs(areas_raw) do
    local tasks = a.tasks or {}
    local by_state = tasks.by_state or {}
    
    -- Build status indicators
    local parts = {}
    if by_state.NEXT and by_state.NEXT > 0 then
      table.insert(parts, "󰁔" .. by_state.NEXT)
    end
    if by_state.TODO and by_state.TODO > 0 then
      table.insert(parts, "󰄲" .. by_state.TODO)
    end
    if by_state.WAITING and by_state.WAITING > 0 then
      table.insert(parts, "󰈸" .. by_state.WAITING)
    end
    if tasks.overdue and tasks.overdue > 0 then
      table.insert(parts, "⚠️" .. tasks.overdue)
    end
    if tasks.done_this_week and tasks.done_this_week > 0 then
      table.insert(parts, "✓" .. tasks.done_this_week)
    end
    
    local status = #parts > 0 and table.concat(parts, " ") or ""
    local proj_info = string.format("[%d projects]", a.project_count or 0)
    
    local display = string.format("󰠱 %s %s  %s", a.name, proj_info, status)
    
    table.insert(items, display)
    area_map[display] = {
      id = a.id,
      name = a.name,
      path = a.path,
      definition = a.definition,
      has_definition = a.has_definition,
    }
  end
  
  local function reopen()
    vim.schedule(function()
      vim.defer_fn(function()
        if M.is_running() then M.query("gtd", "refresh", nil) end
        vim.defer_fn(function() M.pick_areas() end, 200)
      end, 50)
    end)
  end
  
  fzf.fzf_exec(items, {
    prompt = "Areas ❯ ",
    fzf_opts = {
      ["--header"] = "Enter:definition | ^P:projects | ^T:tasks | ^R:review | ^N:new | ^A:archive",
    },
    actions = {
      ["default"] = function(selected)
        -- Open area definition
        if selected and selected[1] then
          local area = area_map[selected[1]]
          if area and area.path then
            local def_path = area.path .. "/_AREA.md"
            if vim.fn.filereadable(def_path) == 1 then
              vim.cmd("edit " .. vim.fn.fnameescape(def_path))
            else
              vim.notify("No _AREA.md found for " .. area.name, vim.log.levels.WARN)
            end
          end
        end
      end,
      ["ctrl-p"] = function(selected)
        -- Show projects in this area
        if selected and selected[1] then
          local area = area_map[selected[1]]
          if area then
            M.pick_tasks({
              filter_file = area.path,
              filter_state = "PROJECT",
              title = area.name .. " Projects",
            })
          end
        end
      end,
      ["ctrl-t"] = function(selected)
        -- Show all tasks in this area
        if selected and selected[1] then
          local area = area_map[selected[1]]
          if area then
            M.pick_tasks({
              filter_file = area.path,
              title = area.name .. " Tasks",
            })
          end
        end
      end,
      ["ctrl-r"] = function(selected)
        -- Area review view
        if selected and selected[1] then
          local area = area_map[selected[1]]
          if area then
            local info = M.area_info(area.id)
            if info then
              local lines = {
                "═══════════════════════════════════════════════",
                "󰠱 " .. info.name:upper(),
                "═══════════════════════════════════════════════",
              }
              
              if info.definition then
                table.insert(lines, "")
                table.insert(lines, info.definition.description or "")
                table.insert(lines, "")
                
                -- Tasks summary
                table.insert(lines, "Tasks:")
                local tasks = info.tasks or {}
                table.insert(lines, string.format("  Total active: %d", tasks.total or 0))
                if tasks.by_state then
                  for state, count in pairs(tasks.by_state) do
                    if state ~= "DONE" and state ~= "CANCELLED" and count > 0 then
                      table.insert(lines, string.format("  %s: %d", state, count))
                    end
                  end
                end
                if tasks.overdue and tasks.overdue > 0 then
                  table.insert(lines, string.format("  ⚠️ Overdue: %d", tasks.overdue))
                end
                if tasks.due_this_week and tasks.due_this_week > 0 then
                  table.insert(lines, string.format("  📅 Due this week: %d", tasks.due_this_week))
                end
                if tasks.done_this_week and tasks.done_this_week > 0 then
                  table.insert(lines, string.format("  ✓ Done this week: %d", tasks.done_this_week))
                end
                
                -- Review questions
                if info.definition.review_questions and #info.definition.review_questions > 0 then
                  table.insert(lines, "")
                  table.insert(lines, "Review Questions:")
                  for _, q in ipairs(info.definition.review_questions) do
                    table.insert(lines, "  □ " .. q)
                  end
                end
              end
              
              vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Area Review" })
            end
          end
        end
        reopen()
      end,
      ["ctrl-n"] = function()
        -- Create new area
        vim.schedule(function()
          vim.ui.input({ prompt = "󰠱 Area number (e.g., 60): " }, function(num)
            if not num or num == "" then return end
            
            vim.schedule(function()
              vim.ui.input({ prompt = "󰠱 Area name: " }, function(name)
                if not name or name == "" then return end
                
                local area_id = num .. "-" .. name:gsub("%s+", "-")
                local area_path = gtd_home() .. "/Areas/" .. area_id
                
                if vim.fn.isdirectory(area_path) == 1 then
                  vim.notify("Area already exists: " .. area_id, vim.log.levels.ERROR)
                  reopen()
                  return
                end
                
                -- Create area directory
                vim.fn.mkdir(area_path, "p")
                
                -- Create _AREA.md template
                local def_content = {
                  "# " .. name,
                  "",
                  "TODO: Define this area of responsibility.",
                  "",
                  "## Responsibilities",
                  "",
                  "- ",
                  "",
                  "## Standards to Maintain",
                  "",
                  "- ",
                  "",
                  "## Review Questions",
                  "",
                  "- [ ] ",
                }
                vim.fn.writefile(def_content, area_path .. "/_AREA.md")
                
                vim.notify("󰠱 Created area: " .. area_id, vim.log.levels.INFO)
                
                -- Open the definition for editing
                vim.cmd("edit " .. vim.fn.fnameescape(area_path .. "/_AREA.md"))
              end)
            end)
          end)
        end)
      end,
      ["ctrl-a"] = function(selected)
        -- Archive area (move to Archive/Areas/{area_id}_{timestamp})
        if not selected or not selected[1] then return end
        
        local area = area_map[selected[1]]
        if not area then return end
        
        vim.ui.select({ "Yes, archive " .. area.name, "Cancel" }, {
          prompt = "Archive area? All projects and tasks will be moved to Archive.",
        }, function(choice)
          if choice and choice:match("^Yes") then
            local timestamp = os.date("%Y%m%d_%H%M%S")
            local archive_base = gtd_home() .. "/Archive/Areas"
            local archive_path = archive_base .. "/" .. area.id .. "_" .. timestamp
            
            vim.fn.mkdir(archive_base, "p")
            
            -- Move the entire area directory
            local ok = vim.fn.rename(area.path, archive_path)
            if ok == 0 then
              vim.notify(string.format("📦 Archived %s → Archive/Areas/%s_%s", 
                area.name, area.id, timestamp), vim.log.levels.INFO)
            else
              vim.notify("Failed to archive area", vim.log.levels.ERROR)
            end
          end
          reopen()
        end)
      end,
      ["esc"] = function() end,
    },
    winopts = { height = 0.5, width = 0.7 },
  })
end

--- Pick a file and convert it to a project
function M.pick_convert_to_project()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local files = get_non_project_files()
  
  if #files == 0 then
    vim.notify("All .org files already have PROJECT headings", vim.log.levels.INFO)
    return
  end
  
  local items = {}
  local file_map = {}
  
  for _, f in ipairs(files) do
    local display = "󰈔 " .. f.name
    table.insert(items, display)
    file_map[display] = f
  end
  
  fzf.fzf_exec(items, {
    prompt = "Convert to Project ❯ ",
    fzf_opts = {
      ["--header"] = "󰌌 Select file to add PROJECT heading",
    },
    actions = {
      ["default"] = function(selected)
        if not selected or not selected[1] then return end
        local f = file_map[selected[1]]
        if not f then return end
        
        -- Get project name from filename or ask user
        local default_name = vim.fn.fnamemodify(f.path, ":t:r")
        -- Capitalize first letter
        default_name = default_name:gsub("^%l", string.upper):gsub("_", " ")
        
        vim.ui.input({ prompt = "Project name: ", default = default_name }, function(name)
          if not name or name == "" then return end
          
          local success, err = convert_file_to_project(f.path, name)
          if success then
            vim.notify("Converted to project: " .. name, vim.log.levels.INFO)
            -- Refresh daemon index
            if M.is_running() then M.query("gtd", "refresh", nil) end
            -- Open the file
            vim.cmd("edit " .. vim.fn.fnameescape(f.path))
          else
            vim.notify("Failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
          end
        end)
      end,
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
  
  vim.api.nvim_create_user_command("ChronosSomeday", function()
    M.pick_tasks({ state = "SOMEDAY", title = "SOMEDAY Tasks" })
  end, { desc = "Pick SOMEDAY tasks via Chronos" })
  
  vim.api.nvim_create_user_command("ChronosSearch", function(opts)
    M.pick_search(opts.args ~= "" and opts.args or nil)
  end, { desc = "Search tasks via Chronos", nargs = "?" })
  
  vim.api.nvim_create_user_command("ChronosArchive", function()
    M.pick_archive()
  end, { desc = "Manage archived tasks" })
  
  vim.api.nvim_create_user_command("ChronosAll", function()
    M.pick_all()
  end, { desc = "All tasks (NEXT/TODO/WAITING/SOMEDAY)" })
  
  vim.api.nvim_create_user_command("ChronosProjects", function()
    M.pick_projects()
  end, { desc = "Project picker (active projects)" })
  
  vim.api.nvim_create_user_command("ChronosAllProjects", function()
    M.pick_all_projects()
  end, { desc = "All projects (incl. ongoing & reminders)" })
  
  vim.api.nvim_create_user_command("ChronosConvertProject", function()
    M.pick_convert_to_project()
  end, { desc = "Convert file to project" })
  
  vim.api.nvim_create_user_command("ChronosAreas", function()
    M.pick_areas()
  end, { desc = "Areas of Responsibility (Horizon 2)" })
  
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
  
  vim.api.nvim_create_user_command("ChronosClipboard", function()
    M.capture_clipboard()
  end, { desc = "Capture from clipboard" })
  
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
  
  -- ┌─────────────────────────────────────────────────────────────┐
  -- │ TASK PICKERS: <leader>xt{key}                               │
  -- └─────────────────────────────────────────────────────────────┘
  map("n", prefix .. "ta", "<cmd>ChronosAll<cr>",
    vim.tbl_extend("force", opts, { desc = "Tasks: ALL" }))
  map("n", prefix .. "tn", "<cmd>ChronosNext<cr>",
    vim.tbl_extend("force", opts, { desc = "Tasks: NEXT" }))
  map("n", prefix .. "tt", "<cmd>ChronosTodo<cr>",
    vim.tbl_extend("force", opts, { desc = "Tasks: TODO" }))
  map("n", prefix .. "tw", "<cmd>ChronosWaiting<cr>",
    vim.tbl_extend("force", opts, { desc = "Tasks: WAITING" }))
  map("n", prefix .. "ts", "<cmd>ChronosSomeday<cr>",
    vim.tbl_extend("force", opts, { desc = "Tasks: SOMEDAY" }))
  
  -- ┌─────────────────────────────────────────────────────────────┐
  -- │ PROJECT PICKERS: <leader>xp{key}                            │
  -- └─────────────────────────────────────────────────────────────┘
  map("n", prefix .. "pp", "<cmd>ChronosProjects<cr>",
    vim.tbl_extend("force", opts, { desc = "Projects: active" }))
  map("n", prefix .. "pa", "<cmd>ChronosAllProjects<cr>",
    vim.tbl_extend("force", opts, { desc = "Projects: all (incl. ongoing)" }))
  map("n", prefix .. "pn", "<cmd>ChronosProject<cr>",
    vim.tbl_extend("force", opts, { desc = "Projects: new" }))
  map("n", prefix .. "pc", "<cmd>ChronosConvertProject<cr>",
    vim.tbl_extend("force", opts, { desc = "Projects: convert file" }))
  
  -- ┌─────────────────────────────────────────────────────────────┐
  -- │ AREAS (Horizon 2): <leader>xo{key}                          │
  -- └─────────────────────────────────────────────────────────────┘
  map("n", prefix .. "oa", "<cmd>ChronosAreas<cr>",
    vim.tbl_extend("force", opts, { desc = "Areas: all" }))
  
  -- ┌─────────────────────────────────────────────────────────────┐
  -- │ CAPTURE: <leader>xc{key}                                    │
  -- └─────────────────────────────────────────────────────────────┘
  map("n", prefix .. "cq", "<cmd>ChronosQuick<cr>",
    vim.tbl_extend("force", opts, { desc = "Capture: quick" }))
  map("n", prefix .. "cc", "<cmd>ChronosCapture<cr>",
    vim.tbl_extend("force", opts, { desc = "Capture: full" }))
  map("n", prefix .. "cv", "<cmd>ChronosClipboard<cr>",
    vim.tbl_extend("force", opts, { desc = "Capture: clipboard" }))
  
  -- ┌─────────────────────────────────────────────────────────────┐
  -- │ OTHER: <leader>x{key}                                       │
  -- └─────────────────────────────────────────────────────────────┘
  map("n", prefix .. "/", "<cmd>ChronosSearch<cr>",
    vim.tbl_extend("force", opts, { desc = "Search tasks" }))
  map("n", prefix .. "a", "<cmd>ChronosArchive<cr>",
    vim.tbl_extend("force", opts, { desc = "Archive management" }))
  map("n", prefix .. "r", "<cmd>ChronosRemindersSync<cr>",
    vim.tbl_extend("force", opts, { desc = "Reminders sync" }))
  map("n", prefix .. "s", "<cmd>ChronosStatus<cr>",
    vim.tbl_extend("force", opts, { desc = "Daemon status" }))
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

-- Context tags for GTD
local CONTEXT_TAGS = {
  "@computer",
  "@phone", 
  "@errands",
  "@home",
  "@office",
  "@anywhere",
  "@email",
  "@read",
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

-- ============================================================================
-- ZETTELKASTEN NOTE CREATION
-- ============================================================================

--- Create a Zettelkasten note for a task or project
---@param opts table Options: title, id, type ("task"|"project"), area, state
---@return string|nil path Path to created note, or nil on failure
local function create_zk_note(opts)
  local title = opts.title
  local id = opts.id or generate_task_id()
  local note_type = opts.type or "task"
  local state = opts.state or "TODO"
  
  -- Determine directory
  local dir
  if note_type == "project" then
    dir = zk_home() .. "/Projects"
  else
    dir = zk_home() .. "/GTD"
  end
  vim.fn.mkdir(dir, "p")
  
  -- Generate filename: {id}-{slug}.md
  local filename = id .. "-" .. slugify(title) .. ".md"
  local path = dir .. "/" .. filename
  
  -- Don't overwrite existing
  if vim.fn.filereadable(path) == 1 then
    return path
  end
  
  -- Build minimal note content with state heading for uniqueness
  local lines = {
    "# " .. title,
    "",
    "**ID:** " .. id,
    "**Created:** " .. os.date("%Y-%m-%d %H:%M"),
  }
  
  if note_type == "project" then
    table.insert(lines, "**Type:** PROJECT")
    if opts.area then
      table.insert(lines, "**Area:** " .. opts.area)
    end
    table.insert(lines, "")
    table.insert(lines, "## Outcome")
    table.insert(lines, "")
    table.insert(lines, "## Notes")
  else
    table.insert(lines, "**Type:** " .. state)
    if opts.area then
      table.insert(lines, "**Area:** " .. opts.area)
    end
    table.insert(lines, "")
    table.insert(lines, "## Notes")
  end
  
  if write_file(path, lines) then
    return path
  end
  return nil
end

--- Format ZK_NOTE property value
---@param path string Full path to note
---@return string Property value like [[file:path][name]]
local function format_zk_note_property(path)
  local name = vim.fn.fnamemodify(path, ":t")
  return string.format("[[file:%s][%s]]", path, name)
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
  table.insert(lines, ":ZK_LINK:   " .. id)
  table.insert(lines, ":CREATED:   " .. format_inactive_timestamp())
  if opts.zk_note then table.insert(lines, ":ZK_NOTE:   " .. format_zk_note_property(opts.zk_note)) end
  if opts.reference then table.insert(lines, ":REFERENCE: " .. opts.reference) end
  if opts.area then table.insert(lines, ":AREA:      " .. opts.area) end
  if opts.effort then table.insert(lines, ":Effort:    " .. opts.effort) end
  if opts.state == "WAITING" then
    if opts.waiting_for then table.insert(lines, ":WAITING_FOR: " .. opts.waiting_for) end
    table.insert(lines, ":WAITING_SINCE: " .. format_inactive_timestamp())
  end
  -- Extra properties (e.g., URL from clipboard capture)
  if opts.extra_props then
    for k, v in pairs(opts.extra_props) do
      table.insert(lines, string.format(":%s: %s", k, v))
    end
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
  table.insert(lines, ":ZK_LINK:   " .. id)
  table.insert(lines, ":CREATED:   " .. format_inactive_timestamp())
  if opts.ongoing then table.insert(lines, ":ONGOING:   t") end
  if opts.zk_note then table.insert(lines, ":ZK_NOTE:   " .. format_zk_note_property(opts.zk_note)) end
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

--- Capture from system clipboard
--- Cleans up clipboard content, detects URLs, allows editing before save
function M.capture_clipboard()
  -- Try system clipboard first, then unnamed register
  local clipboard = vim.fn.getreg("+")
  if not clipboard or clipboard == "" then
    clipboard = vim.fn.getreg('"')
  end
  
  if not clipboard or clipboard == "" then
    vim.notify("Clipboard is empty", vim.log.levels.WARN)
    return
  end
  
  -- Store original for URL detection
  local original = clipboard
  
  -- Clean up: collapse whitespace, trim, limit length
  local title = clipboard
    :gsub("\r\n", " ")      -- Windows line endings
    :gsub("\n", " ")        -- Unix line endings
    :gsub("\t", " ")        -- Tabs
    :gsub("%s+", " ")       -- Multiple spaces
    :gsub("^%s+", "")       -- Leading whitespace
    :gsub("%s+$", "")       -- Trailing whitespace
  
  -- Truncate very long clipboard content
  if #title > 120 then
    title = title:sub(1, 117) .. "..."
  end
  
  if title == "" then
    vim.notify("Clipboard contains only whitespace", vim.log.levels.WARN)
    return
  end
  
  -- Show what we captured and let user edit/confirm
  vim.ui.input({
    prompt = capture_glyphs.inbox .. " From clipboard: ",
    default = title,
  }, function(final_title)
    if not final_title or final_title == "" then return end
    
    -- Build task with optional URL property
    local props = {}
    local body_lines = {}
    
    -- If clipboard was a URL, add it as property and body note
    if original:match("^https?://[^%s]+$") then
      props.URL = original:gsub("%s+$", "")
      table.insert(body_lines, "")
      table.insert(body_lines, "Source: " .. original)
    end
    
    local lines = build_task_entry({
      title = final_title,
      state = "TODO",
      level = 1,
      extra_props = props,
    })
    
    -- Add body lines after :END:
    for _, line in ipairs(body_lines) do
      table.insert(lines, line)
    end
    
    ensure_file(inbox_path(), "Inbox")
    
    if append_to_file(inbox_path(), lines) then
      vim.notify(capture_glyphs.inbox .. " " .. final_title, vim.log.levels.INFO)
      -- Refresh daemon index
      if M.is_running() then M.query("gtd", "refresh", nil) end
    else
      vim.notify("Capture failed", vim.log.levels.ERROR)
    end
  end)
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
    capture_glyphs.area .. " Area...",
  }, {
    prompt = "To ❯ ",
    winopts = { height = 0.3, width = 0.35 },
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
        elseif sel[1]:match("Area") then
          -- Capture to area inbox (standalone task in area)
          vim.schedule(function()
            local areas = M.areas()
            if #areas == 0 then
              vim.notify("No areas found", vim.log.levels.WARN)
              data.path, data.level = inbox_path(), 1
              vim.schedule(function() M._task_step_schedule(data) end)
              return
            end
            
            local items = {}
            local area_map = {}
            for _, a in ipairs(areas) do
              local display = capture_glyphs.area .. " " .. a.name
              table.insert(items, display)
              area_map[display] = a
            end
            
            fzf.fzf_exec(items, {
              prompt = "Area ❯ ",
              winopts = { height = 0.4, width = 0.4 },
              actions = {
                ["default"] = function(area_sel)
                  if area_sel and area_sel[1] then
                    local area = area_map[area_sel[1]]
                    if area then
                      -- Use area Inbox.org (create if needed)
                      local area_inbox = area.path .. "/Inbox.org"
                      ensure_file(area_inbox, area.name .. " Inbox")
                      data.path = area_inbox
                      data.level = 1
                      data.area = area.id
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
  local fzf = require("fzf-lua")
  local today = os.date("%Y-%m-%d")
  
  if data.state == "WAITING" then
    -- WAITING: Ask for follow-up date and who/what we're waiting for
    vim.ui.input({ prompt = "Waiting for (person/thing): " }, function(wf)
      if not wf or wf == "" then
        vim.schedule(function() M._task_step_tags(data) end)
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
              prompt = string.format("Due [%s] (%s, '-' to skip): ", due_default, DATE_HINT)
            }, function(d)
              if d == "-" or d == "skip" then
                data.deadline = nil
              elseif d and d ~= "" then
                data.deadline = parse_smart_date(d, follow_up) or due_default
              else
                data.deadline = due_default
              end
              M._task_step_tags(data)
            end)
          end)
        end)
      end)
    end)
  elseif data.state == "SOMEDAY" then
    -- SOMEDAY: No dates needed
    vim.schedule(function() M._task_step_tags(data) end)
  else
    -- NEXT/TODO: First ask if dates are needed
    fzf.fzf_exec({
      capture_glyphs.calendar .. " Skip dates (add later)",
      capture_glyphs.calendar .. " Add dates now...",
    }, {
      prompt = "Dates ❯ ",
      winopts = { height = 0.25, width = 0.35 },
      actions = {
        ["default"] = function(sel)
          if not sel or not sel[1] or sel[1]:match("Skip") then
            -- No dates
            vim.schedule(function() M._task_step_tags(data) end)
            return
          end
          
          -- Add dates
          vim.schedule(function()
            vim.ui.input({
              prompt = string.format("Defer [%s] (%s, '-' to skip): ", today, DATE_HINT)
            }, function(s)
              if s ~= "-" and s ~= "skip" then
                data.scheduled = parse_smart_date(s) or today
              end
              
              vim.schedule(function()
                local due_default = future_date(DEFAULT_DUE_DAYS, data.scheduled or today)
                vim.ui.input({
                  prompt = string.format("Due [%s] (%s, '-' to skip): ", due_default, DATE_HINT)
                }, function(d)
                  if d ~= "-" and d ~= "skip" then
                    if d and d ~= "" then
                      data.deadline = parse_smart_date(d, data.scheduled) or due_default
                    else
                      data.deadline = due_default
                    end
                  end
                  M._task_step_tags(data)
                end)
              end)
            end)
          end)
        end,
      },
    })
  end
end

--- Task wizard: Context tags step (optional, multi-select)
function M._task_step_tags(data)
  local fzf = require("fzf-lua")
  
  -- Add "skip" option at top
  local items = { capture_glyphs.tag .. " (skip - no tags)" }
  for _, tag in ipairs(CONTEXT_TAGS) do
    table.insert(items, capture_glyphs.tag .. " " .. tag)
  end
  
  fzf.fzf_exec(items, {
    prompt = "Tags ❯ ",
    winopts = { height = 0.45, width = 0.35 },
    fzf_opts = { ["--multi"] = true },
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          local tags = {}
          for _, item in ipairs(selected) do
            local tag = item:match("@%w+")
            if tag then table.insert(tags, tag) end
          end
          if #tags > 0 then
            data.tags = tags
          end
        end
        vim.schedule(function() M._task_step_reference(data) end)
      end,
    },
  })
end

--- Task wizard: Reference step (optional file/URL)
function M._task_step_reference(data)
  vim.ui.input({
    prompt = capture_glyphs.reference .. " Reference (file/URL, empty to skip): "
  }, function(ref)
    if ref and ref ~= "" then
      -- Format as org link if it's a path
      if ref:match("^[~/]") or ref:match("^file:") then
        -- File path - wrap in org link syntax
        local expanded = vim.fn.expand(ref)
        data.reference = "[[file:" .. expanded .. "]]"
      elseif ref:match("^https?://") then
        -- URL - wrap in org link syntax
        data.reference = "[[" .. ref .. "]]"
      else
        -- Plain text reference
        data.reference = ref
      end
    end
    vim.schedule(function() M._task_step_zk(data) end)
  end)
end

--- Task wizard: ZK note step (optional)
function M._task_step_zk(data)
  local fzf = require("fzf-lua")
  
  fzf.fzf_exec({
    capture_glyphs.todo .. " Create task only",
    capture_glyphs.area .. " Create task + ZK note",
  }, {
    prompt = "Note ❯ ",
    winopts = { height = 0.25, width = 0.4 },
    actions = {
      ["default"] = function(sel)
        if sel and sel[1] and sel[1]:match("ZK note") then
          data.create_zk_note = true
        end
        vim.schedule(function() M._task_finalize(data) end)
      end,
    },
  })
end

--- Task wizard: Create task
function M._task_finalize(data)
  local task_id = generate_task_id()
  local zk_note_path = nil
  
  -- Create ZK note if requested (silently, don't open)
  if data.create_zk_note then
    zk_note_path = create_zk_note({
      title = data.title,
      id = task_id,
      type = "task",
      state = data.state,
      area = data.area,
    })
  end
  
  local lines = build_task_entry({
    title = data.title,
    state = data.state,
    level = data.level or 1,
    task_id = task_id,
    scheduled = data.scheduled,
    deadline = data.deadline,
    tags = data.tags,
    reference = data.reference,
    area = data.area,
    waiting_for = data.waiting_for,
    zk_note = zk_note_path,
  })
  
  local target = data.path or inbox_path()
  ensure_file(target, vim.fn.fnamemodify(target, ":t:r"))
  
  if append_to_file(target, lines) then
    local icon = capture_glyphs[data.state:lower()] or capture_glyphs.todo
    local dest = vim.fn.fnamemodify(target, ":t:r")
    local msg = string.format("%s %s → %s", icon, data.title, dest)
    if zk_note_path then
      msg = msg .. " +note"
    end
    vim.notify(msg, vim.log.levels.INFO)
    
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
    vim.schedule(function() M._project_step_zk(data) end)
  end)
end

--- Project wizard: ZK note step
function M._project_step_zk(data)
  local fzf = require("fzf-lua")
  
  fzf.fzf_exec({
    capture_glyphs.project .. " Create project only",
    capture_glyphs.area .. " Create project + ZK note",
  }, {
    prompt = "Note ❯ ",
    winopts = { height = 0.25, width = 0.4 },
    actions = {
      ["default"] = function(sel)
        if sel and sel[1] and sel[1]:match("ZK note") then
          data.create_zk_note = true
        end
        vim.schedule(function() M._project_step_type(data) end)
      end,
    },
  })
end

--- Project wizard: Project type (active/ongoing)
function M._project_step_type(data)
  local fzf = require("fzf-lua")
  
  fzf.fzf_exec({
    "󰷐 Active project (has defined end)",
    "󰑖 Ongoing area (continuous maintenance)",
  }, {
    prompt = "Type ❯ ",
    winopts = { height = 0.25, width = 0.5 },
    actions = {
      ["default"] = function(sel)
        if sel and sel[1] and sel[1]:match("Ongoing") then
          data.ongoing = true
        end
        vim.schedule(function() M._project_finalize(data) end)
      end,
    },
  })
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
  local zk_note_path = nil
  
  -- Create ZK note if requested (silently, don't open)
  if data.create_zk_note then
    zk_note_path = create_zk_note({
      title = data.name,
      id = id,
      type = "project",
      area = data.area,
    })
  end
  
  local file_lines = { "#+TITLE: " .. data.name, "#+FILETAGS: :project:", "" }
  
  local proj_lines = build_project_entry({
    title = data.name,
    task_id = id,
    area = data.area,
    outcome = data.outcome,
    zk_note = zk_note_path,
    ongoing = data.ongoing,
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
    local msg = capture_glyphs.project .. " " .. data.name .. " → " .. loc .. data.slug .. ".org"
    if zk_note_path then
      msg = msg .. " +note"
    end
    vim.notify(msg, vim.log.levels.INFO)
    
    -- Always open the project file
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    
    if M.is_running() then M.query("gtd", "refresh", nil) end
  else
    vim.notify("Failed to create project", vim.log.levels.ERROR)
  end
end

return M
