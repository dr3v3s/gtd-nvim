-- ============================================================================
-- STEP: PROJECT_TASKS
-- ============================================================================
-- Collect multiple tasks for a project.
-- Keeps asking for tasks until user enters empty title.
-- Includes tag selection and contact lookup for communication tasks.
--
-- @module gtd-nvim.capture.steps.project_tasks
-- @version 1.1.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2025-12-23"

M.name = "project_tasks"
M.applies_to = { "project" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  min_tasks = 1,
  ask_dates = true,
  ask_state = true,
  ask_tags = true,
  ask_comms = true,  -- Contact lookup for @phone/@email
  default_state = "TODO",
  
  -- Context tags
  context_tags = {
    "@phone", "@email", "@message",
    "@computer", "@home", "@office", "@errand",
    "@focus", "@quick",
  },
  
  -- Comms triggers
  comms_triggers = {
    phone = { "phone", "call", "ring", "telefon", "opkald" },
    email = { "email", "mail" },
    message = { "message", "sms", "text", "imessage", "besked" },
  },
  
  -- Name extraction patterns
  name_patterns = {
    "^[Cc]all%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Pp]hone%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Ee]mail%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Rr]ing%s+til%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Rr]inge%s+til%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Ss]kriv%s+til%s+([A-Z][a-zæøåÆØÅ]+)",
    "til%s+([A-Z][a-zæøåÆØÅ]+)",
    "to%s+([A-Z][a-zæøåÆØÅ]+)",
  },
}

math.randomseed(os.time())

-- ============================================================================
-- HELPERS
-- ============================================================================

local function generate_task_id()
  return os.date("%Y%m%d%H%M%S") .. string.format("%03d", math.random(0, 999))
end

local function parse_smart_date(input, base)
  if not input or input == "" then return nil end
  if input:match("^%d%d%d%d%-%d%d%-%d%d$") then return input end
  
  local base_time = os.time()
  if base then
    local y, m, d = base:match("(%d+)-(%d+)-(%d+)")
    if y then base_time = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) }) end
  end
  
  local num, unit = input:match("^%+(%d+)([dwm])$")
  if num and unit then
    num = tonumber(num)
    local secs = unit == "d" and num * 86400 or unit == "w" and num * 7 * 86400 or num * 30 * 86400
    return os.date("%Y-%m-%d", base_time + secs)
  end
  
  if input:lower() == "today" then return os.date("%Y-%m-%d", base_time) end
  if input:lower() == "tomorrow" then return os.date("%Y-%m-%d", base_time + 86400) end
  return nil
end

--- Detect communication context from tags
local function detect_comms_context(tags, triggers)
  for context_type, patterns in pairs(triggers) do
    for _, pattern in ipairs(patterns) do
      for _, tag in ipairs(tags or {}) do
        if tag:lower():gsub("^@", "") == pattern:lower() then
          return context_type
        end
      end
    end
  end
  return nil
end

--- Extract name from title
local function extract_name(title, patterns)
  if not title then return nil end
  for _, pattern in ipairs(patterns) do
    local name = title:match(pattern)
    if name then return name end
  end
  return nil
end

-- ============================================================================
-- SHOULD RUN
-- ============================================================================

function M.should_run(obj, opts)
  return obj.type == "project"
end

-- ============================================================================
-- RUN
-- ============================================================================

function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  obj.children = obj.children or {}
  
  vim.notify("󰐕 Add tasks to project (empty title to finish)", vim.log.levels.INFO)
  M._collect_task(obj, opts, 1, next_step)
end

--- Collect a single task
function M._collect_task(obj, opts, task_num, next_step)
  local Object = require("gtd-nvim.capture.model.object")
  
  local prompt = task_num == 1 and "  󱥦 First action: " or string.format("  Task %d: ", task_num)
  
  vim.ui.input({ prompt = prompt }, function(title)
    if not title or title == "" then
      local count = #obj.children
      if count < opts.min_tasks then
        vim.notify(string.format("Need at least %d task(s)", opts.min_tasks), vim.log.levels.WARN)
        vim.schedule(function() M._collect_task(obj, opts, task_num, next_step) end)
        return
      end
      vim.notify(string.format("󰄲 %d tasks added", count), vim.log.levels.INFO)
      next_step(obj)
      return
    end
    
    local task = Object.task(title, opts.default_state)
    task.id = generate_task_id()
    task.level = 2
    task.area = obj.area
    task.tags = {}
    
    -- Chain: state → tags → comms → dates → next task
    vim.schedule(function()
      M._chain_state(obj, task, opts, task_num, next_step)
    end)
  end)
