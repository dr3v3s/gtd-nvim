-- ============================================================================
-- ZETTELKASTEN MANAGE MODULE
-- ============================================================================
-- File management: delete, archive, move, bulk operations
--
-- @module gtd-nvim.zettelkasten.manage
-- @version 2.0.0
-- @requires gtd-nvim.zettelkasten.core
-- ============================================================================

local M = {}

local core = require("gtd-nvim.zettelkasten.core")
local cfg = core.cfg
local g = core.glyphs

-- ============================================================================
-- FILE OPERATIONS
-- ============================================================================

local function try_delete_file(p)
  local rc = vim.fn.delete(p)
  if rc == 0 then return true end
  local ok_uv = pcall(function() return vim.loop.fs_unlink(p) end)
  if ok_uv then return true end
  local ok_os = os.remove(p)
  if ok_os then return true end
  return false
end

local function try_move_file(src, dst)
  pcall(vim.fn.delete, dst)
  local ok = pcall(vim.fn.rename, src, dst)
  if ok and core.file_exists(dst) and not core.file_exists(src) then return true end
  local content = vim.fn.readfile(src)
  local okw = pcall(vim.fn.writefile, content, dst)
  if okw and core.file_exists(dst) then
    local okd = try_delete_file(src)
    return okd == true
  end
  return false
end

local function confirm_yes(msg)
  return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

-- Extract paths from fzf selection
local function sel_to_paths(selected, meta)
  local out = {}
  for _, s in ipairs(selected or {}) do
    -- Strip ANSI codes for matching (fzf may return stripped version)
    local stripped = s:gsub("\27%[[0-9;]*m", "")
    
    -- Try to find in meta.items (may be colored)
    local found = false
    for i, item in ipairs(meta.items) do
      local item_stripped = item:gsub("\27%[[0-9;]*m", "")
      if item_stripped == stripped or item == s then
        local note = meta.notes[i]
        if note and note.path then
          table.insert(out, note.path)
          found = true
          break
        end
      end
    end
    
    -- Fallback: if not found, try to extract path from the string itself
    if not found then
      -- Try to match a file path pattern
      local path_match = s:match("([/%w%-_%.]+%.md)")
      if path_match then
        local full_path = core.to_abs(path_match)
        if full_path and core.file_exists(full_path) then
          table.insert(out, full_path)
        end
      end
    end
  end
  return out
end

-- ============================================================================
-- DELETE
-- ============================================================================

