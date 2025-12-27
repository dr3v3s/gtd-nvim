-- ============================================================================
-- STATUS WORKFLOW V2
-- ============================================================================
-- Change task status with v2 patterns:
-- - On heading: change status directly
-- - Not on heading: pick task first, then change status
-- - SOMEDAY transitions: remove/add dates as appropriate
--
-- @module gtd-nvim.capture.workflows.status
-- @version 1.2.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.3.0"
M._UPDATED = "2025-12-27"

local fzf = require("fzf-lua")
local shared = require("gtd-nvim.gtd.shared")
local fzf_actions = require("gtd-nvim.capture.ui.fzf_actions")
local datepicker = require("gtd-nvim.capture.ui.datepicker")

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local STATUSES = {
  { state = "NEXT",      icon = "󰁔", color = "green",  desc = "Next action" },
  { state = "TODO",      icon = "󰄲", color = "blue",   desc = "To do" },
  { state = "WAITING",   icon = "󰈸", color = "yellow", desc = "Waiting for" },
  { state = "SOMEDAY",   icon = "󰋚", color = "gray",   desc = "Someday/maybe" },
  { state = "DONE",      icon = "󰄳", color = "dim",    desc = "Completed" },
  { state = "CANCELLED", icon = "󰜺", color = "dim",    desc = "Cancelled" },
}

local STATUS_LOOKUP = {}
for _, s in ipairs(STATUSES) do
  STATUS_LOOKUP[s.state] = s
end

-- States that should have dates
local ACTIVE_STATES = { NEXT = true, TODO = true, WAITING = true }

local ANSI = {
  green  = "\27[32m",
  blue   = "\27[34m",
  yellow = "\27[33m",
  gray   = "\27[90m",
  dim    = "\27[2m",
  reset  = "\27[0m",
}

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Check if current line is an org heading with status
---@return table|nil { bufnr, row, line, state, title, file }
local function get_heading_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  
  -- Match org heading: "* STATE Title"
  local stars, state, title = line:match("^(%*+)%s+(%u+)%s+(.*)")
  if stars and state and STATUS_LOOKUP[state] then
    return {
      bufnr = bufnr,
      row = row,
      line = line,
      state = state,
      title = title,
      file = vim.api.nvim_buf_get_name(bufnr),
      lnum = row + 1,
    }
  end
  
  return nil
end

--- Replace status in a heading line
---@param file string File path
---@param lnum number Line number (1-indexed)
---@param old_state string Current state
---@param new_state string New state
---@return boolean success
local function replace_status(file, lnum, old_state, new_state)
  local lines = vim.fn.readfile(file)
  if not lines or #lines < lnum then 
    return false 
  end
  
  local line = lines[lnum]
  local new_line = line:gsub("^(%*+%s+)" .. old_state, "%1" .. new_state, 1)
  
  if new_line == line then 
    return false 
  end
  
  lines[lnum] = new_line
  vim.fn.writefile(lines, file)
  
  -- Reload buffer if open
  local bufnr = vim.fn.bufnr(file)
  if bufnr ~= -1 then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("edit!")
    end)
  end
  
  return true
end

--- Remove SCHEDULED and DEADLINE lines from a task
---@param file string File path
---@param heading_lnum number Line number of the heading (1-indexed)
---@return number removed_count
local function remove_dates(file, heading_lnum)
  local lines = vim.fn.readfile(file)
  if not lines or #lines < heading_lnum then return 0 end
  
  local removed = 0
  local i = heading_lnum + 1  -- Start after heading
  
  -- Look at next few lines for SCHEDULED/DEADLINE (before PROPERTIES or body)
  while i <= #lines and i <= heading_lnum + 5 do
    local line = lines[i]
    
    -- Stop if we hit properties drawer or another heading
    if line:match("^:PROPERTIES:") or line:match("^%*+ ") then
      break
    end
    
    -- Check for SCHEDULED or DEADLINE
    if line:match("^%s*SCHEDULED:") or line:match("^%s*DEADLINE:") then
      table.remove(lines, i)
      removed = removed + 1
      -- Don't increment i since we removed a line
    else
      i = i + 1
    end
  end
  
  if removed > 0 then
    vim.fn.writefile(lines, file)
    
    -- Reload buffer if open
    local bufnr = vim.fn.bufnr(file)
    if bufnr ~= -1 then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit!")
      end)
    end
  end
  
  return removed
end

