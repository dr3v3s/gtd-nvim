-- ~/.config/nvim/lua/utils/gtd-audit/migrate.lua
-- Migration tool to fix org-mode compliance issues in GTD files
-- Run with :lua require("utils.gtd-audit.migrate").fix_all()

local M = {}

M.config = {
  gtd_root = vim.fn.expand("~/Documents/GTD"),
  backup = true,
  dry_run = false,  -- Set to true to preview changes without writing
  skip_archive = true,  -- Skip Archive.org and ArchiveDeleted
}

-- Helpers
local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

local function write_file(path, lines)
  return vim.fn.writefile(lines, path) == 0
end

local function backup_file(path)
  local ts = os.date("%Y%m%d%H%M%S")
  local backup_path = path .. "." .. ts .. ".bak"
  local lines = read_file(path)
  if lines then
    write_file(backup_path, lines)
    return backup_path
  end
  return nil
end

-- Check if line is an org heading
local function is_heading(line)
  return line and line:match("^%*+%s") ~= nil
end

-- Get heading level
local function heading_level(line)
  local stars = line:match("^(%*+)%s")
  return stars and #stars or nil
end

-- Format inactive timestamp
local function format_inactive_timestamp(date_str)
  if not date_str then
    return os.date("[%Y-%m-%d %a %H:%M]")
  end
  
  local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if year then
    local time = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
    return os.date("[%Y-%m-%d %a]", time)
  end
  
  return "[" .. date_str .. "]"
end

