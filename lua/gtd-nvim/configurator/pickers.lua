-- gtd-nvim/configurator/pickers.lua
-- fzf-lua multi-select pickers for configuration
--
-- File:    lua/gtd-nvim/configurator/pickers.lua
-- Version: 0.12.0
-- Updated: 2025-12-27
--
-- Provides interactive pickers for selecting:
-- - Calendars (multi-select)
-- - Reminder lists (multi-select)
-- - Mailboxes per account (multi-select)
-- - File paths
-- - Identity fields

local M = {}

local FileVersion = "0.11.0"

-- ═══════════════════════════════════════════════════════════════════════════
-- DEPENDENCIES
-- ═══════════════════════════════════════════════════════════════════════════

local fzf_ok, fzf = pcall(require, "fzf-lua")
if not fzf_ok then
  vim.notify("[configurator] fzf-lua not found", vim.log.levels.ERROR)
  return M
end

local configurator = require("gtd-nvim.configurator")

-- ═══════════════════════════════════════════════════════════════════════════
-- GLYPHS
-- ═══════════════════════════════════════════════════════════════════════════

local glyphs = {
  calendar = "󰃭",
  reminder = "󰂚",
  mail = "󰇮",
  mailbox = "󰏤",
  folder = "󰉋",
  user = "󰏃",
  check = "󰄬",
  uncheck = "󰄱",
  default = "󰓒",
  enabled = "󰄳",
  disabled = "󰅖",
  warning = "󰀦",
  path = "󰉋",
  identity = "󰀄",
  settings = "󰒓",
  migrate = "󰁔",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function notify(msg, level)
  vim.notify("[configurator] " .. msg, level or vim.log.levels.INFO)
end

--- Format a calendar for display
---@param cal table Calendar info
---@param selected boolean Whether currently selected
---@return string
local function format_calendar(cal, selected)
  local check = selected and glyphs.check or glyphs.uncheck
  local default_mark = cal.is_default and (" " .. glyphs.default) or ""
  local color_block = cal.color and ("█ ") or ""
  return string.format("%s %s%s%s", check, color_block, cal.title, default_mark)
end

--- Format a reminder list for display
---@param list table List info
---@param selected boolean Whether currently selected
---@return string
local function format_reminder_list(list, selected)
  local check = selected and glyphs.check or glyphs.uncheck
  local default_mark = list.is_default and (" " .. glyphs.default) or ""
  return string.format("%s %s%s", check, list.title, default_mark)
end

--- Format a mailbox for display
---@param mb table Mailbox info
---@param selected boolean Whether currently selected
---@return string
local function format_mailbox(mb, selected)
  local check = selected and glyphs.check or glyphs.uncheck
  local unread = mb.unread_count > 0 and string.format(" [%d]", mb.unread_count) or ""
  return string.format("%s %s%s", check, mb.name, unread)
end

--- Extract title from formatted string
---@param formatted string
---@return string
local function extract_title(formatted)
  -- Remove check/uncheck glyph and color block
  local title = formatted:gsub("^[󰄬󰄱] ", "")
  title = title:gsub("^█ ", "")
  -- Remove default marker
  title = title:gsub(" 󰓒$", "")
  -- Remove unread count
  title = title:gsub(" %[%d+%]$", "")
  return title
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN MENU
-- ═══════════════════════════════════════════════════════════════════════════

function M.main_menu()
  local items = {
    { icon = glyphs.identity, label = "Identity", desc = "Name, email, phone, handle", action = M.identity },
    { icon = glyphs.path, label = "Paths", desc = "GTD, Notes, Archive directories", action = M.paths },
    { icon = glyphs.calendar, label = "Calendars", desc = "Select active calendars", action = M.calendars },
    { icon = glyphs.reminder, label = "Reminders", desc = "Select reminder lists", action = M.reminder_lists },
    { icon = glyphs.mail, label = "Mail Accounts", desc = "Inbox Zero tracking", action = M.mail_accounts },
    { icon = glyphs.mailbox, label = "Mailboxes", desc = "Select mailboxes per account", action = M.mailboxes },
    { icon = glyphs.migrate, label = "Migrate", desc = "Move files to new location", action = M.migrate_menu },
  }
  
  local entries = {}
  for i, item in ipairs(items) do
    table.insert(entries, string.format("%s %s │ %s", item.icon, item.label, item.desc))
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.settings .. " Chronos Configurator> ",
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          local idx = nil
          for i, entry in ipairs(entries) do
            if entry == selected[1] then
              idx = i
              break
            end
          end
          if idx and items[idx] and items[idx].action then
            vim.schedule(items[idx].action)
          end
        end
      end,
    },
    winopts = {
      height = 0.4,
      width = 0.6,
      row = 0.3,
    },
    fzf_opts = {
      ["--no-multi"] = "",
      ["--header"] = "Select configuration section",
    },
  })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- IDENTITY PICKER
