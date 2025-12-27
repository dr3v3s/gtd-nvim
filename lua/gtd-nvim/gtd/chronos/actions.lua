-- ============================================================================
-- GTD-NVIM CHRONOS ACTIONS
-- ============================================================================
-- Task and project operations: delete, archive, restore, refile, mark done.
--
-- @module gtd-nvim.gtd.chronos.actions
-- @version 1.0.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-27"

local utils = require("gtd-nvim.gtd.chronos.utils")

-- ============================================================================
-- TASK OPERATIONS
-- ============================================================================

--- Delete task(s) from org file
---@param tasks table Array of task objects with file and line
---@return number Count of deleted tasks
function M.delete_tasks(tasks)
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
---@return number Count of archived tasks
function M.archive_tasks(tasks)
  local archive_dir = utils.archive_path()
  vim.fn.mkdir(archive_dir, "p")
  
  -- Group tasks by file
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
        table.insert(archive_content, "")
        for _, line in ipairs(subtree) do
          table.insert(archive_content, line)
        end
        
        -- Remove from source content
        for i = end_line, start_line, -1 do
          table.remove(content, i)
        end
        archived = archived + 1
      end
      ::continue::
    end
    
    vim.fn.writefile(content, file)
    vim.fn.writefile(archive_content, archive_file)
  end
  
  return archived
end

