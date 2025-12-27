-- ============================================================================
-- GTD-NVIM COMMUNICATION INTEGRATION
-- ============================================================================
-- Enhances capture with contact lookup and action triggers for:
-- - @phone / @call → Phone.app
-- - @email / @mail → Mail.app  
-- - @message / @sms → Messages.app
-- - @facetime → FaceTime.app
--
-- @module gtd-nvim.gtd.comms
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local chronos = safe_require("gtd-nvim.gtd.chronos-client")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.config = {
  -- Context tags that trigger contact lookup
  triggers = {
    phone = { "@phone", "@call", "@ring", "@telefon" },
    email = { "@email", "@mail", "@epost" },
    message = { "@message", "@sms", "@text", "@imessage" },
    facetime = { "@facetime", "@video" },
  },
  
  -- Whether to prompt for immediate action
  prompt_action = true,
  
  -- Whether to auto-add contact properties
  add_properties = true,
  
  -- Name extraction patterns (applied to title)
  name_patterns = {
    -- English patterns
    "^[Cc]all%s+([A-Z][a-zæøåÆØÅ]+)",           -- "Call John..."
    "^[Pp]hone%s+([A-Z][a-zæøåÆØÅ]+)",          -- "Phone John..."
    "^[Ee]mail%s+([A-Z][a-zæøåÆØÅ]+)",          -- "Email John..."
    "^[Mm]essage%s+([A-Z][a-zæøåÆØÅ]+)",        -- "Message John..."
    "^[Tt]ext%s+([A-Z][a-zæøåÆØÅ]+)",           -- "Text John..."
    "^[Cc]ontact%s+([A-Z][a-zæøåÆØÅ]+)",        -- "Contact John..."
    -- Danish patterns
    "^[Rr]ing%s+til%s+([A-Z][a-zæøåÆØÅ]+)",     -- "Ring til John..."
    "^[Rr]inge%s+til%s+([A-Z][a-zæøåÆØÅ]+)",    -- "Ringe til John..."
    "^[Rr]ing%s+([A-Z][a-zæøåÆØÅ]+)",           -- "Ring John..."
    "^[Ss]kriv%s+til%s+([A-Z][a-zæøåÆØÅ]+)",    -- "Skriv til John..."
    -- "... to/til Person" patterns
    "to%s+([A-Z][a-zæøåÆØÅ]+)%s",               -- "...to John about"
    "til%s+([A-Z][a-zæøåÆØÅ]+)%s",              -- "...til John ang"
    -- With last name
    "^[Cc]all%s+([A-Z][a-zæøåÆØÅ]+%s+[A-Z][a-zæøåÆØÅ]+)",
    "^[Rr]ing%s+til%s+([A-Z][a-zæøåÆØÅ]+%s+[A-Z][a-zæøåÆØÅ]+)",
  },
}

-- ============================================================================
-- CONTEXT DETECTION
-- ============================================================================

--- Detect communication context from tags/title
---@param title string Task title
---@param tags table|nil Array of tags
---@return string|nil context_type One of: phone, email, message, facetime, nil
function M.detect_context(title, tags)
  local text = title:lower()
  tags = tags or {}
  
  -- Check tags first
  for context_type, patterns in pairs(M.config.triggers) do
    for _, pattern in ipairs(patterns) do
      local pattern_without_at = pattern:sub(2):lower()  -- "phone" from "@phone"
      
      -- Check in tags array
      for _, tag in ipairs(tags) do
        local tag_lower = tag:lower()
        -- Handle both "phone" and "@phone" inputs
        local tag_without_at = tag_lower:gsub("^@", "")
        if tag_without_at == pattern_without_at then
          return context_type
        end
      end
      
      -- Check in title (look for @phone or just the pattern)
      if text:find(pattern:lower(), 1, true) or text:find(pattern_without_at, 1, true) then
        return context_type
      end
    end
  end
  
  return nil
end

