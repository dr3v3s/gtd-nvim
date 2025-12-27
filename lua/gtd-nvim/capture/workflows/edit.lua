-- ============================================================================
-- WORKFLOW: EDIT
-- ============================================================================
-- Edit existing task using capture steps.
-- Parses task at cursor, runs through steps, saves back.
--
-- Flow: (pick field) → Edit that field → Save
-- Or:   Full edit: Outcome → Title → State → Tags → Comms → Dates → Save
--
-- @module gtd-nvim.capture.workflows.edit
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

local Object = require("gtd-nvim.capture.model.object")

-- ============================================================================
-- TASK PARSER
-- ============================================================================

--- Parse task at cursor into OrgObject
---@return table|nil OrgObject
---@return string|nil error
function M.parse_task_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local filepath = vim.api.nvim_buf_get_name(buf)
  
  -- Find heading line (search upward)
  local h_start = lnum
  while h_start >= 1 do
    if lines[h_start] and lines[h_start]:match("^%*+%s") then
      break
    end
    h_start = h_start - 1
  end
  
  if h_start < 1 or not lines[h_start]:match("^%*+%s") then
    return nil, "Not on an org heading"
  end
  
  local heading = lines[h_start]
  local stars = heading:match("^(%*+)")
  local level = #stars
  
  -- Find heading end
  local h_end = h_start
  for i = h_start + 1, #lines do
    local line = lines[i]
    local next_stars = line:match("^(%*+)")
    if next_stars and #next_stars <= level then
      break
    end
    h_end = i
  end
  
  -- Parse heading: state, title, tags
  local rest = heading:sub(#stars + 1)
  local state = rest:match("^%s+([A-Z]+)%s") or ""
  local title = rest:gsub("^%s+[A-Z]+%s+", ""):gsub("%s*:.*:%s*$", "")
  title = vim.trim(title)
  
  -- Extract inline tags
  local tag_str = heading:match(":([%w@:_-]+):%s*$") or ""
  local tags = {}
  for tag in tag_str:gmatch("[^:]+") do
    table.insert(tags, tag)
  end
  
  -- Parse properties
  local props = {}
  local props_start, props_end = nil, nil
  for i = h_start + 1, h_end do
    local line = lines[i]
    if line:match("^%s*:PROPERTIES:%s*$") then
      props_start = i
    elseif props_start and line:match("^%s*:END:%s*$") then
      props_end = i
      break
    elseif props_start and not props_end then
      local key, val = line:match("^%s*:([^:]+):%s*(.*)$")
      if key then
        props[key:upper()] = vim.trim(val)
      end
    end
  end
  
  -- Extract dates and times
  local scheduled, deadline = nil, nil
  local scheduled_time, deadline_time = nil, nil
  for i = h_start, math.min(h_start + 5, h_end) do
    local line = lines[i] or ""
    local sched = line:match("SCHEDULED:%s*<([^>]+)>")
    local dead = line:match("DEADLINE:%s*<([^>]+)>")
    if sched then 
      scheduled = sched:match("^[%d%-]+")
      scheduled_time = sched:match("(%d%d:%d%d)")
    end
    if dead then 
      deadline = dead:match("^[%d%-]+")
      deadline_time = dead:match("(%d%d:%d%d)")
    end
  end
  
  -- Extract body (content after properties)
  local body_start = (props_end or h_start) + 1
  local body_lines = {}
  for i = body_start, h_end do
    local line = lines[i]
    if not line:match("^%s*SCHEDULED:") and not line:match("^%s*DEADLINE:") then
      table.insert(body_lines, line)
    end
  end
  local body = table.concat(body_lines, "\n")
  
  -- Determine type
  local obj_type = state == "PROJECT" and Object.TYPE.PROJECT or Object.TYPE.TASK
  
  -- Build OrgObject
  local obj = Object.new(obj_type, {
    id = props.TASK_ID or props.ID,
    title = title,
    state = state,
    tags = tags,
    scheduled = scheduled,
    deadline = deadline,
    scheduled_time = scheduled_time,
    deadline_time = deadline_time,
    outcome = props.OUTCOME,
    area = props.AREA,
    focus = props.FOCUS == "t",
    body = body,
    properties = props,
    
    -- Source info for saving back
    _source = {
      file = filepath,
      line = h_start,
      end_line = h_end,
      level = level,
      props_start = props_start,
      props_end = props_end,
    },
    _mode = Object.MODE.EDIT,
  })
  
  -- Contact info if present
  if props.CONTACT_ID or props.CONTACT_NAME then
    obj.contact = {
      id = props.CONTACT_ID,
      name = props.CONTACT_NAME,
      phone = props.PHONE,
      email = props.EMAIL,
    }
  end
  
  -- ZK note if present
  if props.ZK_NOTE then
    local zk_path = props.ZK_NOTE:match("%[%[file:([^]]+)%]%]") or props.ZK_NOTE
    obj.zk_note = zk_path
  end
  
  -- Waiting properties
  if state == "WAITING" then
    obj.waiting_for = props.WAITING_FOR
    obj.waiting_since = props.WAITING_SINCE
    obj.waiting_context = props.WAITING_CONTEXT
  end
  
  return obj, nil
end

-- ============================================================================
-- SAVE EDITED TASK
-- ============================================================================

--- Save edited OrgObject back to file
---@param obj table OrgObject with _source
---@return boolean success
---@return string|nil error
function M.save_task(obj)
  if not obj._source then
    return false, "No source info - cannot save"
  end
  
  local Writer = require("gtd-nvim.capture.model.writer")
  local source = obj._source
  
  -- Read current file
  local lines = vim.fn.readfile(source.file)
  if not lines then
    return false, "Could not read file"
  end
  
  -- Generate new task lines
  obj.level = source.level
  local new_lines = Writer.to_lines(obj, { include_children = false })
  
  -- Replace old lines with new
  local before = {}
  for i = 1, source.line - 1 do
    table.insert(before, lines[i])
  end
  
  local after = {}
  for i = source.end_line + 1, #lines do
    table.insert(after, lines[i])
  end
  
  -- Combine
  local result = {}
  vim.list_extend(result, before)
  vim.list_extend(result, new_lines)
  vim.list_extend(result, after)
  
  -- Write back
  local ok = vim.fn.writefile(result, source.file)
  if ok ~= 0 then
    return false, "Failed to write file"
  end
  
  -- Reload buffer if open
  local bufnr = vim.fn.bufnr(source.file)
  if bufnr ~= -1 then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("edit!")
    end)
  end
  
  return true, nil
