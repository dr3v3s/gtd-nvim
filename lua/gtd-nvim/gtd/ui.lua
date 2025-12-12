-- ============================================================================
-- GTD-NVIM UI MODULE
-- ============================================================================
-- Enhanced UI helpers and shared utilities for GTD system
-- Provides consistent UI patterns, file operations, and common utilities
-- 100% backward compatible with existing ui.select/ui.input/ui.STATUSES
--
-- @module gtd-nvim.gtd.ui
-- @version 0.8.0
-- @requires shared (>= 1.0.0)
-- @todo Use shared.glyphs for icons
-- @todo Use highlight groups for UI elements
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2024-12-09"

-- Load shared utilities
local shared = require("gtd-nvim.gtd.shared")
local g = shared.glyphs

-- ============================================================================
-- BACKWARD COMPATIBILITY - Existing API (DO NOT CHANGE)
-- ============================================================================

local function have_fzf()
  local ok = pcall(require, "fzf-lua")
  return ok and require("fzf-lua") or nil
end

-- Select: prefers fzf-lua (no big footer), falls back to vim.ui.select
-- Signature mirrors vim.ui.select(items, opts, cb)
function M.select(items, opts, cb)
  opts = opts or {}
  local fzf = have_fzf()
  if fzf then
    local display = vim.tbl_map(function(x)
      return type(x) == "table" and (x.display or x[1] or tostring(x)) or tostring(x)
    end, items)

    fzf.fzf_exec(display, {
      prompt = (opts.prompt or "Select") .. "> ",
      actions = {
        ["default"] = function(sel)
          local line = sel and sel[1]
          if not line then return end
          local idx = vim.fn.index(display, line) + 1
          cb(items[idx])
        end,
      },
      fzf_opts = { ["--no-info"] = true },
      winopts = { height = 0.35, width = 0.50, row = 0.15 }, -- small, out of the way
    })
  else
    vim.ui.select(items, opts, cb)
  end
end

-- Input: just a thin wrapper so you can swap later if you want
function M.input(opts, cb)
  vim.ui.input(opts or {}, cb)
end

-- Sane shared statuses
M.STATUSES = { "TODO", "NEXT", "WAITING", "SOMEDAY", "DONE" }

-- ============================================================================
-- NEW SHARED UTILITIES - Foundation for other modules
-- ============================================================================

-- ----------------------------------------------------------------------------
-- File Operations
-- ----------------------------------------------------------------------------

--- Expand path with proper error handling
---@param p string|nil Path to expand
---@return string Expanded path or empty string
function M.expand_path(p)
  if not p or p == "" then return "" end
  return vim.fn.expand(p)
end

--- Check if file exists and is readable
---@param path string Path to check
---@return boolean True if file exists and readable
function M.file_exists(path)
  if not path or path == "" then return false end
  return vim.fn.filereadable(M.expand_path(path)) == 1
end

--- Check if directory exists
---@param path string Path to check
---@return boolean True if directory exists
function M.dir_exists(path)
  if not path or path == "" then return false end
  return vim.fn.isdirectory(M.expand_path(path)) == 1
end

--- Read file contents, return empty table if file doesn't exist
---@param path string File path to read
---@return table Lines from file or empty table
function M.read_file(path)
  if not M.file_exists(path) then return {} end
  local ok, lines = pcall(vim.fn.readfile, M.expand_path(path))
  return ok and lines or {}
end

--- Write lines to file, creating parent directories if needed
---@param path string File path to write
---@param lines table Lines to write
---@return boolean True if successful
function M.write_file(path, lines)
  if not path or not lines then return false end
  local expanded = M.expand_path(path)
  M.ensure_dir(vim.fn.fnamemodify(expanded, ":h"))
  local ok, result = pcall(vim.fn.writefile, lines, expanded)
  return ok and result == 0
end

