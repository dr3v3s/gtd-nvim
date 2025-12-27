-- gtd-nvim/configurator/backup.lua
-- Backup and Snapshot Management UI
--
-- File:    lua/gtd-nvim/configurator/backup.lua
-- Version: 0.10.3
-- Updated: 2025-12-23
--
-- Provides UI for backup/restore operations:
-- - Create snapshots with description
-- - List and browse backups
-- - Restore from backups (full or selective)
-- - Manage old backups

local M = {}

local FileVersion = "0.10.3"

-- Chronos CLI path (symlink or direct)
local CHRONOS_CLI = vim.fn.expand("$HOME/.local/bin/chronos")
if vim.fn.executable(CHRONOS_CLI) ~= 1 then
  CHRONOS_CLI = vim.fn.expand("$HOME/Developer/chronos/bin/chronos")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DEPENDENCIES
-- ═══════════════════════════════════════════════════════════════════════════

local fzf_ok, fzf = pcall(require, "fzf-lua")
if not fzf_ok then
  vim.notify("[backup] fzf-lua not found", vim.log.levels.ERROR)
  return M
end

-- ═══════════════════════════════════════════════════════════════════════════
-- GLYPHS
-- ═══════════════════════════════════════════════════════════════════════════

local glyphs = {
  backup = "󰁯",
  restore = "󰦛",
  create = "󰐕",
  delete = "󰆴",
  list = "󰋊",
  check = "󰄬",
  warning = "󰀦",
  folder = "󰉋",
  file = "󰈙",
  clock = "󰅐",
  size = "󰋊",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function notify(msg, level)
  vim.notify("[backup] " .. msg, level or vim.log.levels.INFO)
end

--- Run chronos backup command and return output
---@param args string Command arguments
---@return string output
---@return boolean success
local function run_backup_cmd(args)
  local cmd = CHRONOS_CLI .. " backup " .. args .. " 2>&1"
  local output = vim.fn.system(cmd)
  local success = vim.v.shell_error == 0
  return output, success
end

--- Parse backup list output into structured data
---@param output string Raw command output
---@return table[] backups
local function parse_backup_list(output)
  local backups = {}
  local current = nil
  
  for line in output:gmatch("[^\r\n]+") do
    -- Match backup filename line: "  1. chronos-snapshot-20251222-214147.tar.gz"
    local num, filename = line:match("^%s*(%d+)%.%s+(.+%.tar%.gz)$")
    if num and filename then
      current = {
        num = tonumber(num),
        filename = filename,
        size = "",
        created = "",
        age = "",
        description = "",
      }
      table.insert(backups, current)
    elseif current then
      -- Match size/created line: "     Size: 293.3 KB  Created: 2025-12-22 21:41 (0 minutes ago)"
      local size, created, age = line:match("Size:%s*([%d%.]+%s*%w+)%s+Created:%s*([%d%-]+%s+[%d:]+)%s+%((.-)%)")
      if size then
        current.size = size
        current.created = created
        current.age = age
      end
      
      -- Match description line: "     Note: Test backup"
      local desc = line:match("Note:%s*(.+)$")
      if desc then
        current.description = desc
      end
    end
  end
  
  return backups
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the backup menu
function M.menu()
  local items = {
    { icon = glyphs.create, label = "Create Backup", desc = "Create a new snapshot", action = M.create },
    { icon = glyphs.list, label = "List Backups", desc = "Browse existing backups", action = M.list },
    { icon = glyphs.restore, label = "Restore Latest", desc = "Restore from latest backup", action = M.restore_latest },
    { icon = glyphs.delete, label = "Clean Old", desc = "Remove old backups", action = M.clean },
    { icon = glyphs.folder, label = "Open Directory", desc = "Open backup folder", action = M.open_dir },
  }
  
  local entries = {}
  for _, item in ipairs(items) do
    table.insert(entries, string.format("%s %s │ %s", item.icon, item.label, item.desc))
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.backup .. " Backup> ",
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          for i, entry in ipairs(entries) do
            if entry == selected[1] and items[i] and items[i].action then
              vim.schedule(items[i].action)
              break
            end
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
      ["--header"] = "Select backup action",
    },
  })
end

--- Create a new backup with optional description
function M.create()
  vim.ui.input({
    prompt = "Backup description (optional): ",
    default = "",
  }, function(description)
    if description == nil then
      return -- Cancelled
    end
    
    notify("Creating backup...", vim.log.levels.INFO)
    
    local args = "create"
    if description and description ~= "" then
      args = args .. " " .. vim.fn.shellescape(description)
    end
    
    -- Run in background
    vim.fn.jobstart(CHRONOS_CLI .. " backup " .. args, {
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            notify("Backup created successfully!", vim.log.levels.INFO)
          else
            notify("Backup failed!", vim.log.levels.ERROR)
          end
        end)
      end,
      on_stdout = function(_, data)
        -- Show progress in messages
        for _, line in ipairs(data) do
          if line and line ~= "" and line:match("󰄳") then
            vim.schedule(function()
              notify(line)
            end)
          end
        end
      end,
    })
  end)
