-- ============================================================================
-- STEP: TAGS
-- ============================================================================
-- Select context tags (@phone, @email, @home, etc).
--
-- @module gtd-nvim.capture.steps.tags
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

M.name = "tags"
M.applies_to = { "task", "project" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  -- Available context tags
  context_tags = {
    "@phone", "@email", "@message",
    "@computer", "@home", "@office", "@errand",
    "@focus", "@quick", "@waiting",
  },
  
  -- Custom tags (user can add more)
  custom_tags = {},
  
  -- Allow free-form tag input
  allow_custom = true,
  
  -- Multi-select
  multi_select = true,
  
  -- Prompt
  prompt = "Tags ❯ ",
  
  -- Icon
  icon = "",
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
  -- Always run unless disabled
  return opts.skip_tags ~= true
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
  
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  
  if fzf_ok then
    M._run_fzf(obj, opts, next_step, fzf)
  else
    M._run_vim_input(obj, opts, next_step)
  end
end

--- Run with fzf-lua (multi-select)
function M._run_fzf(obj, opts, next_step, fzf)
  -- Build items list
  local items = { opts.icon .. " (skip - no tags)" }
  
  -- Combine context and custom tags
  local all_tags = vim.list_extend({}, opts.context_tags)
  vim.list_extend(all_tags, opts.custom_tags or {})
  
  for _, tag in ipairs(all_tags) do
    table.insert(items, opts.icon .. " " .. tag)
  end
  
  if opts.allow_custom then
    table.insert(items, opts.icon .. " + (enter custom tag)")
  end
  
  local fzf_opts = {
    prompt = opts.prompt,
    winopts = { height = 0.45, width = 0.35 },
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          next_step(obj)  -- No selection, continue without tags
          return
        end
        
        local tags = {}
        local needs_custom = false
        
        for _, item in ipairs(selected) do
          if item:match("skip") then
            -- Skip selected, no tags
            vim.schedule(function() next_step(obj) end)
            return
          elseif item:match("custom") then
            needs_custom = true
          else
            local tag = item:match("@%w+")
            if tag then
              table.insert(tags, tag:sub(2))  -- Remove @ prefix for storage
            end
          end
        end
        
        -- Store tags
        obj.tags = vim.list_extend(obj.tags or {}, tags)
        
        if needs_custom then
          -- Ask for custom tag
          vim.schedule(function()
            M._ask_custom_tag(obj, opts, next_step)
          end)
        else
          vim.schedule(function() next_step(obj) end)
        end
      end,
    },
  }
  
  if opts.multi_select then
    fzf_opts.fzf_opts = { ["--multi"] = true }
  end
  
  fzf.fzf_exec(items, fzf_opts)
end

--- Ask for custom tag
function M._ask_custom_tag(obj, opts, next_step)
  vim.ui.input({ prompt = "Custom tag (@): " }, function(tag)
    if tag and tag ~= "" then
      -- Normalize: add @ if missing, then remove for storage
      if not tag:match("^@") then
        tag = "@" .. tag
      end
      obj.tags = obj.tags or {}
      table.insert(obj.tags, tag:sub(2))
    end
    next_step(obj)
  end)
end

--- Fallback: simple input
function M._run_vim_input(obj, opts, next_step)
  local current = obj.tags and #obj.tags > 0 
    and table.concat(vim.tbl_map(function(t) return "@" .. t end, obj.tags), " ")
    or ""
  
  vim.ui.input({ 
    prompt = "Tags (space-separated, e.g., @phone @email): ",
    default = current,
  }, function(input)
    if input == nil then
      next_step(nil)  -- Cancel
      return
    end
    
    if input ~= "" then
      obj.tags = {}
      for tag in input:gmatch("@?(%w+)") do
        table.insert(obj.tags, tag)
      end
    end
    
    next_step(obj)
  end)
end

return M
