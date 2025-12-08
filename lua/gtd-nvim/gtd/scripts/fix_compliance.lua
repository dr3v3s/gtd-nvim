-- GTD Modules Compliance Fixer - Neovim Native
-- Run with: :luafile path/to/gtd-nvim/lua/gtd-nvim/gtd/scripts/fix_compliance.lua
-- Or add as command: :GtdFixCompliance

local M = {}

local config = {
  gtd_path = vim.fn.expand("~/Documents/GTD"),
  backup_suffix = ".backup-" .. os.date("%Y%m%d%H%M%S"),
  dry_run = false,
}

-- Key fixes needed for each module
local fixes = {
  capture = {
    {
      desc = "Remove redundant :ID: property line",
      find = 'table%.insert%(lines,%s*":ID:%s*"%s*%.%.%s*id%)',
      replace = '-- REMOVED: Redundant :ID: (using TASK_ID only)',
    },
    {
      desc = "Update SCHEDULED date to org-mode format",
      find = 'table%.insert%(lines,%s*"SCHEDULED:%s*<"%s*%.%.%s*scheduled%s*%.%.%s*">"%)',
      replace = 'table.insert(lines, "SCHEDULED: " .. (org_dates.format_org_date(scheduled) or "<" .. scheduled .. ">"))',
    },
    {
      desc = "Update DEADLINE date to org-mode format",
      find = 'table%.insert%(lines,%s*"DEADLINE:%s*<"%s*%.%.%s*deadline%s*%.%.%s*">"%)',
      replace = 'table.insert(lines, "DEADLINE: " .. (org_dates.format_org_date(deadline) or "<" .. deadline .. ">"))',
    },
    {
      desc = "Replace now_id() with task_id.generate()",
      find = 'local id = now_id%(%)',
      replace = 'local id = task_id.generate()',
    },
  },
  
  clarify = {
    {
      desc = "Update date format in clarify",
      find = 'SCHEDULED:%s*<%s*"',
      replace = 'SCHEDULED: " .. org_dates.format_org_date(',
    },
  },
  
  projects = {
    {
      desc = "Remove :ID: from project creation",
      find = ':ID:',
      replace = '',  -- Remove entirely
    },
  },
}

-- Manual fix guide for complex cases
local manual_fixes = [=[
========================================
MANUAL FIXES REQUIRED
========================================

Some changes require manual intervention:

1. ADD UTILITY IMPORTS at top of each module:
   
   local task_id = require("gtd-nvim.gtd.utils.task_id")
   local org_dates = require("gtd-nvim.gtd.utils.org_dates")

2. REMOVE now_id() FUNCTION definition:
   
   Delete this entire block:
   local function now_id()
     return os.date("%Y%m%d%H%M%S")
   end

3. UPDATE DATE PROMPTS in interactive functions:
   
   Replace:
     vim.ui.input({prompt = "Date: "}, function(date)
       -- use date directly
     end)
   
   With:
     vim.ui.input({prompt = "Date (YYYY-MM-DD): "}, function(date)
       if date and org_dates.is_valid_date_format(date) then
         local org_date = org_dates.format_org_date(date)
         -- use org_date
       end
     end)

4. UPDATE PROPERTY EXTRACTION in manage.lua/lists.lua:
   
   Replace:
     local id = line:match(":ID:%s*(.+)")
   
   With:
     local task_id = line:match(":TASK_ID:%s*(.+)")

5. UPDATE ZK BREADCRUMB GENERATION:
   
   Keep as:
     ID:: [zk:TASK_ID]
   
   (References TASK_ID, not the old :ID: property)

========================================
]=]

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then return nil end
  return table.concat(lines, "\n")
end

local function write_file(path, content)
  local lines = vim.split(content, "\n")
  return pcall(vim.fn.writefile, lines, path)
end

local function backup_file(path)
  local backup_path = path .. config.backup_suffix
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return false end
  return pcall(vim.fn.writefile, lines, backup_path)
end

local function apply_fixes_to_module(module_name)
  local path = config.gtd_path .. "/" .. module_name .. ".lua"
  local module_fixes = fixes[module_name]
  
  if not module_fixes then
    return {status = "skipped", reason = "No fixes defined for this module"}
  end
  
  local content = read_file(path)
  if not content then
    return {status = "error", reason = "Could not read file"}
  end
  
  local modified = false
  local applied_fixes = {}
  
  for _, fix in ipairs(module_fixes) do
    local new_content = content:gsub(fix.find, fix.replace)
    if new_content ~= content then
      content = new_content
      modified = true
      table.insert(applied_fixes, fix.desc)
    end
  end
  
  if modified and not config.dry_run then
    backup_file(path)
    local ok = write_file(path, content)
    if not ok then
      return {status = "error", reason = "Could not write file"}
    end
  end
  
  return {
    status = modified and "modified" or "clean",
    applied = applied_fixes
  }
end

function M.run(opts)
  opts = opts or {}
  config.dry_run = opts.dry_run or false
  
  vim.notify("Starting GTD compliance fixes...", vim.log.levels.INFO, {title = "GTD Fix"})
  
  local results = {}
  local modules = {"capture", "clarify", "organize", "projects", "manage", "lists"}
  
  for _, module in ipairs(modules) do
    local result = apply_fixes_to_module(module)
    results[module] = result
    
    if result.status == "modified" then
      vim.notify(
        string.format("%s: Applied %d fixes", module, #result.applied),
        vim.log.levels.INFO,
        {title = "GTD Fix"}
      )
    elseif result.status == "error" then
      vim.notify(
        string.format("%s: %s", module, result.reason),
        vim.log.levels.ERROR,
        {title = "GTD Fix"}
      )
    end
  end
  
  -- Show summary
  local modified_count = 0
  for _, result in pairs(results) do
    if result.status == "modified" then
      modified_count = modified_count + 1
    end
  end
  
  if modified_count > 0 then
    vim.notify(
      string.format("Fixed %d modules. Please restart Neovim.", modified_count),
      vim.log.levels.WARN,
      {title = "GTD Fix"}
    )
  else
    vim.notify("All modules are compliant!", vim.log.levels.INFO, {title = "GTD Fix"})
  end
  
  -- Show manual fixes guide
  vim.notify(manual_fixes, vim.log.levels.INFO, {title = "Manual Fixes Required"})
  
  return results
end

-- Create command
vim.api.nvim_create_user_command("GtdFixCompliance", function(opts)
  local dry_run = opts.args:match("dry") ~= nil
  M.run({dry_run = dry_run})
end, {
  nargs = "?",
  complete = function() return {"dry", "live"} end,
  desc = "Fix GTD modules for v2.0 compliance"
})

-- Auto-run if this file is sourced directly
if not pcall(debug.getlocal, 4, 1) then
  vim.notify("Loading GTD compliance fixer...", vim.log.levels.INFO)
  vim.notify("Run :GtdFixCompliance to apply fixes", vim.log.levels.INFO)
end

return M
