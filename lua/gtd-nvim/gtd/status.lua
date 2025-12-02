-- ~/.config/nvim/lua/gtd/status.lua
-- Change org-mode TODO status on the heading under cursor.
-- Statuses: DONE, TODO, NEXT, WAITING, SOMEDAY
-- Excludes the current status from the selection list.

local M = {}

-- All available statuses (order as you like)
local ALL_STATUSES = { "TODO", "NEXT", "WAITING", "SOMEDAY", "DONE" }

-- Simple membership check
local function is_status(word)
  for _, s in ipairs(ALL_STATUSES) do
    if word == s then
      return true
    end
  end
  return false
end

-- Find current status on the line, preferring the word under cursor if valid.
local function detect_status(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

  -- 1) Try word under cursor
  local cword = vim.fn.expand("<cword>")
  if cword ~= "" and is_status(cword) then
    return cword, line
  end

  -- 2) Try matching standard org heading: "* TODO Something"
  --    Capture: stars + space, STATUS, rest
  local prefix, status, rest = line:match("^(%s*%*+%s+)(%u+)(.*)$")
  if prefix and status and is_status(status) then
    return status, line
  end

  return nil, line
end

-- Replace the existing status with a new one on a heading line.
local function replace_status(bufnr, row, old_status, new_status)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

  -- Pattern: front-of-line org heading with STATUS
  -- We preserve everything except the status word itself.
  local prefix, status, rest = line:match("^(%s*%*+%s+)(%u+)(.*)$")
  if prefix and status and status == old_status then
    local new_line = prefix .. new_status .. rest
    vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_line })
    return true
  end

  -- Fallback: conservative single substitution of the status word.
  local changed, n = line:gsub(old_status, new_status, 1)
  if n > 0 then
    vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { changed })
    return true
  end

  return false
end

-- Shared helper: get current status + alternative choices
local function get_status_and_choices()
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0) -- {row, col}
  local row = pos[1] - 1       -- 0-based
  local col = pos[2]           -- 0-based

  local current_status, _ = detect_status(bufnr, row, col)
  if not current_status then
    vim.notify("No org status found on this line", vim.log.levels.WARN, { title = "GTD Status" })
    return nil
  end

  -- Build list excluding the current status
  local choices = {}
  for _, s in ipairs(ALL_STATUSES) do
    if s ~= current_status then
      table.insert(choices, s)
    end
  end

  if #choices == 0 then
    vim.notify("No alternative statuses to choose from", vim.log.levels.INFO, { title = "GTD Status" })
    return nil
  end

  return {
    bufnr = bufnr,
    row = row,
    col = col,
    current_status = current_status,
    choices = choices,
  }
end

----------------------------------------------------------------------
-- UI 1: vim.ui.select (default)
----------------------------------------------------------------------

function M.change_status()
  local ctx = get_status_and_choices()
  if not ctx then
    return
  end

  vim.ui.select(ctx.choices, {
    prompt = ("Change status (%s → ?)"):format(ctx.current_status),
  }, function(choice)
    if not choice then
      return
    end
    local ok = replace_status(ctx.bufnr, ctx.row, ctx.current_status, choice)
    if not ok then
      vim.notify("Failed to change status", vim.log.levels.ERROR, { title = "GTD Status" })
    end
  end)
end

----------------------------------------------------------------------
-- UI 2: fzf-lua selector
----------------------------------------------------------------------

function M.change_status_fzf()
  local ok_fzf, fzf = pcall(require, "fzf-lua")
  if not ok_fzf then
    vim.notify("fzf-lua not available, falling back to vim.ui.select", vim.log.levels.WARN, {
      title = "GTD Status",
    })
    return M.change_status()
  end

  local ctx = get_status_and_choices()
  if not ctx then
    return
  end

  fzf.fzf_exec(ctx.choices, {
    prompt = ("Status (%s -> ?) > "):format(ctx.current_status),
    actions = {
      -- Default action: first selected line
      ["default"] = function(selected)
        local choice = selected and selected[1]
        if not choice or choice == "" then
          return
        end
        local ok = replace_status(ctx.bufnr, ctx.row, ctx.current_status, choice)
        if not ok then
          vim.notify("Failed to change status", vim.log.levels.ERROR, { title = "GTD Status" })
        end
      end,
    },
  })
end

return M