--- Append lines to file, creating parent directories if needed
---@param path string File path to append to
---@param lines table Lines to append
---@return boolean True if successful
function M.append_file(path, lines)
  if not path or not lines then return false end
  local expanded = M.expand_path(path)
  M.ensure_dir(vim.fn.fnamemodify(expanded, ":h"))
  -- Add empty line first to separate content
  local ok1 = pcall(vim.fn.writefile, {""}, expanded, "a")
  local ok2 = pcall(vim.fn.writefile, lines, expanded, "a")
  return ok1 and ok2
end

--- Ensure directory exists, creating parent directories as needed
---@param path string Directory path to create
---@return string Expanded directory path
function M.ensure_dir(path)
  if not path or path == "" then return "" end
  local expanded = M.expand_path(path)
  vim.fn.mkdir(expanded, "p")
  return expanded
end

-- ----------------------------------------------------------------------------
-- Path Operations
-- ----------------------------------------------------------------------------

--- Join path components with proper separator handling
---@param ... string Path components to join
---@return string Joined path
function M.join_path(...)
  local parts = {...}
  if #parts == 0 then return "" end
  if #parts == 1 then return parts[1] end
  
  local result = parts[1]:gsub("/+$", "")
  for i = 2, #parts do
    local part = parts[i]:gsub("^/+", ""):gsub("/+$", "")
    if part ~= "" then
      result = result .. "/" .. part
    end
  end
  return result
end

--- Get relative path from current working directory
---@param path string Absolute or relative path
---@return string Relative path
function M.relative_path(path)
  if not path then return "" end
  return vim.fn.fnamemodify(path, ":.")
end

--- Get filename without extension
---@param path string File path
---@return string Filename without extension
function M.basename_no_ext(path)
  if not path then return "" end
  return vim.fn.fnamemodify(path, ":t:r")
end

-- ----------------------------------------------------------------------------
-- Notification Helpers
-- ----------------------------------------------------------------------------

--- Show info notification with consistent formatting
---@param msg string Message to display
---@param title string|nil Optional title (defaults to "GTD")
function M.info(msg, title)
  vim.notify(msg, vim.log.levels.INFO, { title = title or "GTD" })
end

--- Show warning notification with consistent formatting
---@param msg string Message to display  
---@param title string|nil Optional title (defaults to "GTD")
function M.warn(msg, title)
  vim.notify(msg, vim.log.levels.WARN, { title = title or "GTD" })
end

--- Show error notification with consistent formatting
---@param msg string Message to display
---@param title string|nil Optional title (defaults to "GTD")
function M.error(msg, title)
  vim.notify(msg, vim.log.levels.ERROR, { title = title or "GTD" })
end

--- Show debug notification (only in debug mode)
---@param msg string Message to display
---@param title string|nil Optional title (defaults to "GTD Debug")
function M.debug(msg, title)
  if vim.log.levels.DEBUG >= vim.o.verbose then
    vim.notify(msg, vim.log.levels.DEBUG, { title = title or "GTD Debug" })
  end
end

-- ----------------------------------------------------------------------------
-- Date and Time Utilities
-- ----------------------------------------------------------------------------

--- Generate timestamp ID (YYYYMMDDHHMMSS format)
---@return string Timestamp-based ID
function M.now_id()
  return os.date("!%Y%m%d%H%M%S")
end

--- Get current date in YYYY-MM-DD format
---@param offset_days number|nil Days to offset from today (default 0)
---@return string Date string
function M.today(offset_days)
  local time = os.time() + ((offset_days or 0) * 24 * 3600)
  return os.date("%Y-%m-%d", time)
end

--- Validate date string in YYYY-MM-DD format
---@param date_str string Date string to validate
---@return boolean True if valid date format
function M.is_valid_date(date_str)
  if not date_str or date_str == "" then return true end -- Empty is valid (optional)
  return date_str:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

--- Get current timestamp for logging/archiving
---@return string Formatted timestamp
function M.now_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- ----------------------------------------------------------------------------
-- Enhanced UI Helpers  
-- ----------------------------------------------------------------------------