end

--- Chain step 1: State
function M._chain_state(obj, task, opts, task_num, next_step)
  if not opts.ask_state then
    M._chain_tags(obj, task, opts, task_num, next_step)
    return
  end
  
  M._ask_state(task, opts, function(t)
    vim.schedule(function() M._chain_tags(obj, t, opts, task_num, next_step) end)
  end)
end

--- Chain step 2: Tags
function M._chain_tags(obj, task, opts, task_num, next_step)
  if not opts.ask_tags then
    M._chain_comms(obj, task, opts, task_num, next_step)
    return
  end
  
  M._ask_tags(task, opts, function(t)
    vim.schedule(function() M._chain_comms(obj, t, opts, task_num, next_step) end)
  end)
end

--- Chain step 3: Comms (contact lookup)
function M._chain_comms(obj, task, opts, task_num, next_step)
  if not opts.ask_comms then
    M._chain_dates(obj, task, opts, task_num, next_step)
    return
  end
  
  -- Check if task has communication context
  local context_type = detect_comms_context(task.tags, opts.comms_triggers)
  if not context_type then
    M._chain_dates(obj, task, opts, task_num, next_step)
    return
  end
  
  -- Extract name from title
  local name = extract_name(task.title, opts.name_patterns)
  if not name then
    M._chain_dates(obj, task, opts, task_num, next_step)
    return
  end
  
  -- Look up contact
  M._lookup_contact(task, name, context_type, opts, function(t)
    vim.schedule(function() M._chain_dates(obj, t, opts, task_num, next_step) end)
  end)
end

--- Chain step 4: Dates
function M._chain_dates(obj, task, opts, task_num, next_step)
  local Object = require("gtd-nvim.capture.model.object")
  
  if not opts.ask_dates then
    Object.add_child(obj, task)
    vim.schedule(function() M._collect_task(obj, opts, task_num + 1, next_step) end)
    return
  end
  
  M._ask_dates(task, opts, function(t)
    Object.add_child(obj, t)
    vim.schedule(function() M._collect_task(obj, opts, task_num + 1, next_step) end)
  end)
end

-- ============================================================================
-- UI COMPONENTS
-- ============================================================================

--- Ask for task state
function M._ask_state(task, opts, callback)
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    task.state = opts.default_state
    callback(task)
    return
  end
  
  fzf.fzf_exec({
    "󱥦 NEXT     (ready to do now)",
    "󰄲 TODO     (not yet actionable)",
    " WAITING  (delegated/blocked)",
    "󰋚 SOMEDAY  (maybe/later)",
  }, {
    prompt = "State ❯ ",
    winopts = { height = 0.28, width = 0.4 },
    actions = {
      ["default"] = function(sel)
        task.state = sel and sel[1] and sel[1]:match("(%u+)") or opts.default_state
        vim.schedule(function() callback(task) end)
      end,
    },
  })
end

--- Ask for tags
function M._ask_tags(task, opts, callback)
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    callback(task)
    return
  end
  
  local items = { " (skip - no tags)" }
  for _, tag in ipairs(opts.context_tags) do
    table.insert(items, " " .. tag)
  end
  
  fzf.fzf_exec(items, {
    prompt = "Tags ❯ ",
    fzf_opts = { ["--multi"] = true },
    winopts = { height = 0.4, width = 0.35 },
    actions = {
      ["default"] = function(sel)
        if not sel or #sel == 0 or (sel[1] and sel[1]:match("skip")) then
          vim.schedule(function() callback(task) end)
          return
        end
        
        task.tags = task.tags or {}
        for _, item in ipairs(sel) do
          local tag = item:match("@(%w+)")
          if tag then table.insert(task.tags, tag) end
        end
        vim.schedule(function() callback(task) end)
      end,
    },
  })