-- Fix a single org file
function M.fix_file(path)
  local lines = read_file(path)
  if not lines then
    return nil, "Could not read file"
  end
  
  local changes = {}
  local new_lines = {}
  local i = 1
  
  -- Track state
  local current_heading_line = nil
  local current_heading_level = nil
  local in_properties = false
  local properties_start = nil
  local properties_content = {}
  local seen_scheduled = false
  local seen_deadline = false
  local pending_scheduling = {}  -- SCHEDULED/DEADLINE to insert before PROPERTIES
  local id_from_legacy = nil  -- ID extracted from ID:: line
  
  while i <= #lines do
    local line = lines[i]
    local skip_line = false
    
    -- Detect heading
    if is_heading(line) then
      -- Reset state for new heading
      current_heading_line = i
      current_heading_level = heading_level(line)
      seen_scheduled = false
      seen_deadline = false
      pending_scheduling = {}
      id_from_legacy = nil
      in_properties = false
      properties_start = nil
      properties_content = {}
    end
    
    -- Detect PROPERTIES drawer start
    if line:match("^:PROPERTIES:%s*$") then
      -- Check if we already have a PROPERTIES drawer for this heading
      if in_properties then
        -- Duplicate PROPERTIES - skip this line (we'll merge content)
        table.insert(changes, {
          line = i,
          type = "remove",
          reason = "Duplicate :PROPERTIES: line"
        })
        skip_line = true
        -- Continue processing to capture properties from this duplicate drawer
      else
        in_properties = true
        properties_start = #new_lines + 1
      end
    
    -- Detect :END:
    elseif line:match("^:END:%s*$") then
      if in_properties then
        -- Before closing properties, add :ZK_LINK: if we found a legacy ID::
        if id_from_legacy and not properties_content["ZK_LINK"] then
          local zk_link = string.format(":ZK_LINK:   [[zk:%s]]", id_from_legacy)
          table.insert(new_lines, zk_link)
          table.insert(changes, {
            line = i,
            type = "add",
            reason = "Added :ZK_LINK: property from legacy ID:: line",
            content = zk_link
          })
          id_from_legacy = nil
        end
        
        -- Add :ID: property if missing (org-mode standard)
        if properties_content["TASK_ID"] and not properties_content["ID"] then
          local id_prop = string.format(":ID:        %s", properties_content["TASK_ID"])
          -- Insert after properties_start
          table.insert(new_lines, properties_start + 1, id_prop)
          table.insert(changes, {
            line = i,
            type = "add",
            reason = "Added :ID: property (org-mode standard)",
            content = id_prop
          })
        end
        
        in_properties = false
      else
        -- :END: without :PROPERTIES: - might be a duplicate drawer end
        table.insert(changes, {
          line = i,
          type = "remove",
          reason = "Orphan :END: line (duplicate PROPERTIES cleanup)"
        })
        skip_line = true
      end
    
    -- Property line inside PROPERTIES
    elseif in_properties and line:match("^:[^:]+:") then
      local key, value = line:match("^:([^:]+):%s*(.*)%s*$")
      if key then
        local key_upper = key:upper()
        
        -- Skip duplicate properties
        if properties_content[key_upper] then
          table.insert(changes, {
            line = i,
            type = "remove",
            reason = string.format("Duplicate property :%s:", key)
          })
          skip_line = true
        else
          properties_content[key_upper] = value
          
          -- Fix CREATED format if needed
          if key_upper == "CREATED" and not value:match("^%[") then
            local fixed = format_inactive_timestamp(value)
            line = string.format(":CREATED:   %s", fixed)
            table.insert(changes, {
              line = i,
              type = "modify",
              reason = "Fixed CREATED timestamp format",
              from = lines[i],
              to = line
            })
          end
        end
      end
    
    -- Detect legacy ID:: line
    elseif line:match("^ID::%s*%[%[zk:") then
      local zk_id = line:match("^ID::%s*%[%[zk:([^%]]+)%]%]")
      if zk_id then
        id_from_legacy = zk_id
        table.insert(changes, {
          line = i,
          type = "remove",
          reason = "Legacy ID:: line (will convert to :ZK_LINK: property)"
        })
        skip_line = true
      end
    
    -- Detect SCHEDULED line
    elseif line:match("^SCHEDULED:") then
      if seen_scheduled then
        table.insert(changes, {
          line = i,
          type = "remove",
          reason = "Duplicate SCHEDULED line"
        })
        skip_line = true
      else
        seen_scheduled = true
        -- Check if it's after PROPERTIES (wrong place)
        if in_properties or (properties_start and #new_lines >= properties_start) then
          table.insert(pending_scheduling, line)
          table.insert(changes, {
            line = i,
            type = "move",
            reason = "SCHEDULED moved before PROPERTIES"
          })
          skip_line = true
        end
      end
    
    -- Detect DEADLINE line
    elseif line:match("^DEADLINE:") then
      if seen_deadline then
        table.insert(changes, {
          line = i,
          type = "remove",
          reason = "Duplicate DEADLINE line"
        })
        skip_line = true
      else
        seen_deadline = true
        -- Check if it's after PROPERTIES (wrong place)
        if in_properties or (properties_start and #new_lines >= properties_start) then
          table.insert(pending_scheduling, line)
          table.insert(changes, {
            line = i,
            type = "move",
            reason = "DEADLINE moved before PROPERTIES"
          })
          skip_line = true
        end
      end
    end
    
    -- Add line unless skipped
    if not skip_line then
      -- Before adding :PROPERTIES:, insert any pending scheduling
      if line:match("^:PROPERTIES:%s*$") and #pending_scheduling > 0 then
        for _, sched_line in ipairs(pending_scheduling) do
          table.insert(new_lines, sched_line)
        end
        pending_scheduling = {}
      end
      
      table.insert(new_lines, line)
    end
    
    i = i + 1
  end
  
  -- Handle any remaining ID from legacy format at end of file
  if id_from_legacy then
    table.insert(changes, {
      line = #lines,
      type = "warning",
      reason = "Legacy ID:: at end of file - needs manual review"
    })
  end
  
  return new_lines, changes
end

-- Fix all GTD files
function M.fix_all(opts)
  opts = vim.tbl_extend("force", M.config, opts or {})
  
  local gtd_files = vim.fn.globpath(opts.gtd_root, "**/*.org", false, true)
  
  -- Filter out backup files
  gtd_files = vim.tbl_filter(function(f)
    return not f:match("%.bak$")
  end, gtd_files)
  
  -- Optionally skip archive files
  if opts.skip_archive then
    gtd_files = vim.tbl_filter(function(f)
      return not f:match("/Archive%.org$") and not f:match("/ArchiveDeleted/")
    end, gtd_files)
  end
  
  local results = {
    files_checked = 0,
    files_modified = 0,
    total_changes = 0,
    errors = {},
    file_changes = {},
  }
  
  for _, file in ipairs(gtd_files) do
    results.files_checked = results.files_checked + 1
    
    local new_lines, changes = M.fix_file(file)
    
    if not new_lines then
      table.insert(results.errors, {file = file, error = changes})
    elseif changes and #changes > 0 then
      results.file_changes[file] = changes
      results.total_changes = results.total_changes + #changes
      
      if not opts.dry_run then
        -- Create backup
        if opts.backup then
          local backup_path = backup_file(file)
          if not backup_path then
            table.insert(results.errors, {file = file, error = "Backup failed"})
            goto continue
          end
        end
        
        -- Write fixed file
        if write_file(file, new_lines) then
          results.files_modified = results.files_modified + 1
        else
          table.insert(results.errors, {file = file, error = "Write failed"})
        end
      else
        results.files_modified = results.files_modified + 1  -- Would be modified
      end
    end
    
    ::continue::
  end
  
  return results
end

-- Show migration report
function M.report(opts)
  opts = vim.tbl_extend("force", M.config, opts or {})
  opts.dry_run = true  -- Always dry run for report
  
  local results = M.fix_all(opts)
  
  local report_lines = {
    "GTD Migration Report",
    string.rep("=", 50),
    string.format("Files checked: %d", results.files_checked),
    string.format("Files needing fixes: %d", results.files_modified),
    string.format("Total changes needed: %d", results.total_changes),
    "",
  }
  
  if #results.errors > 0 then
    table.insert(report_lines, "ERRORS:")
    for _, err in ipairs(results.errors) do
      table.insert(report_lines, string.format("  %s: %s", err.file, err.error))
    end
    table.insert(report_lines, "")
  end
  
  -- Group changes by type
  local changes_by_type = {}
  for file, changes in pairs(results.file_changes) do
    for _, change in ipairs(changes) do
      local t = change.type or "unknown"
      changes_by_type[t] = (changes_by_type[t] or 0) + 1
    end
  end
  
  table.insert(report_lines, "CHANGES BY TYPE:")
  for t, count in pairs(changes_by_type) do
    table.insert(report_lines, string.format("  %s: %d", t, count))
  end
  table.insert(report_lines, "")
  
  -- Show per-file details
  table.insert(report_lines, "DETAILS BY FILE:")
  for file, changes in pairs(results.file_changes) do
    local short_file = file:gsub(vim.fn.expand("~/Documents/GTD/"), "")
    table.insert(report_lines, string.format("  %s (%d changes):", short_file, #changes))
    for _, change in ipairs(changes) do
      local reason = change.reason or "unknown"
      table.insert(report_lines, string.format("    Line %d: [%s] %s", 
        change.line or 0, change.type or "?", reason))
    end
  end
  
  -- Display report
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, report_lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_name(buf, "GTD Migration Report")
  
  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, buf)
  
  return results
end

-- Interactive fix with confirmation
function M.fix_interactive()
  local results = M.report()
  
  if results.total_changes == 0 then
    vim.notify("No fixes needed - all files are compliant!", vim.log.levels.INFO)
    return
  end
  
  vim.ui.select(
    {"Yes, apply all fixes (backups will be created)", "No, cancel"},
    {prompt = string.format("Apply %d fixes to %d files?", results.total_changes, results.files_modified)},
    function(choice)
      if choice and choice:match("^Yes") then
        local apply_results = M.fix_all({dry_run = false, backup = true})
        vim.notify(string.format("Fixed %d files (%d changes applied). Backups created.", 
          apply_results.files_modified, apply_results.total_changes), vim.log.levels.INFO)
      else
        vim.notify("Migration cancelled", vim.log.levels.INFO)
      end
    end
  )
end

-- Create user commands
function M.setup()
  vim.api.nvim_create_user_command("GtdMigrateReport", function()
    M.report()
  end, {desc = "Show GTD migration report (dry run)"})
  
  vim.api.nvim_create_user_command("GtdMigrateFix", function()
    M.fix_interactive()
  end, {desc = "Interactive GTD migration fix"})
  
  vim.api.nvim_create_user_command("GtdMigrateFixAll", function(opts)
    local dry_run = opts.args == "dry"
    local results = M.fix_all({dry_run = dry_run})
    if dry_run then
      vim.notify(string.format("DRY RUN: Would fix %d files (%d changes)", 
        results.files_modified, results.total_changes), vim.log.levels.INFO)
    else
      vim.notify(string.format("Fixed %d files (%d changes)", 
        results.files_modified, results.total_changes), vim.log.levels.INFO)
    end
  end, {nargs = "?", desc = "Fix all GTD files (use 'dry' for dry run)"})
end

return M