-- ═══════════════════════════════════════════════════════════════════════════

function M.identity()
  local config, err = configurator.load_config()
  if err then
    config = { identity = {} }
  end
  
  local identity = config.identity or {}
  
  local fields = {
    { key = "name", label = "Name", value = identity.name or "" },
    { key = "email", label = "Email", value = identity.email or "" },
    { key = "phone", label = "Phone", value = identity.phone or "" },
    { key = "handle", label = "Handle", value = identity.handle or "" },
    { key = "timezone", label = "Timezone", value = identity.timezone or "Local" },
    { key = "language", label = "Language", value = identity.language or "en" },
  }
  
  local entries = {}
  for _, field in ipairs(fields) do
    table.insert(entries, string.format("%-10s │ %s", field.label, field.value))
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.identity .. " Identity> ",
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          local idx = nil
          for i, entry in ipairs(entries) do
            if entry == selected[1] then
              idx = i
              break
            end
          end
          if idx and fields[idx] then
            vim.schedule(function()
              M._edit_identity_field(fields[idx], config)
            end)
          end
        end
      end,
    },
    winopts = {
      height = 0.35,
      width = 0.5,
      row = 0.3,
    },
    fzf_opts = {
      ["--no-multi"] = "",
      ["--header"] = "Select field to edit",
    },
  })
end

function M._edit_identity_field(field, config)
  vim.ui.input({
    prompt = field.label .. ": ",
    default = field.value,
  }, function(input)
    if input then
      config.identity = config.identity or {}
      config.identity[field.key] = input
      
      local ok, save_err = configurator.save_config(config)
      if ok then
        notify(field.label .. " updated to: " .. input)
      else
        notify("Failed to save: " .. (save_err or "unknown error"), vim.log.levels.ERROR)
      end
    end
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PATHS PICKER
-- ═══════════════════════════════════════════════════════════════════════════

function M.paths()
  local config, err = configurator.load_config()
  if err then
    config = { paths = {} }
  end
  
  local paths = config.paths or {}
  
  local fields = {
    { key = "gtd_root", label = "GTD Root", value = paths.gtd_root or "~/Documents/GTD" },
    { key = "notes_root", label = "Notes Root", value = paths.notes_root or "~/Documents/Notes" },
    { key = "archive_root", label = "Archive", value = paths.archive_root or "~/Documents/GTD/Archive" },
    { key = "templates_dir", label = "Templates", value = paths.templates_dir or "~/Documents/GTD/Templates" },
    { key = "cache_dir", label = "Cache", value = paths.cache_dir or "~/.cache/chronos" },
  }
  
  local entries = {}
  for _, field in ipairs(fields) do
    local exists = vim.fn.isdirectory(vim.fn.expand(field.value)) == 1
    local status = exists and glyphs.enabled or glyphs.warning
    table.insert(entries, string.format("%s %-12s │ %s", status, field.label, field.value))
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.path .. " Paths> ",
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          local idx = nil
          for i, entry in ipairs(entries) do
            if entry == selected[1] then
              idx = i
              break
            end
          end
          if idx and fields[idx] then
            vim.schedule(function()
              M._edit_path_field(fields[idx], config)
            end)
          end
        end
      end,
    },
    winopts = {
      height = 0.35,
      width = 0.6,
      row = 0.3,
    },
    fzf_opts = {
      ["--no-multi"] = "",
      ["--header"] = "Select path to edit (󰄳 exists, 󰀦 missing)",
    },
  })
end