--- Input with non-empty validation
---@param opts table Input options (same as vim.ui.input)
---@param cb function Callback called only with non-empty input
function M.input_required(opts, cb)
  M.input(opts, function(input)
    if input and input:gsub("^%s+", ""):gsub("%s+$", "") ~= "" then
      cb(input:gsub("^%s+", ""):gsub("%s+$", ""))
    end
  end)
end

--- Input with optional callback (passes empty string if cancelled)
---@param opts table Input options
---@param cb function Callback receives input or empty string
function M.input_optional(opts, cb)
  M.input(opts, function(input)
    cb(input or "")
  end)
end

--- Enhanced fzf-lua picker with consistent styling
---@param items table Items to pick from
---@param opts table Picker options
---@param cb function Callback function
function M.fzf_pick(items, opts, cb)
  local fzf = have_fzf()
  if not fzf then
    M.warn("fzf-lua not available, falling back to vim.ui.select")
    vim.ui.select(items, opts, cb)
    return
  end
  
  opts = opts or {}
  local display = items
  if type(items[1]) == "table" then
    display = vim.tbl_map(function(item)
      return item.display or item[1] or tostring(item)
    end, items)
  end
  
  fzf.fzf_exec(display, {
    prompt = (opts.prompt or "Select") .. "> ",
    winopts = vim.tbl_extend("force", {
      height = 0.40,
      width = 0.60, 
      row = 0.15
    }, opts.winopts or {}),
    fzf_opts = vim.tbl_extend("force", {
      ["--no-info"] = true,
      ["--tiebreak"] = "index"
    }, opts.fzf_opts or {}),
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local item = type(items[1]) == "table" and items[idx] or sel[1]
        cb(item)
      end
    }
  })
end

-- ----------------------------------------------------------------------------
-- Safe Module Loading
-- ----------------------------------------------------------------------------

--- Safely require module with optional fallback
---@param module_name string Module name to require
---@param fallback any Optional fallback value if require fails
---@return any Module or fallback value
function M.safe_require(module_name, fallback)
  local ok, mod = pcall(require, module_name)
  if ok then
    return mod
  else
    if fallback ~= nil then
      return fallback
    end
    M.debug("Failed to require: " .. module_name)
    return nil
  end
end

--- Check if fzf-lua is available
---@return boolean True if fzf-lua can be loaded
function M.has_fzf()
  return have_fzf() ~= nil
end

-- ----------------------------------------------------------------------------
-- String Utilities
-- ----------------------------------------------------------------------------

--- Trim whitespace from string
---@param str string String to trim
---@return string Trimmed string
function M.trim(str)
  if not str then return "" end
  return str:gsub("^%s+", ""):gsub("%s+$", "")
end

--- Convert string to slug (filename safe)
---@param str string String to slugify
---@return string Slug string
function M.slugify(str)
  if not str or str == "" then return "untitled" end
  local slug = tostring(str)
  slug = slug:gsub("[/%\\:*?\"<>|]", "-")  -- Replace problematic chars
  slug = slug:gsub("%s+", "-")             -- Replace spaces with dashes
  slug = slug:gsub("^%-+", "")             -- Remove leading dashes
  slug = slug:gsub("%-+$", "")             -- Remove trailing dashes
  slug = slug:gsub("%-+", "-")             -- Collapse multiple dashes
  return #slug > 0 and slug or "untitled"
end

-- ----------------------------------------------------------------------------
-- Org-mode Utilities (Foundation for other modules)
-- ----------------------------------------------------------------------------

--- Check if line is an org heading
---@param line string Line to check
---@return boolean True if line is heading
function M.is_org_heading(line)
  return line and line:match("^%*+%s") ~= nil
end

--- Get heading level from org line
---@param line string Org heading line
---@return number|nil Heading level or nil if not a heading
function M.org_heading_level(line)
  if not line then return nil end
  local stars = line:match("^(%*+)%s")
  return stars and #stars or nil
end

