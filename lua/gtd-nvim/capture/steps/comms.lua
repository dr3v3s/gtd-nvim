-- ============================================================================
-- STEP: COMMS (Communication Integration)
-- ============================================================================
-- Detect @phone/@email tags, lookup contact, offer immediate action.
--
-- @module gtd-nvim.capture.steps.comms
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

M.name = "comms"
M.applies_to = { "task" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  -- Context tags that trigger contact lookup
  triggers = {
    phone = { "phone", "call", "ring", "telefon" },
    email = { "email", "mail", "epost" },
    message = { "message", "sms", "text", "imessage" },
    facetime = { "facetime", "video" },
  },
  
  -- Name extraction patterns
  name_patterns = {
    "^[Cc]all%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Pp]hone%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Ee]mail%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Rr]ing%s+til%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Rr]inge%s+til%s+([A-Z][a-zæøåÆØÅ]+)",
    "^[Ss]kriv%s+til%s+([A-Z][a-zæøåÆØÅ]+)",
    "til%s+([A-Z][a-zæøåÆØÅ]+)%s",
    "to%s+([A-Z][a-zæøåÆØÅ]+)%s",
  },
  
  -- Auto-trigger action after task creation
  prompt_action = true,
}

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Detect communication context from tags
---@param tags table Array of tags (without @ prefix)
---@param triggers table Trigger patterns
---@return string|nil context_type (phone, email, message, facetime)
local function detect_context(tags, triggers)
  tags = tags or {}
  
  for context_type, patterns in pairs(triggers) do
    for _, pattern in ipairs(patterns) do
      for _, tag in ipairs(tags) do
        if tag:lower() == pattern:lower() then
          return context_type
        end
      end
    end
  end
  
  return nil
end

--- Extract name from title
---@param title string Task title
---@param patterns table Name extraction patterns
---@return string|nil name
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

--- Determine if this step should run
---@param obj table OrgObject
---@param opts table Step options
---@return boolean
function M.should_run(obj, opts)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Check if we have communication-related tags
  local context = detect_context(obj.tags, opts.triggers)
  return context ~= nil
end

-- ============================================================================
-- RUN
-- ============================================================================

--- Execute the step
---@param obj table OrgObject
---@param opts table Step options
---@param next_step function Callback to continue
function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Load comms module for contact search
  local comms_ok, comms = pcall(require, "gtd-nvim.gtd.comms")
  if not comms_ok then
    next_step(obj)
    return
  end
  
  -- Detect context type
  local context_type = detect_context(obj.tags, opts.triggers)
  if not context_type then
    next_step(obj)
    return
  end
  
  -- Extract name from title
  local name = extract_name(obj.title, opts.name_patterns)
  if not name then
    next_step(obj)
    return
  end
  
  -- Search contacts
  vim.notify("󰏲 Looking up: " .. name, vim.log.levels.INFO)
  local contacts = comms.search_contacts(name, 5)
  
  if not contacts or #contacts == 0 then
    vim.notify("No contact found: " .. name, vim.log.levels.INFO)
    next_step(obj)
    return
  end
  
  -- Single match
  if #contacts == 1 then
    M._handle_contact(obj, contacts[1], context_type, opts, comms, next_step)
    return
  end
  
  -- Multiple matches - show picker
  M._show_picker(obj, contacts, context_type, opts, comms, next_step)
end

--- Handle selected contact
function M._handle_contact(obj, contact, context_type, opts, comms, next_step)
  local info = comms.get_contact_info(contact, context_type)
  
  -- Store contact info
  obj.contact = {
    id = contact.id,
    name = contact.full_name,
    context_type = context_type,
  }
  
  if info then
    if context_type == "phone" or context_type == "message" then
      obj.contact.phone = info.value
      obj.contact.url = info.url
    elseif context_type == "email" then
      obj.contact.email = info.value
      obj.contact.url = info.url
    end
  end
  
  vim.notify("󰀄 Contact: " .. contact.full_name, vim.log.levels.INFO)
  
  -- Store for action prompt after finalize
  if opts.prompt_action and info and info.url then
    obj._pending_action = {
      url = info.url,
      contact_name = contact.full_name,
      context_type = context_type,
    }
  end
  
  next_step(obj)
end

--- Show contact picker
function M._show_picker(obj, contacts, context_type, opts, comms, next_step)
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    -- Fallback: use first contact
    M._handle_contact(obj, contacts[1], context_type, opts, comms, next_step)
    return
  end
  
  local display = {}
  local meta = {}
  
  for _, contact in ipairs(contacts) do
    local info = comms.get_contact_info(contact, context_type)
    local detail = info and (" → " .. info.value) or ""
    local org = contact.organization and (" @ " .. contact.organization) or ""
    local line = string.format("󰀄 %s%s%s", contact.full_name or "?", org, detail)
    table.insert(display, line)
    table.insert(meta, contact)
  end
  
  table.insert(display, "󰜺 (skip - no contact)")
  
  fzf.fzf_exec(display, {
    prompt = "Contact ❯ ",
    winopts = { height = 0.35, width = 0.5 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] or sel[1]:match("skip") then
          vim.schedule(function() next_step(obj) end)
          return
        end
        
        for i, line in ipairs(display) do
          if line == sel[1] and meta[i] then
            vim.schedule(function()
              M._handle_contact(obj, meta[i], context_type, opts, comms, next_step)
            end)
            return
          end
        end
        
        vim.schedule(function() next_step(obj) end)
      end,
    },
  })
end

return M
