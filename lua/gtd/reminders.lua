-- ~/.config/nvim/lua/gtd/reminders.lua
-- Apple Reminders integration for GTD system
local M = {}

-- Config
M.cfg = {
  gtd_root = "~/Documents/GTD",
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  default_state = "TODO",
  mark_imported = true,
  skip_completed = true,
  import_lists = {},
  excluded_lists = {"Completed"},
  map_high_priority = "NEXT",
  map_medium_priority = "TODO", 
  map_low_priority = "SOMEDAY",
  create_zk_notes = false,
}

-- Helpers
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

local task_id = require("gtd.utils.task_id")
local ui = require("gtd.ui")

-- Enhanced simple import with detailed date debugging
function M.debug_simple_import()
  vim.notify("🔧 Testing simple import with date debugging...", vim.log.levels.INFO)
  
  local script = [[
tell application "Reminders"
  set output to ""
  repeat with lst in lists
    set listName to name of lst
    repeat with rem in (reminders of lst whose completed is false)
      set remTitle to name of rem
      
      -- Get Apple ID
      set remId to ""
      try
        set remId to (id of rem) as string
      end try
      
      -- Get body/notes
      set remBody to ""
      try
        if body of rem is not missing value then
          set remBody to body of rem
        end if
      end try
      
      -- Get due date with detailed debugging
      set dueText to "NO_DUE"
      try
        if due date of rem is not missing value then
          set dueText to "DUE:" & (due date of rem as string)
        end if
      on error
        set dueText to "DUE_ERROR"
      end try
      
      -- Get reminder/alert date with detailed debugging  
      set remindText to "NO_REMIND"
      try
        if remind me date of rem is not missing value then
          set remindText to "REMIND:" & (remind me date of rem as string)
        end if
      on error
        set remindText to "REMIND_ERROR"
      end try
      
      -- Get priority
      set remPriority to 0
      try
        if priority of rem is not missing value then
          set remPriority to priority of rem
        end if
      end try
      
      set output to output & remTitle & "§§§" & listName & "§§§" & remId & "§§§" & remBody & "§§§" & dueText & "§§§" & remindText & "§§§" & remPriority & "
"
      
      if (count of paragraphs of output) > 5 then exit repeat
    end repeat
    if (count of paragraphs of output) > 5 then exit repeat
  end repeat
  return output
end tell
]]

  local handle = io.popen('osascript -e ' .. vim.fn.shellescape(script))
  if not handle then
    vim.notify("❌ Failed to execute", vim.log.levels.ERROR)
    return
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if not success then
    vim.notify("❌ Command failed", vim.log.levels.ERROR)
    return
  end
  
  vim.notify("📋 Raw AppleScript result:", vim.log.levels.INFO)
  vim.notify(tostring(result), vim.log.levels.INFO)
  
  if result and result ~= "" then
    local reminders = {}
    for line in result:gmatch("[^\r\n]+") do
      if line and line ~= "" then
        local parts = vim.split(line, "§§§", {plain = true})
        if #parts >= 7 then
          local reminder = {
            title = parts[1] or "",
            list = parts[2] or "",
            apple_id = parts[3] or "",
            body = parts[4] or "",
            due_date_raw = parts[5] or "",
            reminder_date_raw = parts[6] or "",
            priority = tonumber(parts[7]) or 0,
            completed = false,
          }
          
          -- Debug the raw date strings
          vim.notify(string.format("📅 DEBUG - %s:", reminder.title), vim.log.levels.INFO)
          vim.notify(string.format("  Due raw: '%s'", reminder.due_date_raw), vim.log.levels.INFO)
          vim.notify(string.format("  Remind raw: '%s'", reminder.reminder_date_raw), vim.log.levels.INFO)
          
          -- Parse dates
          reminder.due_date = M.parse_apple_date_debug(reminder.due_date_raw)
          reminder.reminder_date = M.parse_apple_date_debug(reminder.reminder_date_raw)
          
          vim.notify(string.format("  Due parsed: '%s'", reminder.due_date or "nil"), vim.log.levels.INFO)
          vim.notify(string.format("  Remind parsed: '%s'", reminder.reminder_date or "nil"), vim.log.levels.INFO)
          
          table.insert(reminders, reminder)
        end
      end
    end
    
    if #reminders > 0 then
      vim.notify(string.format("✅ Found %d reminders", #reminders), vim.log.levels.INFO)
      local imported = M.import_to_inbox_enhanced(reminders)
      vim.notify(string.format("✅ Imported %d reminders", imported), vim.log.levels.INFO)
    else
      vim.notify("No reminders parsed", vim.log.levels.WARN)
    end
  else
    vim.notify("No reminders found", vim.log.levels.INFO)
  end
end

function M.parse_apple_date_debug(date_str)
  if not date_str or date_str == "" or date_str == "NO_DUE" or date_str == "NO_REMIND" then 
    return nil 
  end
  
  vim.notify(string.format("🔍 Parsing date string: '%s'", date_str), vim.log.levels.DEBUG)
  
  -- Handle prefixed debug strings
  local clean_date = date_str:gsub("^DUE:", ""):gsub("^REMIND:", "")
  vim.notify(string.format("🔍 Cleaned date string: '%s'", clean_date), vim.log.levels.DEBUG)
  
  -- Handle Danish date formats
  local danish_months = {
    januar = "01", februar = "02", marts = "03", april = "04",
    maj = "05", juni = "06", juli = "07", august = "08",
    september = "09", oktober = "10", november = "11", december = "12"
  }
  
  -- Try various Danish formats
  -- "fredag den 20. juni 2025 kl. 12:00:00"
  local day, month_name, year = clean_date:match("(%d+)%. (%w+) (%d+)")
  if day and month_name and year then
    vim.notify(string.format("🔍 Matched Danish format: day=%s, month=%s, year=%s", day, month_name, year), vim.log.levels.DEBUG)
    local month_num = danish_months[month_name:lower()]
    if month_num then
      local result = string.format("%04d-%s-%02d", tonumber(year), month_num, tonumber(day))
      vim.notify(string.format("✅ Parsed Danish date: %s", result), vim.log.levels.DEBUG)
      return result
    end
  end
  
  -- Try English months too
  local english_months = {
    january = "01", february = "02", march = "03", april = "04", may = "05", june = "06",
    july = "07", august = "08", september = "09", october = "10", november = "11", december = "12"
  }
  
  -- "Friday, June 20, 2025 at 12:00:00 PM"
  local month_eng, day_eng, year_eng = clean_date:match("(%w+) (%d+), (%d+)")
  if month_eng and day_eng and year_eng then
    vim.notify(string.format("🔍 Matched English format: month=%s, day=%s, year=%s", month_eng, day_eng, year_eng), vim.log.levels.DEBUG)
    local month_num = english_months[month_eng:lower()]
    if month_num then
      local result = string.format("%04d-%s-%02d", tonumber(year_eng), month_num, tonumber(day_eng))
      vim.notify(string.format("✅ Parsed English date: %s", result), vim.log.levels.DEBUG)
      return result
    end
  end
  
  -- Try numeric formats: "20/6/2025", "20.6.2025", "2025-06-20"
  local d, m, y = clean_date:match("(%d+)[%./%-](%d+)[%./%-](%d+)")
  if d and m and y then
    vim.notify(string.format("🔍 Matched numeric format: %s-%s-%s", d, m, y), vim.log.levels.DEBUG)
    y = tonumber(y)
    if y < 100 then y = y + 2000 end
    local result = string.format("%04d-%02d-%02d", y, tonumber(m), tonumber(d))
    vim.notify(string.format("✅ Parsed numeric date: %s", result), vim.log.levels.DEBUG)
    return result
  end
  
  vim.notify(string.format("❌ Could not parse date: '%s'", date_str), vim.log.levels.WARN)
  return nil
end

function M.import_to_inbox_enhanced(reminders)
  local count = 0
  local inbox_path = j(xp(M.cfg.gtd_root), M.cfg.inbox_file)
  
  for _, reminder in ipairs(reminders) do
    local id = task_id.generate()
    local title = reminder.title or "Imported Reminder"
    local list_tag = (reminder.list or "APPLE"):gsub("%s+", "_"):upper():gsub("[^%w_]", "")
    
    -- Map priority to state
    local state = M.cfg.default_state
    if reminder.priority >= 9 then
      state = "NEXT"
    elseif reminder.priority >= 5 then  
      state = "TODO"
    elseif reminder.priority >= 1 then
      state = "SOMEDAY"
    end
    
    local lines = {}
    table.insert(lines, string.format("* %s %s  :%s:", state, title, list_tag))
    
    -- Add dates - use the correct function name
    local due = M.parse_apple_date_debug(reminder.due_date_raw)
    local scheduled = M.parse_apple_date_debug(reminder.reminder_date_raw)
    
    if scheduled then
      table.insert(lines, "SCHEDULED: <" .. scheduled .. ">")
      vim.notify(string.format("📅 Added SCHEDULED: %s", scheduled), vim.log.levels.DEBUG)
    end
    if due then
      table.insert(lines, "DEADLINE: <" .. due .. ">")
      vim.notify(string.format("📅 Added DEADLINE: %s", due), vim.log.levels.DEBUG)
    end
    
    table.insert(lines, ":PROPERTIES:")
    table.insert(lines, ":ID:        " .. id)
    table.insert(lines, ":TASK_ID:   " .. id)
    
    -- Only add Apple ID if it's valid
    if reminder.apple_id and reminder.apple_id ~= "" then
      table.insert(lines, ":APPLE_ID:  " .. reminder.apple_id)
    end
    
    table.insert(lines, ":APPLE_LIST: " .. (reminder.list or "Unknown"))
    
    if reminder.priority > 0 then
      table.insert(lines, ":PRIORITY:  " .. reminder.priority)
    end
    
    table.insert(lines, ":END:")
    table.insert(lines, string.format("ID:: [[zk:%s]]", id))
    
    -- Add body if present
    if reminder.body and reminder.body ~= "" then
      table.insert(lines, "")
      table.insert(lines, reminder.body)
    end
    
    table.insert(lines, "")
    table.insert(lines, string.format("#+IMPORTED: %s from Apple Reminders (%s)", 
      os.date("%Y-%m-%d %H:%M"), reminder.list or "Unknown"))
    
    append_lines(inbox_path, lines)
    count = count + 1
  end
  
  return count
end

function M.test_basic()
  vim.notify("🧪 Testing basic Apple Reminders access...", vim.log.levels.INFO)
  
  local handle = io.popen('osascript -e ' .. vim.fn.shellescape('tell application "Reminders" to return "OK"'))
  if not handle then
    vim.notify("❌ Cannot execute osascript", vim.log.levels.ERROR)
    return
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if success and result and result:find("OK") then
    vim.notify("✅ Apple Reminders access works", vim.log.levels.INFO)
  else
    vim.notify("❌ Apple Reminders access failed: " .. tostring(result), vim.log.levels.ERROR)
  end
end

function M.show_config()
  local info = {
    "📋 Apple Reminders Configuration:",
    "",
    "Mark imported as completed: " .. tostring(M.cfg.mark_imported),
    "Skip completed reminders: " .. tostring(M.cfg.skip_completed),
    "Default state: " .. M.cfg.default_state,
    "GTD root: " .. M.cfg.gtd_root,
    "Inbox file: " .. M.cfg.inbox_file,
  }
  
  vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end

function M.clean_inbox_duplicates()
  local inbox_path = j(xp(M.cfg.gtd_root), M.cfg.inbox_file)
  local lines = readfile(inbox_path)
  
  if #lines == 0 then
    vim.notify("Inbox is empty", vim.log.levels.INFO)
    return
  end
  
  -- Simple duplicate removal by Apple ID
  local seen = {}
  local clean_lines = {}
  local removed = 0
  
  local i = 1
  while i <= #lines do
    local line = lines[i]
    
    if line:match("^%*+%s+") then
      -- Found heading, look for Apple ID
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
        -- Skip this duplicate subtree
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
    vim.notify(string.format("🧹 Removed %d duplicates. Backup: %s", removed, vim.fn.fnamemodify(backup, ":t")), vim.log.levels.INFO)
  else
    vim.notify("No duplicates found", vim.log.levels.INFO)
  end
end

function M.configure()
  local options = {
    "1. Show current configuration",
    "2. Toggle: Mark imported as completed", 
    "3. Test: Apple Reminders access",
    "4. Help: Setup instructions",
  }
  
  ui.select(options, { prompt = "Configure Reminders" }, function(choice)
    if not choice then return end
    
    if choice:find("Show current") then
      M.show_config()
    elseif choice:find("Mark imported") then
      M.cfg.mark_imported = not M.cfg.mark_imported
      vim.notify("✅ Mark imported: " .. tostring(M.cfg.mark_imported), vim.log.levels.INFO)
    elseif choice:find("Test:") then
      M.test_basic()
    elseif choice:find("Help:") then
      vim.notify("If tests fail, check System Preferences → Privacy → Automation → [Your Terminal] → Reminders", vim.log.levels.INFO)
    end
  end)
end

-- Main import function (keeping it simple)
function M.import_all()
  vim.notify("🍎 Starting Apple Reminders import...", vim.log.levels.INFO)
  M.debug_simple_import()
end

function M.setup(user_cfg)
  if user_cfg then
    M.cfg = vim.tbl_deep_extend("force", M.cfg, user_cfg)
  end
  
  ensure_dir(j(xp(M.cfg.gtd_root), M.cfg.inbox_file))
  ensure_dir(j(xp(M.cfg.gtd_root), M.cfg.projects_dir))
  
  -- Commands
  vim.api.nvim_create_user_command("GtdImportReminders", function() M.import_all() end, {})
  vim.api.nvim_create_user_command("GtdRemindersConfig", function() M.configure() end, {})
  vim.api.nvim_create_user_command("GtdCleanInboxDuplicates", function() M.clean_inbox_duplicates() end, {})
  vim.api.nvim_create_user_command("GtdRemindersTest", function() M.test_basic() end, {})
  vim.api.nvim_create_user_command("GtdDebugSimple", function() M.debug_simple_import() end, {})
end

return M