function M.delete_files(paths)
  if #paths == 0 then
    core.notify("Nothing to delete", vim.log.levels.WARN)
    return
  end

  if not confirm_yes(("Permanently delete %d file(s)?"):format(#paths)) then
    return
  end

  local okc, errc = 0, 0
  for _, p in ipairs(paths) do
    if core.file_exists(p) and not core.is_dir(p) then
      if try_delete_file(p) then
        okc = okc + 1
      else
        errc = errc + 1
      end
    else
      errc = errc + 1
    end
  end

  core.clear_cache()

  -- Update index
  local notes = require("gtd-nvim.zettelkasten.notes")
  notes.write_index()

  core.notify(string.format("%s Deleted %d file(s), %d failed.", core.g.container.trash, okc, errc))
end

-- ============================================================================
-- ARCHIVE
-- ============================================================================

function M.archive_files(paths)
  if #paths == 0 then
    core.notify("Nothing to archive", vim.log.levels.WARN)
    return
  end

  core.ensure_dir(cfg.archive_dir)
  local moved, failed = 0, 0

  for _, p in ipairs(paths) do
    if core.file_exists(p) and not core.is_dir(p) then
      local dst = core.join(cfg.archive_dir, vim.fn.fnamemodify(p, ":t"))
      if try_move_file(p, dst) then
        moved = moved + 1
      else
        failed = failed + 1
      end
    else
      failed = failed + 1
    end
  end

  core.clear_cache()

  local notes = require("gtd-nvim.zettelkasten.notes")
  notes.write_index()

  core.notify(string.format("%s Archived %d file(s), %d failed.", g.note.archive, moved, failed))
end

-- ============================================================================
-- MOVE
-- ============================================================================

function M.move_files(paths)
  if #paths == 0 then
    core.notify("Nothing to move", vim.log.levels.WARN)
    return
  end

  local dest = vim.fn.input("Move to dir: ", cfg.notes_dir, "dir")
  if dest == nil or dest == "" then return end

  core.ensure_dir(dest)
  local moved, failed = 0, 0

  for _, p in ipairs(paths) do
    if core.file_exists(p) and not core.is_dir(p) then
      local dst = core.join(dest, vim.fn.fnamemodify(p, ":t"))
      if try_move_file(p, dst) then
        moved = moved + 1
      else
        failed = failed + 1
      end
    else
      failed = failed + 1
    end
  end

  core.clear_cache()

  local notes = require("gtd-nvim.zettelkasten.notes")
  notes.write_index()

  core.notify(string.format("%s Moved %d file(s), %d failed.", core.g.phase.organize, moved, failed))
end

-- ============================================================================
-- HELP WINDOW
-- ============================================================================

local function show_help()
  local lines = {
    g.ui.brain .. " ZettelManage - Keys",
    "",
    "  " .. core.g.ui.arrow_right .. " <Enter>   Open file",
    "  " .. core.g.container.trash .. " Ctrl-D    Delete selected",
    "  " .. g.note.archive .. " Ctrl-A    Archive selected",
    "  " .. core.g.phase.organize .. " Ctrl-R    Move/Refile",
    "  " .. g.workflow.backlink .. " Ctrl-B    Show backlinks",
    "  " .. g.workflow.tag .. " Ctrl-T    Show tags",
    "  " .. core.g.ui.question .. " ?         This help",
    "",
    "Features:",
    "  • Junk files filtered (.DS_Store, .continuity, etc)",
    "  • Colored note type glyphs",
    "  • GTD integration",
  }

  local cols, rows = vim.o.columns, vim.o.lines
  local w, h = math.max(55, math.floor(cols * 0.5)), #lines + 4
  local row, col = math.floor((rows - h) / 2), math.floor((cols - w) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = w,
    height = h,
    style = "minimal",
    border = "rounded",
    title = " " .. g.ui.brain .. " Help ",
    title_pos = "center",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set({ "n", "x" }, "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ "n", "x" }, "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

-- ============================================================================
-- MAIN MANAGE PICKER
-- ============================================================================

function M.manage_notes()
  local fzf = core.have_fzf()
  if not fzf then
    core.notify("fzf-lua is required for Manage.", vim.log.levels.ERROR)
    return
  end

  local paths = core.get_paths()
  
  -- Build fd options - only markdown files, exclude junk
  local fd_opts = table.concat({
    "--type", "f",
    "--extension", "md",
    "--exclude", ".DS_Store",
    "--exclude", ".git",
    "--exclude", "node_modules",
    "--exclude", "Archive",
    "--exclude", "Templates",
  }, " ")

  local header = "Enter: Open │ C-d: Delete │ C-a: Archive │ C-r: Move │ Tab: Multi-select │ ?: Help"

  -- Helper to get full paths from selection
  local function get_paths(selected)
    local out = {}
    for _, s in ipairs(selected or {}) do
      -- fzf.files returns relative paths from cwd
      local full = vim.fs.joinpath(paths.notes_dir, s)
      if core.file_exists(full) then
        table.insert(out, full)
      end
    end
    return out
  end

  fzf.files({
    cwd = paths.notes_dir,
    prompt = g.ui.brain .. " Manage> ",
    file_icons = false,
    git_icons = false,
    fd_opts = fd_opts,
    fzf_opts = {
      ["--ansi"] = true,
      ["--header"] = header,
      ["--multi"] = true,
      ["--pointer"] = "▶",
      ["--marker"] = "✓",
    },
    actions = {
      ["default"] = fzf.actions.file_edit,
      ["ctrl-d"] = function(selected)
        local file_paths = get_paths(selected)
        if #file_paths > 0 then
          M.delete_files(file_paths)
        else
          core.notify("No files selected", vim.log.levels.WARN)
        end
      end,
      ["ctrl-a"] = function(selected)
        local file_paths = get_paths(selected)
        if #file_paths > 0 then
          M.archive_files(file_paths)
        else
          core.notify("No files selected", vim.log.levels.WARN)
        end
      end,
      ["ctrl-r"] = function(selected)
        local file_paths = get_paths(selected)
        if #file_paths > 0 then
          M.move_files(file_paths)
        else
          core.notify("No files selected", vim.log.levels.WARN)
        end
      end,
      ["ctrl-b"] = function(selected)
        local file_paths = get_paths(selected)
        if file_paths[1] then
          local search = require("gtd-nvim.zettelkasten.search")
          search.show_backlinks(file_paths[1])
        end
      end,
      ["?"] = function(_)
        M.show_help()
      end,
    },
  })
end

-- ============================================================================
-- BULK TAG OPERATIONS
-- ============================================================================

function M.bulk_tag_add(tag)
  -- TODO: Implement bulk tag addition
  core.notify("Bulk tag add not yet implemented", vim.log.levels.WARN)
end

function M.bulk_tag_remove(tag)
  -- TODO: Implement bulk tag removal
  core.notify("Bulk tag remove not yet implemented", vim.log.levels.WARN)
end

return M
