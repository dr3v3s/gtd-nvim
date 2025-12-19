-- ============================================================================
-- GTD-NVIM UI MODULE
-- ============================================================================
-- Enhanced UI helpers for GTD system
-- Provides consistent UI patterns using fzf-lua with fallback to vim.ui
-- 
-- File/path operations are delegated to shared.lua
-- This module focuses purely on UI interactions
--
-- @module gtd-nvim.gtd.ui
-- @version 1.1.0
-- @requires shared (>= 1.1.0)
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2024-12-19"

-- Load shared utilities (single source of truth for file ops, colors, glyphs)
local shared = require("gtd-nvim.gtd.shared")
local g = shared.glyphs

-- ============================================================================
-- BACKWARD COMPATIBILITY ALIASES
-- ============================================================================
-- These delegate to shared.lua but preserve existing API for other modules

M.expand_path = shared.xp
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
M.info = shared.info
M.warn = shared.warn
M.error = shared.error

-- Sane shared statuses
M.STATUSES = { "TODO", "NEXT", "WAITING", "SOMEDAY", "DONE" }

-- ============================================================================
-- FZF-LUA HELPERS
-- ============================================================================

local function have_fzf()
  local ok = pcall(require, "fzf-lua")
  return ok and require("fzf-lua") or nil
end

local function get_fzf()
  return have_fzf()
end

-- ============================================================================
-- CORE UI FUNCTIONS
-- ============================================================================

--- Select: prefers fzf-lua, falls back to vim.ui.select
--- Signature mirrors vim.ui.select(items, opts, cb)
---@param items table List of items to select from
---@param opts table Options: prompt, format_item
---@param cb function Callback with selected item
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
      fzf_opts = { ["--no-info"] = true, ["--ansi"] = true },
      winopts = { height = 0.35, width = 0.50, row = 0.15 },
    })
  else
    vim.ui.select(items, opts, cb)
  end
end

--- Input: thin wrapper around vim.ui.input
---@param opts table Options: prompt, default
---@param cb function Callback with input string
function M.input(opts, cb)
  vim.ui.input(opts or {}, cb)
end

-- ============================================================================
-- ENHANCED UI FUNCTIONS (Wizards, Confirmations, etc.)
-- ============================================================================

--- Confirm project conversion with task preview
---@param task_data table Task metadata (title, project, state, etc.)
---@param callback function Called if user confirms
function M.confirm_project_conversion(task_data, callback)
  local fzf = get_fzf()
  
  local summary_lines = {
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    (g.container.projects or "󰉋") .. " Converting task to project:",
    "",
    (g.ui.bullet or "•") .. " Title: " .. (task_data.title or "Untitled"),
  }
  
  if task_data.project then
    table.insert(summary_lines, (g.file.org or "") .. " Source: " .. task_data.project)
  end
  if task_data.state then
    table.insert(summary_lines, (g.state[task_data.state] or "○") .. " State: " .. task_data.state)
  end
  if task_data.scheduled then
    table.insert(summary_lines, (g.time.scheduled or "󰃭") .. " Scheduled: " .. task_data.scheduled)
  end
  if task_data.deadline then
    table.insert(summary_lines, (g.time.deadline or "󰀨") .. " Deadline: " .. task_data.deadline)
  end
  if task_data.zk_note then
    table.insert(summary_lines, (g.ui.link or "") .. " ZK Note: " .. vim.fn.fnamemodify(task_data.zk_note, ":t"))
  end
  if task_data.area and task_data.area.name then
    table.insert(summary_lines, (g.container.areas or "󰕰") .. " Area: " .. task_data.area.name)
  end
  
  table.insert(summary_lines, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  
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

--- Enhanced input with step indicator for wizards
---@param step number Current step number
---@param total number Total steps
---@param opts table Options: icon, prompt, hint, default, allow_empty
---@param callback function Callback with input value
function M.enhanced_input(step, total, opts, callback)
  opts = opts or {}
  local icon = opts.icon or (g.ui.bullet or "•")
  local prompt_text = string.format("[%d/%d] %s %s: ", step, total, icon, opts.prompt or "Input")
  
  if opts.hint then
    shared.info(opts.hint)
  end
  
  vim.ui.input({
    prompt = prompt_text,
    default = opts.default or "",
  }, function(input)
    if input == nil then return end
    if input == "" and not opts.allow_empty then
      shared.warn("Input required")
      return
    end
    callback(input)
  end)
end

--- Select area for project placement
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

--- Enhanced area picker for project creation wizard (step 5/5)
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
  
  shared.info(msg)
  
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
}

function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
end

return M
