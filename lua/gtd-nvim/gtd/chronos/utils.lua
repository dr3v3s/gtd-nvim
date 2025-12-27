-- ============================================================================
-- GTD-NVIM CHRONOS UTILITIES
-- ============================================================================
-- Shared helper functions for path resolution, file operations,
-- date formatting, and org-mode entry builders.
--
-- @module gtd-nvim.gtd.chronos.utils
-- @version 1.0.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-27"

-- ============================================================================
-- GLYPHS
-- ============================================================================

M.glyphs = {
  next = "󰁔",
  todo = "󰄲",
  waiting = "󰈸",
  someday = "󰋚",
  done = "󰄳",
  cancelled = "󰜺",
  project = "󰷐",
  inbox = "󰆏",
  area = "󰉋",
  archive = "󰀼",
  calendar = "󰃭",
  recurring = "󰑖",
}

-- ============================================================================
-- LOGGING
-- ============================================================================

M.debug = false

function M.log(msg)
  if M.debug then
    vim.notify("[chronos] " .. msg, vim.log.levels.DEBUG)
  end
end

-- ============================================================================
-- PATH HELPERS
-- ============================================================================

function M.gtd_home()
  local ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  return (ok and shared.gtd_home) and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
end

function M.zk_home()
  local ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  return (ok and shared.notes_home) and shared.notes_home() or vim.fn.expand("~/Documents/Notes")
end

function M.inbox_path()
  return M.gtd_home() .. "/Inbox.org"
end

function M.archive_path()
  return M.gtd_home() .. "/Archive"
end

function M.projects_path()
  return M.gtd_home() .. "/Projects"
end

function M.areas_path()
  return M.gtd_home() .. "/Areas"
end

-- ============================================================================
-- FILE OPERATIONS
-- ============================================================================

function M.file_exists(path)
  return vim.fn.filereadable(vim.fn.expand(path)) == 1
end

function M.ensure_file(path, title)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({ "#+TITLE: " .. title, "" }, path)
  end
end

function M.append_to_file(path, lines)
  local expanded = vim.fn.expand(path)
  local result = vim.fn.writefile(lines, expanded, "a")
  return result == 0
end

function M.write_file(path, lines)
  local expanded = vim.fn.expand(path)
  local result = vim.fn.writefile(lines, expanded)
  return result == 0
end

--- Check if file has a PROJECT heading in first 15 lines
function M.has_project_heading(path)
  local f = io.open(path, "r")
  if not f then return false end
  
  for i = 1, 15 do
    local line = f:read("*line")
    if not line then break end
    if line:match("^%*+%s+PROJECT%s+") then
      f:close()
      return true
    end
  end
  f:close()
  return false
end

-- ============================================================================
-- DATE HELPERS
-- ============================================================================

function M.generate_task_id()
  return os.date("%Y%m%d%H%M%S")
end

function M.format_inactive_timestamp()
  return os.date("[%Y-%m-%d %a]")
end

function M.format_active_timestamp()
  return os.date("<%Y-%m-%d %a>")
end

function M.format_active_date(date_str)
  if not date_str or date_str == "" then return nil end
  
  -- Already formatted
  if date_str:match("^<.*>$") then return date_str end
  
  -- Parse YYYY-MM-DD
  local y, m, d = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if y and m and d then
    local t = os.time({ year = y, month = m, day = d })
    return os.date("<%Y-%m-%d %a>", t)
  end
  
  return "<" .. date_str .. ">"
end

function M.future_date(days, from_date)
  local base = from_date and os.time(from_date) or os.time()
  return os.date("%Y-%m-%d", base + (days * 86400))
end

