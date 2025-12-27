-- ============================================================================
-- STEP: FOCUS
-- ============================================================================
-- Toggle Area of Focus status for projects.
-- Areas of Focus are current priorities surfaced during Weekly Review.
--
-- @module gtd-nvim.capture.steps.focus
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

M.name = "focus"
M.applies_to = { "project" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  -- Property name for focus marker
  property = "FOCUS",
  
  -- Values
  focus_value = "t",
  
  -- Prompt
  prompt = "Set as Area of Focus?",
}

-- ============================================================================
-- SHOULD RUN
-- ============================================================================

function M.should_run(obj, opts)
  -- Only for projects
  return obj.type == "project" or obj.state == "PROJECT"
end

-- ============================================================================
-- RUN
-- ============================================================================

function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  
  -- Current state
  local is_focus = obj.focus == true or obj.focus == "t" or (obj.properties and obj.properties.FOCUS == "t")
  local current_icon = is_focus and "󰓎" or "󰓏"
  local current_label = is_focus and "Currently: Area of Focus" or "Currently: Not a focus area"
  
  if fzf_ok then
    local items = {
      current_icon .. " " .. current_label,
      "───────────────────────────",
      "󰓎 Set as Area of Focus",
      "󰓏 Remove focus status",
      "󰜺 Keep current (skip)",
    }
    
    fzf.fzf_exec(items, {
      prompt = opts.prompt .. " ❯ ",
      winopts = { height = 0.35, width = 0.45 },
      actions = {
        ["default"] = function(sel)
          if not sel or not sel[1] then
            vim.schedule(function() next_step(obj) end)
            return
          end
          
          local choice = sel[1]
          if choice:match("Set as Area") then
            obj.focus = true
            vim.notify("󰓎 Marked as Area of Focus", vim.log.levels.INFO)
          elseif choice:match("Remove focus") then
            obj.focus = nil
            vim.notify("󰓏 Focus status removed", vim.log.levels.INFO)
          end
          -- "Keep current" or separator - no change
          
          vim.schedule(function() next_step(obj) end)
        end,
      },
    })
  else
    -- Simple yes/no
    vim.ui.select({ "Yes - Set as Focus", "No - Skip" }, { prompt = opts.prompt }, function(choice)
      if choice and choice:match("^Yes") then
        obj.focus = true
      end
      next_step(obj)
    end)
  end
end

-- ============================================================================
-- UTILITY: Toggle focus on existing file
-- ============================================================================

--- Toggle focus status on current file
function M.toggle_focus_current_file()
  local filepath = vim.api.nvim_buf_get_name(0)
  if not filepath:match("%.org$") then
    vim.notify("Not an org file", vim.log.levels.WARN)
    return
  end
  
  local lines = vim.fn.readfile(filepath)
  local props_start, props_end = nil, nil
  local focus_line = nil
  local has_focus = false
  
  -- Find PROPERTIES drawer in first heading
  for i, line in ipairs(lines) do
    if line:match("^%s*:PROPERTIES:%s*$") then
      props_start = i
    elseif props_start and line:match("^%s*:END:%s*$") then
      props_end = i
      break
    elseif props_start and line:match("^%s*:FOCUS:") then
      focus_line = i
      has_focus = line:match(":FOCUS:%s*t")
    end
  end
  
  if not props_start or not props_end then
    vim.notify("No PROPERTIES drawer found", vim.log.levels.WARN)
    return
  end
  
  if has_focus then
    -- Remove focus
    if focus_line then
      table.remove(lines, focus_line)
    end
    vim.fn.writefile(lines, filepath)
    vim.cmd("edit!")
    vim.notify("󰓏 Focus status removed", vim.log.levels.INFO)
  else
    -- Add focus
    if focus_line then
      lines[focus_line] = ":FOCUS:     t"
    else
      -- Insert before :END:
      table.insert(lines, props_end, ":FOCUS:     t")
    end
    vim.fn.writefile(lines, filepath)
    vim.cmd("edit!")
    vim.notify("󰓎 Marked as Area of Focus", vim.log.levels.INFO)
  end
end

--- Check if current file is a focus area
function M.is_focus_area(filepath)
  filepath = filepath or vim.api.nvim_buf_get_name(0)
  if not filepath:match("%.org$") then return false end
  
  local lines = vim.fn.readfile(filepath)
  for _, line in ipairs(lines) do
    if line:match("^%s*:FOCUS:%s*t") then
      return true
    end
    -- Stop after first heading's properties
    if line:match("^%*%*") then
      break
    end
  end
  return false
end

--- List all focus areas
function M.list_focus_areas()
  local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  local gtd_home = shared_ok and shared.gtd_home and shared.gtd_home() or vim.fn.expand("~/Documents/GTD")
  
  local cmd = string.format("grep -rl ':FOCUS:.*t' %s --include='*.org' 2>/dev/null", gtd_home)
  local handle = io.popen(cmd)
  if not handle then return {} end
  
  local result = handle:read("*a")
  handle:close()
  
  local focus_areas = {}
  for file in result:gmatch("[^\n]+") do
    -- Extract project name from file
    local name = vim.fn.fnamemodify(file, ":t:r")
    local area = file:match("/Areas/([^/]+)/") or "Projects"
    table.insert(focus_areas, {
      file = file,
      name = name,
      area = area,
    })
  end
  
  return focus_areas
end

return M
