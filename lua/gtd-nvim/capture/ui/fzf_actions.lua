-- ============================================================================
-- FZF SHARED ACTIONS
-- ============================================================================
-- Common fzf-lua actions for GTD task pickers.
-- Use these in any picker that shows tasks.
--
-- Standard actions:
--   <Enter>  - Primary action (defined by picker)
--   <Tab>    - Multi-select toggle
--   <C-e>    - Edit task(s)
--   <C-r>    - Refile task(s)
--   <C-d>    - Delete task(s)
--   <C-b>    - Back to previous picker
--
-- Nested pickers:
--   Use M.nested() to wrap any fzf picker with automatic back navigation
--
-- @module gtd-nvim.capture.ui.fzf_actions
-- @version 1.3.0
-- @updated 2025-12-24
-- ============================================================================

local M = {}

M._VERSION = "1.3.0"
M._UPDATED = "2025-12-24"

-- ============================================================================
-- BACK NAVIGATION
-- ============================================================================

--- Get back action for nested pickers
---@param parent_fn function Function to return to parent picker
---@return function Action function for ctrl-b
function M.back_action(parent_fn)
  return function(_)
    if parent_fn then
      vim.schedule(parent_fn)
    end
  end
end

--- Create actions table with back navigation
---@param actions table Base actions table
---@param parent_fn function Parent picker function for ctrl-b
---@return table Actions with back navigation added
function M.with_back(actions, parent_fn)
  actions = actions or {}
  actions["ctrl-b"] = M.back_action(parent_fn)
  return actions
end

--- Wrap fzf options for a nested picker with automatic back navigation
--- Adds ctrl-b action and updates header to show back hint
---
--- Usage:
---   fzf.fzf_exec(items, fzf_actions.nested(parent_fn, {
---     prompt = "Nested> ",
---     actions = { ["default"] = function(sel) ... end },
---   }))
---
---   -- Or with fzf.files:
---   fzf.files(fzf_actions.nested(parent_fn, { cwd = some_dir }))
---
---@param parent_fn function Function to call when pressing ctrl-b
---@param opts table fzf options (prompt, actions, winopts, fzf_opts, etc.)
---@return table Modified fzf options with back navigation
function M.nested(parent_fn, opts)
  opts = opts or {}
  
  -- Add ctrl-b action
  opts.actions = opts.actions or {}
  opts.actions["ctrl-b"] = M.back_action(parent_fn)
  
  -- Add/update header with back hint
  opts.fzf_opts = opts.fzf_opts or {}
  local header = opts.fzf_opts["--header"] or ""
  
  if header == "" then
    header = "C-b=back"
  elseif not header:match("C%-b") then
    header = header .. " │ C-b=back"
  end
  
  opts.fzf_opts["--header"] = header
  opts.fzf_opts["--header-first"] = true
  
  return opts
end

--- Shorthand for nested picker with custom header
---@param parent_fn function Function to call when pressing ctrl-b
---@param header string Custom header (C-b=back will be appended)
---@param opts table fzf options
---@return table Modified fzf options
function M.nested_with_header(parent_fn, header, opts)
  opts = opts or {}
  opts.fzf_opts = opts.fzf_opts or {}
  opts.fzf_opts["--header"] = header
  return M.nested(parent_fn, opts)
end

-- ============================================================================
-- TASK ACTIONS
-- ============================================================================

--- Delete a task at file:line
---@param file string File path
---@param lnum number Line number
---@param callback function|nil Optional callback after delete
function M.delete_task(file, lnum, callback)
  -- Confirm deletion
  vim.ui.select({ "Yes - Delete", "No - Cancel" }, {
    prompt = "Delete this task?",
  }, function(choice)
    if not choice or choice:match("^No") then
      if callback then callback(false) end
      return
    end
    
    -- Read file
    local lines = vim.fn.readfile(file)
    if not lines or #lines == 0 then
      vim.notify("Could not read file", vim.log.levels.ERROR)
      if callback then callback(false) end
      return
    end
    
    -- Find heading extent
    local h_start = lnum
    local heading = lines[h_start]
    if not heading or not heading:match("^%*+%s") then
      vim.notify("Not a valid heading", vim.log.levels.ERROR)
      if callback then callback(false) end
      return
    end
    
    local level = #(heading:match("^(%*+)"))
    local h_end = h_start
    
    for i = h_start + 1, #lines do
      local line = lines[i]
      local next_stars = line:match("^(%*+)")
      if next_stars and #next_stars <= level then
        break
      end
      h_end = i
    end
    
    -- Remove lines
    local new_lines = {}
    for i = 1, #lines do
      if i < h_start or i > h_end then
        table.insert(new_lines, lines[i])
      end
    end
    
    -- Write back
    vim.fn.writefile(new_lines, file)
    
    -- Reload buffer if open
    local bufnr = vim.fn.bufnr(file)
    if bufnr ~= -1 then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit!")
      end)
    end
    
    vim.notify("󰜺 Task deleted", vim.log.levels.INFO)
    if callback then callback(true) end
  end)