function M._edit_path_field(field, config)
  -- Use file browser if available
  local has_browse = pcall(require, "fzf-lua")
  
  if has_browse then
    fzf.files({
      prompt = field.label .. "> ",
      cwd = vim.fn.expand(field.value),
      cmd = "fd --type d --max-depth 3",
      actions = {
        ["default"] = function(selected)
          if selected and #selected > 0 then
            local new_path = selected[1]
            vim.schedule(function()
              M._save_path(field, new_path, config)
            end)
          end
        end,
      },
    })
  else
    -- Fallback to input
    vim.ui.input({
      prompt = field.label .. ": ",
      default = field.value,
      completion = "dir",
    }, function(input)
      if input then
        M._save_path(field, input, config)
      end
    end)
  end
end

function M._save_path(field, new_path, config)
  config.paths = config.paths or {}
  config.paths[field.key] = new_path
  
  local ok, save_err = configurator.save_config(config)
  if ok then
    notify(field.label .. " updated to: " .. new_path)
  else
    notify("Failed to save: " .. (save_err or "unknown error"), vim.log.levels.ERROR)
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CALENDARS PICKER (Multi-select)
-- ═══════════════════════════════════════════════════════════════════════════

function M.calendars()
  if not configurator.is_bridge_available() then
    notify("chronos-bridge not running. Start it first.", vim.log.levels.WARN)
    return
  end
  
  local config, _ = configurator.load_config()
  config = config or {}
  config.integrations = config.integrations or {}
  config.integrations.calendar = config.integrations.calendar or {}
  
  local enabled_calendars = config.integrations.calendar.enabled_calendars or {}
  local enabled_set = {}
  for _, name in ipairs(enabled_calendars) do
    enabled_set[name] = true
  end
  
  -- Discover available calendars
  local calendars = configurator.discover_calendars()
  
  if #calendars == 0 then
    notify("No calendars found", vim.log.levels.WARN)
    return
  end
  
  local entries = {}
  local calendar_map = {}
  
  for _, cal in ipairs(calendars) do
    local selected = enabled_set[cal.title] or false
    local entry = format_calendar(cal, selected)
    table.insert(entries, entry)
    calendar_map[entry] = cal
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.calendar .. " Calendars> ",
    actions = {
      ["default"] = function(selected)
        if selected then
          -- Toggle selection for each selected item
          local new_enabled = {}
          local toggled = {}
          for _, sel in ipairs(selected) do
            toggled[sel] = true
          end
          
          for entry, cal in pairs(calendar_map) do
            local was_selected = enabled_set[cal.title]
            local is_toggled = toggled[entry]
            
            -- XOR: if it was toggled, flip its state
            if is_toggled then
              if not was_selected then
                table.insert(new_enabled, cal.title)
              end
            else
              if was_selected then
                table.insert(new_enabled, cal.title)
              end
            end
          end
          
          -- Save to config
          config.integrations.calendar.enabled_calendars = new_enabled
          config.integrations.calendar.enabled = #new_enabled > 0
          
          local ok, save_err = configurator.save_config(config)
          if ok then
            notify(string.format("Enabled %d calendars", #new_enabled))
          else
            notify("Failed to save: " .. (save_err or "unknown"), vim.log.levels.ERROR)
          end
        end
      end,
    },
    winopts = {
      height = 0.5,
      width = 0.6,
      row = 0.25,
    },
    fzf_opts = {
      ["--multi"] = "",
      ["--header"] = "TAB to toggle, ENTER to save selection",
    },
  })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- REMINDER LISTS PICKER (Multi-select)
-- ═══════════════════════════════════════════════════════════════════════════