--- Extract person name from title
---@param title string Task title
---@return string|nil name Extracted name
function M.extract_name(title)
  for _, pattern in ipairs(M.config.name_patterns) do
    local name = title:match(pattern)
    if name then
      return name
    end
  end
  return nil
end

-- ============================================================================
-- CONTACT LOOKUP
-- ============================================================================

--- Search for contacts matching a name
---@param name string Name to search
---@param limit number|nil Max results (default 5)
---@return table|nil contacts Array of contact objects
function M.search_contacts(name, limit)
  if not chronos then
    return nil
  end
  
  local data, err = chronos.query_bridge("contacts", "search", {
    query = name,
    limit = limit or 5,
  })
  
  if not data or not data.contacts then
    return nil
  end
  
  return data.contacts
end

--- Get best contact info for a context type
---@param contact table Contact object from search
---@param context_type string One of: phone, email, message, facetime
---@return table|nil { value, label, url }
function M.get_contact_info(contact, context_type)
  if not contact then return nil end
  
  if context_type == "phone" or context_type == "message" then
    -- Get phone number
    local phone = contact.primary_phone
    if not phone and contact.phones and #contact.phones > 0 then
      phone = contact.phones[1].value
    end
    if phone then
      local clean = phone:gsub("[^%d+]", "")
      return {
        value = phone,
        label = "phone",
        url = context_type == "phone" 
          and ("tel:" .. clean)
          or ("sms:" .. clean),
      }
    end
  elseif context_type == "email" then
    -- Get email address
    local email = contact.primary_email
    if not email and contact.emails and #contact.emails > 0 then
      email = contact.emails[1].value
    end
    if email then
      return {
        value = email,
        label = "email",
        url = "mailto:" .. email,
      }
    end
  elseif context_type == "facetime" then
    -- Prefer email for FaceTime, fallback to phone
    local email = contact.primary_email
    if email then
      return {
        value = email,
        label = "facetime",
        url = "facetime:" .. email,
      }
    end
    local phone = contact.primary_phone
    if phone then
      local clean = phone:gsub("[^%d+]", "")
      return {
        value = phone,
        label = "facetime",
        url = "facetime:" .. clean,
      }
    end
  end
  
  return nil
end

-- ============================================================================
-- ACTION TRIGGERS
-- ============================================================================

--- Open URL with macOS open command
---@param url string URL to open (tel:, mailto:, sms:, facetime:)
---@return boolean success
function M.open_url(url)
  if not url then return false end
  
  local cmd = string.format("open '%s'", url:gsub("'", "'\\''"))
  local result = os.execute(cmd)
  return result == 0 or result == true
end

--- Trigger communication action
---@param contact table Contact object
---@param context_type string One of: phone, email, message, facetime
---@return boolean success
function M.trigger_action(contact, context_type)
  local info = M.get_contact_info(contact, context_type)
  if not info then
    vim.notify("No " .. context_type .. " info for " .. (contact.full_name or "contact"), vim.log.levels.WARN)
    return false
  end
  
  return M.open_url(info.url)
end

-- ============================================================================
-- CAPTURE ENHANCEMENT
-- ============================================================================

--- Process capture for communication context
--- Returns enhanced properties and optional action callback
---@param title string Task title
---@param tags table|nil Tags array
---@param callback function Callback with (properties, action_fn)
function M.process_capture(title, tags, callback)
  -- Detect context
  local context_type = M.detect_context(title, tags)
  if not context_type then
    -- No communication context, continue normally
    callback({}, nil)
    return
  end
  
  -- Extract name
  local name = M.extract_name(title)
  if not name then
    -- No name detected, continue normally
    callback({}, nil)
    return
  end
  
  -- Search contacts
  local contacts = M.search_contacts(name)
  if not contacts or #contacts == 0 then
    -- No contacts found, continue normally
    vim.notify("No contact found for: " .. name, vim.log.levels.INFO)
    callback({}, nil)
    return
  end
  
  -- If single match, use it directly
  if #contacts == 1 then
    M._handle_contact_selection(contacts[1], context_type, callback)
    return
  end
  
  -- Multiple matches - show picker
  M._show_contact_picker(contacts, context_type, callback)
