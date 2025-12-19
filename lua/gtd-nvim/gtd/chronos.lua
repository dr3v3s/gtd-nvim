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

M._VERSION = "0.1.0"
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
end

--- Setup keymaps (optional, call separately)
---@param prefix string|nil Keymap prefix (default: <leader>C)
function M.setup_keymaps(prefix)
  prefix = prefix or "<leader>C"
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

return M