function M.reminder_lists()
  if not configurator.is_bridge_available() then
    notify("chronos-bridge not running. Start it first.", vim.log.levels.WARN)
    return
  end
  
  local config, _ = configurator.load_config()
  config = config or {}
  config.integrations = config.integrations or {}
  config.integrations.reminders = config.integrations.reminders or {}
  
  local enabled_lists = config.integrations.reminders.enabled_lists or {}
  local enabled_set = {}
  for _, name in ipairs(enabled_lists) do
    enabled_set[name] = true
  end
  
  -- Discover available lists
  local lists = configurator.discover_reminder_lists()
  
  if #lists == 0 then
    notify("No reminder lists found", vim.log.levels.WARN)
    return
  end
  
  local entries = {}
  local list_map = {}
  
  for _, list in ipairs(lists) do
    local selected = enabled_set[list.title] or false
    local entry = format_reminder_list(list, selected)
    table.insert(entries, entry)
    list_map[entry] = list
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.reminder .. " Reminder Lists> ",
    actions = {
      ["default"] = function(selected)
        if selected then
          local new_enabled = {}
          local toggled = {}
          for _, sel in ipairs(selected) do
            toggled[sel] = true
          end
          
          for entry, list in pairs(list_map) do
            local was_selected = enabled_set[list.title]
            local is_toggled = toggled[entry]
            
            if is_toggled then
              if not was_selected then
                table.insert(new_enabled, list.title)
              end
            else
              if was_selected then
                table.insert(new_enabled, list.title)
              end
            end
          end
          
          config.integrations.reminders.enabled_lists = new_enabled
          config.integrations.reminders.enabled = #new_enabled > 0
          
          local ok, save_err = configurator.save_config(config)
          if ok then
            notify(string.format("Enabled %d reminder lists", #new_enabled))
          else
            notify("Failed to save: " .. (save_err or "unknown"), vim.log.levels.ERROR)
          end
        end
      end,
    },
    winopts = {
      height = 0.5,
      width = 0.5,
      row = 0.25,
    },
    fzf_opts = {
      ["--multi"] = "",
      ["--header"] = "TAB to toggle, ENTER to save selection",
    },
  })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAILBOXES PICKER (Unified view with account grouping)
-- ═══════════════════════════════════════════════════════════════════════════

-- Mail-specific glyphs
local mail_glyphs = {
  inbox = "󰇰",
  sent = "󰑋",
  drafts = "󰷈",
  trash = "󰩹",
  junk = "󰿝",
  archive = "󰀼",
  folder = "󰉋",
  account = "󰏿",
  unread = "󰇮",
  all_mail = "󰻩",
}

--- Get icon for mailbox based on name
local function get_mailbox_icon(name)
  local lower = name:lower()
  if lower == "inbox" then return mail_glyphs.inbox
  elseif lower:match("sent") then return mail_glyphs.sent
  elseif lower:match("draft") then return mail_glyphs.drafts
  elseif lower:match("trash") or lower:match("deleted") then return mail_glyphs.trash
  elseif lower:match("junk") or lower:match("spam") then return mail_glyphs.junk
  elseif lower:match("archive") then return mail_glyphs.archive
  elseif lower:match("all mail") then return mail_glyphs.all_mail
  else return mail_glyphs.folder
  end
end

--- Extract account email from URL path if possible
local function extract_account_hint(mailboxes)
  -- Try to find INBOX to extract account hint from URL structure
  for _, mb in ipairs(mailboxes) do
    if mb.name == "INBOX" and mb.url then
      -- URL like: imap://UUID/INBOX - not much help
      -- But we can use total counts to differentiate
      local total = 0
      for _, m in ipairs(mailboxes) do
        total = total + (m.total_count or 0)
      end
      return string.format("%d msgs", total)
    end
  end
  return nil
end

--- Get total unread for an account
local function get_account_unread(mailboxes)
  local unread = 0
  for _, mb in ipairs(mailboxes) do
    unread = unread + (mb.unread_count or 0)
  end
  return unread
end

--- Format mailbox for unified display
---@param mb table Mailbox info
---@param account_idx number Account index
---@param selected boolean Whether currently selected  
---@param show_path boolean Whether to show folder path
---@return string
local function format_mailbox_unified(mb, account_idx, selected, show_path)
  local check = selected and glyphs.check or glyphs.uncheck
  local icon = get_mailbox_icon(mb.name)
  local unread = ""
  if mb.unread_count and mb.unread_count > 0 then
    unread = string.format(" 󰇮 %d", mb.unread_count)
  end
  
  local path = ""
  if show_path and mb.url then
    -- Extract path from URL: imap://UUID/path/to/folder -> path/to/folder
    local folder_path = mb.url:match("/[^/]+/(.+)$")
    if folder_path and folder_path ~= mb.name then
      folder_path = vim.fn.substitute(folder_path, "%%20", " ", "g")  -- URL decode
      path = string.format(" │ %s", folder_path)
    end
  end
  
  return string.format("%s %s %s%s%s", check, icon, mb.name, unread, path)
end

