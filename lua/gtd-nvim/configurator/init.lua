-- gtd-nvim/configurator/init.lua
-- Chronos Configuration UI
--
-- File:    lua/gtd-nvim/configurator/init.lua
-- Version: 0.12.0
-- Updated: 2025-12-27
--
-- Main entry point for the configuration wizard.
-- Provides fzf-lua based multi-select pickers for:
-- - Calendars
-- - Reminder lists
-- - Mailboxes
-- - File paths
-- - User identity

local M = {}

local FileVersion = "0.11.0"

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

local config_path = vim.fn.expand("~/.config/chronos/config.json")
local bridge_socket = vim.fn.expand("~/.cache/chronos/chronos-bridge.sock")

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function notify(msg, level)
  vim.notify("[configurator] " .. msg, level or vim.log.levels.INFO)
end

local function file_exists(path)
  return vim.fn.filereadable(vim.fn.expand(path)) == 1
end

local function dir_exists(path)
  return vim.fn.isdirectory(vim.fn.expand(path)) == 1
end

local function ensure_dir(path)
  local expanded = vim.fn.expand(path)
  if vim.fn.isdirectory(expanded) ~= 1 then
    vim.fn.mkdir(expanded, "p")
  end
end

--- Query chronos-bridge via socket
---@param module string Module name (calendar, reminders, mail)
---@param cmd string Command name
---@param params table|nil Optional parameters
---@return table|nil response, string|nil error
local function bridge_query(module, cmd, params)
  if not file_exists(bridge_socket) then
    return nil, "chronos-bridge not running"
  end
  
  local request = vim.fn.json_encode({
    module = module,
    cmd = cmd,
    params = params or vim.empty_dict(),
  })
  
  -- Use netcat to query socket
  local result = vim.fn.system(
    string.format("echo '%s' | nc -U %s 2>/dev/null", request, bridge_socket)
  )
  
  if vim.v.shell_error ~= 0 then
    return nil, "Failed to connect to chronos-bridge"
  end
  
  local ok, decoded = pcall(vim.fn.json_decode, result)
  if not ok then
    return nil, "Invalid JSON response"
  end
  
  -- Bridge returns {success: bool, data: {...}, ...}
  if not decoded.success then
    return nil, decoded.error or "Unknown error"
  end
  
  return decoded.data, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- JSON CONFIG HANDLING
-- ═══════════════════════════════════════════════════════════════════════════

--- Load configuration from JSON file
---@return table|nil config, string|nil error
function M.load_config()
  if not file_exists(config_path) then
    return nil, "Config file not found: " .. config_path
  end
  
  local lines = vim.fn.readfile(config_path)
  local json_content = table.concat(lines, "\n")
  
  local ok, decoded = pcall(vim.fn.json_decode, json_content)
  if ok then
    return decoded, nil
  end
  
  return nil, "Failed to parse JSON config"
end

--- Save configuration to JSON file
---@param config table Configuration table
---@return boolean success, string|nil error
function M.save_config(config)
  ensure_dir(vim.fn.fnamemodify(config_path, ":h"))
  
  -- Pretty print JSON
  local json = vim.fn.json_encode(config)
  
  -- Use jq for pretty printing if available
  local jq = vim.fn.executable("jq")
  if jq == 1 then
    local tmpfile = vim.fn.tempname()
    vim.fn.writefile({json}, tmpfile)
    local pretty = vim.fn.system("jq '.' " .. tmpfile)
    vim.fn.delete(tmpfile)
    if vim.v.shell_error == 0 then
      json = pretty
    end
  end
  
  local ok = pcall(vim.fn.writefile, vim.split(json, "\n"), config_path)
  if ok then
    return true, nil
  end
  return false, "Failed to write config file"
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DISCOVERY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

--- Discover available calendars from chronos-bridge
---@return table[] calendars Array of {id, title, color, is_default}
function M.discover_calendars()
  local data, err = bridge_query("calendar", "calendars")
  if err then
    notify("Failed to discover calendars: " .. err, vim.log.levels.WARN)
    return {}
  end
  
  return data.calendars or {}
