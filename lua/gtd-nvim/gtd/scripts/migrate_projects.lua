-- ============================================================================
-- GTD PROJECT MIGRATION SCRIPT
-- ============================================================================
-- Extracts nested PROJECT headings to their own .org files.
-- Each PROJECT becomes a separate file with the project at level 1.
--
-- @module gtd-nvim.gtd.scripts.migrate_projects
-- @version 1.0.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-27"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local function get_gtd_home()
  local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  if shared_ok and shared.gtd_home then
    return shared.gtd_home()
  end
  return vim.fn.expand("~/Documents/GTD")
end

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Generate a slug from a title
local function slugify(title)
  return title:lower()
    :gsub("[æ]", "ae"):gsub("[ø]", "oe"):gsub("[å]", "aa")
    :gsub("[Æ]", "Ae"):gsub("[Ø]", "Oe"):gsub("[Å]", "Aa")
    :gsub("%s+", "-")
    :gsub("[^%w%-]", "")
    :gsub("%-+", "-")
    :gsub("^%-", "")
    :gsub("%-$", "")
end

--- Determine the area from a file path
local function get_area_from_path(filepath)
  local area = filepath:match("/Areas/([^/]+)/")
  return area
end

--- Find the end of a heading block (next heading at same or lower level)
local function find_heading_end(lines, start_line, heading_level)
  for i = start_line + 1, #lines do
    local line = lines[i]
    local stars = line:match("^(%*+) ")
    if stars and #stars <= heading_level then
      return i - 1
    end
  end
  return #lines
end

--- Extract PROPERTIES from a heading block
local function extract_properties(lines, start_line, end_line)
  local props = {}
  local in_props = false
  
  for i = start_line, end_line do
    local line = lines[i]
    if line:match("^:PROPERTIES:") then
      in_props = true
    elseif line:match("^:END:") then
      in_props = false
    elseif in_props then
      local key, value = line:match("^:([^:]+):%s*(.*)$")
      if key then
        props[key] = value
      end
    end
  end
  
  return props
end

-- ============================================================================
-- MIGRATION
-- ============================================================================