end

--- Edit a task (opens quick edit)
---@param file string File path
---@param lnum number Line number
function M.edit_task(file, lnum)
  vim.cmd("edit " .. file)
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  vim.schedule(function()
    local edit_ok, edit_wf = pcall(require, "gtd-nvim.capture.workflows.edit")
    if edit_ok then
      edit_wf.quick_edit()
    end
  end)
end

--- Refile a task
---@param file string File path
---@param lnum number Line number
function M.refile_task(file, lnum)
  vim.cmd("edit " .. file)
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  vim.schedule(function()
    local organize_ok, organize = pcall(require, "gtd-nvim.gtd.organize")
    if organize_ok then
      organize.refile_to_project()
    end
  end)
end

--- Refile multiple tasks to same destination
---@param items table Array of { file, lnum } items
function M.refile_multiple(items)
  if #items == 0 then return end
  
  vim.notify(string.format("Refiling %d tasks...", #items), vim.log.levels.INFO)
  
  -- For multi-refile, pick destination first, then move all
  local organize_ok, organize = pcall(require, "gtd-nvim.gtd.organize")
  if not organize_ok then
    vim.notify("organize module not available", vim.log.levels.ERROR)
    return
  end
  
  -- Use shared module to get destination, then refile each
  local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  local gtd_home = shared_ok and shared.gtd_home and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
  
  -- Get destination via picker
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    vim.notify("fzf-lua required for multi-refile", vim.log.levels.WARN)
    return
  end
  
  -- Find target files (simplified - reuse organize's list if available)
  local cmd = string.format("find %s -name '*.org' -type f 2>/dev/null | grep -v Archive", gtd_home)
  local handle = io.popen(cmd)
  if not handle then return end
  local result = handle:read("*a")
  handle:close()
  
  local targets = {}
  for file in result:gmatch("[^\n]+") do
    local name = vim.fn.fnamemodify(file, ":t:r")
    table.insert(targets, { file = file, name = name })
  end
  
  local display = {}
  local lookup = {}
  for _, t in ipairs(targets) do
    table.insert(display, t.name)
    lookup[t.name] = t.file
  end
  
  fzf.fzf_exec(display, {
    prompt = string.format("Move %d tasks to → ", #items),
    winopts = { height = 0.5, width = 0.5 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local dest = lookup[sel[1]]
        if not dest then return end
        
        vim.schedule(function()
          -- Move each task (in reverse order to preserve line numbers)
          local sorted = {}
          for _, item in ipairs(items) do
            table.insert(sorted, item)
          end
          table.sort(sorted, function(a, b)
            if a.file ~= b.file then return a.file > b.file end
            return a.lnum > b.lnum
          end)
          
          local moved = 0
          for _, item in ipairs(sorted) do
            -- Simple append to destination (proper refile would adjust levels)
            local lines = vim.fn.readfile(item.file)
            if lines then
              -- Find heading extent
              local h_start = item.lnum
              local heading = lines[h_start]
              if heading and heading:match("^%*+%s") then
                local level = #(heading:match("^(%*+)"))
                local h_end = h_start
                
                for i = h_start + 1, #lines do
                  local next_stars = lines[i]:match("^(%*+)")
                  if next_stars and #next_stars <= level then break end
                  h_end = i
                end
                
                -- Extract task lines
                local task_lines = {}
                for i = h_start, h_end do
                  table.insert(task_lines, lines[i])
                end
                
                -- Append to destination
                local dest_lines = vim.fn.readfile(dest)
                table.insert(dest_lines, "")
                vim.list_extend(dest_lines, task_lines)
                vim.fn.writefile(dest_lines, dest)
                
                -- Remove from source
                local new_lines = {}
                for i = 1, #lines do
                  if i < h_start or i > h_end then
                    table.insert(new_lines, lines[i])
                  end
                end
                vim.fn.writefile(new_lines, item.file)
                
                moved = moved + 1
              end
            end
          end
          
          vim.notify(string.format("󰈔 Moved %d tasks", moved), vim.log.levels.INFO)
          vim.cmd("edit!")  -- Refresh current buffer
        end)
      end,
    },
  })
end

--- Delete multiple tasks
---@param items table Array of { file, lnum } items
function M.delete_multiple(items)
  if #items == 0 then return end
  
  vim.ui.select({ 
    string.format("Yes - Delete %d tasks", #items), 
    "No - Cancel" 
  }, {
    prompt = string.format("Delete %d tasks?", #items),
  }, function(choice)
    if not choice or choice:match("^No") then return end
    
    -- Sort by file and line (descending) to preserve line numbers during deletion
    local sorted = {}
    for _, item in ipairs(items) do
      table.insert(sorted, item)
    end
    table.sort(sorted, function(a, b)
      if a.file ~= b.file then return a.file > b.file end
      return a.lnum > b.lnum
    end)
    
    local deleted = 0
    local files_modified = {}
    
    for _, item in ipairs(sorted) do
      local lines = vim.fn.readfile(item.file)
      if lines then
        local h_start = item.lnum
        local heading = lines[h_start]
        if heading and heading:match("^%*+%s") then
          local level = #(heading:match("^(%*+)"))
          local h_end = h_start
          
          for i = h_start + 1, #lines do
            local next_stars = lines[i]:match("^(%*+)")
            if next_stars and #next_stars <= level then break end
            h_end = i
          end
          
          local new_lines = {}
          for i = 1, #lines do
            if i < h_start or i > h_end then
              table.insert(new_lines, lines[i])
            end
          end
          
          vim.fn.writefile(new_lines, item.file)
          files_modified[item.file] = true
          deleted = deleted + 1
        end
      end
    end
    
    -- Reload modified buffers
    for file, _ in pairs(files_modified) do
      local bufnr = vim.fn.bufnr(file)
      if bufnr ~= -1 then
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("edit!")
        end)
      end
    end
    
    vim.notify(string.format("󰜺 Deleted %d tasks", deleted), vim.log.levels.INFO)
  end)
end

-- ============================================================================
-- FZF ACTION BUILDERS
-- ============================================================================

--- Extract valid items from selection (filters out headers)
---@param selections table Array of selected strings
---@param lookup table Display string -> task info mapping
---@return table Array of valid items
local function get_valid_items(selections, lookup)
  local items = {}
  for _, sel in ipairs(selections) do
    if not sel:match("^━━━") then
      local item = lookup[sel]
      if item and item.file and item.lnum then
        table.insert(items, item)
      end
    end
  end
  return items
end

--- Build standard task actions for fzf
--- The lookup table maps display strings to { file = path, lnum = number }
---@param lookup table Display string -> task info mapping
---@param primary_action function|nil Custom primary action (default: edit)
---@return table fzf actions table
function M.task_actions(lookup, primary_action)
  return {
    ["default"] = function(sel)
      if not sel or #sel == 0 then return end
      local items = get_valid_items(sel, lookup)
      if #items == 0 then return end
      
      if primary_action then
        -- For multi-select, process first item (primary action typically opens something)
        primary_action(items[1])
      else
        vim.schedule(function()
          M.edit_task(items[1].file, items[1].lnum)
        end)
      end
    end,
    
    ["ctrl-e"] = function(sel)
      if not sel or #sel == 0 then return end
      local items = get_valid_items(sel, lookup)
      if #items == 0 then return end
      
      if #items == 1 then
        vim.schedule(function()
          M.edit_task(items[1].file, items[1].lnum)
        end)
      else
        -- Multi-select: edit first, notify about others
        vim.schedule(function()
          M.edit_task(items[1].file, items[1].lnum)
          vim.notify(string.format("Editing 1 of %d selected (edit others after)", #items), vim.log.levels.INFO)
        end)
      end
    end,
    
    ["ctrl-r"] = function(sel)
      if not sel or #sel == 0 then return end
      local items = get_valid_items(sel, lookup)
      if #items == 0 then return end
      
      if #items == 1 then
        vim.schedule(function()
          M.refile_task(items[1].file, items[1].lnum)
        end)
      else
        -- Multi-select: refile all to same destination
        vim.schedule(function()
          M.refile_multiple(items)
        end)
      end
    end,
    
    ["ctrl-d"] = function(sel)
      if not sel or #sel == 0 then return end
      local items = get_valid_items(sel, lookup)
      if #items == 0 then return end
      
      if #items == 1 then
        vim.schedule(function()
          M.delete_task(items[1].file, items[1].lnum)
        end)
      else
        -- Multi-select: delete all with single confirmation
        vim.schedule(function()
          M.delete_multiple(items)
        end)
      end
    end,
  }
end

--- Standard header hint for task pickers
---@param include_back boolean|nil Include back hint (for nested pickers)
---@return string
function M.task_header(include_back)
  local base = "Enter=select │ Tab=multi │ C-e=edit │ C-r=refile │ C-d=delete"
  if include_back then
    return base .. " │ C-b=back"
  end
  return base
end

--- Standard fzf_opts with header and multi-select
---@param include_back boolean|nil Include back hint
---@return table
function M.task_fzf_opts(include_back)
  return {
    ["--header"] = M.task_header(include_back),
    ["--multi"] = true,
  }
end

--- Header for nested pickers (includes back)
---@param custom_actions string|nil Additional action hints
---@return string
function M.nested_header(custom_actions)
  local base = custom_actions or "Enter=select"
  return base .. " │ C-b=back"
end

return M
