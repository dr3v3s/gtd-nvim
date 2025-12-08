-- gtd-nvim/gtd/fzf.lua
-- Centralized fzf-lua utilities for consistent UI across all GTD modules
-- Features: previews, actions, inputs, styling, and standard configurations

local M = {}

-- ============================================================================
-- FZF-LUA DETECTION
-- ============================================================================

local fzf_lua = nil
local function get_fzf()
  if fzf_lua then return fzf_lua end
  local ok, f = pcall(require, "fzf-lua")
  if ok then fzf_lua = f end
  return fzf_lua
end

function M.available()
  return get_fzf() ~= nil
end

-- ============================================================================
-- COLOR SCHEME / ICONS
-- ============================================================================

M.icons = {
  -- Status icons
  NEXT     = "⚡",
  TODO     = "📋",
  WAITING  = "⏳",
  SOMEDAY  = "💭",
  DONE     = "✅",
  PROJECT  = "📂",
  INBOX    = "📥",
  
  -- Priority icons
  urgent   = "🔴",
  high     = "🟡",
  medium   = "🔵",
  low      = "⚪",
  
  -- Context icons
  email    = "📧",
  phone    = "📞",
  meeting  = "🤝",
  slack    = "💬",
  text     = "📱",
  errand   = "🚗",
  home     = "🏠",
  office   = "🏢",
  computer = "💻",
  
  -- UI icons
  calendar = "📅",
  clock    = "⏰",
  tag      = "🏷️",
  link     = "🔗",
  note     = "📝",
  warning  = "⚠️",
  error    = "❌",
  success  = "✓",
  arrow    = "→",
  bullet   = "•",
}

M.colors = {
  NEXT     = "Green",
  TODO     = "Blue",
  WAITING  = "Yellow",
  SOMEDAY  = "Cyan",
  DONE     = "Comment",
  PROJECT  = "Magenta",
  overdue  = "Red",
  today    = "Yellow",
  upcoming = "Green",
}

-- ============================================================================
-- STANDARD WINDOW CONFIGURATIONS
-- ============================================================================

M.winopts = {
  -- Full picker (lists, search results)
  full = {
    height = 0.85,
    width = 0.90,
    row = 0.10,
    col = 0.50,
    border = "rounded",
    title_pos = "center",
    preview = {
      layout = "vertical",
      vertical = "down:45%",
      border = "rounded",
    },
  },
  
  -- Medium picker (task selection, refiling)
  medium = {
    height = 0.60,
    width = 0.80,
    row = 0.15,
    col = 0.50,
    border = "rounded",
    title_pos = "center",
    preview = {
      layout = "vertical", 
      vertical = "down:40%",
      border = "rounded",
    },
  },
  
  -- Small picker (status, quick select)
  small = {
    height = 0.40,
    width = 0.50,
    row = 0.20,
    col = 0.50,
    border = "rounded",
    title_pos = "center",
  },
  
  -- Minimal picker (yes/no, simple choices)
  minimal = {
    height = 0.25,
    width = 0.40,
    row = 0.30,
    col = 0.50,
    border = "rounded",
  },
  
  -- Input replacement
  input = {
    height = 0.15,
    width = 0.50,
    row = 0.35,
    col = 0.50,
    border = "rounded",
  },
}

-- ============================================================================
-- STANDARD FZF OPTIONS
-- ============================================================================

M.fzf_opts = {
  -- Default for all pickers
  default = {
    ["--no-info"] = true,
    ["--tiebreak"] = "index",
    ["--pointer"] = "▶",
    ["--marker"] = "●",
    ["--cycle"] = true,
  },
  
  -- For task/item lists (with multi-select)
  list = {
    ["--no-info"] = true,
    ["--tiebreak"] = "index",
    ["--pointer"] = "▶",
    ["--marker"] = "●",
    ["--cycle"] = true,
    ["--multi"] = true,
  },
  
  -- For single selection
  single = {
    ["--no-info"] = true,
    ["--tiebreak"] = "index",
    ["--pointer"] = "▶",
    ["--cycle"] = true,
    ["--no-multi"] = true,
  },
}


