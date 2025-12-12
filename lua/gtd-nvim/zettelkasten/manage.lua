-- ~/.config/nvim/lua/gtd-nvim/zettelkasten/manage.lua
-- File management operations module

local M = {}

-- Get core zettelkasten module (must require core directly, not init)
local core = require("gtd-nvim.zettelkasten.core")

----------------------------------------------------------------------
-- File Operations
----------------------------------------------------------------------
local function try_delete_file(p)
  local rc = vim.fn.delete(p)
  if rc == 0 then return true end
  local ok_uv, err_uv = pcall(function() return vim.loop.fs_unlink(p) end)
  if ok_uv and err_uv == nil then return true end
  local ok_os, msg = os.remove(p)
  if ok_os then return true end
  return false, ("delete() rc=%s; uv=%s; os.remove=%s"):format(tostring(rc), tostring(err_uv), tostring(msg))
end

local function try_move_file(src, dst)
  pcall(vim.fn.delete, dst)
  local ok = pcall(vim.fn.rename, src, dst)
  if ok and vim.fn.filereadable(dst) == 1 and vim.fn.filereadable(src) == 0 then
    return true
  end
  local content = vim.fn.readfile(src)
  local okw = pcall(vim.fn.writefile, content, dst)
  if okw and vim.fn.filereadable(dst) == 1 then
    local okd = try_delete_file(src)
    return okd == true
  end
  return false
end

local function confirm_yes(msg)
  return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