end

--- Discover available reminder lists from chronos-bridge
---@return table[] lists Array of {id, title, is_default}
function M.discover_reminder_lists()
  local data, err = bridge_query("reminders", "lists")
  if err then
    notify("Failed to discover reminder lists: " .. err, vim.log.levels.WARN)
    return {}
  end
  
  return data.lists or {}
end

--- Discover available mailboxes from chronos-bridge
---@return table[] accounts Array of {name, mailboxes}
function M.discover_mailboxes()
  local data, err = bridge_query("mail", "mailboxes")
  if err then
    notify("Failed to discover mailboxes: " .. err, vim.log.levels.WARN)
    return {}
  end
  
  -- Group by account
  local accounts = {}
  local account_map = {}
  
  for _, mb in ipairs(data.mailboxes or {}) do
    local acc_name = mb.account or "default"
    if not account_map[acc_name] then
      account_map[acc_name] = {
        name = acc_name,
        mailboxes = {}
      }
      table.insert(accounts, account_map[acc_name])
    end
    table.insert(account_map[acc_name].mailboxes, mb)
  end
  
  return accounts
end

--- Discover mail accounts with unread stats from chronos-bridge
---@return table[] accounts Array of {id, name, inbox_unread, total_unread, mailbox_count}
function M.discover_mail_accounts()
  local data, err = bridge_query("mail", "accounts")
  if err then
    notify("Failed to discover mail accounts: " .. err, vim.log.levels.WARN)
    return {}
  end
  
  -- Filter out empty/UUID-only accounts
  local accounts = {}
  for _, acc in ipairs(data.accounts or {}) do
    local name = acc.name or ""
    -- Skip if empty or looks like a UUID
    if name ~= "" and not name:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
      table.insert(accounts, acc)
    end
  end
  
  return accounts
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the main configurator menu
function M.open()
  local pickers_mod = require("gtd-nvim.configurator.pickers")
  pickers_mod.main_menu()
end

--- Open calendar selector
function M.select_calendars()
  local pickers_mod = require("gtd-nvim.configurator.pickers")
  pickers_mod.calendars()
end

--- Open reminder lists selector
function M.select_reminders()
  local pickers_mod = require("gtd-nvim.configurator.pickers")
  pickers_mod.reminder_lists()
end

--- Open mailbox selector
function M.select_mailboxes()
  local pickers_mod = require("gtd-nvim.configurator.pickers")
  pickers_mod.mailboxes()
end

--- Open mail accounts selector (for Inbox Zero tracking)
function M.select_mail_accounts()
  local pickers_mod = require("gtd-nvim.configurator.pickers")
  pickers_mod.mail_accounts()
end

--- Open paths configuration
function M.configure_paths()
  local pickers_mod = require("gtd-nvim.configurator.pickers")
  pickers_mod.paths()
end

--- Open identity configuration
function M.configure_identity()
  local pickers_mod = require("gtd-nvim.configurator.pickers")
  pickers_mod.identity()
end

--- Run the full setup wizard
function M.wizard()
  local wizard_mod = require("gtd-nvim.configurator.wizard")
  wizard_mod.start()
end

--- Open backup menu
function M.backup()
  local backup_mod = require("gtd-nvim.configurator.backup")
  backup_mod.menu()
end

--- Quick backup (no prompts)
function M.quick_backup()
  local backup_mod = require("gtd-nvim.configurator.backup")
  backup_mod.quick()
end

--- Check if chronos-bridge is available
---@return boolean
function M.is_bridge_available()
  return file_exists(bridge_socket)
end

--- Get the config file path
---@return string
function M.get_config_path()
  return config_path
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MODULE INFO
-- ═══════════════════════════════════════════════════════════════════════════

function M.version()
  return FileVersion
end

return M