--- Parse smart date input like "+1d", "+2w", "monday", "2025-01-15"
function M.parse_smart_date(input, base_date)
  if not input or input == "" then return nil end
  
  input = vim.trim(input:lower())
  local base = base_date and os.time(base_date) or os.time()
  
  -- Relative: +1d, +2w, +3m
  local num, unit = input:match("^%+(%d+)([dwm])$")
  if num and unit then
    num = tonumber(num)
    if unit == "d" then
      return os.date("%Y-%m-%d", base + num * 86400)
    elseif unit == "w" then
      return os.date("%Y-%m-%d", base + num * 7 * 86400)
    elseif unit == "m" then
      local t = os.date("*t", base)
      t.month = t.month + num
      return os.date("%Y-%m-%d", os.time(t))
    end
  end
  
  -- Day names
  local days = { sunday = 0, monday = 1, tuesday = 2, wednesday = 3,
                 thursday = 4, friday = 5, saturday = 6,
                 sun = 0, mon = 1, tue = 2, wed = 3, thu = 4, fri = 5, sat = 6 }
  if days[input] then
    local t = os.date("*t", base)
    local target = days[input]
    local diff = (target - t.wday + 7) % 7
    if diff == 0 then diff = 7 end
    return os.date("%Y-%m-%d", base + diff * 86400)
  end
  
  -- Special keywords
  if input == "today" then
    return os.date("%Y-%m-%d", base)
  elseif input == "tomorrow" or input == "tom" then
    return os.date("%Y-%m-%d", base + 86400)
  elseif input == "next week" or input == "nextweek" then
    return os.date("%Y-%m-%d", base + 7 * 86400)
  elseif input == "next month" or input == "nextmonth" then
    local t = os.date("*t", base)
    t.month = t.month + 1
    return os.date("%Y-%m-%d", os.time(t))
  end
  
  -- ISO date: YYYY-MM-DD
  if input:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return input
  end
  
  -- Short date: MM-DD (assume current year)
  local m, d = input:match("^(%d%d)%-(%d%d)$")
  if m and d then
    local t = os.date("*t", base)
    return string.format("%04d-%02d-%02d", t.year, tonumber(m), tonumber(d))
  end
  
  return nil
end

-- ============================================================================
-- STRING HELPERS
-- ============================================================================

function M.slugify(title)
  return title:lower()
    :gsub("[æ]", "ae"):gsub("[ø]", "oe"):gsub("[å]", "aa")
    :gsub("[Æ]", "Ae"):gsub("[Ø]", "Oe"):gsub("[Å]", "Aa")
    :gsub("%s+", "-")
    :gsub("[^%w%-]", "")
    :gsub("%-+", "-")
    :gsub("^%-", "")
    :gsub("%-$", "")
end

-- ============================================================================
-- ORG ENTRY BUILDERS
-- ============================================================================

--- Build a task entry (returns lines array and task_id)
---@param opts table { title, state, level, tags, scheduled, deadline, area, effort, ... }
---@return table lines, string task_id
function M.build_task_entry(opts)
  opts = opts or {}
  local id = opts.task_id or M.generate_task_id()
  local level = opts.level or 1
  local state = opts.state or "TODO"
  local stars = string.rep("*", level)
  
  local lines = {}
  
  -- Heading line
  local heading = stars .. " " .. state .. " " .. (opts.title or "Untitled")
  if opts.tags and #opts.tags > 0 then
    local tag_str = ":" .. table.concat(opts.tags, ":") .. ":"
    heading = heading .. "  " .. tag_str
  end
  table.insert(lines, heading)
  
  -- SCHEDULED/DEADLINE
  if opts.scheduled then
    table.insert(lines, "SCHEDULED: " .. M.format_active_date(opts.scheduled))
  end
  if opts.deadline then
    table.insert(lines, "DEADLINE: " .. M.format_active_date(opts.deadline))
  end
  
  -- PROPERTIES
  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":TASK_ID:   " .. id)
  table.insert(lines, ":ID:        " .. id)
  table.insert(lines, ":ZK_LINK:   " .. id)
  table.insert(lines, ":CREATED:   " .. M.format_inactive_timestamp())
  if opts.outcome then table.insert(lines, ":OUTCOME:   " .. opts.outcome) end
  if opts.area then table.insert(lines, ":AREA:      " .. opts.area) end
  if opts.effort then table.insert(lines, ":Effort:    " .. opts.effort) end
  if opts.assigned then table.insert(lines, ":ASSIGNED:  " .. opts.assigned) end
  if opts.waiting_for then table.insert(lines, ":WAITING_FOR: " .. opts.waiting_for) end
  if opts.waiting_since then table.insert(lines, ":WAITING_SINCE: " .. opts.waiting_since) end
  if opts.zk_note then table.insert(lines, ":ZK_NOTE:   " .. M.format_zk_note_property(opts.zk_note)) end
  table.insert(lines, ":END:")
  
  return lines, id