----------------------------------------------------------------------
-- Mass File Operations
----------------------------------------------------------------------
function M.delete_notes(paths)
  if #paths == 0 then
    core.notify("Nothing to delete", vim.log.levels.WARN)
    return
  end
  
  if not confirm_yes(("Permanently delete %d file(s)?"):format(#paths)) then
    return
  end
  
  local okc, errc = 0, 0
  for _, p in ipairs(paths) do
    if vim.fn.filereadable(p) == 1 then
      local ok, msg = try_delete_file(p)
      if ok then
        okc = okc + 1
      else
        errc = errc + 1
        core.notify("Delete failed: " .. p .. " — " .. (msg or ""), vim.log.levels.ERROR)
      end
    else
      errc = errc + 1
      core.notify("Not a file or missing: " .. p, vim.log.levels.ERROR)
    end
  end
  
  core.clear_cache()
  core.write_index()
  core.notify(("Deleted %d file(s), %d failed."):format(okc, errc))
end

function M.archive_notes(paths)
  if #paths == 0 then
    core.notify("Nothing to archive", vim.log.levels.WARN)
    return
  end
  
  local archive_dir = core.get_paths().archive_dir
  vim.fn.mkdir(archive_dir, "p")
  
  local moved, failed = 0, 0
  for _, p in ipairs(paths) do
    if vim.fn.filereadable(p) == 1 then
      local dst = vim.fs.joinpath(archive_dir, vim.fn.fnamemodify(p, ":t"))
      if try_move_file(p, dst) then
        moved = moved + 1
      else
        failed = failed + 1
      end
    else
      failed = failed + 1
      core.notify("Not a file or missing: " .. p, vim.log.levels.ERROR)
    end
  end
  
  core.clear_cache()
  core.write_index()
  core.notify(("Archived %d file(s), %d failed."):format(moved, failed))
end

function M.move_notes(paths)
  if #paths == 0 then
    core.notify("Nothing to move", vim.log.levels.WARN)
    return
  end
  
  local dest = vim.fn.input("Move to dir: ", core.get_paths().notes_dir, "dir")
  if dest == nil or dest == "" then return end
  
  vim.fn.mkdir(dest, "p")
  
  local moved, failed = 0, 0
  for _, p in ipairs(paths) do
    if vim.fn.filereadable(p) == 1 then
      local dst = vim.fs.joinpath(dest, vim.fn.fnamemodify(p, ":t"))
      if try_move_file(p, dst) then
        moved = moved + 1
      else
        failed = failed + 1
      end
    else
      failed = failed + 1
      core.notify("Not a file or missing: " .. p, vim.log.levels.ERROR)
    end
  end
  
  core.clear_cache()
  core.write_index()
  core.notify(("Moved %d file(s), %d failed."):format(moved, failed))
end

----------------------------------------------------------------------
-- Management Interface
----------------------------------------------------------------------
local function show_help()
  local lines = {
    "ZettelManage — Mass Management Keys",
    "",
    "MULTI-SELECT MODE:",
    "  TAB       Mark/unmark file for batch operations",
    "  Shift-TAB Unmark file",
    "  Alt-A     Select all files",
    "  Alt-D     Deselect all files",
    "",
    "ACTIONS (work on marked files or current file):",
    "  <Enter>   Open file",
    "  Ctrl-D    Delete selected file(s) [CAREFUL!]",
    "  Ctrl-A    Archive selected file(s) → Archive/",
    "  Ctrl-R    Move selected file(s) → choose dir",
    "  Ctrl-B    Show backlinks for selected file",
    "  Ctrl-T    Browse tags in selected file",
    "  ?         Show this help",
    "",
    "PRO TIPS:",
    "  • Mark multiple files with TAB before deleting",
    "  • Use Alt-A to select all, then Shift-TAB to deselect",
    "  • Selection counter shows in prompt",
  }
  
  local cols, rows = vim.o.columns, vim.o.lines
  local w, h = math.max(70, math.floor(cols * 0.6)), #lines + 4
  local row, col = math.floor((rows - h) / 2), math.floor((cols - w) / 2)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = w, height = h,
    style = "minimal", border = "rounded", title = " Mass Management Help ", title_pos = "center",
  })
  
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  
  vim.keymap.set({ "n", "x" }, "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ "n", "x" }, "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

function M.manage_notes()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    core.notify("fzf-lua is required for Manage", vim.log.levels.ERROR)
    return
  end
  
  local header = "[TAB] Multi-Select | [Enter] Open | [Ctrl-D] Delete | [Ctrl-A] Archive | [Ctrl-R] Move | [?] Help"
  local paths = core.get_paths()
  
  -- Build fd options - only markdown files, exclude junk
  local fd_opts = table.concat({
    "--type", "f",
    "--extension", "md",
    "--hidden",
    "--exclude", ".DS_Store",
    "--exclude", ".git",
    "--exclude", "node_modules",
    "--exclude", "Archive",
    "--exclude", "Templates",
    "--exclude", "'*.bak'",
    "--exclude", "'*~'",
  }, " ")
  
  fzf.files({
    cwd = paths.notes_dir,
    prompt = "ZK ⟩ ",
    file_icons = false,
    fzf_opts = {
      ["--multi"] = true,
      ["--bind"] = "alt-a:select-all,alt-d:deselect-all",
      ["--header"] = header,
      ["--info"] = "inline-right",
      ["--pointer"] = "▶",
      ["--marker"] = "✓",
    },
    fd_opts = fd_opts,
    actions = {
      ["default"] = fzf.actions.file_edit,
      ["ctrl-d"] = function(selected)
        local file_paths = core.sel_to_paths_fzf(selected)
        if #file_paths > 0 then
          core.notify(string.format("About to delete %d file(s)...", #file_paths), vim.log.levels.WARN)
          M.delete_notes(file_paths)
        end
      end,
      ["ctrl-a"] = function(selected)
        local file_paths = core.sel_to_paths_fzf(selected)
        if #file_paths > 0 then
          core.notify(string.format("Archiving %d file(s)...", #file_paths))
          M.archive_notes(file_paths)
        end
      end,
      ["ctrl-r"] = function(selected)
        local file_paths = core.sel_to_paths_fzf(selected)
        if #file_paths > 0 then
          core.notify(string.format("Moving %d file(s)...", #file_paths))
          M.move_notes(file_paths)
        end
      end,
      ["ctrl-b"] = function(selected)
        local file_paths = core.sel_to_paths_fzf(selected)
        if file_paths[1] then
          core.show_backlinks(file_paths[1])
        end
      end,
      ["ctrl-t"] = function(selected)
        local file_paths = core.sel_to_paths_fzf(selected)
        if file_paths[1] and vim.fn.filereadable(file_paths[1]) == 1 then
          local content = table.concat(vim.fn.readfile(file_paths[1]), "\n")
          local tags = core.extract_tags(content)
          if #tags > 0 then
            core.notify("Tags: " .. table.concat(tags, ", "))
          else
            core.notify("No tags found in file")
          end
        end
      end,
      ["?"] = function(_) show_help() end,
      ["alt-?"] = function(_) show_help() end,
    },
  })
end

----------------------------------------------------------------------
-- Bulk Operations
----------------------------------------------------------------------
function M.bulk_tag_add()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    core.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  vim.ui.input({ prompt = "Tag to add: " }, function(tag)
    if not tag or tag == "" then return end
    tag = tag:gsub("^#", "")  -- Remove leading # if present
    
    fzf.files({
      cwd = core.get_paths().notes_dir,
      prompt = "Select files to tag ⟩ ",
      fzf_opts = {
        ["--multi"] = true,
        ["--header"] = string.format("Adding tag: #%s | TAB to select | Enter to confirm", tag),
      },
      actions = {
        ["default"] = function(selected)
          local file_paths = core.sel_to_paths_fzf(selected)
          local tagged = 0
          
          for _, path in ipairs(file_paths) do
            if vim.fn.filereadable(path) == 1 then
              local lines = vim.fn.readfile(path)
              local found_tags_line = false
              
              for i, line in ipairs(lines) do
                if line:match("^%*%*Tags:%*%*") or line:match("^Tags:") then
                  if not line:match("#" .. tag) then
                    lines[i] = line .. " #" .. tag
                    tagged = tagged + 1
                  end
                  found_tags_line = true
                  break
                end
              end
              
              if found_tags_line then
                vim.fn.writefile(lines, path)
              end
            end
          end
          
          core.clear_cache()
          core.notify(string.format("Tagged %d file(s) with #%s", tagged, tag))
        end,
      },
    })
  end)
end

function M.bulk_tag_remove()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    core.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  -- Get all tags first
  local tags = core.get_all_tags()
  local tag_list = {}
  for tag in pairs(tags) do
    table.insert(tag_list, tag)
  end
  table.sort(tag_list)
  
  if #tag_list == 0 then
    core.notify("No tags found", vim.log.levels.WARN)
    return
  end
  
  fzf.fzf_exec(tag_list, {
    prompt = "Select tag to remove ⟩ ",
    actions = {
      ["default"] = function(selected)
        local tag = selected[1]
        if not tag then return end
        
        fzf.files({
          cwd = core.get_paths().notes_dir,
          prompt = string.format("Remove #%s from files ⟩ ", tag),
          fzf_opts = {
            ["--multi"] = true,
            ["--header"] = "TAB to select | Enter to confirm",
          },
          actions = {
            ["default"] = function(file_selected)
              local file_paths = core.sel_to_paths_fzf(file_selected)
              local removed = 0
              
              for _, path in ipairs(file_paths) do
                if vim.fn.filereadable(path) == 1 then
                  local content = table.concat(vim.fn.readfile(path), "\n")
                  local new_content = content:gsub("#" .. tag, "")
                  new_content = new_content:gsub("%s+", " ")  -- Clean up extra spaces
                  
                  vim.fn.writefile(vim.split(new_content, "\n"), path)
                  removed = removed + 1
                end
              end
              
              core.clear_cache()
              core.notify(string.format("Removed #%s from %d file(s)", tag, removed))
            end,
          },
        })
      end,
    },
  })
end

----------------------------------------------------------------------
-- Setup Commands
----------------------------------------------------------------------
function M.setup_commands()
  vim.api.nvim_create_user_command("ZettelManage", M.manage_notes, {})
  vim.api.nvim_create_user_command("ZettelBulkTag", M.bulk_tag_add, {})
  vim.api.nvim_create_user_command("ZettelBulkUntag", M.bulk_tag_remove, {})
end

----------------------------------------------------------------------
-- Setup Keymaps
----------------------------------------------------------------------
function M.setup_keymaps()
  vim.keymap.set("n", "<leader>zm", M.manage_notes, { desc = "Manage notes" })
  vim.keymap.set("n", "<leader>zt", M.bulk_tag_add, { desc = "Bulk tag add" })
  vim.keymap.set("n", "<leader>zT", M.bulk_tag_remove, { desc = "Bulk tag remove" })
end

return M