--- Parse org heading state and title
---@param line string Org heading line
---@return string|nil, string|nil state, title
function M.parse_org_heading(line)
  if not M.is_org_heading(line) then return nil, nil end
  local stars, rest = line:match("^(%*+)%s+(.*)")
  if not rest then return nil, nil end
  
  -- Try to extract state keyword (uppercase words)
  local state, title = rest:match("^([A-Z]+)%s+(.*)")
  if state then
    return state, title
  else
    return nil, rest
  end
end

--- Find subtree range for org heading
---@param lines table File lines
---@param heading_line number Line number of heading (1-indexed)
---@return number|nil, number|nil start_line, end_line (inclusive)
function M.org_subtree_range(lines, heading_line)
  if not lines or not heading_line or heading_line > #lines then return nil, nil end
  
  local heading = lines[heading_line]
  local level = M.org_heading_level(heading)
  if not level then return nil, nil end
  
  local end_line = heading_line
  for i = heading_line + 1, #lines do
    local line_level = M.org_heading_level(lines[i])
    if line_level and line_level <= level then
      break
    end
    end_line = i
  end
  
  return heading_line, end_line
end

-- ============================================================================
-- ENHANCED UI FUNCTIONS (for projects.lua create_from_task_at_cursor)
-- ============================================================================

--- Show extraction summary with fzf preview
---@param task_data table Task metadata extracted from cursor
---@param callback function Callback when user confirms
function M.show_extraction_summary(task_data, callback)
  local fzf = have_fzf()
  
  local summary_lines = {
    "Task: " .. (task_data.title or "Untitled"),
    "State: " .. (task_data.state or "TODO"),
  }
  
  if task_data.description then
    table.insert(summary_lines, "Desc: " .. task_data.description)
  end
  if task_data.scheduled then
    table.insert(summary_lines, "Scheduled: " .. task_data.scheduled)
  end
  if task_data.deadline then
    table.insert(summary_lines, "Deadline: " .. task_data.deadline)
  end
  if task_data.zk_note then
    table.insert(summary_lines, "ZK Note: " .. vim.fn.fnamemodify(task_data.zk_note, ":t"))
  end
  if task_data.area and task_data.area.name then
    table.insert(summary_lines, "Area: " .. task_data.area.name)
  end
  
  if fzf then
    local preview_content = table.concat(summary_lines, "\n")
    fzf.fzf_exec({"→ Create Project from this task", "✗ Cancel"}, {
      prompt = (g.container.projects or "󰉋") .. " Convert to Project> ",
      winopts = { height = 0.40, width = 0.60, row = 0.20 },
      fzf_opts = { 
        ["--ansi"] = true,
        ["--header"] = preview_content,
      },
      actions = {
        ["default"] = function(sel)
          if sel and sel[1] and sel[1]:match("Create Project") then
            callback()
          end
        end,
      },
    })
  else
    -- Fallback to vim.ui.select
    local confirm_msg = "Convert to project: " .. (task_data.title or "Untitled") .. "?"
    vim.ui.select({"Yes, create project", "Cancel"}, { prompt = confirm_msg }, function(choice)
      if choice and choice:match("Yes") then
        callback()
      end
    end)
  end
end

--- Enhanced input with step indicator
---@param step number Current step number
---@param total number Total steps
---@param opts table Options: icon, prompt, hint, default, allow_empty
---@param callback function Callback with input value
function M.enhanced_input(step, total, opts, callback)
  opts = opts or {}
  local icon = opts.icon or (g.ui.bullet or "•")
  local prompt_text = string.format("[%d/%d] %s %s: ", step, total, icon, opts.prompt or "Input")
  
  if opts.hint then
    vim.notify(opts.hint, vim.log.levels.INFO)
  end
  
  vim.ui.input({
    prompt = prompt_text,
    default = opts.default or "",
  }, function(input)
    if input == nil then
      -- User cancelled
      return
    end
    if input == "" and not opts.allow_empty then
      vim.notify("Input required", vim.log.levels.WARN)
      return
    end
    callback(input)
  end)
end