-- ============================================================================
-- STANDARD HEADERS
-- ============================================================================

M.headers = {
  tasks = "Enter:Open │ Ctrl-E:Edit+Return │ Ctrl-X:Clarify │ Ctrl-R:Refile │ Ctrl-A:Archive",
  projects = "Enter:Open │ Ctrl-E:Edit+Return │ Ctrl-S:Stats │ Ctrl-Z:ZK Note │ Ctrl-A:Archive",
  lists = "Enter:Open │ Ctrl-E:Edit+Return │ Ctrl-X:Clarify │ Ctrl-F:Fast Clarify",
  waiting = "Enter:Open │ Ctrl-E:Edit+Return │ Ctrl-W:Update │ Ctrl-C:Convert │ Ctrl-X:Clarify",
  simple = "Enter:Select │ Esc:Cancel",
  refile = "Enter:Refile Here │ Ctrl-N:New Project │ Esc:Cancel",
  input = "Enter:Confirm │ Esc:Cancel",
}

-- ============================================================================
-- PREVIEW GENERATORS
-- ============================================================================

--- Generate preview content for a task/heading
---@param item table Task item with path, lnum, h_start, h_end
---@return string[] Preview lines
function M.preview_task(item)
  if not item or not item.path then return {"No item selected"} end
  
  local lines = {}
  local file_lines = vim.fn.readfile(vim.fn.expand(item.path))
  
  -- Header
  table.insert(lines, "╭─────────────────────────────────────────────╮")
  table.insert(lines, "│ " .. (item.filename or vim.fn.fnamemodify(item.path, ":t")))
  table.insert(lines, "╰─────────────────────────────────────────────╯")
  table.insert(lines, "")
  
  -- Status & Title
  if item.state then
    local icon = M.icons[item.state] or "•"
    table.insert(lines, icon .. " " .. item.state .. ": " .. (item.title or ""))
  else
    table.insert(lines, (item.title or item.line or ""))
  end
  table.insert(lines, "")
  
  -- Extract metadata from subtree
  local start_line = item.h_start or item.lnum or 1
  local end_line = item.h_end or math.min(start_line + 30, #file_lines)
  
  local props = {}
  local scheduled, deadline = nil, nil
  local tags = nil
  local body_lines = {}
  local in_props = false
  
  for i = start_line, end_line do
    local line = file_lines[i]
    if not line then break end
    
    -- Dates
    local sched = line:match("SCHEDULED:%s*<([^>]+)>")
    if sched then scheduled = sched end
    local dead = line:match("DEADLINE:%s*<([^>]+)>")
    if dead then deadline = dead end
    
    -- Tags
    local t = line:match(":([%w_:]+):$")
    if t then tags = t end
    
    -- Properties
    if line:match("^%s*:PROPERTIES:") then in_props = true end
    if in_props then
      local key, val = line:match("^%s*:([^:]+):%s*(.+)$")
      if key and val and key ~= "PROPERTIES" and key ~= "END" then
        props[key] = val
      end
    end
    if line:match("^%s*:END:") then in_props = false end
    
    -- Body text (not properties, not heading)
    if not in_props and i > start_line and not line:match("^%*") and not line:match("^%s*:") and not line:match("SCHEDULED") and not line:match("DEADLINE") then
      local trimmed = line:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        table.insert(body_lines, trimmed)
      end
    end
  end
  
  -- Display metadata
  table.insert(lines, "─── Dates ───")
  if scheduled then table.insert(lines, M.icons.calendar .. " Scheduled: " .. scheduled) end
  if deadline then table.insert(lines, M.icons.clock .. " Deadline:  " .. deadline) end
  if not scheduled and not deadline then table.insert(lines, "  (none)") end
  table.insert(lines, "")
  
  -- Tags
  if tags then
    table.insert(lines, "─── Tags ───")
    table.insert(lines, M.icons.tag .. " " .. tags)
    table.insert(lines, "")
  end
  
  -- WAITING metadata
  if item.state == "WAITING" or props.WAITING_FOR then
    table.insert(lines, "─── Waiting For ───")
    if props.WAITING_FOR then table.insert(lines, "  Who:      " .. props.WAITING_FOR) end
    if props.WAITING_WHAT then table.insert(lines, "  What:     " .. props.WAITING_WHAT) end
    if props.REQUESTED then table.insert(lines, "  Requested: " .. props.REQUESTED) end
    if props.FOLLOW_UP then table.insert(lines, "  Follow-up: " .. props.FOLLOW_UP) end
    if props.CONTEXT then 
      local ctx_icon = M.icons[props.CONTEXT] or ""
      table.insert(lines, "  Context:  " .. ctx_icon .. " " .. props.CONTEXT) 
    end
    if props.PRIORITY then
      local pri_icon = M.icons[props.PRIORITY] or ""
      table.insert(lines, "  Priority: " .. pri_icon .. " " .. props.PRIORITY)
    end
    table.insert(lines, "")
  end
  
  -- Key properties
  if next(props) then
    table.insert(lines, "─── Properties ───")
    for k, v in pairs(props) do
      if not k:match("WAITING") and k ~= "TASK_ID" and k ~= "ID" then
        table.insert(lines, "  " .. k .. ": " .. v)
      end
    end
    table.insert(lines, "")
  end
  
  -- Body/Description
  if #body_lines > 0 then
    table.insert(lines, "─── Content ───")
    for i, bl in ipairs(body_lines) do
      if i <= 10 then table.insert(lines, "  " .. bl) end
    end
    if #body_lines > 10 then
      table.insert(lines, "  ... (" .. (#body_lines - 10) .. " more lines)")
    end
  end
  
  return lines
end

--- Generate preview for a project
---@param proj table Project info
---@return string[] Preview lines
function M.preview_project(proj)
  if not proj then return {"No project selected"} end
  
  local lines = {}
  
  table.insert(lines, "╭─────────────────────────────────────────────╮")
  table.insert(lines, "│ " .. M.icons.PROJECT .. " " .. (proj.name or proj.filename or "Project"))
  table.insert(lines, "╰─────────────────────────────────────────────╯")
  table.insert(lines, "")
  
  -- Stats
  table.insert(lines, "─── Statistics ───")
  table.insert(lines, M.icons.NEXT .. " Next Actions: " .. (proj.next_actions or 0))
  table.insert(lines, M.icons.TODO .. " TODO:         " .. (proj.todo_tasks or 0))
  table.insert(lines, M.icons.WAITING .. " Waiting:      " .. (proj.waiting_tasks or 0))
  table.insert(lines, M.icons.DONE .. " Done:         " .. (proj.done_tasks or 0))
  table.insert(lines, "")
  
  if proj.earliest_deadline then
    table.insert(lines, "─── Deadlines ───")
    table.insert(lines, M.icons.clock .. " Next: " .. proj.earliest_deadline)
    table.insert(lines, "")
  end
  
  if proj.area then
    table.insert(lines, "─── Area ───")
    table.insert(lines, "  " .. proj.area)
    table.insert(lines, "")
  end
  
  if proj.zk_note then
    table.insert(lines, "─── ZK Note ───")
    table.insert(lines, M.icons.link .. " " .. proj.zk_note)
  end
  
  return lines
end


-- ============================================================================
-- ACTION GENERATORS
-- ============================================================================

--- Create standard task actions for fzf
---@param display table Display items
---@param meta table Meta items (actual data)
---@param return_fn function|nil Function to call after edit-and-return
---@param opts table|nil Additional options
---@return table Actions table for fzf
function M.task_actions(display, meta, return_fn, opts)
  opts = opts or {}
  
  local function get_item(sel)
    if not sel or not sel[1] then return nil end
    local idx = vim.fn.index(display, sel[1]) + 1
    return meta[idx]
  end
  
  local actions = {
    -- Open file at task
    ["default"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
    end,
    
    -- Edit and return to picker
    ["ctrl-e"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      M.edit_and_return(item, return_fn, opts)
    end,
    
    -- Open in split
    ["ctrl-s"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("split " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
    end,
    
    -- Open in vsplit
    ["ctrl-v"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("vsplit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
    end,
    
    -- Open in tab
    ["ctrl-t"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("tabedit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
    end,
  }
  
  -- Add clarify action
  if opts.clarify_fn then
    actions["ctrl-x"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
      vim.schedule(function()
        opts.clarify_fn({ item = item })
      end)
    end
  end
  
  -- Add fast clarify
  if opts.fast_clarify_fn then
    actions["ctrl-f"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
      vim.schedule(function()
        opts.fast_clarify_fn({ item = item })
      end)
    end
  end
  
  -- Add refile action
  if opts.refile_fn then
    actions["ctrl-r"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
      vim.schedule(function()
        opts.refile_fn()
      end)
    end
  end
  
  -- Add archive action
  if opts.archive_fn then
    actions["ctrl-a"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
      vim.schedule(function()
        opts.archive_fn()
      end)
    end
  end
  
  -- Add ZK note action
  if opts.zk_fn then
    actions["ctrl-z"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      opts.zk_fn(item)
    end
  end
  
  -- WAITING-specific actions
  if opts.waiting_update_fn then
    actions["ctrl-w"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
      vim.schedule(function()
        opts.waiting_update_fn()
      end)
    end
  end
  
  if opts.waiting_convert_fn then
    actions["ctrl-c"] = function(sel)
      local item = get_item(sel)
      if not item then return end
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
      vim.schedule(function()
        opts.waiting_convert_fn()
      end)
    end
  end
  
  return actions
end

-- ============================================================================
-- EDIT AND RETURN
-- ============================================================================

--- Open file for editing and return to picker when done
---@param item table Item with path and lnum
---@param return_fn function Function to call on return
---@param opts table|nil Options
function M.edit_and_return(item, return_fn, opts)
  if not item or not item.path then
    vim.notify("Invalid item for editing", vim.log.levels.ERROR)
    return
  end
  
  -- Open file
  local ok = pcall(function()
    vim.cmd("edit " .. vim.fn.fnameescape(item.path))
    if item.lnum then vim.api.nvim_win_set_cursor(0, { item.lnum, 0 }) end
  end)
  
  if not ok then
    vim.notify("Failed to open: " .. item.path, vim.log.levels.ERROR)
    return
  end
  
  -- Set up return mechanism
  local bufnr = vim.api.nvim_get_current_buf()
  local group_name = "GTDEditReturn_" .. bufnr .. "_" .. os.time()
  
  pcall(vim.api.nvim_del_augroup_by_name, group_name)
  
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd({"BufLeave", "WinLeave"}, {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      vim.schedule(function()
        pcall(vim.api.nvim_del_augroup_by_name, group_name)
        vim.defer_fn(function()
          if type(return_fn) == "function" then
            return_fn(opts)
          end
        end, 100)
      end)
    end,
  })
  
  vim.notify("📝 Editing... Leave buffer to return to picker", vim.log.levels.INFO)
end


-- ============================================================================
-- FZF-BASED INPUT (replaces vim.ui.input)
-- ============================================================================

--- FZF-based text input
---@param opts table Options {prompt, default, completion}
---@param cb function Callback(input_string)
function M.input(opts, cb)
  opts = opts or {}
  local fzf = get_fzf()
  
  if not fzf then
    -- Fallback to vim.ui.input
    vim.ui.input(opts, cb)
    return
  end
  
  local prompt = (opts.prompt or "Input") .. ": "
  local default = opts.default or ""
  
  -- If completion items provided, show them as suggestions
  if opts.completion and type(opts.completion) == "table" and #opts.completion > 0 then
    local items = vim.deepcopy(opts.completion)
    if default ~= "" then
      table.insert(items, 1, default)
    end
    
    fzf.fzf_exec(items, {
      prompt = prompt,
      fzf_opts = vim.tbl_extend("force", M.fzf_opts.single, {
        ["--print-query"] = true,
        ["--query"] = default,
      }),
      winopts = M.winopts.small,
      actions = {
        ["default"] = function(sel)
          if sel and #sel > 0 then
            -- First element is query if --print-query is set
            local result = sel[2] or sel[1]
            cb(result)
          end
        end,
      },
    })
  else
    -- Simple input with no completions - use fzf's query
    fzf.fzf_exec({}, {
      prompt = prompt,
      fzf_opts = vim.tbl_extend("force", M.fzf_opts.single, {
        ["--print-query"] = true,
        ["--query"] = default,
        ["--header"] = "Type your input and press Enter",
      }),
      winopts = M.winopts.input,
      actions = {
        ["default"] = function(sel)
          if sel and sel[1] then
            cb(sel[1])
          end
        end,
      },
    })
  end
end

--- FZF-based text input with validation
---@param opts table Options {prompt, default, validate, required}
---@param cb function Callback(validated_input)
function M.input_validated(opts, cb)
  opts = opts or {}
  
  local function do_input()
    M.input(opts, function(result)
      if opts.required and (not result or result == "") then
        vim.notify("Input is required", vim.log.levels.WARN)
        return
      end
      
      if opts.validate and type(opts.validate) == "function" then
        local valid, err = opts.validate(result)
        if not valid then
          vim.notify(err or "Invalid input", vim.log.levels.WARN)
          -- Retry
          vim.schedule(do_input)
          return
        end
      end
      
      cb(result)
    end)
  end
  
  do_input()
end

-- ============================================================================
-- FZF-BASED SELECT (replaces vim.ui.select)
-- ============================================================================

--- FZF-based selection
---@param items table List of items to select from
---@param opts table Options {prompt, format_item, preview}
---@param cb function Callback(selected_item, index)
function M.select(items, opts, cb)
  opts = opts or {}
  local fzf = get_fzf()
  
  if not items or #items == 0 then
    cb(nil, nil)
    return
  end
  
  if not fzf then
    -- Fallback to vim.ui.select
    vim.ui.select(items, opts, cb)
    return
  end
  
  -- Format items for display
  local display = {}
  local format_fn = opts.format_item or tostring
  for _, item in ipairs(items) do
    table.insert(display, format_fn(item))
  end
  
  local config = {
    prompt = (opts.prompt or "Select") .. "> ",
    fzf_opts = M.fzf_opts.single,
    winopts = opts.winopts or M.winopts.small,
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then
          cb(nil, nil)
          return
        end
        local idx = vim.fn.index(display, sel[1]) + 1
        cb(items[idx], idx)
      end,
    },
  }
  
  -- Add header if provided
  if opts.header then
    config.fzf_opts = vim.tbl_extend("force", config.fzf_opts, {
      ["--header"] = opts.header,
    })
  end
  
  -- Add preview if provided
  if opts.preview then
    config.previewer = false
    config.preview = opts.preview
  end
  
  fzf.fzf_exec(display, config)
end

--- Multi-select with fzf
---@param items table List of items
---@param opts table Options
---@param cb function Callback(selected_items, indices)
function M.select_multi(items, opts, cb)
  opts = opts or {}
  local fzf = get_fzf()
  
  if not items or #items == 0 then
    cb({}, {})
    return
  end
  
  if not fzf then
    -- Fallback: use vim.ui.select multiple times
    vim.notify("Multi-select requires fzf-lua", vim.log.levels.WARN)
    cb({}, {})
    return
  end
  
  local display = {}
  local format_fn = opts.format_item or tostring
  for _, item in ipairs(items) do
    table.insert(display, format_fn(item))
  end
  
  fzf.fzf_exec(display, {
    prompt = (opts.prompt or "Select") .. "> ",
    fzf_opts = M.fzf_opts.list,
    winopts = opts.winopts or M.winopts.medium,
    actions = {
      ["default"] = function(sel)
        if not sel or #sel == 0 then
          cb({}, {})
          return
        end
        
        local selected = {}
        local indices = {}
        for _, s in ipairs(sel) do
          local idx = vim.fn.index(display, s) + 1
          if idx > 0 then
            table.insert(selected, items[idx])
            table.insert(indices, idx)
          end
        end
        cb(selected, indices)
      end,
    },
  })
end


-- ============================================================================
-- MAIN PICKER FUNCTION
-- ============================================================================

--- Create a full-featured task picker
---@param opts table Options
---  - items: table of task items
---  - title: string window title
---  - prompt: string prompt text
---  - header: string header text
---  - size: string "full"|"medium"|"small"
---  - preview: boolean|function enable preview
---  - actions: table additional actions
---  - return_fn: function for edit-and-return
---  - on_select: function called on selection
function M.task_picker(opts)
  opts = opts or {}
  local fzf = get_fzf()
  
  if not fzf then
    vim.notify("fzf-lua required for task picker", vim.log.levels.ERROR)
    return
  end
  
  local items = opts.items or {}
  if #items == 0 then
    vim.notify("No items to display", vim.log.levels.INFO)
    return
  end
  
  -- Build display strings
  local display = {}
  local meta = {}
  
  for _, item in ipairs(items) do
    local icon = item.context_icon or M.icons[item.state] or "•"
    local state_str = item.state and ("[" .. item.state .. "] ") or ""
    local filename = item.filename and (" │ " .. item.filename) or ""
    
    local line = string.format("%s %s%s%s", icon, state_str, item.title or "(no title)", filename)
    table.insert(display, line)
    table.insert(meta, item)
  end
  
  -- Window config
  local winopts = vim.deepcopy(M.winopts[opts.size or "full"])
  if opts.title then
    winopts.title = " " .. opts.title .. " "
  end
  
  -- FZF options
  local fzf_opts = vim.deepcopy(M.fzf_opts.default)
  if opts.header then
    fzf_opts["--header"] = opts.header
  end
  
  -- Build actions
  local actions = M.task_actions(display, meta, opts.return_fn, {
    clarify_fn = opts.clarify_fn,
    fast_clarify_fn = opts.fast_clarify_fn,
    refile_fn = opts.refile_fn,
    archive_fn = opts.archive_fn,
    zk_fn = opts.zk_fn,
    waiting_update_fn = opts.waiting_update_fn,
    waiting_convert_fn = opts.waiting_convert_fn,
  })
  
  -- Merge custom actions
  if opts.actions then
    for k, v in pairs(opts.actions) do
      actions[k] = v
    end
  end
  
  -- Build config
  local config = {
    prompt = (opts.prompt or "Tasks") .. "> ",
    fzf_opts = fzf_opts,
    winopts = winopts,
    actions = actions,
  }
  
  -- Preview setup
  if opts.preview ~= false then
    config.previewer = false  -- Disable built-in
    config.preview = function(sel)
      if not sel or #sel == 0 then return end
      local idx = vim.fn.index(display, sel[1]) + 1
      local item = meta[idx]
      if item then
        if type(opts.preview) == "function" then
          return opts.preview(item)
        else
          return table.concat(M.preview_task(item), "\n")
        end
      end
      return ""
    end
  end
  
  fzf.fzf_exec(display, config)
end

--- Create a simple choice picker
---@param choices table List of choice strings
---@param opts table Options {title, prompt, callback}
function M.choice(choices, opts)
  opts = opts or {}
  local fzf = get_fzf()
  
  if not fzf then
    vim.ui.select(choices, { prompt = opts.prompt or "Choose" }, opts.callback)
    return
  end
  
  fzf.fzf_exec(choices, {
    prompt = (opts.prompt or "Choose") .. "> ",
    fzf_opts = M.fzf_opts.single,
    winopts = opts.winopts or M.winopts.small,
    actions = {
      ["default"] = function(sel)
        if sel and sel[1] and opts.callback then
          opts.callback(sel[1])
        end
      end,
    },
  })
end

-- ============================================================================
-- DATE PICKER
-- ============================================================================

--- Pick a date with fzf
---@param opts table Options {prompt, default, include_relative}
---@param cb function Callback(date_string)
function M.pick_date(opts, cb)
  opts = opts or {}
  
  local today = os.date("%Y-%m-%d")
  local tomorrow = os.date("%Y-%m-%d", os.time() + 86400)
  local next_week = os.date("%Y-%m-%d", os.time() + 7 * 86400)
  local next_month = os.date("%Y-%m-%d", os.time() + 30 * 86400)
  
  local items = {
    M.icons.calendar .. " Today (" .. today .. ")",
    M.icons.calendar .. " Tomorrow (" .. tomorrow .. ")",
    M.icons.calendar .. " Next week (" .. next_week .. ")",
    M.icons.calendar .. " Next month (" .. next_month .. ")",
    M.icons.calendar .. " No date (clear)",
    M.icons.calendar .. " Custom date...",
  }
  
  M.select(items, {
    prompt = opts.prompt or "Date",
    winopts = M.winopts.small,
  }, function(choice)
    if not choice then return end
    
    if choice:match("Today") then
      cb(today)
    elseif choice:match("Tomorrow") then
      cb(tomorrow)
    elseif choice:match("Next week") then
      cb(next_week)
    elseif choice:match("Next month") then
      cb(next_month)
    elseif choice:match("No date") then
      cb("")
    elseif choice:match("Custom") then
      M.input({
        prompt = "Date (YYYY-MM-DD)",
        default = opts.default or today,
      }, function(custom)
        if custom and custom:match("^%d%d%d%d%-%d%d%-%d%d$") then
          cb(custom)
        else
          vim.notify("Invalid date format", vim.log.levels.WARN)
        end
      end)
    end
  end)
end

-- ============================================================================
-- STATUS PICKER
-- ============================================================================

--- Pick a GTD status with fzf
---@param opts table Options {prompt, current, exclude}
---@param cb function Callback(status)
function M.pick_status(opts, cb)
  opts = opts or {}
  
  local statuses = {
    { state = "NEXT", icon = M.icons.NEXT, desc = "Next physical action" },
    { state = "TODO", icon = M.icons.TODO, desc = "Task to be done" },
    { state = "WAITING", icon = M.icons.WAITING, desc = "Waiting for someone/something" },
    { state = "SOMEDAY", icon = M.icons.SOMEDAY, desc = "Maybe later" },
    { state = "DONE", icon = M.icons.DONE, desc = "Completed" },
  }
  
  local items = {}
  local meta = {}
  
  for _, s in ipairs(statuses) do
    -- Skip current status if specified
    if s.state ~= opts.current then
      -- Skip excluded statuses
      local excluded = false
      if opts.exclude then
        for _, ex in ipairs(opts.exclude) do
          if s.state == ex then excluded = true; break end
        end
      end
      
      if not excluded then
        table.insert(items, string.format("%s %s - %s", s.icon, s.state, s.desc))
        table.insert(meta, s.state)
      end
    end
  end
  
  M.select(items, {
    prompt = opts.prompt or "Status",
    winopts = M.winopts.small,
  }, function(choice, idx)
    if choice and idx then
      cb(meta[idx])
    end
  end)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Format a task item for display
---@param item table Task item
---@param opts table|nil Options {show_file, show_state, compact}
---@return string Formatted display string
function M.format_task(item, opts)
  opts = opts or {}
  local icon = item.context_icon or M.icons[item.state] or "•"
  
  local parts = { icon }
  
  if opts.show_state ~= false and item.state then
    table.insert(parts, "[" .. item.state .. "]")
  end
  
  table.insert(parts, item.title or "(no title)")
  
  if opts.show_file ~= false and item.filename then
    table.insert(parts, "│ " .. item.filename)
  end
  
  return table.concat(parts, " ")
end

--- Notify with consistent styling
---@param msg string Message
---@param level string|nil "INFO"|"WARN"|"ERROR"
function M.notify(msg, level)
  local levels = {
    INFO = vim.log.levels.INFO,
    WARN = vim.log.levels.WARN,
    ERROR = vim.log.levels.ERROR,
  }
  vim.notify(msg, levels[level] or vim.log.levels.INFO, { title = "GTD" })
end

return M