--- Insert SCHEDULED/DEADLINE lines after heading
---@param file string File path
---@param heading_lnum number Line number of the heading (1-indexed)
---@param scheduled string|nil SCHEDULED date (YYYY-MM-DD)
---@param deadline string|nil DEADLINE date (YYYY-MM-DD)
---@return boolean success
local function insert_dates(file, heading_lnum, scheduled, deadline)
  if not scheduled and not deadline then return true end
  
  local lines = vim.fn.readfile(file)
  if not lines or #lines < heading_lnum then return false end
  
  -- Build date line(s)
  local date_lines = {}
  
  -- Get day name for the date
  local function get_day_name(date_str)
    local y, m, d = date_str:match("(%d+)-(%d+)-(%d+)")
    if y then
      local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
      return os.date("%a", t)
    end
    return ""
  end
  
  if scheduled then
    local day = get_day_name(scheduled)
    table.insert(date_lines, string.format("SCHEDULED: <%s %s>", scheduled, day))
  end
  
  if deadline then
    local day = get_day_name(deadline)
    -- If we already have SCHEDULED, append DEADLINE to same line
    if #date_lines > 0 then
      date_lines[1] = date_lines[1] .. string.format(" DEADLINE: <%s %s>", deadline, day)
    else
      table.insert(date_lines, string.format("DEADLINE: <%s %s>", deadline, day))
    end
  end
  
  -- Insert after heading line
  for i, date_line in ipairs(date_lines) do
    table.insert(lines, heading_lnum + i, date_line)
  end
  
  vim.fn.writefile(lines, file)
  
  -- Reload buffer if open
  local bufnr = vim.fn.bufnr(file)
  if bufnr ~= -1 then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("edit!")
    end)
  end
  
  return true
end

--- Build task picker items (reuse pattern from clarify)
---@return table items, table lookup
local function build_task_picker_items()
  local chronos = require("gtd-nvim.gtd.chronos")
  local items = {}
  local lookup = {}
  
  -- Get tasks from daemon
  local data = chronos.query_daemon("gtd", "tasks", {})
  if not data or not data.tasks then
    return items, lookup
  end
  
  -- Group by source
  local inbox = {}
  local by_area = {}
  local by_project = {}
  
  for _, task in ipairs(data.tasks) do
    if task.state and task.state ~= "DONE" and task.state ~= "CANCELLED" then
      local file = task.file or ""
      if file:match("/Inbox%.org$") then
        table.insert(inbox, task)
      elseif file:match("/Areas/") then
        local area = file:match("/Areas/([^/]+)/")
        by_area[area] = by_area[area] or {}
        table.insert(by_area[area], task)
      else
        local proj = file:match("/Projects/([^/]+)%.org$") or file:match("([^/]+)%.org$")
        by_project[proj] = by_project[proj] or {}
        table.insert(by_project[proj], task)
      end
    end
  end
  
  local function add_task(task)
    local s = STATUS_LOOKUP[task.state] or { icon = "•", color = "reset" }
    local color = ANSI[s.color] or ANSI.reset
    local line = string.format("%s%s %s%s", color, s.icon, task.title or "Untitled", ANSI.reset)
    table.insert(items, line)
    lookup[line] = {
      file = task.file,
      lnum = task.line or 1,
      state = task.state,
      title = task.title,
      task = task,
    }
  end
  
  local function add_header(text)
    table.insert(items, "━━━ " .. text .. " ━━━")
  end
  
  -- Inbox first
  if #inbox > 0 then
    add_header("Inbox")
    for _, t in ipairs(inbox) do add_task(t) end
  end
  
  -- Areas
  local area_names = vim.tbl_keys(by_area)
  table.sort(area_names)
  for _, area in ipairs(area_names) do
    add_header(area)
    for _, t in ipairs(by_area[area]) do add_task(t) end
  end
  
  -- Projects
  local proj_names = vim.tbl_keys(by_project)
  table.sort(proj_names)
  for _, proj in ipairs(proj_names) do
    add_header(proj)
    for _, t in ipairs(by_project[proj]) do add_task(t) end
  end
  
  return items, lookup
end

-- ============================================================================
-- DATE PROMPT
-- ============================================================================

--- Prompt for dates when activating a SOMEDAY task
---@param task table { file, lnum, state, title }
---@param new_state string The new state being set
---@param on_complete function|nil Callback after dates are set
local function prompt_for_dates(task, new_state, on_complete)
  datepicker.open({
    on_complete = function(defer_date, due_date, defer_time, due_time, create_event)
      if defer_date or due_date then
        -- Remove any existing dates first
        remove_dates(task.file, task.lnum)
        -- Insert new dates
        insert_dates(task.file, task.lnum, defer_date, due_date)
        
        local date_info = {}
        if defer_date then table.insert(date_info, "SCHEDULED: " .. defer_date) end
        if due_date then table.insert(date_info, "DEADLINE: " .. due_date) end
        vim.notify("Added: " .. table.concat(date_info, ", "), vim.log.levels.INFO)
      end
      
      if on_complete then on_complete() end
    end,
  })