end

--- Handle selected contact
---@param contact table Selected contact
---@param context_type string Communication type
---@param callback function Callback function
function M._handle_contact_selection(contact, context_type, callback)
  local info = M.get_contact_info(contact, context_type)
  
  -- Build properties to add to task
  local props = {}
  if M.config.add_properties then
    props.CONTACT_ID = contact.id
    props.CONTACT_NAME = contact.full_name
    
    if info then
      if context_type == "phone" or context_type == "message" then
        props.PHONE = info.value
      elseif context_type == "email" then
        props.EMAIL = info.value
      end
    end
  end
  
  -- Create action function
  local action_fn = nil
  if info and M.config.prompt_action then
    action_fn = function()
      return M.open_url(info.url)
    end
  end
  
  callback(props, action_fn, contact, info)
end

--- Show contact picker for multiple matches
---@param contacts table Array of contacts
---@param context_type string Communication type
---@param callback function Callback function
function M._show_contact_picker(contacts, context_type, callback)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    -- Fallback to first contact
    M._handle_contact_selection(contacts[1], context_type, callback)
    return
  end
  
  local display = {}
  local meta = {}
  
  for _, contact in ipairs(contacts) do
    local info = M.get_contact_info(contact, context_type)
    local detail = info and info.value or ""
    local org = contact.organization and (" @ " .. contact.organization) or ""
    
    local line = string.format("󰀄 %s%s  %s", 
      contact.full_name or "?",
      org,
      detail)
    
    table.insert(display, line)
    table.insert(meta, contact)
  end
  
  fzf.fzf_exec(display, {
    prompt = "Select contact> ",
    actions = {
      ["default"] = function(sel, opts)
        if not sel or not sel[1] then
          callback({}, nil)
          return
        end
        -- Find selected contact
        for i, line in ipairs(display) do
          if line == sel[1] or sel[1]:find(meta[i].full_name, 1, true) then
            vim.schedule(function()
              M._handle_contact_selection(meta[i], context_type, callback)
            end)
            return
          end
        end
        callback({}, nil)
      end,
      ["esc"] = function()
        callback({}, nil)
      end,
    },
    winopts = {
      height = 0.3,
      width = 0.5,
      row = 0.4,
    },
  })
end

-- ============================================================================
-- PROMPT FOR ACTION
-- ============================================================================

--- Prompt user to execute action now
---@param action_fn function Action to execute
---@param contact table Contact info
---@param context_type string Communication type
---@param on_complete function Called after decision
function M.prompt_action(action_fn, contact, context_type, on_complete)
  if not action_fn then
    if on_complete then on_complete() end
    return
  end
  
  local action_labels = {
    phone = "Call",
    email = "Email",
    message = "Message",
    facetime = "FaceTime",
  }
  
  local label = action_labels[context_type] or "Contact"
  local name = contact and contact.full_name or "contact"
  
  vim.ui.select({ "Yes", "No" }, {
    prompt = label .. " " .. name .. " now?",
  }, function(choice)
    if choice == "Yes" then
      action_fn()
    end
    if on_complete then on_complete() end
  end)
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  
  -- Commands for testing
  vim.api.nvim_create_user_command("CommsTest", function(cmd_opts)
    local title = cmd_opts.args
    if title == "" then
      title = "Call John about the project @phone"
    end
    
    M.process_capture(title, {}, function(props, action_fn, contact, info)
      vim.notify(vim.inspect({
        props = props,
        contact = contact and contact.full_name,
        info = info,
        has_action = action_fn ~= nil,
      }), vim.log.levels.INFO)
      
      if action_fn then
        M.prompt_action(action_fn, contact, "phone", nil)
      end
    end)
  end, { nargs = "*", desc = "Test communication detection" })
end

return M
