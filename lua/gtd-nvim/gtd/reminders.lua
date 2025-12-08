-- Apple Reminders bidirectional integration for GTD system
-- Import from Reminders → GTD Inbox
-- Export GTD tasks → Reminders
-- Sync task completion status

local M = {}

-- ============================================================================
-- Config
-- ============================================================================
M.cfg = {
  gtd_root = "~/Documents/GTD",
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  default_state = "TODO",
  
  -- Import settings
  mark_imported = false,           -- Mark reminders as complete after import
  skip_completed = true,            -- Skip completed reminders on import
  import_lists = {},                -- Empty = all lists
  excluded_lists = {"Completed"},  -- Lists to skip
  
  -- Export settings
  export_list = "GTD",              -- Default list for exported tasks
  export_states = {"TODO", "NEXT", "WAITING"}, -- States to export
  sync_completion = true,           -- Mark reminders complete when task is DONE
  
  -- Priority mapping
  map_high_priority = "NEXT",      -- Priority 9 → NEXT
  map_medium_priority = "TODO",    -- Priority 5-8 → TODO  
  map_low_priority = "SOMEDAY",    -- Priority 1-4 → SOMEDAY
  
  -- Advanced
  create_zk_notes = false,
  auto_sync_on_save = false,
}

-- ============================================================================
-- Helpers
-- ============================================================================
local function xp(p) return vim.fn.expand(p) end
local function j(a,b) return (a:gsub("/+$","")).."/"..(b:gsub("^/+","")) end
local function ensure_dir(p) vim.fn.mkdir(vim.fn.fnamemodify(xp(p), ":h"), "p") end
local function readfile(p) return vim.fn.filereadable(xp(p)) == 1 and vim.fn.readfile(xp(p)) or {} end
local function writefile(p, lines) ensure_dir(xp(p)); vim.fn.writefile(lines, xp(p)) end
local function append_lines(path, lines) 
  ensure_dir(path)
  vim.fn.writefile({""}, xp(path), "a")
  vim.fn.writefile(lines, xp(path), "a")
end

local task_id = require("gtd-nvim.gtd.utils.task_id")
local ui = require("gtd-nvim.gtd.ui")

local function safe_exec_applescript(script)
  local handle = io.popen('osascript -e ' .. vim.fn.shellescape(script))
  if not handle then return nil, "Failed to execute osascript" end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if not success then return nil, "AppleScript execution failed" end
  return result
end

-- ============================================================================
-- Date Parsing & Formatting
-- ============================================================================

function M.parse_apple_date(date_str)
  if not date_str or date_str == "" or date_str == "NO_DUE" or date_str == "NO_REMIND" then 
    return nil 
  end
  
  local clean_date = date_str:gsub("^DUE:", ""):gsub("^REMIND:", ""):gsub("^DATE:", "")
  
  -- Danish months
  local danish_months = {
    januar = "01", februar = "02", marts = "03", april = "04",
    maj = "05", juni = "06", juli = "07", august = "08",
    september = "09", oktober = "10", november = "11", december = "12"
  }
  
  -- English months
  local english_months = {
    january = "01", february = "02", march = "03", april = "04", may = "05", june = "06",
    july = "07", august = "08", september = "09", october = "10", november = "11", december = "12"
  }
  
  -- Try Danish: "20. juni 2025"
  local day, month_name, year = clean_date:match("(%d+)%. (%w+) (%d+)")
  if day and month_name and year then
    local month_num = danish_months[month_name:lower()] or english_months[month_name:lower()]
    if month_num then
      return string.format("%04d-%s-%02d", tonumber(year), month_num, tonumber(day))
    end
  end
  
  -- Try English: "June 20, 2025"
  local month_eng, day_eng, year_eng = clean_date:match("(%w+) (%d+), (%d+)")
  if month_eng and day_eng and year_eng then
    local month_num = english_months[month_eng:lower()] or danish_months[month_eng:lower()]
    if month_num then
      return string.format("%04d-%s-%02d", tonumber(year_eng), month_num, tonumber(day_eng))
    end
  end
  
  -- Try numeric: "20/6/2025" or "20.6.2025"
  local d, m, y = clean_date:match("(%d+)[%./%-](%d+)[%./%-](%d+)")
  if d and m and y then
    y = tonumber(y)
    if y < 100 then y = y + 2000 end
    -- Handle both DD/MM/YYYY and MM/DD/YYYY
    if tonumber(d) > 12 then
      return string.format("%04d-%02d-%02d", y, tonumber(m), tonumber(d))
    else
      return string.format("%04d-%02d-%02d", y, tonumber(d), tonumber(m))
    end
  end
  
  return nil