end

--- Build a project entry (returns lines array and project_id)
---@param opts table { title, area, outcome, zk_note, ongoing, ... }
---@return table lines, string project_id
function M.build_project_entry(opts)
  opts = opts or {}
  local id = opts.task_id or M.generate_task_id()
  
  local lines = {}
  
  -- Heading
  local heading = "* PROJECT " .. (opts.title or "Untitled")
  if opts.tags and #opts.tags > 0 then
    heading = heading .. "  :" .. table.concat(opts.tags, ":") .. ":"
  end
  table.insert(lines, heading)
  
  -- SCHEDULED/DEADLINE
  if opts.scheduled then
    table.insert(lines, "SCHEDULED: " .. M.format_active_date(opts.scheduled))
  end
  if opts.deadline then
    table.insert(lines, "DEADLINE: " .. M.format_active_date(opts.deadline))
  end
  
  -- PROPERTIES
  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":ID: " .. id)
  table.insert(lines, ":TASK_ID: " .. id)
  table.insert(lines, ":CREATED: " .. M.format_inactive_timestamp())
  if opts.ongoing then table.insert(lines, ":ONGOING: t") end
  if opts.zk_note then table.insert(lines, ":ZK_NOTE: " .. M.format_zk_note_property(opts.zk_note)) end
  if opts.description then table.insert(lines, ":DESCRIPTION: " .. opts.description) end
  if opts.area then table.insert(lines, ":AREA: " .. opts.area) end
  table.insert(lines, ":END:")
  
  if opts.outcome then
    table.insert(lines, "")
    table.insert(lines, "** Outcome")
    table.insert(lines, opts.outcome)
  end
  
  return lines, id
end

--- Format ZK note path for PROPERTIES
function M.format_zk_note_property(path)
  if not path then return nil end
  if path:match("^%[%[") then return path end
  local filename = vim.fn.fnamemodify(path, ":t")
  return string.format("[[file:%s][%s]]", path, filename)
end

-- ============================================================================
-- FZF FORMATTING
-- ============================================================================

--- Format task for fzf display
---@param task table Task object from daemon
---@return string Formatted display string
function M.format_task_for_fzf(task)
  local icon = M.glyphs.todo
  local state = task.state or "TODO"
  if state == "NEXT" then icon = M.glyphs.next
  elseif state == "WAITING" then icon = M.glyphs.waiting
  elseif state == "SOMEDAY" then icon = M.glyphs.someday
  elseif state == "DONE" then icon = M.glyphs.done
  elseif state == "CANCELLED" then icon = M.glyphs.cancelled
  end
  
  local title = task.title or "Untitled"
  local file = vim.fn.fnamemodify(task.file or "", ":t:r")
  
  return string.format("%s %s  %s", icon, title, file)
end

--- Format project for fzf display
---@param project table Project object
---@return string Formatted display string
function M.format_project_for_fzf(project)
  local parts = { M.glyphs.project, project.title or project.name or "Untitled" }
  
  if project.area then
    table.insert(parts, " [" .. project.area .. "]")
  end
  
  if project.tasks and project.tasks.total then
    table.insert(parts, " (" .. project.tasks.total .. ")")
  end
  
  return table.concat(parts)
end

-- ============================================================================
-- PROJECT/AREA DISCOVERY
-- ============================================================================

