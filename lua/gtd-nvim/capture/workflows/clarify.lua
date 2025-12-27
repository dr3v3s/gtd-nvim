-- ============================================================================
-- WORKFLOW: CLARIFY
-- ============================================================================
-- GTD Clarify workflow - process inbox items and unclear tasks.
-- Uses composable steps from capture system.
--
-- Single entry point: M.clarify()
-- - On heading → clarify directly
-- - Not on heading → task picker (Inbox first)
--
-- @module gtd-nvim.capture.workflows.clarify
-- @version 1.1.0
-- @updated 2025-12-24
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2025-12-24"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local Object = require("gtd-nvim.capture.model.object")
local shared = safe_require("gtd-nvim.gtd.shared")
local fzf_actions = safe_require("gtd-nvim.capture.ui.fzf_actions")

local g = shared and shared.glyphs or {}

-- ============================================================================
-- STEP: ACTIONABLE
-- ============================================================================

local actionable_step = {
  name = "actionable",
  
  run = function(obj, opts, next_step)
    local fzf_ok, fzf = pcall(require, "fzf-lua")
    
    local items = {
      "󰄲 Yes - It's actionable",
      "󰋚 Someday/Maybe - Not now",
      "󰈔 Reference - Just information",
      "󰜺 Trash - Delete it",
    }
    
    if fzf_ok then
      fzf.fzf_exec(items, {
        prompt = "Actionable? ❯ ",
        winopts = { height = 0.3, width = 0.4, title = " 󰔢 Is it actionable? ", title_pos = "center" },
        fzf_opts = { ["--no-info"] = true },
        actions = {
          ["default"] = function(sel)
            if not sel or not sel[1] then
              vim.schedule(function() next_step(obj) end)
              return
            end
            
            local choice = sel[1]
            if choice:match("^󰄲 Yes") then
              obj._actionable = "yes"
            elseif choice:match("^󰋚 Someday") then
              obj._actionable = "someday"
              obj.state = "SOMEDAY"
              obj.scheduled = nil
              obj.deadline = nil
            elseif choice:match("^󰈔 Reference") then
              obj._actionable = "reference"
              obj._skip_remaining = true
            elseif choice:match("^󰜺 Trash") then
              obj._actionable = "trash"
              obj._skip_remaining = true
              obj._delete = true
            end
            
            vim.schedule(function() next_step(obj) end)
          end,
        },
      })
    else
      vim.ui.select(items, { prompt = "Is it actionable?" }, function(choice)
        if choice then
          if choice:match("Yes") then obj._actionable = "yes"
          elseif choice:match("Someday") then 
            obj._actionable = "someday"
            obj.state = "SOMEDAY"
          elseif choice:match("Reference") then 
            obj._actionable = "reference"
            obj._skip_remaining = true
          elseif choice:match("Trash") then
            obj._actionable = "trash"
            obj._skip_remaining = true
            obj._delete = true
          end
        end
        next_step(obj)
      end)
    end
  end,
}

-- ============================================================================
-- STEP: SINGLE OR PROJECT
-- ============================================================================

local action_type_step = {
  name = "action_type",
  
  should_run = function(obj)
    return obj._actionable == "yes" and not obj._skip_remaining
  end,
  
  run = function(obj, opts, next_step)
    local fzf_ok, fzf = pcall(require, "fzf-lua")
    
    local items = {
      "󱥦 Single action - One step",
      "󰷐 Project - Multiple steps",
    }
    
    if fzf_ok then
      fzf.fzf_exec(items, {
        prompt = "Type? ❯ ",
        winopts = { height = 0.2, width = 0.35, title = "  Single or multi-step? ", title_pos = "center" },
        fzf_opts = { ["--no-info"] = true },
        actions = {
          ["default"] = function(sel)
            if sel and sel[1] and sel[1]:match("^󰷐 Project") then
              obj._is_project = true
              obj.state = "PROJECT"
            end
            vim.schedule(function() next_step(obj) end)
          end,
        },
      })
    else
      vim.ui.select(items, { prompt = "Action type?" }, function(choice)
        if choice and choice:match("Project") then
          obj._is_project = true
          obj.state = "PROJECT"
        end
        next_step(obj)
      end)
    end
  end,
}

-- ============================================================================
-- STEP: DELEGATE (WAITING)
-- ============================================================================