end

-- Format org date to AppleScript date
function M.format_for_applescript(org_date)
  if not org_date or org_date == "" then return nil end
  
  -- Extract YYYY-MM-DD from <2025-06-20> or SCHEDULED: <2025-06-20>
  local date = org_date:match("(%d%d%d%d%-%d%d%-%d%d)")
  if not date then return nil end
  
  -- Convert to "date \"YYYY-MM-DD 00:00:00\""
  return string.format('date "%s 09:00:00"', date)
end

-- ============================================================================
-- IMPORT: Apple Reminders → GTD
-- ============================================================================

function M.fetch_reminders()
  local excluded = table.concat(vim.tbl_map(function(l) return '"'..l..'"' end, M.cfg.excluded_lists), ", ")
  
  local script = [[
tell application "Reminders"
  set output to ""
  repeat with lst in lists
    set listName to name of lst
    
    if listName is not in {]] .. excluded .. [[} then
      repeat with rem in (reminders of lst]] .. (M.cfg.skip_completed and " whose completed is false" or "") .. [[)
        try
          set remTitle to name of rem
          set remId to (id of rem) as string
          
          set remBody to ""
          try
            if body of rem is not missing value then
              set remBody to body of rem
            end if
          end try
          
          set dueText to "NO_DUE"
          try
            if due date of rem is not missing value then
              set dueText to "DUE:" & (due date of rem as string)
            end if
          end try
          
          set remindText to "NO_REMIND"
          try
            if remind me date of rem is not missing value then
              set remindText to "REMIND:" & (remind me date of rem as string)
            end if
          end try
          
          set remPriority to 0
          try
            if priority of rem is not missing value then
              set remPriority to priority of rem
            end if
          end try
          
          set isCompleted to "false"
          try
            if completed of rem is true then
              set isCompleted to "true"
            end if
          end try
          
          set output to output & remTitle & "§§§" & listName & "§§§" & remId & "§§§" & remBody & "§§§" & dueText & "§§§" & remindText & "§§§" & remPriority & "§§§" & isCompleted & "
"
        end try
      end repeat
    end if
  end repeat
  return output
end tell
]]

  local result, err = safe_exec_applescript(script)
  if not result then
    return nil, err
  end
  
  local reminders = {}
  for line in result:gmatch("[^\r\n]+") do
    if line and line ~= "" then
      local parts = vim.split(line, "§§§", {plain = true})
      if #parts >= 8 then
        table.insert(reminders, {
          title = parts[1] or "",
          list = parts[2] or "",
          apple_id = parts[3] or "",
          body = parts[4] or "",
          due_date_raw = parts[5] or "",
          reminder_date_raw = parts[6] or "",
          priority = tonumber(parts[7]) or 0,
          completed = parts[8] == "true",
        })
      end
    end
  end
  
  return reminders
end

