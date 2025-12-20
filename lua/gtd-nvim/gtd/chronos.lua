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

M._VERSION = "0.10.1"
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
      if M.is_running() then M.query("gtd", "refresh", nil) end
      -- Small delay to let daemon refresh
      vim.defer_fn(function() M.pick_tasks(opts) end, 100)
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
      vim.defer_fn(function() M.pick_archive() end, 100)
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
      if M.is_running() then M.query("gtd", "refresh", nil) end
      vim.defer_fn(function() M.pick_all() end, 100)
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

--- Project picker with actions
function M.pick_projects()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  local projects = get_projects()
  
  if #projects == 0 then
    vim.notify("No projects found", vim.log.levels.INFO)
    return
  end
  
  -- Get task counts per project from daemon
  local task_counts = {}
  local all_tasks = {}
  for _, state in ipairs({"NEXT", "TODO", "WAITING", "SOMEDAY"}) do
    for _, t in ipairs(M.tasks(state, 500) or {}) do
      table.insert(all_tasks, t)
    end
  end
  for _, t in ipairs(all_tasks) do
    local proj = t.project or vim.fn.fnamemodify(t.file or "", ":t:r")
    task_counts[proj] = (task_counts[proj] or 0) + 1
  end
  
  local items = {}
  local proj_map = {}
  
  for _, p in ipairs(projects) do
    local count = task_counts[p.name] or 0
    local area_part = p.area and (" [" .. p.area .. "]") or ""
    local display = string.format("%s %s%s  (%d tasks)", capture_glyphs.project, p.name, area_part, count)
    table.insert(items, display)
    proj_map[display] = p
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
      if M.is_running() then M.query("gtd", "refresh", nil) end
      vim.defer_fn(function() M.pick_projects() end, 100)
    end)
  end
  
  fzf.fzf_exec(items, {
    prompt = "Projects ❯ ",
    fzf_opts = {
      ["--multi"] = true,
      ["--header"] = "󰌌 Enter:open | ^T:tasks | ^N:new task | ^A:archive | ^X:delete",
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
            -- Filter tasks by project file
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
  end, { desc = "Project picker" })
  
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
    vim.tbl_extend("force", opts, { desc = "Projects: list" }))
  map("n", prefix .. "pn", "<cmd>ChronosProject<cr>",
    vim.tbl_extend("force", opts, { desc = "Projects: new" }))
  
  -- ┌─────────────────────────────────────────────────────────────┐
  -- │ CAPTURE: <leader>xc{key}                                    │
  -- └─────────────────────────────────────────────────────────────┘
  map("n", prefix .. "cq", "<cmd>ChronosQuick<cr>",
    vim.tbl_extend("force", opts, { desc = "Capture: quick" }))
  map("n", prefix .. "cc", "<cmd>ChronosCapture<cr>",
    vim.tbl_extend("force", opts, { desc = "Capture: full" }))
  
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
              prompt = string.format("Due [%s] (%s): ", due_default, DATE_HINT)
            }, function(d)
              data.deadline = parse_smart_date(d, follow_up) or due_default
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
          M._task_step_tags(data)
        end)
      end)
    end)
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