end

--- Look up contact via chronos-bridge
function M._lookup_contact(task, name, context_type, opts, callback)
  local comms_ok, comms = pcall(require, "gtd-nvim.gtd.comms")
  if not comms_ok then
    callback(task)
    return
  end
  
  vim.notify("󰏲 Looking up: " .. name, vim.log.levels.INFO)
  local contacts = comms.search_contacts(name, 5)
  
  if not contacts or #contacts == 0 then
    vim.notify("No contact found: " .. name, vim.log.levels.INFO)
    callback(task)
    return
  end
  
  -- Single match - auto-select
  if #contacts == 1 then
    M._apply_contact(task, contacts[1], context_type, comms)
    callback(task)
    return
  end
  
  -- Multiple matches - picker
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    M._apply_contact(task, contacts[1], context_type, comms)
    callback(task)
    return
  end
  
  local items = {}
  local lookup = {}
  for _, contact in ipairs(contacts) do
    local info = comms.get_contact_info(contact, context_type)
    local detail = info and (" → " .. info.value) or ""
    local org = contact.organization and (" @ " .. contact.organization) or ""
    local line = string.format("󰀄 %s%s%s", contact.full_name or "?", org, detail)
    table.insert(items, line)
    lookup[line] = contact
  end
  table.insert(items, "󰜺 (skip - no contact)")
  
  fzf.fzf_exec(items, {
    prompt = "Contact ❯ ",
    winopts = { height = 0.35, width = 0.5 },
    actions = {
      ["default"] = function(sel)
        if sel and sel[1] and lookup[sel[1]] then
          M._apply_contact(task, lookup[sel[1]], context_type, comms)
        end
        vim.schedule(function() callback(task) end)
      end,
    },
  })
end

--- Apply contact info to task
function M._apply_contact(task, contact, context_type, comms)
  local info = comms.get_contact_info(contact, context_type)
  
  task.contact = {
    id = contact.id,
    name = contact.full_name,
    context_type = context_type,
  }
  
  if info then
    if context_type == "phone" or context_type == "message" then
      task.contact.phone = info.value
      task.contact.url = info.url
    elseif context_type == "email" then
      task.contact.email = info.value
      task.contact.url = info.url
    end
  end
  
  vim.notify("󰀄 Contact: " .. contact.full_name, vim.log.levels.INFO)
end

--- Ask for dates
function M._ask_dates(task, opts, callback)
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    callback(task)
    return
  end
  
  fzf.fzf_exec({
    "󰃰 Set dates (calendar)",
    "󰜺 No dates (later)",
  }, {
    prompt = "Dates? ❯ ",
    winopts = { height = 0.18, width = 0.35 },
    actions = {
      ["default"] = function(sel)
        if sel and sel[1] and sel[1]:match("Set dates") then
          vim.schedule(function()
            local picker_ok, picker = pcall(require, "gtd-nvim.capture.ui.datepicker")
            if picker_ok then
              picker.open({
                on_complete = function(defer, due)
                  if defer then task.scheduled = defer end
                  if due then task.deadline = due end
                  vim.schedule(function() callback(task) end)
                end,
              })
            else
              M._input_dates(task, callback)
            end
          end)
        else
          vim.schedule(function() callback(task) end)
        end
      end,
    },
  })
end

--- Text fallback for dates
function M._input_dates(task, callback)
  local today = os.date("%Y-%m-%d")
  vim.ui.input({ prompt = "  Defer [today]: " }, function(defer)
    if defer and defer ~= "" then
      task.scheduled = parse_smart_date(defer, today) or defer
    end
    vim.schedule(function()
      vim.ui.input({ prompt = "  Due [+3d]: " }, function(due)
        if due and due ~= "" then
          task.deadline = parse_smart_date(due, task.scheduled or today) or due
        end
        callback(task)
      end)
    end)
  end)
end

return M