function M.import_reminders(reminders)
  local inbox_path = j(xp(M.cfg.gtd_root), M.cfg.inbox_file)
  local imported = 0
  local skipped = 0
  
  -- Check for existing Apple IDs
  local existing_ids = {}
  local existing_lines = readfile(inbox_path)
  for _, line in ipairs(existing_lines) do
    local aid = line:match(":APPLE_ID:%s*(.+)")
    if aid and aid ~= "missing value" then
      existing_ids[aid] = true
    end
  end
  
  for _, reminder in ipairs(reminders) do
    if existing_ids[reminder.apple_id] then
      skipped = skipped + 1
      goto continue
    end
    
    -- Apply list filter
    if #M.cfg.import_lists > 0 then
      local found = false
      for _, allowed in ipairs(M.cfg.import_lists) do
        if reminder.list == allowed then found = true; break end
      end
      if not found then
        skipped = skipped + 1
        goto continue
      end
    end
    
    local id = task_id.generate()
    local title = reminder.title or "Imported Reminder"
    local list_tag = (reminder.list or "APPLE"):gsub("%s+", "_"):upper():gsub("[^%w_]", "")
    
    -- Map priority to state
    local state = M.cfg.default_state
    if reminder.priority >= 9 then
      state = M.cfg.map_high_priority
    elseif reminder.priority >= 5 then  
      state = M.cfg.map_medium_priority
    elseif reminder.priority >= 1 then
      state = M.cfg.map_low_priority
    end
    
    local lines = {}
    table.insert(lines, string.format("* %s %s  :%s:", state, title, list_tag))
    
    -- Add dates
    local due = M.parse_apple_date(reminder.due_date_raw)
    local scheduled = M.parse_apple_date(reminder.reminder_date_raw)
    
    if scheduled then
      table.insert(lines, "SCHEDULED: <" .. scheduled .. ">")
    end
    if due then
      table.insert(lines, "DEADLINE: <" .. due .. ">")
    end
    
    table.insert(lines, ":PROPERTIES:")
    table.insert(lines, ":ID:        " .. id)
    table.insert(lines, ":TASK_ID:   " .. id)
    table.insert(lines, ":APPLE_ID:  " .. reminder.apple_id)
    table.insert(lines, ":APPLE_LIST: " .. reminder.list)
    if reminder.priority > 0 then
      table.insert(lines, ":PRIORITY:  " .. reminder.priority)
    end
    table.insert(lines, ":END:")
    table.insert(lines, string.format("ID:: [[zk:%s]]", id))
    
    if reminder.body and reminder.body ~= "" then
      table.insert(lines, "")
      table.insert(lines, reminder.body)
    end
    
    table.insert(lines, "")
    table.insert(lines, string.format("#+IMPORTED: %s from Apple Reminders (%s)", 
      os.date("%Y-%m-%d %H:%M"), reminder.list))
    
    append_lines(inbox_path, lines)
    imported = imported + 1
    
    if M.cfg.mark_imported and reminder.apple_id and reminder.apple_id ~= "" then
      M.complete_reminder(reminder.apple_id)
    end
    
    ::continue::
  end
  
  return imported, skipped
end