end

--- List all backups in fzf picker
function M.list()
  local output, success = run_backup_cmd("list")
  
  if not success then
    notify("Failed to list backups", vim.log.levels.ERROR)
    return
  end
  
  local backups = parse_backup_list(output)
  
  if #backups == 0 then
    notify("No backups found. Create one with :lua require('gtd-nvim.configurator.backup').create()")
    return
  end
  
  local entries = {}
  local backup_map = {}
  
  for _, b in ipairs(backups) do
    local entry = string.format("%s %s │ %s │ %s",
      glyphs.backup,
      b.filename,
      b.size,
      b.age .. " ago")
    if b.description ~= "" then
      entry = entry .. " │ " .. b.description
    end
    table.insert(entries, entry)
    backup_map[entry] = b
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.list .. " Backups> ",
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          -- Single selection: show actions
          if #selected == 1 then
            local backup = backup_map[selected[1]]
            if backup then
              vim.schedule(function()
                M.show_backup_actions(backup)
              end)
            end
          else
            -- Multi-selection: show count
            vim.schedule(function()
              notify(string.format("%d backups selected. Use ctrl-d to delete.", #selected))
            end)
          end
        end
      end,
      ["ctrl-d"] = function(selected)
        if selected and #selected > 0 then
          local to_delete = {}
          for _, entry in ipairs(selected) do
            local backup = backup_map[entry]
            if backup then
              table.insert(to_delete, backup)
            end
          end
          vim.schedule(function()
            M.delete_multiple(to_delete)
          end)
        end
      end,
      ["ctrl-i"] = function(selected)
        if selected and #selected > 0 then
          local backup = backup_map[selected[1]]
          if backup then
            vim.schedule(function()
              M.show_details(backup)
            end)
          end
        end
      end,
      ["ctrl-b"] = function(_)
        vim.schedule(function()
          M.menu()
        end)
      end,
    },
    winopts = {
      height = 0.5,
      width = 0.7,
      row = 0.25,
    },
    fzf_opts = {
      ["--multi"] = "",
      ["--header"] = "enter=actions │ tab=select │ ctrl-i=info │ ctrl-d=delete │ ctrl-b=back",
    },
  })
end

--- Show actions for a specific backup
---@param backup table Backup info
function M.show_backup_actions(backup)
  local items = {
    { label = "Show Details", action = function() M.show_details(backup) end },
    { label = "Restore All", action = function() M.restore(backup, nil) end },
    { label = "Restore GTD Only", action = function() M.restore(backup, "gtd") end },
    { label = "Restore Notes Only", action = function() M.restore(backup, "notes") end },
    { label = "Restore Config Only", action = function() M.restore(backup, "config") end },
    { label = "Delete Backup", action = function() M.delete(backup) end },
  }
  
  local entries = {}
  for _, item in ipairs(items) do
    table.insert(entries, item.label)
  end
  
  fzf.fzf_exec(entries, {
    prompt = glyphs.backup .. " " .. backup.filename .. "> ",
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          for _, item in ipairs(items) do
            if item.label == selected[1] then
              vim.schedule(item.action)
              break
            end
          end
        end
      end,
      ["ctrl-b"] = function(_)
        vim.schedule(function()
          M.list()
        end)
      end,
    },
    winopts = {
      height = 0.3,
      width = 0.4,
      row = 0.35,
    },
    fzf_opts = {
      ["--no-multi"] = "",
      ["--header"] = "enter=select │ ctrl-b=back to list",
    },
  })
end

--- Show backup details in floating window
---@param backup table Backup info
function M.show_details(backup)
  local output, _ = run_backup_cmd("show " .. vim.fn.shellescape(backup.filename))
  
  local lines = vim.split(output, "\n")
  -- Add help line at the bottom
  table.insert(lines, "")
  table.insert(lines, "───────────────────────────────────────────────────")
  table.insert(lines, "Press: q/Esc=close │ b=back to list │ r=restore menu")
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
    title = " " .. glyphs.backup .. " " .. backup.filename .. " ",
    title_pos = "center",
  })
  
  -- Keymaps
  local opts = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("n", "q", "<cmd>close<CR>", opts)
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", opts)
  vim.keymap.set("n", "b", function()
    vim.cmd("close")
    M.list()
  end, opts)
  vim.keymap.set("n", "r", function()
    vim.cmd("close")
    M.show_backup_actions(backup)
  end, opts)
