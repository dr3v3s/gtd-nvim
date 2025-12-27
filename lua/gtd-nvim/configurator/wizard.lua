-- gtd-nvim/configurator/wizard.lua
-- Full setup wizard for Chronos configuration
--
-- File:    lua/gtd-nvim/configurator/wizard.lua
-- Version: 0.10.1
-- Updated: 2025-12-22
--
-- Guides user through complete initial setup:
-- 1. Identity (name, email, etc.)
-- 2. File paths (GTD, Notes)
-- 3. Calendar selection
-- 4. Reminder lists selection
-- 5. Mailbox selection
-- 6. Summary and confirmation

local M = {}

local FileVersion = "0.10.1"

-- ═══════════════════════════════════════════════════════════════════════════
-- DEPENDENCIES
-- ═══════════════════════════════════════════════════════════════════════════

local configurator = require("gtd-nvim.configurator")
local pickers = require("gtd-nvim.configurator.pickers")

-- ═══════════════════════════════════════════════════════════════════════════
-- GLYPHS
-- ═══════════════════════════════════════════════════════════════════════════

local glyphs = {
  wizard = "󰔡",
  step = "󰁔",
  done = "󰄳",
  skip = "󰜺",
  identity = "󰀄",
  path = "󰉋",
  calendar = "󰃭",
  reminder = "󰂚",
  mail = "󰇮",
  check = "󰄬",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

local wizard_state = {
  step = 1,
  config = nil,
  completed_steps = {},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function notify(msg, level)
  vim.notify("[wizard] " .. msg, level or vim.log.levels.INFO)
end

local function clear_state()
  wizard_state.step = 1
  wizard_state.config = nil
  wizard_state.completed_steps = {}
end

--- Ensure config has all required nested structures
local function ensure_config_structure(cfg)
  cfg = cfg or {}
  cfg._meta = cfg._meta or { version = 1 }
  cfg.identity = cfg.identity or {}
  cfg.paths = cfg.paths or {
    gtd_root = "~/Documents/GTD",
    notes_root = "~/Documents/Notes",
    archive_root = "~/Documents/GTD/Archive",
    templates_dir = "~/Documents/GTD/Templates",
    cache_dir = "~/.cache/chronos",
  }
  cfg.integrations = cfg.integrations or {}
  cfg.integrations.calendar = cfg.integrations.calendar or { enabled = false, enabled_calendars = {} }
  cfg.integrations.reminders = cfg.integrations.reminders or { enabled = false, enabled_lists = {} }
  cfg.integrations.mail = cfg.integrations.mail or { enabled = false, accounts = {} }
  return cfg
end

-- ═══════════════════════════════════════════════════════════════════════════
-- WIZARD STEPS
-- ═══════════════════════════════════════════════════════════════════════════

local steps = {
  {
    id = "welcome",
    title = "Welcome",
    icon = glyphs.wizard,
    description = "Welcome to Chronos Setup Wizard",
  },
  {
    id = "identity",
    title = "Identity",
    icon = glyphs.identity,
    description = "Set your name, email, and contact info",
  },
  {
    id = "paths",
    title = "Paths",
    icon = glyphs.path,
    description = "Configure GTD and Notes directories",
  },
  {
    id = "calendars",
    title = "Calendars",
    icon = glyphs.calendar,
    description = "Select which calendars to sync",
  },
  {
    id = "reminders",
    title = "Reminders",
    icon = glyphs.reminder,
    description = "Select which reminder lists to use",
  },
  {
    id = "mail",
    title = "Mail",
    icon = glyphs.mail,
    description = "Select which mailboxes to monitor",
  },
  {
    id = "summary",
    title = "Summary",
    icon = glyphs.done,
    description = "Review and save configuration",
  },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN WIZARD
-- ═══════════════════════════════════════════════════════════════════════════

function M.start()
  clear_state()
  
  -- Load existing config or create new, then ensure structure
  local config, _ = configurator.load_config()
  wizard_state.config = ensure_config_structure(config)
  
  M.show_step(1)
end

function M.show_step(step_num)
  wizard_state.step = step_num
  local step = steps[step_num]
  
  if not step then
    M.finish()
    return
  end
  
  if step.id == "welcome" then
    M._show_welcome()
  elseif step.id == "identity" then
    M._show_identity()
  elseif step.id == "paths" then
    M._show_paths()
  elseif step.id == "calendars" then
    M._show_calendars()
  elseif step.id == "reminders" then
    M._show_reminders()
  elseif step.id == "mail" then
    M._show_mail()
  elseif step.id == "summary" then
    M._show_summary()
  end
end

function M.next_step()
  wizard_state.completed_steps[wizard_state.step] = true
  M.show_step(wizard_state.step + 1)
end

function M.prev_step()
  if wizard_state.step > 1 then
    M.show_step(wizard_state.step - 1)
  end
end

function M.skip_step()
  M.next_step()
end

function M.finish()
  -- Save configuration
  local ok, err = configurator.save_config(wizard_state.config)
  
  if ok then
    notify("Configuration saved successfully!", vim.log.levels.INFO)
    
    -- Show completion message
    local msg = string.format([[
%s Chronos Setup Complete!

Configuration saved to:
  %s

Next steps:
  • Start chronos-bridge daemon
  • Start chronosd daemon
  • Run :GTD to open task manager

Press any key to close...
]], glyphs.done, configurator.get_config_path())
    
    M._show_popup(msg, "Setup Complete", function()
      clear_state()
    end)
  else
    notify("Failed to save configuration: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP: WELCOME
-- ═══════════════════════════════════════════════════════════════════════════

function M._show_welcome()
  local content = string.format([[
%s Welcome to Chronos GTD Setup

This wizard will help you configure Chronos for your workflow.

We'll set up:
  %s Identity     Your name, email, and contact info
  %s Paths        Where to store GTD and Notes files
  %s Calendars    Which calendars to sync (if available)
  %s Reminders    Which reminder lists to use (if available)
  %s Mail         Which mailboxes to monitor (if available)

Press ENTER to begin, or 'q' to quit.
]], glyphs.wizard, glyphs.identity, glyphs.path, glyphs.calendar, glyphs.reminder, glyphs.mail)
  
  M._show_popup(content, "Chronos Setup Wizard", function()
    vim.schedule(function()
      M.next_step()
    end)
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP: IDENTITY
-- ═══════════════════════════════════════════════════════════════════════════

function M._show_identity()
  -- Ensure identity section exists
  if not wizard_state.config.identity then
    wizard_state.config.identity = {}
  end
  local identity = wizard_state.config.identity
  
  local fields = {
    { key = "name", label = "Name", required = true },
    { key = "email", label = "Email", required = true },
    { key = "phone", label = "Phone", required = false },
    { key = "handle", label = "Handle (@username)", required = false },
  }
  
  local current_field = 1
  
  local function prompt_field()
    local field = fields[current_field]
    if not field then
      -- All fields done
      vim.schedule(M.next_step)
      return
    end
    
    local req = field.required and " (required)" or " (optional)"
    local default = identity[field.key] or ""
    
    vim.ui.input({
      prompt = string.format("Step 2/%d: %s%s: ", #steps - 1, field.label, req),
      default = default,
    }, function(input)
      if input == nil then
        -- User cancelled
        return
      end
      
      if input ~= "" then
        wizard_state.config.identity[field.key] = input
      elseif field.required then
        notify(field.label .. " is required", vim.log.levels.WARN)
        vim.schedule(prompt_field)
        return
      end
      
      current_field = current_field + 1
      vim.schedule(prompt_field)
    end)
  end
  
  prompt_field()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP: PATHS
-- ═══════════════════════════════════════════════════════════════════════════

function M._show_paths()
  -- Ensure paths section exists
  if not wizard_state.config.paths then
    wizard_state.config.paths = {
      gtd_root = "~/Documents/GTD",
      notes_root = "~/Documents/Notes",
    }
  end
  local paths = wizard_state.config.paths
  
  local fields = {
    { key = "gtd_root", label = "GTD Root", default = "~/Documents/GTD" },
    { key = "notes_root", label = "Notes Root", default = "~/Documents/Notes" },
  }
  
  local current_field = 1
  
  local function prompt_field()
    local field = fields[current_field]
    if not field then
      -- All fields done
      vim.schedule(M.next_step)
      return
    end
    
    local default = paths[field.key] or field.default
    
    vim.ui.input({
      prompt = string.format("Step 3/%d: %s: ", #steps - 1, field.label),
      default = default,
      completion = "dir",
    }, function(input)
      if input == nil then
        return
      end
      
      if input ~= "" then
        wizard_state.config.paths[field.key] = input
      end
      
      current_field = current_field + 1
      vim.schedule(prompt_field)
    end)
  end
  
  prompt_field()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP: CALENDARS
-- ═══════════════════════════════════════════════════════════════════════════

function M._show_calendars()
  if not configurator.is_bridge_available() then
    notify("chronos-bridge not available, skipping calendars", vim.log.levels.INFO)
    vim.schedule(M.next_step)
    return
  end
  
  local calendars = configurator.discover_calendars()
  
  if #calendars == 0 then
    notify("No calendars found, skipping", vim.log.levels.INFO)
    vim.schedule(M.next_step)
    return
  end
  
  -- Build selection list
  local items = {}
  for _, cal in ipairs(calendars) do
    local mark = cal.is_default and " (default)" or ""
    table.insert(items, cal.title .. mark)
  end
  
  vim.ui.select(items, {
    prompt = "Step 4: Select calendars (multi-select not supported in vim.ui.select)",
  }, function(choice)
    if choice then
      -- Extract calendar name
      local name = choice:gsub(" %(default%)$", "")
      wizard_state.config.integrations.calendar.enabled_calendars = { name }
      wizard_state.config.integrations.calendar.enabled = true
      notify("Selected calendar: " .. name)
    end
    vim.schedule(M.next_step)
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP: REMINDERS
-- ═══════════════════════════════════════════════════════════════════════════

function M._show_reminders()
  if not configurator.is_bridge_available() then
    notify("chronos-bridge not available, skipping reminders", vim.log.levels.INFO)
    vim.schedule(M.next_step)
    return
  end
  
  local lists = configurator.discover_reminder_lists()
  
  if #lists == 0 then
    notify("No reminder lists found, skipping", vim.log.levels.INFO)
    vim.schedule(M.next_step)
    return
  end
  
  local items = {}
  for _, list in ipairs(lists) do
    local mark = list.is_default and " (default)" or ""
    table.insert(items, list.title .. mark)
  end
  
  vim.ui.select(items, {
    prompt = "Step 5: Select inbox list for capture",
  }, function(choice)
    if choice then
      local name = choice:gsub(" %(default%)$", "")
      wizard_state.config.integrations.reminders.inbox_list = name
      wizard_state.config.integrations.reminders.enabled_lists = { name }
      wizard_state.config.integrations.reminders.enabled = true
      notify("Selected reminder list: " .. name)
    end
    vim.schedule(M.next_step)
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP: MAIL
-- ═══════════════════════════════════════════════════════════════════════════

function M._show_mail()
  if not configurator.is_bridge_available() then
    notify("chronos-bridge not available, skipping mail", vim.log.levels.INFO)
    vim.schedule(M.next_step)
    return
  end
  
  local accounts = configurator.discover_mailboxes()
  
  if #accounts == 0 then
    notify("No mail accounts found, skipping", vim.log.levels.INFO)
    vim.schedule(M.next_step)
    return
  end
  
  -- For wizard, just enable INBOX for all accounts
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Step 6: Enable mail monitoring for %d account(s)?", #accounts),
  }, function(choice)
    if choice == "Yes" then
      local mail_accounts = {}
      for _, acc in ipairs(accounts) do
        -- Find INBOX mailbox
        local inbox_name = nil
        for _, mb in ipairs(acc.mailboxes) do
          if mb.name:lower() == "inbox" then
            inbox_name = mb.name
            break
          end
        end
        
        if inbox_name then
          table.insert(mail_accounts, {
            name = acc.name,
            enabled = true,
            enabled_mailboxes = { inbox_name },
          })
        end
      end
      
      wizard_state.config.integrations.mail.enabled = #mail_accounts > 0
      wizard_state.config.integrations.mail.accounts = mail_accounts
      notify("Enabled INBOX monitoring for " .. #mail_accounts .. " account(s)")
    end
    vim.schedule(M.next_step)
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP: SUMMARY
-- ═══════════════════════════════════════════════════════════════════════════

function M._show_summary()
  local cfg = wizard_state.config
  
  local cal_status = cfg.integrations.calendar.enabled 
    and (#cfg.integrations.calendar.enabled_calendars .. " calendars")
    or "disabled"
  
  local rem_status = cfg.integrations.reminders.enabled
    and (#cfg.integrations.reminders.enabled_lists .. " lists")
    or "disabled"
  
  local mail_status = cfg.integrations.mail.enabled
    and (#cfg.integrations.mail.accounts .. " accounts")
    or "disabled"
  
  local content = string.format([[
%s Configuration Summary

%s Identity
  Name:     %s
  Email:    %s
  Phone:    %s
  Handle:   %s

%s Paths
  GTD Root:   %s
  Notes Root: %s

%s Integrations
  Calendars: %s
  Reminders: %s
  Mail:      %s

Press ENTER to save, 'q' to cancel.
]], 
    glyphs.done,
    glyphs.identity,
    cfg.identity.name or "(not set)",
    cfg.identity.email or "(not set)",
    cfg.identity.phone or "(not set)",
    cfg.identity.handle or "(not set)",
    glyphs.path,
    cfg.paths.gtd_root or "(not set)",
    cfg.paths.notes_root or "(not set)",
    glyphs.check,
    cal_status,
    rem_status,
    mail_status
  )
  
  M._show_popup(content, "Configuration Summary", function()
    vim.schedule(M.finish)
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- UI HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

function M._show_popup(content, title, on_confirm)
  local lines = vim.split(content, "\n")
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  
  local width = 60
  local height = math.min(#lines + 2, 25)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })
  
  -- Keymaps
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
    end,
  })
  
  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
      if on_confirm then
        on_confirm()
      end
    end,
  })
  
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
    end,
  })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MODULE INFO
-- ═══════════════════════════════════════════════════════════════════════════

function M.version()
  return FileVersion
end

return M
