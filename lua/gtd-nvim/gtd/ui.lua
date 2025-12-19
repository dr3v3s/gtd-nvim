-- ============================================================================
-- GTD-NVIM UI MODULE
-- ============================================================================
-- Enhanced UI helpers for GTD system
-- Delegates core functions to shared.lua, provides UI-specific enhancements
-- 100% backward compatible with existing ui.select/ui.input/ui.STATUSES
--
-- @module gtd-nvim.gtd.ui
-- @version 1.1.0
-- @requires shared (>= 1.1.0)
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2024-12-19"

-- Load shared utilities (core functions)
local shared = require("gtd-nvim.gtd.shared")
local g = shared.glyphs

-- ============================================================================
-- RE-EXPORTED FROM SHARED (backward compatibility)
-- ============================================================================

-- File operations
M.expand_path = shared.xp
M.xp = shared.xp
M.file_exists = shared.file_exists
M.dir_exists = shared.dir_exists
M.read_file = shared.read_file
M.write_file = shared.write_file
M.append_file = shared.append_file
M.ensure_dir = shared.ensure_dir
M.join_path = shared.join_path
M.relative_path = shared.relative_path
M.basename_no_ext = shared.basename_no_ext
M.slugify = shared.slugify

-- Date/time
M.gen_id = shared.gen_id
M.now_id = shared.gen_id
M.today = shared.today
M.is_valid_date = shared.is_valid_date
M.now_timestamp = shared.now_timestamp
M.parse_org_date = shared.parse_org_date
M.days_between = shared.days_between

-- Notifications
M.notify = shared.notify
M.info = shared.info
M.warn = shared.warn
M.error = shared.error

-- Input helpers
M.input = shared.input
M.input_required = shared.input_required
M.input_optional = shared.input_optional
M.select = shared.select

-- Org parsing
M.is_org_heading = shared.is_org_heading
M.org_heading_level = shared.heading_level
M.parse_org_heading = shared.parse_org_heading

-- FZF check
M.has_fzf = shared.have_fzf
M.have_fzf = shared.have_fzf

-- Sane shared statuses
M.STATUSES = { "TODO", "NEXT", "WAITING", "SOMEDAY", "DONE" }

-- ============================================================================
-- UI-SPECIFIC HELPERS
-- ============================================================================

local function get_fzf()
  local ok, fzf = pcall(require, "fzf-lua")
  return ok and fzf or nil
end

--- Trim whitespace from string
---@param str string String to trim
---@return string Trimmed string
function M.trim(str)
  if not str then return "" end
  return str:gsub("^%s+", ""):gsub("%s+$", "")
end

--- Show debug notification (only in debug mode)
---@param msg string Message to display
---@param title string|nil Optional title
function M.debug(msg, title)
  if vim.g.gtd_debug then
    vim.notify(msg, vim.log.levels.DEBUG, { title = title or "GTD Debug" })
  end
end

--- Safely require module with optional fallback
---@param module_name string Module name to require
---@param fallback any Optional fallback value if require fails
---@return any Module or fallback value
function M.safe_require(module_name, fallback)
  local ok, mod = pcall(require, module_name)
  return ok and mod or fallback
end

--- Find subtree range for org heading
---@param lines table File lines
---@param heading_line number Line number of heading (1-indexed)
---@return number|nil, number|nil start_line, end_line (inclusive)
function M.org_subtree_range(lines, heading_line)
  if not lines or not heading_line or heading_line > #lines then return nil, nil end
  
  local heading = lines[heading_line]
  local level = shared.heading_level(heading)
  if not level then return nil, nil end
  
  local end_line = heading_line
  for i = heading_line + 1, #lines do
    local line_level = shared.heading_level(lines[i])
    if line_level and line_level <= level then
      break
    end
    end_line = i
  end
  
  return heading_line, end_line
end

-- ============================================================================
-- ENHANCED FZF PICKERS
-- ============================================================================

--- Enhanced fzf-lua picker with consistent styling
---@param items table Items to pick from
---@param opts table Picker options
---@param cb function Callback function
function M.fzf_pick(items, opts, cb)
  local fzf = get_fzf()
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

-- ============================================================================
-- PROJECT CREATION WIZARDS
-- ============================================================================

--- Show extraction summary with fzf preview
---@param task_data table Task metadata extracted from cursor
---@param callback function Callback when user confirms
function M.show_extraction_summary(task_data, callback)
  local fzf = get_fzf()
  
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
    if input == nil then return end
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
  local fzf = get_fzf()
  
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
  lookup[display[1]] = nil
  
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
  local fzf = get_fzf()
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
  
  vim.defer_fn(function()
    vim.cmd("edit " .. filepath)
  end, 100)
end

-- ============================================================================
-- MODULE SETUP
-- ============================================================================

M.config = {
  notifications = { title = "GTD", show_debug = false },
  ui = { prefer_fzf = true, fzf_height = 0.40, fzf_width = 0.60 },
  files = { backup_on_write = false, create_dirs = true }
}

function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
end

return M
