-- gtd/utils/refile.lua — Task refile operations
-- Move tasks between GTD files while preserving metadata

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.config = {
  gtd_root = "~/Documents/GTD",
  projects_dir = "Projects",
  areas_dir = "Areas",
  inbox_file = "Inbox.org",
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function xp(p) return vim.fn.expand(p or "") end
local function j(a, b) return (a:gsub("/+$", "")) .. "/" .. (b:gsub("^/+", "")) end

local function readfile(path)
  local expanded = xp(path)
  if vim.fn.filereadable(expanded) == 1 then
    return vim.fn.readfile(expanded)
  end
  return {}
end

local function writefile(path, lines)
  local expanded = xp(path)
  vim.fn.mkdir(vim.fn.fnamemodify(expanded, ":h"), "p")
  return vim.fn.writefile(lines, expanded) == 0
end

local function is_heading(line)
  return line and line:match("^%*+%s") ~= nil
end

local function heading_level(line)
  local stars = line and line:match("^(%*+)%s")
  return stars and #stars or nil
end

local function subtree_range(lines, head_idx)
  local head = lines[head_idx]
  if not head then return nil, nil end
  local lvl = heading_level(head) or 1
  local end_idx = head_idx
  for i = head_idx + 1, #lines do
    local line_lvl = heading_level(lines[i] or "")
    if line_lvl and line_lvl <= lvl then break end
    end_idx = i
  end
  return head_idx, end_idx
end

local function find_properties(lines, start_idx, end_idx)
  for i = start_idx, end_idx do
    if (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
      for k = i + 1, end_idx do
        if (lines[k] or ""):match("^%s*:END:%s*$") then
          return i, k
        end
      end
    end
  end
  return nil, nil
end

local function get_property(lines, start_idx, end_idx, key)
  local ps, pe = find_properties(lines, start_idx, end_idx)
  if not ps or not pe then return nil end
  for i = ps + 1, pe - 1 do
    local k, v = (lines[i] or ""):match("^%s*:(%w+):%s*(.*)%s*$")
    if k and k:upper() == key:upper() then return v end
  end
  return nil
end

-- ============================================================================
-- DESTINATION SCANNING
-- ============================================================================

--- Get all valid refile destinations
---@param config table|nil Override config
---@return table List of {path, display, category, filename}
function M.get_destinations(config)
  config = config or M.config
  local root = xp(config.gtd_root)
  local destinations = {}

  -- Scan all .org files in GTD root
  local files = vim.fn.globpath(root, "**/*.org", false, true)
  if type(files) == "string" then files = { files } end

  for _, path in ipairs(files) do
    local filename = vim.fn.fnamemodify(path, ":t")
    local filename_lower = filename:lower()
    local parent = vim.fn.fnamemodify(path, ":h:t")
    local grandparent = vim.fn.fnamemodify(path, ":h:h:t")

    -- Skip archive and deleted files
    if filename_lower:match("archive") or path:lower():match("deleted") then
      goto continue
    end

    -- Categorize the file
    local category = "GTD"
    local display = filename:gsub("%.org$", "")

    if parent == config.projects_dir then
      category = "Project"
      display = "📂 " .. display
    elseif grandparent == config.areas_dir then
      category = "Area:" .. parent
      display = "🏠 " .. parent .. "/" .. display
    elseif parent == config.areas_dir then
      category = "Area"
      display = "🏠 " .. display
    elseif filename_lower == "inbox.org" then
      display = "📥 Inbox"
    else
      display = "📋 " .. display
    end

    table.insert(destinations, {
      path = path,
      display = display,
      category = category,
      filename = filename,
    })

    ::continue::
  end

  -- Sort: GTD root files first, then Projects, then Areas
  table.sort(destinations, function(a, b)
    local priority = { GTD = 1, Project = 2 }
    local pa = priority[a.category] or (a.category:match("^Area") and 3 or 4)
    local pb = priority[b.category] or (b.category:match("^Area") and 3 or 4)
    if pa ~= pb then return pa < pb end
    return a.display < b.display
  end)

  return destinations
end

-- ============================================================================
-- REFILE OPERATIONS
-- ============================================================================

--- Refile a task by TASK_ID from source to destination
---@param source_path string Source file path
---@param task_id string TASK_ID to find
---@param dest_path string Destination file path
---@return boolean, string Success and message
function M.refile_by_id(source_path, task_id, dest_path)
  if not task_id or task_id == "" then
    return false, "No TASK_ID provided"
  end

  local source_lines = readfile(source_path)
  if #source_lines == 0 then
    return false, "Could not read source file"
  end

  -- Find the task by TASK_ID
  local task_start, task_end = nil, nil
  for i, line in ipairs(source_lines) do
    if is_heading(line) then
      local h_start, h_end = subtree_range(source_lines, i)
      if h_start and h_end then
        local tid = get_property(source_lines, h_start, h_end, "TASK_ID")
        if tid == task_id then
          task_start, task_end = h_start, h_end
          break
        end
      end
    end
  end

  if not task_start then
    return false, "Task with TASK_ID " .. task_id .. " not found"
  end

  -- Extract the subtree
  local subtree = {}
  for i = task_start, task_end do
    table.insert(subtree, source_lines[i])
  end

  -- Adjust heading level to 1 (top-level in destination)
  local orig_level = heading_level(subtree[1]) or 1
  if orig_level > 1 then
    local diff = orig_level - 1
    for i, line in ipairs(subtree) do
      local stars = line:match("^(%*+)")
      if stars then
        local new_stars = string.rep("*", math.max(1, #stars - diff))
        subtree[i] = new_stars .. line:sub(#stars + 1)
      end
    end
  end

  -- Read destination and append
  local dest_lines = readfile(dest_path)
  table.insert(dest_lines, "")
  for _, line in ipairs(subtree) do
    table.insert(dest_lines, line)
  end

  -- Write destination
  if not writefile(dest_path, dest_lines) then
    return false, "Failed to write destination file"
  end

  -- Remove from source
  local new_source = {}
  for i = 1, task_start - 1 do
    table.insert(new_source, source_lines[i])
  end
  for i = task_end + 1, #source_lines do
    table.insert(new_source, source_lines[i])
  end

  if not writefile(source_path, new_source) then
    return false, "Failed to update source file (task copied but not removed)"
  end

  return true, "Refiled successfully"
end

--- Interactive refile using fzf
---@param config table|nil Override config
function M.to_project_at_cursor(config)
  config = config or M.config

  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    vim.notify("fzf-lua required for refile", vim.log.levels.WARN)
    return
  end

  local task_id_mod = require("gtd-nvim.gtd.utils.task_id")

  -- Get current buffer and cursor
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local path = vim.api.nvim_buf_get_name(buf)

  -- Find heading at cursor
  local h_start, h_end = nil, nil
  for i = lnum, 1, -1 do
    if is_heading(lines[i]) then
      h_start, h_end = subtree_range(lines, i)
      break
    end
  end

  if not h_start then
    vim.notify("No heading found at cursor", vim.log.levels.WARN)
    return
  end

  -- Ensure TASK_ID exists
  local tid = get_property(lines, h_start, h_end, "TASK_ID")
  if not tid then
    -- Generate and insert TASK_ID
    lines, tid = task_id_mod.ensure_in_properties(lines, h_start)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.cmd("write")
  end

  -- Get destinations
  local destinations = M.get_destinations(config)

  -- Filter out current file
  destinations = vim.tbl_filter(function(d)
    return d.path ~= path
  end, destinations)

  if #destinations == 0 then
    vim.notify("No refile destinations found", vim.log.levels.WARN)
    return
  end

  -- Build display list
  local display = {}
  local dest_map = {}
  for _, d in ipairs(destinations) do
    table.insert(display, d.display)
    dest_map[d.display] = d
  end

  -- Show picker
  fzf.fzf_exec(display, {
    prompt = "Refile to> ",
    fzf_opts = {
      ["--no-info"] = true,
      ["--header"] = "Enter: Refile │ Ctrl-B: Cancel",
    },
    winopts = { height = 0.50, width = 0.60, row = 0.15 },
    actions = {
      ["default"] = function(sel)
        local choice = sel and sel[1]
        if not choice or not dest_map[choice] then return end

        local dest = dest_map[choice]
        local ok, msg = M.refile_by_id(path, tid, dest.path)

        if ok then
          vim.notify("Refiled to: " .. dest.display, vim.log.levels.INFO)
          -- Reload buffer
          vim.cmd("edit!")
        else
          vim.notify("Refile failed: " .. msg, vim.log.levels.ERROR)
        end
      end,
    },
  })
end

--- Extract subtree lines without modifying file
---@param path string File path
---@param start_line number Start line (1-indexed)
---@param end_line number End line (1-indexed)
---@return table Lines of subtree
function M.extract_subtree(path, start_line, end_line)
  local lines = readfile(path)
  local subtree = {}
  for i = start_line, math.min(end_line, #lines) do
    table.insert(subtree, lines[i])
  end
  return subtree
end

--- Refile subtree at cursor (without TASK_ID requirement)
---@param dest_path string Destination file path
function M.refile_subtree_at_cursor(dest_path)
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local path = vim.api.nvim_buf_get_name(buf)

  -- Find heading
  local h_start, h_end = nil, nil
  for i = lnum, 1, -1 do
    if is_heading(lines[i]) then
      h_start, h_end = subtree_range(lines, i)
      break
    end
  end

  if not h_start then
    vim.notify("No heading found", vim.log.levels.WARN)
    return false
  end

  -- Extract subtree
  local subtree = {}
  for i = h_start, h_end do
    table.insert(subtree, lines[i])
  end

  -- Adjust heading level
  local orig_level = heading_level(subtree[1]) or 1
  if orig_level > 1 then
    local diff = orig_level - 1
    for i, line in ipairs(subtree) do
      local stars = line:match("^(%*+)")
      if stars then
        subtree[i] = string.rep("*", math.max(1, #stars - diff)) .. line:sub(#stars + 1)
      end
    end
  end

  -- Append to destination
  local dest_lines = readfile(dest_path)
  table.insert(dest_lines, "")
  for _, line in ipairs(subtree) do
    table.insert(dest_lines, line)
  end

  if not writefile(dest_path, dest_lines) then
    vim.notify("Failed to write destination", vim.log.levels.ERROR)
    return false
  end

  -- Remove from source
  local new_lines = {}
  for i = 1, h_start - 1 do table.insert(new_lines, lines[i]) end
  for i = h_end + 1, #lines do table.insert(new_lines, lines[i]) end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  vim.notify("Refiled successfully", vim.log.levels.INFO)
  return true
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
end

return M