function M.import_all()
  vim.notify("🍎 Importing from Apple Reminders...", vim.log.levels.INFO)
  
  local reminders, err = M.fetch_reminders()
  if not reminders then
    vim.notify("❌ Failed to fetch: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end
  
  if #reminders == 0 then
    vim.notify("No reminders found to import", vim.log.levels.INFO)
    return
  end
  
  local imported, skipped = M.import_reminders(reminders)
  vim.notify(string.format("✅ Imported %d reminders, skipped %d", imported, skipped), 
    vim.log.levels.INFO)
end

-- ============================================================================
-- EXPORT: GTD Tasks → Apple Reminders
-- ============================================================================

function M.scan_tasks_for_export()
  local files = vim.fn.globpath(xp(M.cfg.gtd_root), "**/*.org", false, true)
  local tasks = {}
  
  for _, path in ipairs(files) do
    local lines = readfile(path)
    
    for i, line in ipairs(lines) do
      if line:match("^%*+%s+") then
        local state = line:match("^%*+%s+(%u+)%s")
        
        local should_export = false
        for _, s in ipairs(M.cfg.export_states) do
          if state == s then should_export = true; break end
        end
        
        if should_export then
          local title = line:gsub("^%*+%s+%u+%s+", ""):gsub("%s*:%w+:%s*$", "")
          local task_id_val, apple_id, scheduled, deadline
          
          for j = i + 1, math.min(i + 20, #lines) do
            if lines[j]:match("^%*") then break end
            task_id_val = task_id_val or lines[j]:match(":TASK_ID:%s*(.+)")
            apple_id = apple_id or lines[j]:match(":APPLE_ID:%s*(.+)")
            scheduled = scheduled or lines[j]:match("SCHEDULED:%s*<([^>]+)>")
            deadline = deadline or lines[j]:match("DEADLINE:%s*<([^>]+)>")
          end
          
          if title ~= "" then
            table.insert(tasks, {
              title = title,
              state = state,
              task_id = task_id_val,
              apple_id = apple_id,
              scheduled = scheduled,
              deadline = deadline,
              path = path,
              lnum = i,
            })
          end
        end
      end
    end
  end
  
  return tasks
end

function M.create_reminder(task, list_name)
  list_name = list_name or M.cfg.export_list
  
  local due_str = task.deadline and string.format("set due date of newReminder to %s", 
    M.format_for_applescript(task.deadline)) or ""
  local remind_str = task.scheduled and string.format("set remind me date of newReminder to %s", 
    M.format_for_applescript(task.scheduled)) or ""
  local priority_str = task.state == "NEXT" and "set priority of newReminder to 9" or ""
  
  local script = string.format([[
tell application "Reminders"
  set targetList to list "%s"
  set newReminder to make new reminder at end of targetList
  set name of newReminder to %s
  %s
  %s
  %s
  return (id of newReminder) as string
end tell
]], 
    list_name,
    vim.fn.shellescape(task.title),
    due_str,
    remind_str,
    priority_str
  )
  
  local result, err = safe_exec_applescript(script)
  if not result then
    return nil, err
  end
  
  return result:gsub("%s+$", "")
end

function M.update_reminder(apple_id, task)
  local due_str = task.deadline and string.format("set due date of targetReminder to %s", 
    M.format_for_applescript(task.deadline)) or "set due date of targetReminder to missing value"
  local remind_str = task.scheduled and string.format("set remind me date of targetReminder to %s", 
    M.format_for_applescript(task.scheduled)) or "set remind me date of targetReminder to missing value"
  local priority_str = task.state == "NEXT" and "set priority of targetReminder to 9" or "set priority of targetReminder to 0"
  
  local script = string.format([[
tell application "Reminders"
  set targetReminder to reminder id "%s"
  set name of targetReminder to %s
  %s
  %s
  %s
  return "OK"
end tell
]], 
    apple_id,
    vim.fn.shellescape(task.title),
    due_str,
    remind_str,
    priority_str
  )
  
  local result, err = safe_exec_applescript(script)
  return result ~= nil, err
end

function M.complete_reminder(apple_id)
  if not apple_id or apple_id == "" or apple_id == "missing value" then
    return false
  end
  
  local script = string.format([[
tell application "Reminders"
  try
    set targetReminder to reminder id "%s"
    set completed of targetReminder to true
    return "OK"
  on error
    return "ERROR"
  end try
end tell
]], apple_id)
  
  local result = safe_exec_applescript(script)
  return result and result:find("OK") ~= nil
end

function M.delete_reminder(apple_id)
  if not apple_id or apple_id == "" or apple_id == "missing value" then
    return false
  end
  
  local script = string.format([[
tell application "Reminders"
  try
    set targetReminder to reminder id "%s"
    delete targetReminder
    return "OK"
  on error
    return "ERROR"
  end try
end tell
]], apple_id)
  
  local result = safe_exec_applescript(script)
  return result and result:find("OK") ~= nil
end

function M.export_tasks()
  vim.notify("🚀 Exporting tasks to Apple Reminders...", vim.log.levels.INFO)
  
  local tasks = M.scan_tasks_for_export()
  if #tasks == 0 then
    vim.notify("No tasks found to export", vim.log.levels.INFO)
    return
  end
  
  local created, updated, errors = 0, 0, 0
  
  for _, task in ipairs(tasks) do
    if task.apple_id and task.apple_id ~= "" then
      local ok, err = M.update_reminder(task.apple_id, task)
      if ok then
        updated = updated + 1
      else
        errors = errors + 1
        vim.notify(string.format("⚠️  Failed to update: %s (%s)", task.title, err or "unknown"), 
          vim.log.levels.WARN)
      end
    else
      local apple_id, err = M.create_reminder(task, M.cfg.export_list)
      if apple_id then
        created = created + 1
        M.add_apple_id_to_task(task.path, task.lnum, apple_id)
      else
        errors = errors + 1
        vim.notify(string.format("⚠️  Failed to create: %s (%s)", task.title, err or "unknown"),
          vim.log.levels.WARN)
      end
    end
  end
  
  vim.notify(string.format("✅ Export complete: %d created, %d updated, %d errors", 
    created, updated, errors), vim.log.levels.INFO)
end

function M.add_apple_id_to_task(path, lnum, apple_id)
  local lines = readfile(path)
  if not lines or #lines == 0 then return end
  
  local prop_start, prop_end
  for i = lnum + 1, math.min(lnum + 15, #lines) do
    if lines[i]:match("^%s*:PROPERTIES:%s*$") then
      prop_start = i
    elseif prop_start and lines[i]:match("^%s*:END:%s*$") then
      prop_end = i
      break
    end
  end
  
  if prop_start and prop_end then
    for i = prop_start + 1, prop_end - 1 do
      if lines[i]:match(":APPLE_ID:") then
        lines[i] = ":APPLE_ID:  " .. apple_id
        writefile(path, lines)
        return
      end
    end
    table.insert(lines, prop_end, ":APPLE_ID:  " .. apple_id)
    writefile(path, lines)
  end
end

-- ============================================================================
-- SYNC Operations
-- ============================================================================

function M.sync_completion_status()
  vim.notify("🔄 Syncing completion status...", vim.log.levels.INFO)
  
  local files = vim.fn.globpath(xp(M.cfg.gtd_root), "**/*.org", false, true)
  local completed, errors = 0, 0
  
  for _, path in ipairs(files) do
    local lines = readfile(path)
    
    for i, line in ipairs(lines) do
      if line:match("^%*+%s+DONE%s") then
        local apple_id
        for j = i + 1, math.min(i + 15, #lines) do
          if lines[j]:match("^%*") then break end
          apple_id = lines[j]:match(":APPLE_ID:%s*(.+)")
          if apple_id then break end
        end
        
        if apple_id and apple_id ~= "" and apple_id ~= "missing value" then
          if M.complete_reminder(apple_id) then
            completed = completed + 1
          else
            errors = errors + 1
          end
        end
      end
    end
  end
  
  vim.notify(string.format("✅ Marked %d reminders complete, %d errors", completed, errors),
    vim.log.levels.INFO)
end

function M.bidirectional_sync()
  vim.notify("🔄 Starting bidirectional sync...", vim.log.levels.INFO)
  
  M.import_all()
  M.export_tasks()
  
  if M.cfg.sync_completion then
    M.sync_completion_status()
  end
  
  vim.notify("✅ Bidirectional sync complete", vim.log.levels.INFO)
end

-- ============================================================================
-- Utilities
-- ============================================================================

function M.clean_inbox_duplicates()
  local inbox_path = j(xp(M.cfg.gtd_root), M.cfg.inbox_file)
  local lines = readfile(inbox_path)
  
  if #lines == 0 then
    vim.notify("Inbox is empty", vim.log.levels.INFO)
    return
  end
  
  local seen = {}
  local clean_lines = {}
  local removed = 0
  
  local i = 1
  while i <= #lines do
    local line = lines[i]
    
    if line:match("^%*+%s+") then
      local apple_id = nil
      for j = i + 1, math.min(i + 15, #lines) do
        if lines[j]:match("^%*") then break end
        local aid = lines[j]:match(":APPLE_ID:%s*(.+)")
        if aid and aid ~= "missing value" then
          apple_id = aid
          break
        end
      end
      
      if apple_id and seen[apple_id] then
        removed = removed + 1
        local level = #(line:match("^(%*+)") or "")
        repeat
          i = i + 1
        until i > #lines or (lines[i]:match("^(%*+)") and #(lines[i]:match("^(%*+)")) <= level)
        goto continue
      elseif apple_id then
        seen[apple_id] = true
      end
    end
    
    table.insert(clean_lines, line)
    i = i + 1
    ::continue::
  end
  
  if removed > 0 then
    local backup = inbox_path .. ".backup." .. os.date("%Y%m%d_%H%M%S")
    writefile(backup, lines)
    writefile(inbox_path, clean_lines)
    vim.notify(string.format("🧹 Removed %d duplicates. Backup: %s", removed, 
      vim.fn.fnamemodify(backup, ":t")), vim.log.levels.INFO)
  else
    vim.notify("No duplicates found", vim.log.levels.INFO)
  end
end

function M.test_basic()
  vim.notify("🧪 Testing Apple Reminders access...", vim.log.levels.INFO)
  
  local result, err = safe_exec_applescript('tell application "Reminders" to return "OK"')
  
  if result and result:find("OK") then
    vim.notify("✅ Apple Reminders access works", vim.log.levels.INFO)
  else
    vim.notify("❌ Failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    vim.notify("Check System Settings → Privacy & Security → Automation", vim.log.levels.INFO)
  end
end

function M.show_config()
  local info = {
    "📋 Apple Reminders Configuration:",
    "",
    "Import:",
    "  Mark imported as completed: " .. tostring(M.cfg.mark_imported),
    "  Skip completed: " .. tostring(M.cfg.skip_completed),
    "  Import lists: " .. (#M.cfg.import_lists > 0 and table.concat(M.cfg.import_lists, ", ") or "All"),
    "  Excluded: " .. table.concat(M.cfg.excluded_lists, ", "),
    "",
    "Export:",
    "  Export list: " .. M.cfg.export_list,
    "  Export states: " .. table.concat(M.cfg.export_states, ", "),
    "  Sync completion: " .. tostring(M.cfg.sync_completion),
    "",
    "GTD root: " .. M.cfg.gtd_root,
  }
  
  vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end

function M.configure()
  local options = {
    "1. Show configuration",
    "2. Toggle: Mark imported as completed", 
    "3. Toggle: Sync completion status",
    "4. Test: Apple Reminders access",
    "5. Help: Setup instructions",
  }
  
  ui.select(options, { prompt = "Configure Reminders" }, function(choice)
    if not choice then return end
    
    if choice:find("Show") then
      M.show_config()
    elseif choice:find("Mark imported") then
      M.cfg.mark_imported = not M.cfg.mark_imported
      vim.notify("✅ Mark imported: " .. tostring(M.cfg.mark_imported), vim.log.levels.INFO)
    elseif choice:find("Sync completion") then
      M.cfg.sync_completion = not M.cfg.sync_completion
      vim.notify("✅ Sync completion: " .. tostring(M.cfg.sync_completion), vim.log.levels.INFO)
    elseif choice:find("Test") then
      M.test_basic()
    elseif choice:find("Help") then
      local help = {
        "📚 Apple Reminders Setup:",
        "",
        "1. Grant permissions:",
        "   System Settings → Privacy & Security → Automation",
        "   → [Your Terminal] → Enable 'Reminders'",
        "",
        "2. Commands:",
        "   :GtdImportReminders   - Import from Reminders",
        "   :GtdExportTasks       - Export to Reminders",
        "   :GtdSyncReminders     - Bidirectional sync",
        "   :GtdSyncCompletion    - Sync DONE tasks",
        "",
        "3. Properties:",
        "   :APPLE_ID:  - Links task to Reminders",
        "   :APPLE_LIST: - Source list name",
      }
      vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
    end
  end)
end

-- ============================================================================
-- Setup
-- ============================================================================

function M.setup(user_cfg)
  if user_cfg then
    M.cfg = vim.tbl_deep_extend("force", M.cfg, user_cfg)
  end
  
  ensure_dir(j(xp(M.cfg.gtd_root), M.cfg.inbox_file))
  ensure_dir(j(xp(M.cfg.gtd_root), M.cfg.projects_dir))
  
  vim.api.nvim_create_user_command("GtdImportReminders", function() M.import_all() end, {})
  vim.api.nvim_create_user_command("GtdExportTasks", function() M.export_tasks() end, {})
  vim.api.nvim_create_user_command("GtdSyncReminders", function() M.bidirectional_sync() end, {})
  vim.api.nvim_create_user_command("GtdSyncCompletion", function() M.sync_completion_status() end, {})
  vim.api.nvim_create_user_command("GtdRemindersConfig", function() M.configure() end, {})
  vim.api.nvim_create_user_command("GtdCleanInboxDuplicates", function() M.clean_inbox_duplicates() end, {})
  vim.api.nvim_create_user_command("GtdRemindersTest", function() M.test_basic() end, {})
  
  if M.cfg.auto_sync_on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = "*.org",
      callback = function()
        local path = vim.fn.expand("%:p")
        if path:find(xp(M.cfg.gtd_root), 1, true) then
          vim.schedule(function()
            M.export_tasks()
            if M.cfg.sync_completion then
              M.sync_completion_status()
            end
          end)
        end
      end,
    })
  end
end

return M