local delegate_step = {
  name = "delegate",
  
  should_run = function(obj)
    return obj._actionable == "yes" and not obj._is_project and not obj._skip_remaining
  end,
  
  run = function(obj, opts, next_step)
    local fzf_ok, fzf = pcall(require, "fzf-lua")
    
    local items = {
      "󰄴 Do it myself",
      " Delegate (WAITING)",
    }
    
    if fzf_ok then
      fzf.fzf_exec(items, {
        prompt = "Do or delegate? ❯ ",
        winopts = { height = 0.2, width = 0.35, title = " 󰔢 Do or delegate? ", title_pos = "center" },
        fzf_opts = { ["--no-info"] = true },
        actions = {
          ["default"] = function(sel)
            if sel and sel[1] and sel[1]:match("Delegate") then
              obj._delegated = true
              obj.state = "WAITING"
            end
            vim.schedule(function() next_step(obj) end)
          end,
        },
      })
    else
      vim.ui.select(items, { prompt = "Do or delegate?" }, function(choice)
        if choice and choice:match("Delegate") then
          obj._delegated = true
          obj.state = "WAITING"
        end
        next_step(obj)
      end)
    end
  end,
}

-- ============================================================================
-- STEP: WAITING METADATA
-- ============================================================================

local waiting_step = {
  name = "waiting",
  
  should_run = function(obj)
    return obj.state == "WAITING" and not obj._skip_remaining
  end,
  
  run = function(obj, opts, next_step)
    vim.ui.input({ prompt = " Waiting for WHO: " }, function(who)
      if who and who ~= "" then
        obj.waiting_for = who
      end
      
      vim.schedule(function()
        vim.ui.input({ prompt = " Waiting for WHAT: " }, function(what)
          if what and what ~= "" then
            obj.waiting_context = what
          end
          obj.waiting_since = os.date("%Y-%m-%d")
          vim.schedule(function() next_step(obj) end)
        end)
      end)
    end)
  end,
}

-- ============================================================================
-- STEP: REFILE
-- ============================================================================

local refile_step = {
  name = "refile",
  
  should_run = function(obj)
    if obj._skip_remaining then return false end
    if obj._source and obj._source.file then
      return obj._source.file:match("Inbox%.org$") ~= nil
    end
    return false
  end,
  
  run = function(obj, opts, next_step)
    local fzf_ok, fzf = pcall(require, "fzf-lua")
    if not fzf_ok then
      next_step(obj)
      return
    end
    
    local gtd_home = shared and shared.gtd_home and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
    
    local function get_sort_group(filepath)
      local fname = vim.fn.fnamemodify(filepath, ":t")
      if fname == "Inbox.org" and filepath:match("/Areas/") then 
        local area = filepath:match("/Areas/([^/]+)/")
        return 2, area
      end
      local area = filepath:match("/Areas/([^/]+)/")
      if area then return 2, area end
      if filepath:match("/Projects/") then return 100, "Projects" end
      return 999, "Other"
    end
    
    local cmd = string.format("find %s -name '*.org' -type f 2>/dev/null | grep -v Archive | grep -v '/Inbox.org$'", gtd_home)
    local handle = io.popen(cmd)
    if not handle then
      next_step(obj)
      return
    end
    local result = handle:read("*a")
    handle:close()
    
    local items = {}
    for filepath in result:gmatch("[^\n]+") do
      local sort_group, group_name = get_sort_group(filepath)
      local fname = vim.fn.fnamemodify(filepath, ":t:r")
      local area = filepath:match("/Areas/([^/]+)/")
      local display_name = (area and fname == "Inbox") and (area .. "/Inbox") or fname
      
      table.insert(items, {
        file = filepath,
        name = display_name,
        sort_group = sort_group,
        group_name = group_name,
      })
    end
    
    table.sort(items, function(a, b)
      if a.sort_group ~= b.sort_group then return a.sort_group < b.sort_group end
      if a.group_name ~= b.group_name then return a.group_name < b.group_name end
      return a.name < b.name
    end)
    
    local display_items = { "  󰏫 Keep in Inbox" }
    local lookup = {}
    local current_group = nil
    
    for _, item in ipairs(items) do
      if item.group_name ~= current_group then
        current_group = item.group_name
        table.insert(display_items, string.format("━━━ %s ━━━", current_group))
      end
      
      local icon = item.sort_group == 2 and "󰉋" or item.sort_group == 100 and "󰷐" or "󰈔"
      local display = string.format("  %s %s", icon, item.name)
      
      table.insert(display_items, display)
      lookup[display] = item
    end
    
    fzf.fzf_exec(display_items, {
      prompt = "Refile to → ",
      winopts = { height = 0.6, width = 0.5, title = " 󰉋 Refile destination ", title_pos = "center" },
      fzf_opts = { ["--no-info"] = true },
      actions = {
        ["default"] = function(sel)
          if not sel or not sel[1] or sel[1]:match("^━━━") or sel[1]:match("Keep in Inbox") then
            vim.schedule(function() next_step(obj) end)
            return
          end
          
          local item = lookup[sel[1]]
          if item then
            obj._refile_to = item.file
          end
          
          vim.schedule(function() next_step(obj) end)
        end,
      },
    })
  end,
}