--- Scan Archive folder and return archived tasks
---@return table[] Array of archived task objects
function M.get_archived_tasks()
  local archive_dir = utils.archive_path()
  local tasks = {}
  
  if vim.fn.isdirectory(archive_dir) == 0 then
    return tasks
  end
  
  local files = vim.fn.glob(archive_dir .. "/*.org", false, true)
  
  for _, file in ipairs(files) do
    local content = vim.fn.readfile(file)
    local source_name = vim.fn.fnamemodify(file, ":t:r")
    
    for i, line in ipairs(content) do
      local stars, state, title
      
      -- Try matching each keyword
      for _, kw in ipairs({"NEXT", "TODO", "WAITING", "SOMEDAY", "DONE", "CANCELLED", "PROJECT"}) do
        stars, title = line:match("^(%*+)%s+" .. kw .. "%s+(.+)")
        if stars then
          state = kw
          break
        end
      end
      
      if stars and state and title then
        title = title:gsub("%s+:[%w@:]+:%s*$", "")
        
        table.insert(tasks, {
          title = title,
          state = state,
          file = file,
          line = i,
          level = #stars,
          source = source_name,
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
function M.restore_tasks(tasks, target_file)
  target_file = target_file or utils.inbox_path()
  utils.ensure_file(target_file, vim.fn.fnamemodify(target_file, ":t:r"))
  
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
  
  local by_file = {}
  for _, task in ipairs(tasks) do
    if task.file and task.line then
      by_file[task.file] = by_file[task.file] or {}
      table.insert(by_file[task.file], task)
    end
  end
  
  for archive_file, file_tasks in pairs(by_file) do
    local content = vim.fn.readfile(archive_file)
    table.sort(file_tasks, function(a, b) return a.line > b.line end)
    
    for _, task in ipairs(file_tasks) do
      local start_line = task.line
      local stars = content[start_line]:match("^(%*+)")
      
      if stars then
        local source_level = #stars
        local end_line = start_line
        local subtree = {}
        
        for i = start_line, #content do
          local s = content[i]:match("^(%*+)")
          if i > start_line and s and #s <= source_level then break end
          local line = content[i]
          
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
        
        target_content = vim.fn.readfile(target_file)
        table.insert(target_content, "")
        for _, line in ipairs(subtree) do
          table.insert(target_content, line)
        end
        vim.fn.writefile(target_content, target_file)
        
        for i = end_line, start_line, -1 do
          table.remove(content, i)
        end
        restored = restored + 1
      end
    end
    
    -- Clean up empty archive file
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
function M.delete_archived_tasks(tasks)
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
---@return number Count of completed tasks
function M.mark_tasks_done(tasks)
  local done = 0
  for _, task in ipairs(tasks) do
    if task.file and task.line then
      local content = vim.fn.readfile(task.file)
      local line = content[task.line]
      if line then
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
---@return number Count of refiled tasks
function M.refile_tasks(tasks, target_file)
  if not target_file or target_file == "" then return 0 end
  
  utils.ensure_file(target_file, vim.fn.fnamemodify(target_file, ":t:r"))
  
  -- Determine target heading level
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
      
      if start_line > #content or not content[start_line] then
        goto continue
      end
      
      local stars = content[start_line]:match("^(%*+)")
      
      if stars then
        local source_level = #stars
        local end_line = start_line
        local subtree = {}
        
        for i = start_line, #content do
          local s = content[i]:match("^(%*+)")
          if i > start_line and s and #s <= source_level then break end
          local line = content[i]
          
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
        
        target_content = vim.fn.readfile(target_file)
        table.insert(target_content, "")
        for _, line in ipairs(subtree) do
          table.insert(target_content, line)
        end
        vim.fn.writefile(target_content, target_file)
        
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
-- PROJECT OPERATIONS
-- ============================================================================

--- Archive a project (move file to Archive folder)
---@param project table Project object with path
---@return boolean success
function M.archive_project(project)
  if not project or not project.path then return false end
  
  local archive_dir = utils.archive_path()
  vim.fn.mkdir(archive_dir, "p")
  
  local filename = vim.fn.fnamemodify(project.path, ":t")
  local archive_path = archive_dir .. "/" .. filename
  
  -- Handle name collision
  if vim.fn.filereadable(archive_path) == 1 then
    local base = vim.fn.fnamemodify(filename, ":r")
    local ext = vim.fn.fnamemodify(filename, ":e")
    local timestamp = os.date("%Y%m%d%H%M%S")
    archive_path = archive_dir .. "/" .. base .. "-" .. timestamp .. "." .. ext
  end
  
  local ok = vim.fn.rename(project.path, archive_path)
  return ok == 0
end

--- Toggle ONGOING property on a project
---@param project table Project object with path
---@return boolean success
function M.toggle_ongoing(project)
  if not project or not project.path then return false end
  
  local content = vim.fn.readfile(project.path)
  local in_props = false
  local has_ongoing = false
  local props_end = nil
  
  for i, line in ipairs(content) do
    if line:match("^:PROPERTIES:") then
      in_props = true
    elseif line:match("^:END:") and in_props then
      props_end = i
      in_props = false
      break
    elseif in_props and line:match("^:ONGOING:") then
      has_ongoing = true
      -- Remove the line
      table.remove(content, i)
      vim.fn.writefile(content, project.path)
      return true
    end
  end
  
  -- Add ONGOING property
  if props_end then
    table.insert(content, props_end, ":ONGOING: t")
    vim.fn.writefile(content, project.path)
    return true
  end
  
  return false
end

--- Toggle ON_HOLD property on a project
---@param project table Project object with path
---@return boolean success
function M.toggle_on_hold(project)
  if not project or not project.path then return false end
  
  local content = vim.fn.readfile(project.path)
  local in_props = false
  local has_on_hold = false
  local props_end = nil
  
  for i, line in ipairs(content) do
    if line:match("^:PROPERTIES:") then
      in_props = true
    elseif line:match("^:END:") and in_props then
      props_end = i
      in_props = false
      break
    elseif in_props and line:match("^:ON_HOLD:") then
      has_on_hold = true
      table.remove(content, i)
      vim.fn.writefile(content, project.path)
      return true
    end
  end
  
  if props_end then
    table.insert(content, props_end, ":ON_HOLD: t")
    vim.fn.writefile(content, project.path)
    return true
  end
  
  return false
end

return M