end

-- ============================================================================
-- STATUS PICKER
-- ============================================================================

--- Show status picker for a task
---@param task table { file, lnum, state, title }
---@param on_complete function|nil Callback after status change
local function show_status_picker(task, on_complete)
  local current = task.state or "TODO"
  local current_info = STATUS_LOOKUP[current] or { icon = "•" }
  
  -- Build choices (exclude current)
  local items = {}
  local lookup = {}  -- Maps display string (without ANSI) to state
  
  for _, s in ipairs(STATUSES) do
    if s.state ~= current then
      local color = ANSI[s.color] or ANSI.reset
      local line = string.format("%s%s  %-10s  %s%s", color, s.icon, s.state, s.desc, ANSI.reset)
      table.insert(items, line)
      -- Create lookup key without ANSI codes
      local plain = string.format("%s  %-10s  %s", s.icon, s.state, s.desc)
      lookup[plain] = s.state
    end
  end
  
  fzf.fzf_exec(items, {
    prompt = "Status ❯ ",
    fzf_opts = {
      ["--ansi"] = true,
      ["--no-info"] = true,
      ["--header"] = string.format("Current: %s %s │ Task: %s",
        current_info.icon, current, task.title or ""),
      ["--header-first"] = true,
    },
    winopts = {
      height = 0.35,
      width = 0.50,
      title = " 󰔡 Change Status ",
      title_pos = "center",
    },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        
        -- fzf strips ANSI, so sel[1] is the plain text
        local new_state = lookup[sel[1]]
        
        if new_state then
          vim.schedule(function()
            -- First, change the status
            if not replace_status(task.file, task.lnum, current, new_state) then
              vim.notify("Failed to change status", vim.log.levels.ERROR)
              return
            end
            
            local new_info = STATUS_LOOKUP[new_state] or { icon = "•" }
            vim.notify(string.format("%s %s → %s %s",
              current_info.icon, current,
              new_info.icon, new_state
            ), vim.log.levels.INFO)
            
            -- Handle SOMEDAY transitions
            if new_state == "SOMEDAY" then
              -- Moving TO SOMEDAY: remove dates
              local removed = remove_dates(task.file, task.lnum)
              if removed > 0 then
                vim.notify("Removed " .. removed .. " date(s) for SOMEDAY", vim.log.levels.INFO)
              end
              if on_complete then on_complete(new_state) end
              
            elseif current == "SOMEDAY" and ACTIVE_STATES[new_state] then
              -- Moving FROM SOMEDAY to active state: prompt for dates
              prompt_for_dates(task, new_state, function()
                if on_complete then on_complete(new_state) end
              end)
              
            else
              -- Normal transition
              if on_complete then on_complete(new_state) end
            end
          end)
        end
      end,
    },
  })
end

-- ============================================================================
-- MAIN ENTRY POINT
-- ============================================================================

--- Change status - unified entry point
--- On org heading: change directly
--- Not on heading: pick task first
function M.change_status()
  -- Check if on heading
  local heading = get_heading_at_cursor()
  
  if heading then
    -- On heading - show status picker directly
    show_status_picker(heading)
    return
  end
  
  -- Not on heading - show task picker first
  local items, lookup = build_task_picker_items()
  
  if #items == 0 then
    vim.notify("No tasks found", vim.log.levels.INFO)
    return
  end
  
  fzf.fzf_exec(items, {
    prompt = "Pick task ❯ ",
    fzf_opts = {
      ["--ansi"] = true,
      ["--no-info"] = true,
      ["--header"] = "Enter=change status │ C-e=edit │ C-r=refile │ C-d=delete",
      ["--header-first"] = true,
    },
    winopts = {
      height = 0.70,
      width = 0.80,
      title = " 󰔡 Change Status ",
      title_pos = "center",
    },
    actions = fzf_actions.with_back(
      vim.tbl_extend("force", fzf_actions.task_actions(lookup), {
        ["default"] = function(sel)
          if not sel or not sel[1] then return end
          if sel[1]:match("^━━━") then return end
          
          local task = lookup[sel[1]]
          if task then
            vim.schedule(function()
              show_status_picker(task, function(_)
                -- After status change, could return to picker
              end)
            end)
          end
        end,
      }),
      M.change_status  -- Back returns to task picker
    ),
  })
end

return M