function M.mailboxes()
  if not configurator.is_bridge_available() then
    notify("chronos-bridge not running. Start it first.", vim.log.levels.WARN)
    return
  end
  
  local accounts = configurator.discover_mailboxes()
  
  if #accounts == 0 then
    notify("No mail accounts found", vim.log.levels.WARN)
    return
  end
  
  -- Load current config to check enabled state
  local config, _ = configurator.load_config()
  config = config or {}
  config.integrations = config.integrations or {}
  config.integrations.mail = config.integrations.mail or {}
  config.integrations.mail.accounts = config.integrations.mail.accounts or {}
  
  -- Build enabled set per account
  local enabled_per_account = {}
  for _, acc in ipairs(config.integrations.mail.accounts) do
    enabled_per_account[acc.name] = {}
    for _, mb_name in ipairs(acc.enabled_mailboxes or {}) do
      enabled_per_account[acc.name][mb_name] = true
    end
  end
  
  -- Sort accounts by unread count (most active first)
  table.sort(accounts, function(a, b)
    return get_account_unread(a.mailboxes) > get_account_unread(b.mailboxes)
  end)
  
  -- Build unified entry list with account headers
  local entries = {}
  local entry_data = {}  -- Maps entry string to {account, mailbox} or {account_header=true}
  
  for acc_idx, account in ipairs(accounts) do
    local unread = get_account_unread(account.mailboxes)
    local hint = extract_account_hint(account.mailboxes)
    local acc_enabled_set = enabled_per_account[account.name] or {}
    
    -- Account header (short UUID + hint)
    local acc_display = account.name:sub(1, 8) .. "..."
    if hint then
      acc_display = acc_display .. " (" .. hint .. ")"
    end
    local unread_str = unread > 0 and string.format(" 󰇮 %d unread", unread) or ""
    local header = string.format("─── %s %s%s ───", mail_glyphs.account, acc_display, unread_str)
    table.insert(entries, header)
    entry_data[header] = { account_header = true, account = account }
    
    -- Sort mailboxes: INBOX first, then by unread, then alphabetically
    local sorted_mbs = vim.deepcopy(account.mailboxes)
    table.sort(sorted_mbs, function(a, b)
      -- INBOX always first
      if a.name == "INBOX" then return true end
      if b.name == "INBOX" then return false end
      -- Important folders next
      local important = { Sent = 1, Drafts = 2, Archive = 3, Trash = 4, Junk = 5 }
      local a_imp = important[a.name] or 99
      local b_imp = important[b.name] or 99
      if a_imp ~= b_imp then return a_imp < b_imp end
      -- Then by unread count
      local a_unread = a.unread_count or 0
      local b_unread = b.unread_count or 0
      if a_unread ~= b_unread then return a_unread > b_unread end
      -- Finally alphabetically
      return a.name < b.name
    end)
    
    -- Add mailboxes with indentation
    for _, mb in ipairs(sorted_mbs) do
      local selected = acc_enabled_set[mb.name] or false
      local show_path = mb.url and mb.url:match("/[^/]+/.+/")  -- Has nested path
      local entry = "  " .. format_mailbox_unified(mb, acc_idx, selected, show_path)
      table.insert(entries, entry)
      entry_data[entry] = { account = account, mailbox = mb }
    end
    
    -- Add spacer between accounts
    if acc_idx < #accounts then
      table.insert(entries, "")
      entry_data[""] = { spacer = true }
    end
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.mail .. " Mailboxes> ",
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then return end
        
        -- Process selections
        local changes = {}  -- account_name -> { added = {}, removed = {} }
        
        for _, sel in ipairs(selected) do
          local data = entry_data[sel]
          if data and data.mailbox then
            local acc_name = data.account.name
            changes[acc_name] = changes[acc_name] or { added = {}, removed = {} }
            
            local was_enabled = enabled_per_account[acc_name] and enabled_per_account[acc_name][data.mailbox.name]
            if was_enabled then
              table.insert(changes[acc_name].removed, data.mailbox.name)
            else
              table.insert(changes[acc_name].added, data.mailbox.name)
            end
          end
        end
        
        -- Apply changes to config
        local total_enabled = 0
        for acc_name, change in pairs(changes) do
          -- Get current enabled list for this account
          local current_enabled = {}
          for i, acc in ipairs(config.integrations.mail.accounts) do
            if acc.name == acc_name then
              current_enabled = vim.deepcopy(acc.enabled_mailboxes or {})
              break
            end
          end
          
          -- Apply adds
          for _, name in ipairs(change.added) do
            if not vim.tbl_contains(current_enabled, name) then
              table.insert(current_enabled, name)
            end
          end
          
          -- Apply removes
          for _, name in ipairs(change.removed) do
            for i, existing in ipairs(current_enabled) do
              if existing == name then
                table.remove(current_enabled, i)
                break
              end
            end
          end
          
          -- Update config
          local found = false
          for i, acc in ipairs(config.integrations.mail.accounts) do
            if acc.name == acc_name then
              config.integrations.mail.accounts[i].enabled_mailboxes = current_enabled
              config.integrations.mail.accounts[i].enabled = #current_enabled > 0
              found = true
              break
            end
          end
          
          if not found then
            table.insert(config.integrations.mail.accounts, {
              name = acc_name,
              enabled = #current_enabled > 0,
              enabled_mailboxes = current_enabled,
            })
          end
          
          total_enabled = total_enabled + #current_enabled
        end
        
        -- Update mail enabled status
        config.integrations.mail.enabled = total_enabled > 0
        
        -- Save
        local ok, save_err = configurator.save_config(config)
        if ok then
          local adds = 0
          local removes = 0
          for _, change in pairs(changes) do
            adds = adds + #change.added
            removes = removes + #change.removed
          end
          notify(string.format("Mailboxes updated: +%d enabled, -%d disabled", adds, removes))
        else
          notify("Failed to save: " .. (save_err or "unknown"), vim.log.levels.ERROR)
        end
      end,
    },
    winopts = {
      height = 0.7,
      width = 0.7,
      row = 0.15,
    },
    fzf_opts = {
      ["--multi"] = "",
      ["--header"] = "TAB: toggle mailbox │ ENTER: save │ Sorted by unread",
      ["--no-sort"] = "",  -- Keep our custom sort order
    },
  })
