-- GTD Status Module
-- Change org-mode TODO status on the heading under cursor.
-- Uses centralized fzf utilities for consistent UI

local M = {}

-- Load centralized fzf utilities
local fzf_utils = require("gtd-nvim.gtd.fzf")

-- All available statuses with metadata
local STATUSES = {
  { state = "NEXT",    icon = fzf_utils.icons.NEXT,    desc = "Next physical action to take" },
  { state = "TODO",    icon = fzf_utils.icons.TODO,    desc = "Task to be done" },
  { state = "WAITING", icon = fzf_utils.icons.WAITING, desc = "Waiting for someone/something" },
  { state = "SOMEDAY", icon = fzf_utils.icons.SOMEDAY, desc = "Maybe/someday" },
  { state = "DONE",    icon = fzf_utils.icons.DONE,    desc = "Completed" },
}

local ALL_STATUS_NAMES = { "NEXT", "TODO", "WAITING", "SOMEDAY", "DONE" }

-- ============================================================================
-- Helpers
-- ============================================================================

local function is_status(word)
  for _, s in ipairs(ALL_STATUS_NAMES) do
    if word == s then return true end
  end
  return false
end

local function detect_status(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

  -- Try word under cursor
  local cword = vim.fn.expand("<cword>")
  if cword ~= "" and is_status(cword) then
    return cword, line
  end

  -- Try matching standard org heading: "* TODO Something"
  local prefix, status, rest = line:match("^(%s*%*+%s+)(%u+)(.*)$")
  if prefix and status and is_status(status) then
    return status, line
  end

  return nil, line
end

local function replace_status(bufnr, row, old_status, new_status)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

  local prefix, status, rest = line:match("^(%s*%*+%s+)(%u+)(.*)$")
  if prefix and status and status == old_status then
    local new_line = prefix .. new_status .. rest
    vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_line })
    return true
  end

  -- Fallback: conservative single substitution
  local changed, n = line:gsub(old_status, new_status, 1)
  if n > 0 then
    vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { changed })
    return true
  end

  return false
end

local function get_status_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local row = pos[1] - 1
  local col = pos[2]

  local current_status, line = detect_status(bufnr, row, col)
  if not current_status then
    fzf_utils.notify("No org status found on this line", "WARN")
    return nil
  end

  -- Build choices excluding current status
  local choices = {}
  for _, s in ipairs(STATUSES) do
    if s.state ~= current_status then
      table.insert(choices, s)
    end
  end

  if #choices == 0 then
    fzf_utils.notify("No alternative statuses", "INFO")
    return nil
  end

  return {
    bufnr = bufnr,
    row = row,
    col = col,
    line = line,
    current_status = current_status,
    choices = choices,
  }
end

-- ============================================================================
-- Main Status Change Function
-- ============================================================================

--- Change status using fzf-lua (with vim.ui.select fallback)
function M.change_status()
  local ctx = get_status_context()
  if not ctx then return end

  if not fzf_utils.available() then
    -- Fallback to vim.ui.select
    local names = {}
    for _, s in ipairs(ctx.choices) do
      table.insert(names, s.state)
    end
    
    vim.ui.select(names, {
      prompt = ("Status (%s → ?)"):format(ctx.current_status),
    }, function(choice)
      if not choice then return end
      if replace_status(ctx.bufnr, ctx.row, ctx.current_status, choice) then
        fzf_utils.notify(ctx.current_status .. " → " .. choice, "INFO")
      end
    end)
    return
  end

  -- Build display items with icons and descriptions
  local display = {}
  local meta = {}
  for _, s in ipairs(ctx.choices) do
    local line = string.format("%s  %-8s  %s", s.icon, s.state, s.desc)
    table.insert(display, line)
    table.insert(meta, s.state)
  end

  local fzf = require("fzf-lua")
  fzf.fzf_exec(display, {
    prompt = string.format("Status (%s → ?)> ", ctx.current_status),
    fzf_opts = vim.tbl_extend("force", fzf_utils.fzf_opts.single, {
      ["--header"] = string.format("Current: %s %s │ Enter: Change │ Esc: Cancel",
        fzf_utils.icons[ctx.current_status] or "•", ctx.current_status),
    }),
    winopts = fzf_utils.winopts.small,
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local new_status = meta[idx]
        if new_status then
          if replace_status(ctx.bufnr, ctx.row, ctx.current_status, new_status) then
            fzf_utils.notify(string.format("%s %s → %s %s",
              fzf_utils.icons[ctx.current_status] or "", ctx.current_status,
              fzf_utils.icons[new_status] or "", new_status
            ), "INFO")
          else
            fzf_utils.notify("Failed to change status", "ERROR")
          end
        end
      end,
    },
  })
end

--- Change status with fzf (explicit function name for backward compat)
function M.change_status_fzf()
  return M.change_status()
end

--- Cycle to next status (for quick keybinding)
---@param direction number 1 for forward, -1 for backward
function M.cycle_status(direction)
  direction = direction or 1
  local ctx = get_status_context()
  if not ctx then return end
  
  -- Find current index
  local current_idx = nil
  for i, name in ipairs(ALL_STATUS_NAMES) do
    if name == ctx.current_status then
      current_idx = i
      break
    end
  end
  
  if not current_idx then return end
  
  -- Calculate next index (wrap around)
  local next_idx = current_idx + direction
  if next_idx < 1 then next_idx = #ALL_STATUS_NAMES end
  if next_idx > #ALL_STATUS_NAMES then next_idx = 1 end
  
  local new_status = ALL_STATUS_NAMES[next_idx]
  if replace_status(ctx.bufnr, ctx.row, ctx.current_status, new_status) then
    fzf_utils.notify(string.format("%s → %s", ctx.current_status, new_status), "INFO")
  end
end

--- Set status directly (for programmatic use)
---@param new_status string The status to set
function M.set_status(new_status)
  if not is_status(new_status) then
    fzf_utils.notify("Invalid status: " .. tostring(new_status), "ERROR")
    return false
  end
  
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local current_status, _ = detect_status(bufnr, row, 0)
  
  if not current_status then
    fzf_utils.notify("No org heading found", "WARN")
    return false
  end
  
  if current_status == new_status then
    fzf_utils.notify("Already " .. new_status, "INFO")
    return true
  end
  
  return replace_status(bufnr, row, current_status, new_status)
end

return M