-- ============================================================================
-- WORKFLOW DEFINITION
-- ============================================================================

M.definition = {
  name = "clarify",
  description = "GTD clarify workflow",
  object_type = Object.TYPE.TASK,
  
  steps = {
    actionable_step,
    action_type_step,
    delegate_step,
    waiting_step,
    "outcome",
    "state",
    "tags",
    "schedule",
    refile_step,
  },
  
  opts = {
    outcome = { prompt = "󰆤 What does DONE look like? " },
    state = { skip_if_set = true },
    schedule = { skip_for_someday = true },
  },
}

-- ============================================================================
-- TASK PICKER (shared pattern)
-- ============================================================================

local function build_task_picker_items()
  local gtd_home = shared and shared.gtd_home and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
  
  local cmd = string.format(
    "grep -rn '^\\*\\+\\s\\+\\(NEXT\\|TODO\\|WAITING\\|SOMEDAY\\)' %s --include='*.org' 2>/dev/null | grep -v Archive",
    gtd_home
  )
  
  local handle = io.popen(cmd)
  if not handle then return {}, {} end
  
  local result = handle:read("*a")
  handle:close()
  
  local items = {}
  local state_icons = { NEXT = "󱥦", TODO = "󰄲", WAITING = "", SOMEDAY = "󰋚" }
  
  local function get_sort_group(filepath)
    local fname = vim.fn.fnamemodify(filepath, ":t")
    if fname == "Inbox.org" and not filepath:match("/Areas/") then return 1, "00-Inbox" end
    local area = filepath:match("/Areas/([^/]+)/")
    if area then return 2, area end
    if filepath:match("/Projects/") then return 100, "Projects" end
    return 999, "Other"
  end
  
  for line in result:gmatch("[^\n]+") do
    local file, lnum, content = line:match("^([^:]+):(%d+):(.+)$")
    if file and lnum and content then
      local state = content:match("^%*+%s+(%u+)")
      local title = content:gsub("^%*+%s+%u+%s+", ""):gsub("%s*:.*:%s*$", "")
      local sort_group, group_name = get_sort_group(file)
      
      table.insert(items, {
        file = file,
        lnum = tonumber(lnum),
        state = state,
        title = vim.trim(title),
        sort_group = sort_group,
        group_name = group_name,
      })
    end
  end
  
  -- Sort: Inbox first, then areas, then projects
  local state_order = { TODO = 1, NEXT = 2, WAITING = 3, SOMEDAY = 4 }
  table.sort(items, function(a, b)
    if a.sort_group ~= b.sort_group then return a.sort_group < b.sort_group end
    if a.group_name ~= b.group_name then return a.group_name < b.group_name end
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
    if item.group_name ~= current_group then
      current_group = item.group_name
      table.insert(display_items, string.format("━━━ %s ━━━", current_group))
    end
    
    local icon = state_icons[item.state] or "󰄱"
    local display = string.format("  %s %s", icon, item.title)
    
    table.insert(display_items, display)
    lookup[display] = item
  end
  
  return display_items, lookup
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Parse task at cursor into OrgObject
---@return table|nil OrgObject
function M.parse_at_cursor()
  local edit_wf = safe_require("gtd-nvim.capture.workflows.edit")
  if edit_wf and edit_wf.parse_at_cursor then
    return edit_wf.parse_at_cursor()
  end
  return nil
end

--- Main entry point: clarify at cursor or pick task
--- Pattern: Same as refile - auto-detect cursor position
function M.clarify()
  -- Check if on org heading
  local line = vim.api.nvim_get_current_line()
  if line:match("^%*+%s+") then
    -- On heading → clarify directly
    M._clarify_at_cursor()
    return
  end
  
  -- Not on heading → show task picker
  M._pick_task_then_clarify()
end

--- Clarify task at cursor
function M._clarify_at_cursor()
  local obj = M.parse_at_cursor()
  if not obj then
    if shared and shared.notify then
      shared.notify("Not on a valid task heading", "WARN")
    else
      vim.notify("Not on a valid task heading", vim.log.levels.WARN)
    end
    return
  end
  
  obj._mode = Object.MODE.EDIT
  M._run_clarify(obj)
end

--- Pick task then clarify
function M._pick_task_then_clarify()
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    if shared and shared.notify then
      shared.notify("fzf-lua required", "WARN")
    end
    return
  end
  
  local display_items, lookup = build_task_picker_items()
  
  if #display_items == 0 then
    if shared and shared.notify then
      shared.notify("No tasks to clarify", "INFO")
    end
    return
  end
  
  -- Build actions using fzf_actions
  local actions
  if fzf_actions then
    actions = fzf_actions.task_actions(lookup, function(item)
      -- Primary action: open file, position cursor, then clarify
      vim.schedule(function()
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
        vim.schedule(function()
          M._clarify_at_cursor()
        end)
      end)
    end)
  else
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] or sel[1]:match("^━━━") then return end
        local item = lookup[sel[1]]
        if item then
          vim.schedule(function()
            vim.cmd("edit " .. vim.fn.fnameescape(item.file))
            vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
            vim.schedule(function()
              M._clarify_at_cursor()
            end)
          end)
        end
      end,
    }
  end
  
  local header = fzf_actions and fzf_actions.task_header() or "Enter=clarify"
  
  fzf.fzf_exec(display_items, {
    prompt = "Clarify task ❯ ",
    winopts = { 
      height = 0.75, 
      width = 0.85,
      title = " 󰔢 Clarify - Pick Task ",
      title_pos = "center",
    },
    fzf_opts = fzf_actions and fzf_actions.task_fzf_opts() or {
      ["--header"] = header,
      ["--no-info"] = true,
    },
    actions = actions,
  })