end

-- ============================================================================
-- EDIT WORKFLOWS
-- ============================================================================

--- Full edit (all fields)
M.definition = {
  name = "edit",
  description = "Edit existing task with all fields",
  object_type = Object.TYPE.TASK,
  
  steps = {
    "outcome",
    "title",
    "state",
    "area",
    "tags",
    "comms",
    "schedule",
  },
  
  opts = {
    -- Pre-fill from existing values
    always_ask_title = true,
    always_ask = true,
  },
  
  on_complete = function(obj)
    local success, err = M.save_task(obj)
    if success then
      vim.notify("󰄲 Task updated: " .. obj.title, vim.log.levels.INFO)
      
      -- Refresh daemon
      local chronos_ok, chronos = pcall(require, "gtd-nvim.gtd.chronos")
      if chronos_ok and chronos.is_running and chronos.is_running() then
        chronos.query("gtd", "refresh", nil)
      end
    else
      vim.notify("Failed to save: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end,
}

-- ============================================================================
-- QUICK EDIT (pick single field)
-- ============================================================================

--- Quick edit - pick which field to edit
---@param obj table|nil OrgObject (if nil, parses from cursor or shows picker)
function M.quick_edit(obj)
  if not obj then
    -- Check if cursor is on an org heading
    local line = vim.api.nvim_get_current_line()
    if not line:match("^%*+%s+") then
      -- NOT on a heading - show task picker
      vim.schedule(function()
        M._pick_task_to_edit()
      end)
      return
    end
    
    -- On a heading - parse it
    local parsed, err = M.parse_task_at_cursor()
    if not parsed then
      vim.notify(err or "Could not parse task", vim.log.levels.ERROR)
      return
    end
    obj = parsed
  end
  
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    vim.notify("fzf-lua required for quick edit", vim.log.levels.ERROR)
    return
  end
  
  -- Build field options
  local defer_str = obj.scheduled or "(none)"
  if obj.scheduled and obj.scheduled_time then
    defer_str = obj.scheduled .. " " .. obj.scheduled_time
  end
  local due_str = obj.deadline or "(none)"
  if obj.deadline and obj.deadline_time then
    due_str = obj.deadline .. " " .. obj.deadline_time
  end
  
  -- Focus status (for projects)
  local is_project = obj.state == "PROJECT" or obj.type == "project"
  local focus_icon = obj.focus and "󰓎" or "󰓏"
  local focus_str = obj.focus and "Yes" or "No"
  
  local items = {
    string.format("󰏫 Title: %s", obj.title or ""),
    string.format("󰆤 Outcome: %s", obj.outcome or "(none)"),
    string.format(" State: %s", obj.state or ""),
    string.format("󰉋 Area: %s", obj.area or "(none)"),
    string.format(" Tags: %s", obj.tags and #obj.tags > 0 and table.concat(obj.tags, ", ") or "(none)"),
    string.format("󰃰 Defer: %s", defer_str),
    string.format("󰃰 Due: %s", due_str),
  }
  
  -- Add focus option for projects
  if is_project then
    table.insert(items, string.format("%s Focus Area: %s", focus_icon, focus_str))
  end
  
  table.insert(items, "───────────────────────────────────")
  table.insert(items, "󰷐 Edit ALL fields")
  table.insert(items, "󰜺 Cancel")
  
  fzf.fzf_exec(items, {
    prompt = "Edit field ❯ ",
    winopts = { height = 0.55, width = 0.6 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local choice = sel[1]
        
        if choice:match("Cancel") then
          return
        elseif choice:match("Edit ALL") then
          vim.schedule(function()
            M.full_edit(obj)
          end)
        elseif choice:match("Title") then
          vim.schedule(function() M._edit_field(obj, "title") end)
        elseif choice:match("Outcome") then
          vim.schedule(function() M._edit_field(obj, "outcome") end)
        elseif choice:match("State") then
          vim.schedule(function() M._edit_field(obj, "state") end)
        elseif choice:match("Area") then
          vim.schedule(function() M._edit_field(obj, "area") end)
        elseif choice:match("Tags") then
          vim.schedule(function() M._edit_field(obj, "tags") end)
        elseif choice:match("Defer") or choice:match("Due") then
          vim.schedule(function() M._edit_field(obj, "schedule") end)
        elseif choice:match("Focus Area") then
          vim.schedule(function() M._edit_field(obj, "focus") end)
        end
      end,
    },
  })
end

--- Edit a single field
function M._edit_field(obj, field)
  local step_ok, step = pcall(require, "gtd-nvim.capture.steps." .. field)
  if not step_ok then
    vim.notify("Unknown field: " .. field, vim.log.levels.ERROR)
    return
  end
  
  step.run(obj, { always_ask = true }, function(updated_obj)
    if not updated_obj then
      vim.notify("Edit cancelled", vim.log.levels.INFO)
      return
    end
    
    local success, err = M.save_task(updated_obj)
    if success then
      vim.notify("󰄲 Updated: " .. field, vim.log.levels.INFO)
    else
      vim.notify("Failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end)
end

--- Full edit using workflow engine
function M.full_edit(obj)
  if not obj then
    -- Check if cursor is on an org heading
    local line = vim.api.nvim_get_current_line()
    if not line:match("^%*+%s+") then
      -- NOT on a heading - show task picker
      vim.schedule(function()
        M._pick_task_to_edit("full")
      end)
      return
    end
    
    local parsed, err = M.parse_task_at_cursor()
    if not parsed then
      vim.notify(err or "Could not parse task", vim.log.levels.ERROR)
      return
    end
    obj = parsed
  end
  
  local Engine = require("gtd-nvim.capture.engine")
  Engine.run("edit", { 
    mode = Object.MODE.EDIT, 
    object = obj,
  })
end

-- ============================================================================
-- TASK PICKER (when not on a heading)
-- ============================================================================

--- Determine sort group for a file path
-- Returns: 1 = Inbox, 2-99 = Areas (sorted), 100 = Projects, 999 = Other
local function get_sort_group(filepath, gtd_home)
  local fname = vim.fn.fnamemodify(filepath, ":t")
  
  -- Inbox first
  if fname == "Inbox.org" then
    return 1, "00-Inbox"
  end
  
  -- Areas (extract area name)
  local area = filepath:match("/Areas/([^/]+)/")
  if area then
    return 2, area
  end
  
  -- Standalone projects
  if filepath:match("/Projects/") then
    return 100, "Projects"
  end
  
  -- Everything else
  return 999, "Other"
end

--- Pick a task to edit from all tasks
---@param mode string|nil "quick" or "full" (default: "quick")
function M._pick_task_to_edit(mode)
  mode = mode or "quick"
  
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    vim.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  -- Get GTD path
  local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  local gtd_home = shared_ok and shared.gtd_home and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
  
  -- Find all org files and grep for headings
  local cmd = string.format(
    "grep -rn '^\\*\\+\\s\\+\\(NEXT\\|TODO\\|WAITING\\|SOMEDAY\\|PROJECT\\)' %s --include='*.org' 2>/dev/null",
    gtd_home
  )
  
  local handle = io.popen(cmd)
  if not handle then
    vim.notify("Could not search tasks", vim.log.levels.ERROR)
    return
  end
  
  local result = handle:read("*a")
  handle:close()
  
  local items = {}
  local state_icons = { 
    NEXT = "󱥦", TODO = "󰄲", WAITING = "", SOMEDAY = "󰋚", PROJECT = "󰷐" 
  }
  
  for line in result:gmatch("[^\n]+") do
    local file, lnum, content = line:match("^([^:]+):(%d+):(.+)$")
    if file and lnum and content then
      local state = content:match("^%*+%s+(%u+)")
      local title = content:gsub("^%*+%s+%u+%s+", ""):gsub("%s*:.*:%s*$", "")
      local tags = content:match(":([%w@:_-]+):%s*$") or ""
      
      local sort_group, group_name = get_sort_group(file, gtd_home)
      
      table.insert(items, {
        file = file,
        lnum = tonumber(lnum),
        state = state,
        title = vim.trim(title),
        tags = tags,
        sort_group = sort_group,
        group_name = group_name,
      })
    end
  end
  
  -- Sort: by group, then by state within group
  local state_order = { NEXT = 1, TODO = 2, WAITING = 3, PROJECT = 4, SOMEDAY = 5 }
  table.sort(items, function(a, b)
    if a.sort_group ~= b.sort_group then
      return a.sort_group < b.sort_group
    end
    if a.group_name ~= b.group_name then
      return a.group_name < b.group_name
    end
    local oa = state_order[a.state] or 99
    local ob = state_order[b.state] or 99
    if oa ~= ob then return oa < ob end
    return a.title < b.title
  end)
  
  -- Build display with group headers
  local display_items = {}
  local lookup = {}
  local current_group = nil
  
  for _, item in ipairs(items) do
    -- Add group header if changed
    if item.group_name ~= current_group then
      current_group = item.group_name
      local header = string.format("━━━ %s ━━━", current_group)
      table.insert(display_items, header)
    end
    
    local icon = state_icons[item.state] or "󰄱"
    local tag_str = item.tags ~= "" and (" :" .. item.tags .. ":") or ""
    local display = string.format("  %s %-8s %s%s", icon, item.state, item.title, tag_str)
    
    table.insert(display_items, display)
    lookup[display] = item
  end
  
  if #display_items == 0 then
    vim.notify("No tasks found", vim.log.levels.INFO)
    return
  end
  
  -- Use shared actions
  local fzf_actions = require("gtd-nvim.capture.ui.fzf_actions")
  local actions = fzf_actions.task_actions(lookup, function(item)
    -- Primary action for edit picker: quick_edit
    vim.schedule(function()
      vim.cmd("edit " .. item.file)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      vim.schedule(function()
        if mode == "full" then
          M.full_edit()
        else
          M.quick_edit()
        end
      end)
    end)
  end)
  
  fzf.fzf_exec(display_items, {
    prompt = "Edit task ❯ ",
    winopts = { height = 0.75, width = 0.85 },
    fzf_opts = fzf_actions.task_fzf_opts(),
    actions = actions,
  })
end

return M