end

-- Keep the old per-account function for direct access if needed
function M._select_mailboxes_for_account(account)
  -- Redirect to unified view
  M.mailboxes()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIL ACCOUNTS PICKER (Inbox Zero tracking)
-- ═══════════════════════════════════════════════════════════════════════════

--- Format mail account for display
---@param acc table Account info {id, name, inbox_unread, total_unread, mailbox_count}
---@param selected boolean Whether currently enabled
---@return string
local function format_mail_account(acc, selected)
  local check = selected and glyphs.check or glyphs.uncheck
  local inbox_status = acc.inbox_unread == 0 and "✅" or "📬"
  local stats = string.format("%d/%d", acc.inbox_unread, acc.total_unread)
  return string.format("%s %s %-25s %s", check, inbox_status, acc.name, stats)
end

function M.mail_accounts()
  if not configurator.is_bridge_available() then
    notify("chronos-bridge not running. Start it first.", vim.log.levels.WARN)
    return
  end
  
  local config, _ = configurator.load_config()
  config = config or {}
  config.integrations = config.integrations or {}
  config.integrations.mail = config.integrations.mail or {}
  config.integrations.mail.accounts = config.integrations.mail.accounts or {}
  
  -- Build enabled set
  local enabled_set = {}
  for _, acc in ipairs(config.integrations.mail.accounts) do
    if acc.enabled then
      enabled_set[acc.name] = true
    end
  end
  
  -- Discover available accounts
  local accounts = configurator.discover_mail_accounts()
  
  if #accounts == 0 then
    notify("No mail accounts found", vim.log.levels.WARN)
    return
  end
  
  local entries = {}
  local account_map = {}
  
  -- Sort by inbox unread (highest first)
  table.sort(accounts, function(a, b)
    return (a.inbox_unread or 0) > (b.inbox_unread or 0)
  end)
  
  for _, acc in ipairs(accounts) do
    local selected = enabled_set[acc.name] or false
    local entry = format_mail_account(acc, selected)
    table.insert(entries, entry)
    account_map[entry] = acc
  end
  
  -- Add summary header
  local total_inbox = 0
  local total_all = 0
  for _, acc in ipairs(accounts) do
    total_inbox = total_inbox + (acc.inbox_unread or 0)
    total_all = total_all + (acc.total_unread or 0)
  end
  local header = string.format("Inbox Zero Status: %d/%d │ TAB: toggle, ENTER: save", total_inbox, total_all)
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.mail .. " Mail Accounts> ",
    actions = {
      ["default"] = function(selected)
        if selected then
          local new_accounts = {}
          local toggled = {}
          for _, sel in ipairs(selected) do
            toggled[sel] = true
          end
          
          for entry, acc in pairs(account_map) do
            local was_enabled = enabled_set[acc.name]
            local is_toggled = toggled[entry]
            
            local new_enabled
            if is_toggled then
              new_enabled = not was_enabled
            else
              new_enabled = was_enabled
            end
            
            table.insert(new_accounts, {
              name = acc.name,
              enabled = new_enabled,
              inbox_zero = true,  -- Track for Inbox Zero by default
            })
          end
          
          -- Save to config
          config.integrations.mail.accounts = new_accounts
          config.integrations.mail.enabled = true
          
          local ok, save_err = configurator.save_config(config)
          if ok then
            local enabled_count = 0
            for _, acc in ipairs(new_accounts) do
              if acc.enabled then enabled_count = enabled_count + 1 end
            end
            notify(string.format("Enabled %d mail accounts for Inbox Zero tracking", enabled_count))
          else
            notify("Failed to save: " .. (save_err or "unknown"), vim.log.levels.ERROR)
          end
        end
      end,
    },
    winopts = {
      height = 0.4,
      width = 0.6,
      row = 0.3,
    },
    fzf_opts = {
      ["--multi"] = "",
      ["--header"] = header,
      ["--no-sort"] = "",  -- Keep our custom sort order
    },
  })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MIGRATION MENU