--- Extract a nested project to its own file
---@param source_path string Source file containing nested project
---@param project_info table { line, level, title, raw }
---@return boolean success
---@return string|nil error_or_new_path
function M.extract_project(source_path, project_info)
  local lines = vim.fn.readfile(source_path)
  if not lines then
    return false, "Could not read source file"
  end
  
  local start_line = project_info.line
  local end_line = find_heading_end(lines, start_line, project_info.level)
  
  -- Extract the project block
  local project_lines = {}
  for i = start_line, end_line do
    table.insert(project_lines, lines[i])
  end
  
  -- Demote heading levels (** -> *, *** -> **, etc.)
  local level_reduction = project_info.level - 1
  for i, line in ipairs(project_lines) do
    local stars = line:match("^(%*+)")
    if stars and #stars > level_reduction then
      project_lines[i] = string.rep("*", #stars - level_reduction) .. line:sub(#stars + 1)
    end
  end
  
  -- Determine target directory and filename
  local area = get_area_from_path(source_path)
  local slug = slugify(project_info.title)
  local gtd_home = get_gtd_home()
  
  local target_dir, target_path
  if area then
    target_dir = gtd_home .. "/Areas/" .. area
    target_path = target_dir .. "/" .. slug .. ".org"
  else
    target_dir = gtd_home .. "/Projects"
    target_path = target_dir .. "/" .. slug .. ".org"
  end
  
  -- Check if target already exists (allow overwriting empty files)
  if vim.fn.filereadable(target_path) == 1 then
    local size = vim.fn.getfsize(target_path)
    if size > 0 then
      return false, "Target file already exists (non-empty): " .. target_path
    end
    -- File exists but is empty - we can overwrite it
  end
  
  -- Create target file
  local file_lines = {
    "#+TITLE: " .. project_info.title,
    "#+FILETAGS: :project:",
    "",
  }
  for _, line in ipairs(project_lines) do
    table.insert(file_lines, line)
  end
  
  -- Ensure directory exists
  vim.fn.mkdir(target_dir, "p")
  
  -- Write new file
  local write_ok = vim.fn.writefile(file_lines, target_path)
  if write_ok ~= 0 then
    return false, "Failed to write target file"
  end
  
  -- Remove from source file
  local new_source_lines = {}
  for i = 1, start_line - 1 do
    table.insert(new_source_lines, lines[i])
  end
  for i = end_line + 1, #lines do
    table.insert(new_source_lines, lines[i])
  end
  
  -- Clean up empty lines at the end
  while #new_source_lines > 0 and new_source_lines[#new_source_lines]:match("^%s*$") do
    table.remove(new_source_lines)
  end
  
  -- Write updated source
  vim.fn.writefile(new_source_lines, source_path)
  
  return true, target_path
end

--- Migrate all nested projects in a file
---@param filepath string Path to file with nested projects
---@return table results { success = {}, failed = {} }
function M.migrate_file(filepath)
  local validate = require("gtd-nvim.gtd.scripts.validate_projects")
  
  local results = { success = {}, failed = {} }
  
  -- Keep extracting until no more nested projects
  -- (We re-scan each time because line numbers change)
  local max_iterations = 50  -- Safety limit
  local iteration = 0
  
  while iteration < max_iterations do
    iteration = iteration + 1
    
    local scan_results = validate.scan_all()
    local violations = scan_results[filepath]
    
    if not violations or #violations == 0 then
      break
    end
    
    -- Extract the first nested project
    local v = violations[1]
    local ok, result = M.extract_project(filepath, v)
    
    if ok then
      table.insert(results.success, {
        title = v.title,
        new_file = result,
      })
    else
      table.insert(results.failed, {
        title = v.title,
        error = result,
      })
      -- If one fails, continue with others
      break
    end
  end
  
  return results
end

--- Migrate all nested projects in GTD directory
---@return table results { by_file = { filepath = results, ... }, totals = { success, failed } }
function M.migrate_all()
  local validate = require("gtd-nvim.gtd.scripts.validate_projects")
  local scan_results, total = validate.scan_all()
  
  if total == 0 then
    vim.notify("✅ No nested projects to migrate", vim.log.levels.INFO)
    return { by_file = {}, totals = { success = 0, failed = 0 } }
  end
  
  local all_results = { by_file = {}, totals = { success = 0, failed = 0 } }
  
  for filepath, _ in pairs(scan_results) do
    local results = M.migrate_file(filepath)
    all_results.by_file[filepath] = results
    all_results.totals.success = all_results.totals.success + #results.success
    all_results.totals.failed = all_results.totals.failed + #results.failed
  end
  
  return all_results
end

--- Interactive migration with preview
function M.migrate_interactive()
  local validate = require("gtd-nvim.gtd.scripts.validate_projects")
  local scan_results, total = validate.scan_all()
  
  if total == 0 then
    vim.notify("✅ No nested projects to migrate", vim.log.levels.INFO)
    return
  end
  
  -- Show what will be migrated
  local preview_lines = {
    "📦 NESTED PROJECTS TO MIGRATE",
    "==============================",
    "",
  }
  
  local gtd_home = get_gtd_home()
  for filepath, violations in pairs(scan_results) do
    local rel_path = filepath:gsub(gtd_home .. "/", "")
    local area = get_area_from_path(filepath)
    
    table.insert(preview_lines, "📁 " .. rel_path)
    for _, v in ipairs(violations) do
      local slug = slugify(v.title)
      local target
      if area then
        target = "Areas/" .. area .. "/" .. slug .. ".org"
      else
        target = "Projects/" .. slug .. ".org"
      end
      table.insert(preview_lines, string.format("   → %s", target))
    end
    table.insert(preview_lines, "")
  end
  
  table.insert(preview_lines, string.format("Total: %d project(s) will be extracted", total))
  table.insert(preview_lines, "")
  table.insert(preview_lines, "Press 'y' to proceed, 'n' or 'q' to cancel")
  
  -- Show preview in floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  
  local width = 70
  local height = math.min(#preview_lines + 2, 30)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " Project Migration Preview ",
    title_pos = "center",
  })
  
  -- Handle user input
  local function close_and_migrate(do_migrate)
    vim.api.nvim_win_close(win, true)
    if do_migrate then
      vim.schedule(function()
        local results = M.migrate_all()
        
        if results.totals.success > 0 then
          vim.notify(
            string.format("✅ Migrated %d project(s) to separate files", results.totals.success),
            vim.log.levels.INFO
          )
          
          -- Refresh daemon if available
          local chronos_ok, chronos = pcall(require, "gtd-nvim.gtd.chronos")
          if chronos_ok and chronos.is_running and chronos.is_running() then
            chronos.query("gtd", "refresh", nil)
          end
        end
        
        if results.totals.failed > 0 then
          vim.notify(
            string.format("⚠️  %d project(s) failed to migrate", results.totals.failed),
            vim.log.levels.WARN
          )
        end
      end)
    end
  end
  
  vim.keymap.set("n", "y", function() close_and_migrate(true) end, { buffer = buf })
  vim.keymap.set("n", "n", function() close_and_migrate(false) end, { buffer = buf })
  vim.keymap.set("n", "q", function() close_and_migrate(false) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() close_and_migrate(false) end, { buffer = buf })
end

-- ============================================================================
-- COMMANDS
-- ============================================================================

function M.setup_commands()
  vim.api.nvim_create_user_command("GtdMigrateProjects", function()
    M.migrate_interactive()
  end, { desc = "Migrate nested projects to separate files" })
end

return M