end

--- Run clarify workflow on object
---@param obj table OrgObject
function M._run_clarify(obj)
  local engine = safe_require("gtd-nvim.capture.engine")
  if not engine then
    vim.notify("Capture engine not available", vim.log.levels.ERROR)
    return
  end
  
  engine.run(M.definition, obj, function(result)
    if result._delete then
      M._delete_task(result)
      if shared and shared.notify then
        shared.notify("󰜺 Task deleted", "INFO")
      end
      return
    end
    
    if result._actionable == "reference" then
      if shared and shared.notify then
        shared.notify("󰈔 Reference - file for reference (TODO)", "INFO")
      end
      return
    end
    
    -- Save changes
    M._save_task(result)
    
    -- Refile if needed
    if result._refile_to then
      vim.schedule(function()
        M._refile_task(result, result._refile_to)
      end)
    end
    
    if shared and shared.notify then
      shared.notify("󰄲 Task clarified", "INFO")
    end
  end)
end

--- Save task back to file
---@param obj table OrgObject
function M._save_task(obj)
  local edit_wf = safe_require("gtd-nvim.capture.workflows.edit")
  if edit_wf and edit_wf.save then
    edit_wf.save(obj)
  end
end

--- Delete task
---@param obj table OrgObject
function M._delete_task(obj)
  if not obj._source or not obj._source.file then return end
  
  if fzf_actions and fzf_actions.delete_task then
    fzf_actions.delete_task(obj._source.file, obj._source.line)
  end
end

--- Refile task to destination
---@param obj table OrgObject
---@param dest string Destination file
function M._refile_task(obj, dest)
  if not obj._source or not obj._source.file then return end
  
  local organize = safe_require("gtd-nvim.gtd.organize")
  if not organize then return end
  
  -- Navigate to task and refile
  vim.cmd("edit " .. vim.fn.fnameescape(obj._source.file))
  vim.api.nvim_win_set_cursor(0, { obj._source.line, 0 })
  
  -- Find subtree bounds
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local h_start = obj._source.line
  local h_end = h_start
  local level = #(lines[h_start]:match("^(%*+)") or "*")
  
  for i = h_start + 1, #lines do
    local next_level = lines[i]:match("^(%*+)")
    if next_level and #next_level <= level then
      break
    end
    h_end = i
  end
  
  -- Call internal refile with destination
  if organize._refile_subtree_to_file then
    organize._refile_subtree_to_file(bufnr, h_start, h_end, dest)
  elseif organize.refile_subtree_to_file then
    organize.refile_subtree_to_file(bufnr, h_start, h_end, dest)
  end
end

return M