-- ═══════════════════════════════════════════════════════════════════════════

function M.migrate_menu()
  local items = {
    { label = "Migrate GTD files", which = "gtd" },
    { label = "Migrate Notes files", which = "notes" },
  }
  
  local entries = {}
  for _, item in ipairs(items) do
    table.insert(entries, glyphs.migrate .. " " .. item.label)
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.migrate .. " Migration> ",
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          local idx = nil
          for i, entry in ipairs(entries) do
            if entry == selected[1] then
              idx = i
              break
            end
          end
          if idx and items[idx] then
            vim.schedule(function()
              M._start_migration(items[idx].which)
            end)
          end
        end
      end,
    },
    winopts = {
      height = 0.2,
      width = 0.4,
      row = 0.35,
    },
    fzf_opts = {
      ["--no-multi"] = "",
      ["--header"] = "Select what to migrate",
    },
  })
end

function M._start_migration(which)
  vim.ui.input({
    prompt = "New path for " .. which .. " files: ",
    default = vim.fn.expand("~/Documents/" .. which:upper()),
    completion = "dir",
  }, function(new_path)
    if new_path and new_path ~= "" then
      -- Call chronos CLI for migration
      local cmd = string.format("chronos config migrate %s %s --dry-run", which, vim.fn.shellescape(new_path))
      
      vim.notify("Running: " .. cmd, vim.log.levels.INFO)
      
      local output = vim.fn.system(cmd)
      
      -- Show output in a floating window
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, "\n"))
      vim.api.nvim_buf_set_option(buf, "modifiable", false)
      
      local width = math.min(80, vim.o.columns - 4)
      local height = math.min(20, vim.o.lines - 4)
      
      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = (vim.o.lines - height) / 2,
        col = (vim.o.columns - width) / 2,
        style = "minimal",
        border = "rounded",
        title = " Migration Plan ",
        title_pos = "center",
      })
      
      -- Keymaps for the preview window
      vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
      vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })
      vim.api.nvim_buf_set_keymap(buf, "n", "y", "", {
        noremap = true,
        silent = true,
        callback = function()
          vim.api.nvim_win_close(win, true)
          vim.schedule(function()
            M._confirm_migration(which, new_path)
          end)
        end,
      })
    end
  end)
end

function M._confirm_migration(which, new_path)
  vim.ui.select({ "Yes, proceed with migration", "No, cancel" }, {
    prompt = "Execute migration?",
  }, function(choice)
    if choice and choice:match("^Yes") then
      local cmd = string.format("chronos config migrate %s %s", which, vim.fn.shellescape(new_path))
      
      vim.notify("Migrating " .. which .. " files...", vim.log.levels.INFO)
      
      local output = vim.fn.system(cmd)
      
      if vim.v.shell_error == 0 then
        vim.notify("Migration complete!", vim.log.levels.INFO)
      else
        vim.notify("Migration failed:\n" .. output, vim.log.levels.ERROR)
      end
    end
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MODULE INFO
-- ═══════════════════════════════════════════════════════════════════════════

function M.version()
  return FileVersion
end

return M