--- Get all project files (files with PROJECT heading)
---@return table[] Array of { name, path, area, display }
function M.get_projects()
  local projects = {}
  local root = M.gtd_home()
  
  -- Standalone projects in Projects/
  local pdir = root .. "/Projects"
  if vim.fn.isdirectory(pdir) == 1 then
    for _, f in ipairs(vim.fn.glob(pdir .. "/*.org", false, true)) do
      if M.has_project_heading(f) then
        local name = vim.fn.fnamemodify(f, ":t:r")
        table.insert(projects, { 
          name = name, 
          path = f, 
          display = M.glyphs.project .. " " .. name 
        })
      end
    end
  end
  
  -- Area projects in Areas/*/
  local adir = root .. "/Areas"
  if vim.fn.isdirectory(adir) == 1 then
    for _, ap in ipairs(vim.fn.glob(adir .. "/*", false, true)) do
      if vim.fn.isdirectory(ap) == 1 then
        local aname = vim.fn.fnamemodify(ap, ":t")
        for _, f in ipairs(vim.fn.glob(ap .. "/*.org", false, true)) do
          if M.has_project_heading(f) then
            local name = vim.fn.fnamemodify(f, ":t:r")
            table.insert(projects, {
              name = name, 
              path = f, 
              area = aname,
              display = M.glyphs.area .. " " .. aname .. "/" .. name
            })
          end
        end
      end
    end
  end
  
  return projects
end

--- Get all areas
---@return table[] Array of { name, path }
function M.get_areas()
  local areas = {}
  local adir = M.gtd_home() .. "/Areas"
  if vim.fn.isdirectory(adir) == 1 then
    for _, p in ipairs(vim.fn.glob(adir .. "/*", false, true)) do
      if vim.fn.isdirectory(p) == 1 then
        table.insert(areas, { 
          name = vim.fn.fnamemodify(p, ":t"), 
          path = p 
        })
      end
    end
  end
  return areas
end

--- Get .org files that are NOT projects (no PROJECT heading)
---@return table[] Array of { name, path }
function M.get_non_project_files()
  local files = {}
  local root = M.gtd_home()
  local skip_files = { "Inbox.org", "Recurring.org", "Tickler.org" }
  
  local function should_skip(name)
    for _, s in ipairs(skip_files) do
      if name == s then return true end
    end
    return false
  end
  
  local function scan_dir(dir, prefix)
    if vim.fn.isdirectory(dir) ~= 1 then return end
    for _, f in ipairs(vim.fn.glob(dir .. "/*.org", false, true)) do
      local name = vim.fn.fnamemodify(f, ":t")
      if not should_skip(name) and not M.has_project_heading(f) then
        local display_name = vim.fn.fnamemodify(f, ":t:r")
        if prefix then display_name = prefix .. "/" .. display_name end
        table.insert(files, { name = display_name, path = f })
      end
    end
  end
  
  scan_dir(root .. "/Projects", nil)
  scan_dir(root .. "/Reminders", "Reminders")
  
  -- Areas subdirs
  local adir = root .. "/Areas"
  if vim.fn.isdirectory(adir) == 1 then
    for _, ap in ipairs(vim.fn.glob(adir .. "/*", false, true)) do
      if vim.fn.isdirectory(ap) == 1 then
        scan_dir(ap, "Areas/" .. vim.fn.fnamemodify(ap, ":t"))
      end
    end
  end
  
  return files
end

--- Convert a file to a project (add PROJECT heading)
---@param path string File path
---@param project_name string Project name
---@return boolean success, string|nil error
function M.convert_file_to_project(path, project_name)
  local lines = vim.fn.readfile(path)
  if not lines then return false, "Could not read file" end
  
  local task_id = M.generate_task_id()
  
  -- Find where to insert (after #+TITLE and #+FILETAGS)
  local insert_at = 1
  for i, line in ipairs(lines) do
    if line:match("^#%+") then
      insert_at = i + 1
    else
      break
    end
  end
  
  -- Build PROJECT heading
  local project_lines = {
    "",
    "* PROJECT " .. project_name,
    ":PROPERTIES:",
    ":ID: " .. task_id,
    ":TASK_ID: " .. task_id,
    ":CREATED: " .. M.format_inactive_timestamp(),
    ":END:",
    "",
  }
  
  -- Insert project heading
  for i, pl in ipairs(project_lines) do
    table.insert(lines, insert_at + i - 1, pl)
  end
  
  -- Adjust existing headings: * → **
  for i = insert_at + #project_lines, #lines do
    if lines[i]:match("^%* ") then
      lines[i] = "*" .. lines[i]
    end
  end
  
  vim.fn.writefile(lines, path)
  return true
end

return M