--- Select area for project
---@param areas table List of area tables with name and dir
---@param callback function Callback with selected area directory
function M.select_area(areas, callback)
  local fzf = have_fzf()
  
  if not areas or #areas == 0 then
    callback(nil)
    return
  end
  
  local display = {}
  local lookup = {}
  
  for _, area in ipairs(areas) do
    local line = (g.container.areas or "󰕰") .. " " .. area.name
    table.insert(display, line)
    lookup[line] = area.dir
  end
  
  table.insert(display, 1, (g.container.projects or "󰉋") .. " Projects (no area)")
  lookup[display[1]] = nil  -- nil means use default projects dir
  
  if fzf then
    fzf.fzf_exec(display, {
      prompt = "Select Area> ",
      winopts = { height = 0.35, width = 0.50, row = 0.20 },
      fzf_opts = { ["--ansi"] = true },
      actions = {
        ["default"] = function(sel)
          if sel and sel[1] then
            callback(lookup[sel[1]])
          end
        end,
      },
    })
  else
    vim.ui.select(display, { prompt = "Select area:" }, function(choice)
      if choice then
        callback(lookup[choice])
      end
    end)
  end
end

--- Enhanced area picker for project creation (step 5/5)
---@param task_data table Task metadata with optional area info
---@param total_steps number Total steps in wizard
---@param callback function Callback with choice: "keep", "choose", "root"
function M.enhanced_area_picker(task_data, total_steps, callback)
  local fzf = have_fzf()
  local step = 5
  
  local options = {}
  local has_area = task_data and task_data.area and task_data.area.name
  
  if has_area then
    table.insert(options, (g.container.areas or "󰕰") .. " Keep: " .. task_data.area.name)
  end
  table.insert(options, (g.ui.search or "") .. " Choose different area...")
  table.insert(options, (g.container.projects or "󰉋") .. " Projects root (no area)")
  
  local prompt_text = string.format("[%d/%d] %s Select Area> ", step, total_steps, g.container.areas or "󰕰")
  
  if fzf then
    fzf.fzf_exec(options, {
      prompt = prompt_text,
      winopts = { height = 0.30, width = 0.50, row = 0.20 },
      fzf_opts = { ["--ansi"] = true },
      actions = {
        ["default"] = function(sel)
          if not sel or not sel[1] then return end
          local choice = sel[1]
          if choice:match("Keep:") then
            callback("keep")
          elseif choice:match("Choose different") then
            callback("choose")
          elseif choice:match("root") then
            callback("root")
          else
            callback("choose")
          end
        end,
      },
    })
  else
    vim.ui.select(options, { prompt = "Select area:" }, function(choice)
      if not choice then return end
      if choice:match("Keep:") then
        callback("keep")
      elseif choice:match("Choose different") then
        callback("choose")
      else
        callback("root")
      end
    end)
  end
end

--- Show success message after project creation
---@param filepath string Path to created project file
---@param project_id string Project ID
---@param zkpath string|nil Path to associated ZK note
function M.show_success(filepath, project_id, zkpath)
  local filename = vim.fn.fnamemodify(filepath, ":t")
  local msg = (g.state.DONE or "󰸟") .. " Project created: " .. filename
  
  if zkpath then
    local zkname = vim.fn.fnamemodify(zkpath, ":t")
    msg = msg .. "\n" .. (g.ui.link or "") .. " ZK: " .. zkname
  end
  
  vim.notify(msg, vim.log.levels.INFO)
  
  -- Open the new project file
  vim.defer_fn(function()
    vim.cmd("edit " .. filepath)
  end, 100)
end

-- ============================================================================
-- MODULE SETUP
-- ============================================================================

--- Module configuration (expandable by other modules)
M.config = {
  -- Notification settings
  notifications = {
    title = "GTD",
    show_debug = false,
  },
  
  -- UI settings
  ui = {
    prefer_fzf = true,
    fzf_height = 0.40,
    fzf_width = 0.60,
  },
  
  -- File operation settings
  files = {
    backup_on_write = false,
    create_dirs = true,
  }
}

--- Setup function for configuration
---@param user_config table|nil User configuration overrides
function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
end

return M