end

--- Restore from a backup
---@param backup table Backup info
---@param target string|nil Target component (gtd, notes, config, cache) or nil for all
function M.restore(backup, target)
  local msg = "Restore "
  if target then
    msg = msg .. target .. " from " .. backup.filename .. "?"
  else
    msg = msg .. "ALL from " .. backup.filename .. "?"
  end
  
  vim.ui.select({ "Yes, restore", "No, cancel" }, {
    prompt = msg,
  }, function(choice)
    if not choice or not choice:match("^Yes") then
      notify("Restore cancelled")
      return
    end
    
    notify("Restoring from backup...", vim.log.levels.INFO)
    
    local args = "restore " .. vim.fn.shellescape(backup.filename) .. " --force"
    if target then
      args = args .. " --target " .. target
    end
    
    vim.fn.jobstart(CHRONOS_CLI .. " backup " .. args, {
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            notify("Restore completed successfully!", vim.log.levels.INFO)
          else
            notify("Restore failed!", vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end)
end

--- Restore from latest backup
function M.restore_latest()
  local output, success = run_backup_cmd("list")
  
  if not success then
    notify("Failed to list backups", vim.log.levels.ERROR)
    return
  end
  
  local backups = parse_backup_list(output)
  
  if #backups == 0 then
    notify("No backups found", vim.log.levels.WARN)
    return
  end
  
  M.show_backup_actions(backups[1])
end

--- Delete a backup
---@param backup table Backup info
function M.delete(backup)
  vim.ui.select({ "Yes, delete", "No, keep" }, {
    prompt = "Delete " .. backup.filename .. "? This cannot be undone.",
  }, function(choice)
    if not choice or not choice:match("^Yes") then
      return
    end
    
    local _, success = run_backup_cmd("delete " .. vim.fn.shellescape(backup.filename) .. " --force")
    
    if success then
      notify("Backup deleted")
    else
      notify("Failed to delete backup", vim.log.levels.ERROR)
    end
  end)
end

--- Delete multiple backups with confirmation
---@param backups table[] List of backup info tables
function M.delete_multiple(backups)
  if not backups or #backups == 0 then
    return
  end
  
  -- Build confirmation message
  local filenames = {}
  for _, b in ipairs(backups) do
    table.insert(filenames, "  • " .. b.filename)
  end
  
  local msg = string.format("Delete %d backup(s)?\n\n%s\n\nThis cannot be undone.",
    #backups,
    table.concat(filenames, "\n"))
  
  vim.ui.select({ "Yes, delete all", "No, cancel" }, {
    prompt = msg,
  }, function(choice)
    if not choice or not choice:match("^Yes") then
      notify("Deletion cancelled")
      return
    end
    
    local deleted = 0
    local failed = 0
    
    for _, backup in ipairs(backups) do
      local _, success = run_backup_cmd("delete " .. vim.fn.shellescape(backup.filename) .. " --force")
      if success then
        deleted = deleted + 1
      else
        failed = failed + 1
      end
    end
    
    if failed == 0 then
      notify(string.format("Deleted %d backup(s)", deleted))
    else
      notify(string.format("Deleted %d, failed %d", deleted, failed), vim.log.levels.WARN)
    end
  end)
end

--- Clean old backups
function M.clean()
  vim.ui.input({
    prompt = "Remove backups older than (e.g., 7d, 2w, 1m): ",
    default = "30d",
  }, function(age)
    if not age or age == "" then
      return
    end
    
    vim.ui.input({
      prompt = "Minimum backups to keep: ",
      default = "3",
    }, function(keep)
      if not keep or keep == "" then
        return
      end
      
      local args = string.format("clean --older-than %s --keep %s", age, keep)
      local output, success = run_backup_cmd(args)
      
      if success then
        notify("Cleanup complete:\n" .. output)
      else
        notify("Cleanup failed", vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Open backup directory in file manager
function M.open_dir()
  local output = vim.fn.system(CHRONOS_CLI .. " backup dir"):gsub("%s+$", "")
  
  if vim.fn.isdirectory(output) == 1 then
    vim.fn.system("open " .. vim.fn.shellescape(output))
    notify("Opened: " .. output)
  else
    notify("Backup directory not found", vim.log.levels.WARN)
  end
end

--- Quick backup (no prompts)
function M.quick()
  notify("Creating quick backup...", vim.log.levels.INFO)
  
  vim.fn.jobstart(CHRONOS_CLI .. " backup create 'Quick backup from Neovim'", {
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          notify("Quick backup created!", vim.log.levels.INFO)
        else
          notify("Quick backup failed!", vim.log.levels.ERROR)
        end
      end)
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
