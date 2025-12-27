-- ============================================================================
-- STEP: STATE
-- ============================================================================
-- Pick task state (TODO, NEXT, WAITING, SOMEDAY).
--
-- @module gtd-nvim.capture.steps.state
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

M.name = "state"
M.applies_to = { "task" }  -- Projects always have PROJECT state

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  -- Available states
  states = {
    { state = "NEXT", icon = "󱥦", desc = "ready to do" },
    { state = "TODO", icon = "󰄲", desc = "not yet ready" },
    { state = "WAITING", icon = "", desc = "delegated/blocked" },
    { state = "SOMEDAY", icon = "󰋚", desc = "maybe later" },
  },
  
  -- Default state
  default_state = "TODO",
  
  -- Prompt
  prompt = "State ❯ ",
}

-- ============================================================================
-- SHOULD RUN
-- ============================================================================

--- Determine if this step should run
---@param obj table OrgObject
---@param opts table Step options
---@return boolean
function M.should_run(obj, opts)
  opts = opts or {}
  
  -- Projects don't need state selection
  if obj.type == "project" then
    return false
  end
  
  -- Skip if state is already set and skip_if_set is true
  if opts.skip_if_set and obj.state then
    return false
  end
  
  -- In edit mode, optionally skip if state exists
  if obj._mode == "edit" and obj.state and opts.always_ask_state ~= true then
    return false
  end
  
  return true
end

-- ============================================================================
-- RUN
-- ============================================================================

--- Execute the step
---@param obj table OrgObject
---@param opts table Step options
---@param next_step function Callback to continue to next step
function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Try to use fzf-lua
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  
  if fzf_ok then
    M._run_fzf(obj, opts, next_step, fzf)
  else
    M._run_vim_select(obj, opts, next_step)
  end
end

--- Run with fzf-lua
function M._run_fzf(obj, opts, next_step, fzf)
  local items = {}
  local lookup = {}
  
  for _, s in ipairs(opts.states) do
    local line = string.format("%s %s  (%s)", s.icon, s.state, s.desc)
    table.insert(items, line)
    lookup[line] = s.state
  end
  
  fzf.fzf_exec(items, {
    prompt = opts.prompt,
    winopts = { height = 0.3, width = 0.4 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then
          next_step(nil)  -- Cancel
          return
        end
        
        local state = lookup[sel[1]] or sel[1]:match("(%u+)")
        obj.state = state or opts.default_state
        
        -- SOMEDAY tasks don't have dates - clear them
        if obj.state == "SOMEDAY" then
          if obj.scheduled or obj.deadline then
            vim.notify("󰋚 SOMEDAY: dates removed", vim.log.levels.INFO)
          end
          obj.scheduled = nil
          obj.deadline = nil
        end
        
        vim.schedule(function()
          next_step(obj)
        end)
      end,
    },
  })
end

--- Fallback: run with vim.ui.select
function M._run_vim_select(obj, opts, next_step)
  local items = {}
  local lookup = {}
  
  for _, s in ipairs(opts.states) do
    local line = string.format("%s %s (%s)", s.icon, s.state, s.desc)
    table.insert(items, line)
    lookup[line] = s.state
  end
  
  vim.ui.select(items, { prompt = opts.prompt }, function(choice)
    if not choice then
      next_step(nil)  -- Cancel
      return
    end
    
    obj.state = lookup[choice] or opts.default_state
    
    -- SOMEDAY tasks don't have dates - clear them
    if obj.state == "SOMEDAY" then
      if obj.scheduled or obj.deadline then
        vim.notify("󰋚 SOMEDAY: dates removed", vim.log.levels.INFO)
      end
      obj.scheduled = nil
      obj.deadline = nil
    end
    
    next_step(obj)
  end)
end

return M
