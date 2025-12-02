-- GTD System Migration Script
-- Converts system to use TASK_ID only and org-mode date formats
-- Run with: :luafile ~/.config/nvim/lua/gtd/scripts/migrate_to_v2.lua

local M = {}

-- Configuration
local config = {
  gtd_root = vim.fn.expand("~/Documents/GTD"),
  backup_suffix = ".backup-" .. os.date("%Y%m%d%H%M%S"),
  dry_run = false,  -- Set to false to actually make changes
  verbose = true,
}

-- Utilities
local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local task_id = safe_require("gtd.utils.task_id")
local org_dates = safe_require("gtd.utils.org_dates")

local function log(msg, level)
  if config.verbose then
    vim.notify(msg, level or vim.log.levels.INFO, { title = "GTD Migration" })
  end
end

local function backup_file(path)
  local backup_path = path .. config.backup_suffix
  local ok, err = pcall(function()
    local lines = vim.fn.readfile(path)
    vim.fn.writefile(lines, backup_path)
  end)
  
  if ok then
    log("Backed up: " .. vim.fn.fnamemodify(path, ":t"), vim.log.levels.DEBUG)
    return backup_path
  else
    log("Backup failed for " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end
end

-- ============================================================================
-- MIGRATION FUNCTIONS
-- ============================================================================

--- Convert date from <YYYY-MM-DD> to <YYYY-MM-DD Day>
local function fix_date_format(line)
  if not org_dates then return line, false end
  
  local modified = false
  local result = line
  
  -- Match SCHEDULED or DEADLINE with simple date
  local keyword, prefix, date = line:match("^(%s*)(SCHEDULED:%s*|DEADLINE:%s*)<(%d%d%d%d%-%d%d%-%d%d)>")
  
  if date and org_dates.is_valid_date_format(date) then
    local org_date = org_dates.format_org_date(date)
    if org_date then
      result = prefix .. keyword .. org_date
      modified = true
    end
  end
  
  return result, modified
end

--- Remove :ID: property and keep :TASK_ID:
local function remove_redundant_id(line)
  -- Check if this is an :ID: property line
  local id_value = line:match("^%s*:ID:%s*(.-)%s*$")
  
  if id_value and id_value ~= "" then
    -- This is an :ID: line - should be removed
    return nil, true, id_value
  end
  
  return line, false, nil
end

--- Ensure TASK_ID exists in properties drawer
local function ensure_task_id(lines, heading_idx)
  if not task_id then return false end
  
  local new_lines, task_id_value = task_id.ensure_in_properties(lines, heading_idx)
  
  -- Replace lines in place
  for i = 1, #new_lines do
    lines[i] = new_lines[i]
  end
  
  return true
end

--- Update ID:: breadcrumb to reference TASK_ID
local function fix_zk_breadcrumb(line, task_id_value)
  -- Match ID:: [[zk:...]] pattern
  local prefix, old_id = line:match("^(ID::%s*%[%[zk:)(.-)%]%]")
  
  if prefix and old_id and task_id_value then
    return string.format("ID:: [[zk:%s]]", task_id_value), true
  end
  
  return line, false
end

-- ============================================================================
-- FILE MIGRATION
-- ============================================================================

--- Migrate a single org file
local function migrate_file(file_path)
  local stats = {
    dates_fixed = 0,
    ids_removed = 0,
    task_ids_added = 0,
    breadcrumbs_fixed = 0,
    heading_count = 0,
  }
  
  -- Read file
  local ok, lines = pcall(vim.fn.readfile, file_path)
  if not ok or not lines then
    log("Could not read file: " .. file_path, vim.log.levels.ERROR)
    return nil
  end
  
  -- Backup original
  if not config.dry_run then
    local backup_path = backup_file(file_path)
    if not backup_path then
      log("Skipping file (backup failed): " .. file_path, vim.log.levels.WARN)
      return nil
    end
  end
  
  -- Track modifications
  local modified = false
  local new_lines = {}
  local current_task_id = nil
  local in_properties = false
  local removed_id_value = nil
  
  for i = 1, #lines do
    local line = lines[i]
    local keep_line = true
    
    -- Track properties drawer
    if line:match("^%s*:PROPERTIES:%s*$") then
      in_properties = true
    elseif line:match("^%s*:END:%s*$") then
      in_properties = false
    end
    
    -- Track headings
    if line:match("^%*+%s") then
      stats.heading_count = stats.heading_count + 1
      current_task_id = nil  -- Reset for new heading
      
      -- Ensure TASK_ID for this heading
      if ensure_task_id(lines, i) then
        stats.task_ids_added = stats.task_ids_added + 1
        modified = true
      end
      
      -- Extract current TASK_ID for breadcrumb fixing
      if task_id then
        current_task_id = task_id.extract_from_properties(lines, i)
      end
    end
    
    -- Fix dates
    local fixed_line, date_modified = fix_date_format(line)
    if date_modified then
      line = fixed_line
      stats.dates_fixed = stats.dates_fixed + 1
      modified = true
    end
    
    -- Remove redundant :ID: properties
    local checked_line, is_redundant_id, id_val = remove_redundant_id(line)
    if is_redundant_id then
      keep_line = false
      stats.ids_removed = stats.ids_removed + 1
      removed_id_value = id_val
      modified = true
    else
      line = checked_line
    end
    
    -- Fix ZK breadcrumbs
    if current_task_id then
      local fixed_breadcrumb, breadcrumb_modified = fix_zk_breadcrumb(line, current_task_id)
      if breadcrumb_modified then
        line = fixed_breadcrumb
        stats.breadcrumbs_fixed = stats.breadcrumbs_fixed + 1
        modified = true
      end
    end
    
    -- Add line to output
    if keep_line then
      table.insert(new_lines, line)
    end
  end
  
  -- Write back if modified and not dry run
  if modified and not config.dry_run then
    local write_ok = pcall(vim.fn.writefile, new_lines, file_path)
    if not write_ok then
      log("Failed to write: " .. file_path, vim.log.levels.ERROR)
      return nil
    end
  end
  
  return modified and stats or nil
end

-- ============================================================================
-- SYSTEM MIGRATION
-- ============================================================================

--- Migrate entire GTD system
function M.migrate()
  local start_time = os.time()
  
  log("========================================", vim.log.levels.INFO)
  log("GTD System Migration to v2.0", vim.log.levels.INFO)
  log("========================================", vim.log.levels.INFO)
  log(config.dry_run and "DRY RUN MODE - No changes will be made" or "LIVE MODE - Files will be modified", 
      config.dry_run and vim.log.levels.WARN or vim.log.levels.INFO)
  log("GTD Root: " .. config.gtd_root, vim.log.levels.INFO)
  log("", vim.log.levels.INFO)
  
  -- Find all org files
  local files = vim.fn.globpath(config.gtd_root, "**/*.org", false, true)
  if type(files) == "string" then
    files = {files}
  end
  
  log(string.format("Found %d org files to process", #files), vim.log.levels.INFO)
  log("", vim.log.levels.INFO)
  
  -- Process each file
  local total_stats = {
    files_processed = 0,
    files_modified = 0,
    files_failed = 0,
    dates_fixed = 0,
    ids_removed = 0,
    task_ids_added = 0,
    breadcrumbs_fixed = 0,
    heading_count = 0,
  }
  
  for _, file in ipairs(files) do
    local short_name = vim.fn.fnamemodify(file, ":t")
    log("Processing: " .. short_name .. "...", vim.log.levels.DEBUG)
    
    local stats = migrate_file(file)
    
    if stats then
      total_stats.files_modified = total_stats.files_modified + 1
      total_stats.dates_fixed = total_stats.dates_fixed + stats.dates_fixed
      total_stats.ids_removed = total_stats.ids_removed + stats.ids_removed
      total_stats.task_ids_added = total_stats.task_ids_added + stats.task_ids_added
      total_stats.breadcrumbs_fixed = total_stats.breadcrumbs_fixed + stats.breadcrumbs_fixed
      total_stats.heading_count = total_stats.heading_count + stats.heading_count
      
      if stats.dates_fixed > 0 or stats.ids_removed > 0 or stats.breadcrumbs_fixed > 0 then
        log(string.format("  ✓ %s: %d dates, %d IDs removed, %d breadcrumbs fixed",
          short_name, stats.dates_fixed, stats.ids_removed, stats.breadcrumbs_fixed),
          vim.log.levels.INFO)
      end
    else
      total_stats.files_failed = total_stats.files_failed + 1
    end
    
    total_stats.files_processed = total_stats.files_processed + 1
  end
  
  local elapsed = os.time() - start_time
  
  -- Report
  log("", vim.log.levels.INFO)
  log("========================================", vim.log.levels.INFO)
  log("Migration Complete!", vim.log.levels.INFO)
  log("========================================", vim.log.levels.INFO)
  log(string.format("Time elapsed: %d seconds", elapsed), vim.log.levels.INFO)
  log(string.format("Files processed: %d", total_stats.files_processed), vim.log.levels.INFO)
  log(string.format("Files modified:  %d", total_stats.files_modified), vim.log.levels.INFO)
  log(string.format("Files failed:    %d", total_stats.files_failed), vim.log.levels.INFO)
  log("", vim.log.levels.INFO)
  log("Changes made:", vim.log.levels.INFO)
  log(string.format("  Total headings:      %d", total_stats.heading_count), vim.log.levels.INFO)
  log(string.format("  Dates fixed:         %d", total_stats.dates_fixed), vim.log.levels.INFO)
  log(string.format("  :ID: removed:        %d", total_stats.ids_removed), vim.log.levels.INFO)
  log(string.format("  :TASK_ID: added:     %d", total_stats.task_ids_added), vim.log.levels.INFO)
  log(string.format("  Breadcrumbs fixed:   %d", total_stats.breadcrumbs_fixed), vim.log.levels.INFO)
  log("", vim.log.levels.INFO)
  
  if config.dry_run then
    log("⚠️  DRY RUN: No actual changes were made", vim.log.levels.WARN)
    log("Set config.dry_run = false to apply changes", vim.log.levels.WARN)
  else
    log("✅ Migration applied successfully!", vim.log.levels.INFO)
    log("Backup files created with suffix: " .. config.backup_suffix, vim.log.levels.INFO)
  end
  
  log("", vim.log.levels.INFO)
  log("Next steps:", vim.log.levels.INFO)
  log("1. Run :GtdAudit to verify system health", vim.log.levels.INFO)
  log("2. Review any issues in the audit report", vim.log.levels.INFO)
  log("3. Test your GTD workflows", vim.log.levels.INFO)
  log("========================================", vim.log.levels.INFO)
  
  return total_stats
end

-- ============================================================================
-- MAIN EXECUTION
-- ============================================================================

-- Interactive prompts
local function run_interactive()
  vim.ui.select(
    {"Dry Run (preview changes)", "Live Migration (apply changes)", "Cancel"},
    {prompt = "GTD Migration Mode:"},
    function(choice)
      if not choice or choice == "Cancel" then
        log("Migration cancelled", vim.log.levels.INFO)
        return
      end
      
      config.dry_run = (choice:match("Dry Run") ~= nil)
      
      vim.ui.select(
        {"Yes, proceed", "No, cancel"},
        {prompt = "This will modify " .. config.gtd_root .. ". Continue?"},
        function(confirm)
          if confirm == "Yes, proceed" then
            M.migrate()
          else
            log("Migration cancelled", vim.log.levels.INFO)
          end
        end
      )
    end
  )
end

-- Command setup
vim.api.nvim_create_user_command("GtdMigrate", function(opts)
  if opts.args == "dry" then
    config.dry_run = true
    M.migrate()
  elseif opts.args == "live" then
    config.dry_run = false
    M.migrate()
  else
    run_interactive()
  end
end, {
  nargs = "?",
  complete = function() return {"dry", "live"} end,
  desc = "Migrate GTD system to v2.0 (TASK_ID only, org-mode dates)"
})

log("GTD Migration script loaded. Run :GtdMigrate to begin.", vim.log.levels.INFO)

return M
