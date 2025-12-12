-- ============================================================================
-- GTD-NVIM MANAGE MODULE
-- ============================================================================
-- Task & project management with enhanced GTD workflow integration
-- Actions: Open, Clarify, Archive, Delete, Refile, Open ZK
--
-- @module gtd-nvim.gtd.manage
-- @version 1.0.0
-- @requires shared (>= 1.0.0)
-- @see 202512081430-GTD-Nvim-Shared-Module-Audit
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2024-12-08"

-- Load shared utilities with glyph system
local shared = require("gtd-nvim.gtd.shared")
local g = shared.glyphs  -- Glyph shortcuts

-- ------------------------ Config ------------------------
M.cfg = {
  gtd_root            = "~/Documents/GTD",
  projects_dir        = "Projects",       -- under gtd_root
  areas_dir           = "Areas",          -- under gtd_root (new: Areas support)
  inbox_file          = "Inbox.org",      -- under gtd_root
  archive_file        = "Archive.org",    -- under gtd_root
  archive_deleted_dir = "ArchiveDeleted", -- under gtd_root

  zk_root             = "~/Documents/Notes",
  zk_archive_dir      = "Archive",        -- under zk_root

  -- Display options
  show_archive_tasks  = true,             -- include archived tasks in listings
  max_title_length    = 60,               -- truncate long titles
  date_format         = "%Y-%m-%d %H:%M", -- for timestamps
}

-- ------------------------ Dependencies ------------------------
local ui = require("gtd-nvim.gtd.ui")
local task_id = require("gtd-nvim.gtd.utils.task_id")

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local org_dates = safe_require("gtd-nvim.gtd.utils.org_dates")  -- ✅ Added
local clarify = safe_require("gtd-nvim.gtd.clarify")
local organize = safe_require("gtd-nvim.gtd.organize")

-- ------------------------ Helpers ------------------------
local function xp(p) return vim.fn.expand(p) end
local function j(a, b) return (a:gsub("/+$", "")) .. "/" .. (b:gsub("^/+", "")) end
local function ensure_dir(path) vim.fn.mkdir(vim.fn.fnamemodify(path, ":p:h"), "p"); return path end
local function readf(path) if vim.fn.filereadable(path) == 1 then return vim.fn.readfile(path) else return {} end end
local function writef(path, L) ensure_dir(path); return vim.fn.writefile(L, path) == 0 end
local function appendf(path, L) ensure_dir(path); vim.fn.writefile({ "" }, path, "a"); return vim.fn.writefile(L, path, "a") == 0 end
local function now() return os.date(M.cfg.date_format) end
local function have_fzf() return pcall(require, "fzf-lua") end

local function truncate_title(title, max_len)
  max_len = max_len or M.cfg.max_title_length
  if not title or #title <= max_len then return title or "" end
  return title:sub(1, max_len - 3) .. "..."
end

local function paths()
  local root = xp(M.cfg.gtd_root)
  local zk_root = xp(M.cfg.zk_root)
  return {
    root       = root,
    inbox      = j(root, M.cfg.inbox_file),
    archive    = j(root, M.cfg.archive_file),
    projdir    = j(root, M.cfg.projects_dir),
    areas_root = j(root, M.cfg.areas_dir),
    deldir     = j(root, M.cfg.archive_deleted_dir),
    zk_root    = zk_root,
    zk_arch    = j(zk_root, M.cfg.zk_archive_dir),
  }
end

-- ------------------------ Org Helpers ------------------------
local function is_heading(ln) return ln:match("^%*+%s") ~= nil end
local function heading_level(ln) local s = ln:match("^(%*+)%s"); return s and #s or nil end

local function subtree_range(lines, hstart)
  local head = lines[hstart]; if not head then return nil end
  local lvl = heading_level(head) or 1
  local i = hstart + 1
  while i <= #lines do
    local lv2 = heading_level(lines[i] or "")
    if lv2 and lv2 <= lvl then break end
    i = i + 1
  end
  return hstart, i - 1
end

local function parse_state_title(ln)
  local _, rest = ln:match("^(%*+)%s+(.*)")
  if not rest then return nil, nil end
  local state, title = rest:match("^([A-Z]+)%s+(.*)")
  return state or nil, title or rest
end

local function find_properties_block(lines, start_idx, end_idx)
  start_idx = start_idx or 1
  end_idx = end_idx or #lines
  for i = start_idx, end_idx do
    if lines[i]:match("^%s*:PROPERTIES:%s*$") then
      for j = i + 1, end_idx do
        if lines[j]:match("^%s*:END:%s*$") then
          return i, j
        end
      end
    end
  end
  return nil, nil
end

local function get_property(lines, start_idx, end_idx, key)
  local p_start, p_end = find_properties_block(lines, start_idx, end_idx)
  if not p_start then return nil end
  for i = p_start + 1, p_end - 1 do
    local k, v = lines[i]:match("^%s*:(%w+):%s*(.*)%s*$")
    if k and k:upper() == key:upper() then return v end
  end
  return nil
end

local function find_dates_in_subtree(lines, start_idx, end_idx)
  local scheduled, deadline
  for i = start_idx, end_idx do
    local ln = lines[i] or ""
    local sch = ln:match("SCHEDULED:%s*<([^>]+)>")
    local ddl = ln:match("DEADLINE:%s*<([^>]+)>")
    if sch and not scheduled then scheduled = sch end
    if ddl and not deadline then deadline = ddl end
  end
  return scheduled, deadline
end

local function zk_path_in_subtree(lines, hstart, hend)
  -- Look for ZK_NOTE property first (file path)
  local zk_prop = get_property(lines, hstart, hend, "ZK_NOTE")
  if zk_prop then
    local p = zk_prop:match("%[%[file:(.-)%]%]") or zk_prop:match("^file:(.+)")
    if p then return xp(p) end
  end

  -- Look for ZK_LINK property (org-mode compliant format)
  local zk_link = get_property(lines, hstart, hend, "ZK_LINK")
  if zk_link then
    local zkid = zk_link:match("%[%[zk:(%w+)%]%]")
    if zkid then
      -- Has ZK ID reference - resolution left to ZK tooling
      return nil  -- Return nil since we don't have the actual path
    end
  end

  -- Look for body links (Notes: [[file:...]])
  for i = hstart, hend do
    local p = (lines[i] or ""):match("^%s*Notes:%s*%[%[file:(.-)%]%]")
    if p and p ~= "" then return xp(p) end

    -- Legacy fallback: check for standalone ID:: lines
    local zkid = (lines[i] or ""):match("ID::%s*%[%[zk:(%w+)%]%]")
    if zkid then
      -- Legacy format exists - resolution left to ZK tooling
    end
  end
  return nil
end

-- ------------------------ Enhanced Scanners ------------------------
local function scan_all_tasks()
  local P = paths()
  local files = vim.fn.globpath(P.root, "**/*.org", false, true)
  if type(files) == "string" then files = { files } end
  table.sort(files)
  local items = {}

  for _, path in ipairs(files) do
    local filename = vim.fn.fnamemodify(path, ":t")
    local dirname  = vim.fn.fnamemodify(path, ":h:t")

    -- Skip deleted/archived-deleted project files entirely
    if dirname ~= M.cfg.archive_deleted_dir then
      local lines = readf(path)
      for i, ln in ipairs(lines) do
        if is_heading(ln) then
          local hstart, hend = subtree_range(lines, i)
          if not hstart or not hend then goto continue_heading end

          local state, title = parse_state_title(ln)
          local level = heading_level(ln) or 1
          local is_project = ln:match("^%*+%s+PROJECT%s") ~= nil
          local kind = is_project and "project" or "task"

          -- Enhanced metadata extraction
          local zk = zk_path_in_subtree(lines, hstart, hend)
          local task_id_val = get_property(lines, hstart, hend, "TASK_ID")
          local scheduled, deadline = find_dates_in_subtree(lines, hstart, hend)
          local effort = get_property(lines, hstart, hend, "Effort")
          local assigned = get_property(lines, hstart, hend, "ASSIGNED")

          -- Parse tags from heading
          local tags = {}
          local tag_block = ln:match("%s+:([%w_:%-]+):%s*$")
          if tag_block then
            for t in tag_block:gmatch("([^:]+)") do
              table.insert(tags, t)
            end
          end

          local from_archive = (filename == M.cfg.archive_file)

          -- Get container type and state priority for GTD sorting
          local container_type, container_priority = shared.get_container_type(path, filename)
          local state_priority_val = shared.get_state_priority(state)

          table.insert(items, {
            kind = kind,
            path = path,
            lnum = i,
            hstart = hstart,
            hend = hend,
            line = ln,
            level = level,
            state = state,
            title = title,
            filename = filename,
            zk_path = zk,
            task_id = task_id_val,
            scheduled = scheduled,
            deadline = deadline,
            effort = effort,
            assigned = assigned,
            tags = tags,
            from_archive = from_archive, -- kept for backward compatibility
            container_type = container_type,
            container_priority = container_priority,
            state_priority = state_priority_val,
          })

          ::continue_heading::
        end
      end
    end
  end

  return items
end

local function list_project_files()
  local P = paths()
  local files = {}

  -- Classic Projects/ dir (existing behavior)
  local proj_files = vim.fn.globpath(P.projdir, "*.org", false, true)
  if type(proj_files) == "string" then proj_files = { proj_files } end
  for _, p in ipairs(proj_files) do
    table.insert(files, p)
  end

  -- New: Areas/… project files
  if vim.fn.isdirectory(P.areas_root) == 1 then
    local area_files = vim.fn.globpath(P.areas_root, "**/*.org", false, true)
    if type(area_files) == "string" then area_files = { area_files } end
    for _, p in ipairs(area_files) do
      table.insert(files, p)
    end
  end

  -- Deduplicate (just in case)
  local seen = {}
  local unique = {}
  for _, p in ipairs(files) do
    if not seen[p] then
      seen[p] = true
      table.insert(unique, p)
    end
  end
  files = unique
  table.sort(files)

  -- Enhanced project file metadata with detailed task analysis
  -- ONLY include files that actually have a PROJECT heading
  local enhanced = {}
  for _, path in ipairs(files) do
    local lines = readf(path)
    local first_heading = nil
    local is_actual_project = false  -- Must have PROJECT state to be included
    local project_info = {
      path = path,
      headings = 0,
      tasks = 0,
      next_actions = 0,
      todo_tasks = 0,
      waiting_tasks = 0,
      done_tasks = 0,
      has_deadlines = false,
      earliest_deadline = nil,
      last_modified = vim.fn.getftime(path),
    }

    for i, ln in ipairs(lines) do
      if is_heading(ln) then
        project_info.headings = project_info.headings + 1
        local state, title = parse_state_title(ln)
        
        -- Check if this file has a PROJECT heading (typically first heading)
        if state == "PROJECT" then
          is_actual_project = true
        end
        
        if not first_heading then
          first_heading = ln
          project_info.title = title
        end

        -- Analyze task states and dates
        local hstart, hend = subtree_range(lines, i)
        if hstart and hend then
          if state == "NEXT" then
            project_info.next_actions = project_info.next_actions + 1
            project_info.tasks = project_info.tasks + 1
          elseif state == "TODO" then
            project_info.todo_tasks = project_info.todo_tasks + 1
            project_info.tasks = project_info.tasks + 1
          elseif state == "WAITING" then
            project_info.waiting_tasks = project_info.waiting_tasks + 1
            project_info.tasks = project_info.tasks + 1
          elseif state == "DONE" then
            project_info.done_tasks = project_info.done_tasks + 1
          end

          -- Check for deadlines
          local _, deadline = find_dates_in_subtree(lines, hstart, hend)
          if deadline then
            project_info.has_deadlines = true
            if not project_info.earliest_deadline or deadline < project_info.earliest_deadline then
              project_info.earliest_deadline = deadline
            end
          end
        end
      end
    end

    -- Only include files that actually have a PROJECT heading
    if is_actual_project then
      table.insert(enhanced, project_info)
    end
  end

  return enhanced
end

-- GTD Project Sorting: Areas (alphabetically) first, then Projects (alphabetically)
local function sort_projects_gtd_workflow(projects)
  table.sort(projects, function(a, b)
    local P = paths()
    
    -- Determine location type and area name
    local function get_location_info(proj)
      local dir = vim.fn.fnamemodify(proj.path, ":h")
      local parent = vim.fn.fnamemodify(proj.path, ":h:t")
      local grandparent = vim.fn.fnamemodify(proj.path, ":h:h:t")
      
      -- Check if under Areas/
      if grandparent == M.cfg.areas_dir or dir:find(P.areas_root, 1, true) then
        return 1, parent  -- Areas first, sorted by area name
      elseif dir == P.projdir or parent == M.cfg.projects_dir then
        return 2, ""  -- Projects second
      else
        return 3, ""  -- Other locations last
      end
    end
    
    local loc_a, area_a = get_location_info(a)
    local loc_b, area_b = get_location_info(b)
    
    -- First sort by location type (Areas < Projects < Other)
    if loc_a ~= loc_b then
      return loc_a < loc_b
    end
    
    -- Within Areas, sort by area name
    if loc_a == 1 and area_a ~= area_b then
      return area_a < area_b
    end
    
    -- Finally, sort alphabetically by project title
    local title_a = (a.title or vim.fn.fnamemodify(a.path, ":t:r")):lower()
    local title_b = (b.title or vim.fn.fnamemodify(b.path, ":t:r")):lower()
    return title_a < title_b
  end)
end

-- ------------------------ GTD-Optimized Sorting ------------------------
local state_priority = {
  NEXT = 1,
  TODO = 2,
  WAITING = 3,
  SOMEDAY = 4,
  DONE = 5,
}

local function get_state_priority(state)
  return state_priority[state or ""] or 6
end

local function get_file_priority(item)
  local filename = vim.fn.fnamemodify(item.path, ":t")
  local dirname  = vim.fn.fnamemodify(item.path, ":h:t")
  local grand    = vim.fn.fnamemodify(item.path, ":h:h:t")

  -- Inbox gets highest priority
  if filename == M.cfg.inbox_file then
    return 1
  end

  -- Projects dir or Areas hierarchy → second priority
  if dirname == M.cfg.projects_dir or grand == M.cfg.areas_dir then
    return 2
  end

  -- Archive file → lowest priority
  if filename == M.cfg.archive_file then
    return 4
  end

  -- Everything else in the middle
  return 3
end

local function sort_items_gtd_workflow(items)
  -- Use shared GTD hierarchy sorting: Inbox → Areas → Projects
  shared.gtd_sort(items)
end

-- ------------------------ Enhanced Display Formatting ------------------------
local function format_task_display(item)
  -- File indicator with clear priority
  local filename = vim.fn.fnamemodify(item.path, ":t")
  local dirname  = vim.fn.fnamemodify(item.path, ":h:t")
  local grand    = vim.fn.fnamemodify(item.path, ":h:h:t")
  local file_indicator = ""

  if filename == M.cfg.inbox_file then
    file_indicator = g.container.inbox .. " Inbox"
  elseif dirname == M.cfg.projects_dir or grand == M.cfg.areas_dir then
    file_indicator = g.container.projects .. " " .. vim.fn.fnamemodify(item.path, ":t:r")
  elseif filename == M.cfg.archive_file then
    file_indicator = g.container.someday .. " Archive"
  else
    file_indicator = g.file.org .. " " .. vim.fn.fnamemodify(item.path, ":t:r")
  end

  -- State indicator
  local state_icon = ""
  if item.state == "NEXT" then state_icon = g.state.NEXT
  elseif item.state == "TODO" then state_icon = g.state.TODO
  elseif item.state == "WAITING" then state_icon = g.state.WAITING
  elseif item.state == "SOMEDAY" then state_icon = g.state.SOMEDAY
  elseif item.state == "DONE" then state_icon = g.state.DONE
  end

  -- Title with truncation
  local title = truncate_title(item.title or item.line or "")

  -- Date indicators
  local date_info = ""
  if item.deadline then
    date_info = " " .. g.ui.warning .. item.deadline
  elseif item.scheduled then
    date_info = " " .. g.container.calendar .. item.scheduled
  end

  -- ZK indicator
  local zk_indicator = item.zk_path and (" " .. g.ui.note) or ""

  -- Tags
  local tag_display = ""
  if item.tags and #item.tags > 0 then
    tag_display = " :" .. table.concat(item.tags, ":") .. ":"
  end

  return string.format("%s %s %s%s%s%s",
    file_indicator, state_icon, title, date_info, zk_indicator, tag_display)
end

-- ------------------------ Enhanced Mutations ------------------------
local function move_or_delete_file(p, do_delete, archive_dir)
  if do_delete then
    local success = os.remove(p)
    return success == nil, "(deleted)"
  else
    ensure_dir(j(archive_dir, "dummy"))
    local base = vim.fn.fnamemodify(p, ":t")
    local dst = j(archive_dir, base)

    -- Handle collisions
    local counter = 1
    while vim.fn.filereadable(dst) == 1 or vim.fn.isdirectory(dst) == 1 do
      local stem = vim.fn.fnamemodify(base, ":r")
      local ext = vim.fn.fnamemodify(base, ":e")
      local suffix = string.format("-%d", counter)
      base = stem .. suffix .. (ext ~= "" and ("." .. ext) or "")
      dst = j(archive_dir, base)
      counter = counter + 1
    end

    return vim.fn.rename(p, dst) == 0, dst
  end
end

local function remove_subtree_from_file(path, hstart, hend)
  local L = readf(path)
  local out = {}
  for i = 1, hstart - 1 do table.insert(out, L[i]) end
  for i = hend + 1, #L do table.insert(out, L[i]) end
  return writef(path, out)
end

local function archive_subtree_to_file(path, hstart, hend, dest_archive, tag)
  local L = readf(path)
  local chunk = {}
  local head = L[hstart] or "*"
  local title = head:gsub("^%*+%s+", "")

  -- Enhanced archive header with more metadata
  local header_lines = {
    string.format("* %s (%s)", title, tag or "archived"),
    ":PROPERTIES:",
    string.format(":SOURCE:   [[file:%s::%d][%s]]", path, hstart, vim.fn.fnamemodify(path, ":t")),
    string.format(":DATE:     %s", now()),
    string.format(":ARCHIVED_FROM_LINE: %d", hstart),
    ":END:",
  }

  for _, line in ipairs(header_lines) do
    table.insert(chunk, line)
  end

  -- Add original subtree
  for i = hstart, hend do
    table.insert(chunk, L[i])
  end

  table.insert(chunk, "") -- Add separator

  return appendf(dest_archive, chunk)
end

local function archive_or_delete_zk(zk_path, action)
  if not zk_path or zk_path == "" then return true end

  local P = paths()
  if action == "delete" then
    local success = os.remove(zk_path)
    if success == nil then
      vim.notify(g.ui.warning .. " Failed to delete ZK note: " .. zk_path, vim.log.levels.WARN)
      return false
    end
    return true
  end

  -- Move to Notes/Archive with collision handling
  ensure_dir(j(P.zk_arch, "dummy"))
  local base = vim.fn.fnamemodify(zk_path, ":t")
  local stem = vim.fn.fnamemodify(base, ":r")
  local ext = vim.fn.fnamemodify(base, ":e")
  local dst = j(P.zk_arch, base)

  -- Handle filename collisions
  local counter = 1
  while vim.fn.filereadable(dst) == 1 do
    local suffix = string.format("-%d", counter)
    local new_base = stem .. suffix .. (ext ~= "" and ("." .. ext) or "")
    dst = j(P.zk_arch, new_base)
    counter = counter + 1
  end

  local success = vim.fn.rename(zk_path, dst) == 0
  if not success then
    vim.notify("⚠️  Failed to move ZK note to archive", vim.log.levels.WARN)
  end
  return success
end

-- ------------------------ Archive Handling Helper ------------------------
local function archive_whole_project_file(proj_path, opts)
  opts = opts or {}
  local P = paths()
  local L = readf(proj_path)
  if #L == 0 then return false end

  -- Create archive entry with enhanced metadata
  local proj_title = L[1]:match("^%*+%s+(.*)") or vim.fn.fnamemodify(proj_path, ":t:r")
  local chunk = {
    string.format("* PROJECT %s (archived)", proj_title),
    ":PROPERTIES:",
    string.format(":SOURCE:   [[file:%s][%s]]", proj_path, vim.fn.fnamemodify(proj_path, ":t")),
    string.format(":DATE:     %s", now()),
    string.format(":ARCHIVED_BY: %s", vim.fn.expand("$USER")),
    ":END:",
    "",
  }

  -- Add original content
  for _, ln in ipairs(L) do
    table.insert(chunk, ln)
  end
  table.insert(chunk, "")

  if not appendf(P.archive, chunk) then
    return false
  end

  -- Handle ZK notes
  local zk_files = {}
  for _, ln in ipairs(L) do
    local p = ln:match(":ZK_NOTE:%s*%[%[file:(.-)%]%]") or
             ln:match("^%s*Notes:%s*%[%[file:(.-)%]%]")
    if p then zk_files[xp(p)] = true end
  end

  for zk, _ in pairs(zk_files) do
    archive_or_delete_zk(zk, opts.zk_action or "move")
  end

  -- Move project file to archive-deleted directory (ArchiveDeleted)
  local ok, _ = move_or_delete_file(proj_path, opts.delete, P.deldir)
  return ok
end

-- ------------------------ Enhanced Action Menus ------------------------
local function task_actions_menu(item, on_done)
  if not have_fzf() then
    vim.notify("fzf-lua is required for task management", vim.log.levels.WARN)
    return
  end

  local fzf = require("fzf-lua")
  local actions = { "Open", "Clarify", "Archive (→ DONE)", "Delete", "Refile", "Open ZK", "Cancel" }

  -- Remove actions that don't apply
  if not item.zk_path then
    actions = vim.tbl_filter(function(a) return a ~= "Open ZK" end, actions)
  end

  if not clarify then
    actions = vim.tbl_filter(function(a) return a ~= "Clarify" end, actions)
  end

  if not organize then
    actions = vim.tbl_filter(function(a) return a ~= "Refile" end, actions)
  end

  fzf.fzf_exec(actions, {
    prompt = shared.colorize(g.ui.menu, "info") .. " Task Action> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index", ["--ansi"] = true },
    winopts = { height = 0.30, width = 0.50, row = 0.10 },
    actions = {
      ["default"] = function(sel)
        local action = sel and sel[1]
        if not action then return end

        if action == "Open" then
          vim.cmd("edit " .. vim.fn.fnameescape(item.path))
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })

        elseif action == "Clarify" and clarify then
          vim.cmd("edit " .. vim.fn.fnameescape(item.path))
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
          clarify.clarify({})

        elseif action == "Archive (→ DONE)" then
          local P = paths()
          -- First mark as DONE, then archive
          local lines = readf(item.path)
          if lines[item.hstart] then
            -- Change state to DONE in the heading line
            local heading = lines[item.hstart]
            local stars, state, title = heading:match("^(%*+%s+)([A-Z]+)%s+(.*)")
            if stars and state and title then
              -- Replace any GTD state with DONE
              local gtd_states = { TODO = true, NEXT = true, WAITING = true, SOMEDAY = true }
              if gtd_states[state] then
                lines[item.hstart] = stars .. "DONE " .. title
                writef(item.path, lines)
              end
            end
          end
          -- Now archive the (now DONE) task
          if archive_subtree_to_file(item.path, item.hstart, item.hend, P.archive, "task") then
            remove_subtree_from_file(item.path, item.hstart, item.hend)
            archive_or_delete_zk(item.zk_path, "move")
            vim.notify(g.state.DONE .. " Task marked DONE and archived", vim.log.levels.INFO)
          else
            vim.notify(g.ui.cross .. " Failed to archive task", vim.log.levels.ERROR)
          end
          if on_done then on_done() end

        elseif action == "Delete" then
          ui.select({ "Yes, delete permanently", "Cancel" },
            { prompt = g.ui.warning .. " Really delete this task?" },
            function(choice)
              if choice and choice:match("Yes") then
                if remove_subtree_from_file(item.path, item.hstart, item.hend) then
                  archive_or_delete_zk(item.zk_path, "delete")
                  vim.notify(g.container.trash .. " Task deleted permanently", vim.log.levels.INFO)
                else
                  vim.notify("❌ Failed to delete task", vim.log.levels.ERROR)
                end
                if on_done then on_done() end
              end
            end)

        elseif action == "Refile" and organize then
          vim.cmd("edit " .. vim.fn.fnameescape(item.path))
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
          -- organize.refile_at_cursor may be an alias to refile_to_project in your organize.lua
          if organize.refile_at_cursor then
            organize.refile_at_cursor({})
          else
            organize.refile_to_project({})
          end

        elseif action == "Open ZK" then
          if item.zk_path then
            vim.cmd("edit " .. vim.fn.fnameescape(item.zk_path))
          else
            vim.notify("No ZK note linked to this task", vim.log.levels.INFO)
            if on_done then on_done() end
          end

        else
          if on_done then on_done() end
        end
      end,
    },
  })
end

-- ------------------------ Refile Project Helper ------------------------
local function refile_project(proj_path, on_done)
  if not have_fzf() then
    vim.notify("fzf-lua is required for refiling", vim.log.levels.WARN)
    return
  end
  
  local P = paths()
  local fzf = require("fzf-lua")
  
  -- Build list of possible destinations
  local destinations = {}
  
  -- Add Projects/ directory
  table.insert(destinations, {
    display = g.container.projects .. " Projects/",
    path = P.projdir,
    type = "projects"
  })
  
  -- Add each Area
  if vim.fn.isdirectory(P.areas_root) == 1 then
    local areas = vim.fn.glob(P.areas_root .. "/*", false, true)
    for _, area_path in ipairs(areas) do
      if vim.fn.isdirectory(area_path) == 1 then
        local area_name = vim.fn.fnamemodify(area_path, ":t")
        table.insert(destinations, {
          display = g.container.areas .. " Areas/" .. area_name,
          path = area_path,
          type = "area"
        })
      end
    end
  end
  
  -- Sort: Areas alphabetically, then Projects
  table.sort(destinations, function(a, b)
    if a.type ~= b.type then
      return a.type == "area"  -- Areas first
    end
    return a.display < b.display
  end)
  
  local display_list = {}
  for _, d in ipairs(destinations) do
    table.insert(display_list, d.display)
  end
  
  local current_dir = vim.fn.fnamemodify(proj_path, ":h")
  local filename = vim.fn.fnamemodify(proj_path, ":t")
  
  fzf.fzf_exec(display_list, {
    prompt = g.phase.organize .. " Move project to> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index", ["--ansi"] = true },
    winopts = { height = 0.40, width = 0.60, row = 0.15 },
    actions = {
      ["default"] = function(sel)
        local choice = sel and sel[1]
        if not choice then
          if on_done then on_done() end
          return
        end
        
        local idx = vim.fn.index(display_list, choice) + 1
        local dest = destinations[idx]
        if not dest then
          if on_done then on_done() end
          return
        end
        
        -- Don't move to same location
        if dest.path == current_dir then
          vim.notify("Project is already in this location", vim.log.levels.INFO)
          if on_done then on_done() end
          return
        end
        
        -- Ensure destination exists
        ensure_dir(j(dest.path, "dummy"))
        
        -- Build new path
        local new_path = j(dest.path, filename)
        
        -- Handle collision
        local counter = 1
        while vim.fn.filereadable(new_path) == 1 do
          local stem = vim.fn.fnamemodify(filename, ":r")
          local ext = vim.fn.fnamemodify(filename, ":e")
          local new_filename = stem .. "-" .. counter .. (ext ~= "" and ("." .. ext) or "")
          new_path = j(dest.path, new_filename)
          counter = counter + 1
        end
        
        -- Move the file
        local success = vim.fn.rename(proj_path, new_path) == 0
        if success then
          local dest_display = dest.display:gsub("^[^%s]+%s", "")  -- Remove icon
          vim.notify(g.ui.check .. " Project moved to " .. dest_display, vim.log.levels.INFO)
        else
          vim.notify(g.ui.cross .. " Failed to move project", vim.log.levels.ERROR)
        end
        
        if on_done then on_done() end
      end,
    },
  })
end

local function project_actions_menu(proj_info, on_done)
  if not have_fzf() then
    vim.notify("fzf-lua is required for project management", vim.log.levels.WARN)
    return
  end

  local fzf = require("fzf-lua")
  local actions = { "Open", "Refile", "Archive", "Delete", "Open ZK", "Stats", "Cancel" }
  local title = proj_info.title or vim.fn.fnamemodify(proj_info.path, ":t")

  fzf.fzf_exec(actions, {
    prompt = shared.colorize(g.container.projects, "project") .. " Project Action> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index", ["--ansi"] = true },
    winopts = {
      height = 0.30,
      width = 0.50,
      row = 0.10,
      title = string.format("%s (%d%s %d%s %d%s)",
        title, proj_info.next_actions, g.state.NEXT, proj_info.todo_tasks, g.state.TODO, proj_info.waiting_tasks, g.state.WAITING),
      title_pos = "center",
    },
    actions = {
      ["default"] = function(sel)
        local action = sel and sel[1]
        if not action then return end

        if action == "Open" then
          vim.cmd("edit " .. vim.fn.fnameescape(proj_info.path))

        elseif action == "Refile" then
          refile_project(proj_info.path, on_done)

        elseif action == "Archive" then
          ui.select({ "Yes, archive project", "Cancel" },
            { prompt = "Archive this entire project?" },
            function(choice)
              if choice and choice:match("Yes") then
                if archive_whole_project_file(proj_info.path, { zk_action = "move" }) then
                  vim.notify(g.container.someday .. " Project archived successfully", vim.log.levels.INFO)
                else
                  vim.notify(g.ui.cross .. " Failed to archive project", vim.log.levels.ERROR)
                end
                if on_done then on_done() end
              end
            end)

        elseif action == "Delete" then
          ui.select({ "Yes, delete permanently", "Cancel" },
            { prompt = "⚠️  Really delete this project file?" },
            function(choice)
              if choice and choice:match("Yes") then
                local P = paths()
                local ok, _ = move_or_delete_file(proj_info.path, false, P.deldir)
                if ok then
                  vim.notify("🗑️  Project moved to ArchiveDeleted", vim.log.levels.INFO)
                else
                  vim.notify("❌ Failed to delete project", vim.log.levels.ERROR)
                end
                if on_done then on_done() end
              end
            end)

        elseif action == "Open ZK" then
          local L = readf(proj_info.path)
          for _, ln in ipairs(L) do
            local zk = ln:match(":ZK_NOTE:%s*%[%[file:(.-)%]%]") or
                      ln:match("^%s*Notes:%s*%[%[file:(.-)%]%]")
            if zk then
              vim.cmd("edit " .. vim.fn.fnameescape(xp(zk)))
              return
            end
          end
          vim.notify("No ZK note found in project", vim.log.levels.INFO)
          if on_done then on_done() end

        elseif action == "Stats" then
          local stats = {
            string.format("%s Project: %s", g.container.projects, proj_info.title or vim.fn.fnamemodify(proj_info.path, ":t:r")),
            string.format("%s Headings: %d", g.ui.list, proj_info.headings),
            string.format("%s Next Actions: %d", g.state.NEXT, proj_info.next_actions),
            string.format("%s TODO Tasks: %d", g.state.TODO, proj_info.todo_tasks),
            string.format("%s Waiting Tasks: %d", g.state.WAITING, proj_info.waiting_tasks),
            string.format("%s Done Tasks: %d", g.state.DONE, proj_info.done_tasks),
          }

          if proj_info.earliest_deadline then
            table.insert(stats, string.format("%s Earliest Deadline: %s", g.ui.warning, proj_info.earliest_deadline))
          end

          table.insert(stats, string.format("%s File: %s", g.file.org, vim.fn.fnamemodify(proj_info.path, ":~:.")))
          table.insert(stats, string.format("%s Modified: %s", g.container.calendar, os.date("%Y-%m-%d %H:%M", proj_info.last_modified)))

          vim.notify(table.concat(stats, "\n"), vim.log.levels.INFO, { title = "Project Stats" })
          if on_done then on_done() end

        else
          if on_done then on_done() end
        end
      end,
    },
  })
end

-- ------------------------ Enhanced Pickers ------------------------
local function manage_tasks_picker()
  if not have_fzf() then
    vim.notify("fzf-lua is required for task management", vim.log.levels.WARN)
    return
  end

  local fzf = require("fzf-lua")
  local all_items = scan_all_tasks()

  -- Filter tasks vs projects
  local tasks = {}
  for _, item in ipairs(all_items) do
    if item.kind == "task" then
      table.insert(tasks, item)
    end
  end

  if #tasks == 0 then
    vim.notify("No tasks found in GTD system", vim.log.levels.INFO)
    return
  end

  -- Apply archive filter if configured (only Archive.org; ArchiveDeleted is already skipped)
  if not M.cfg.show_archive_tasks then
    tasks = vim.tbl_filter(function(t)
      local filename = vim.fn.fnamemodify(t.path, ":t")
      return filename ~= M.cfg.archive_file
    end, tasks)
  end

  sort_items_gtd_workflow(tasks)

  local display = {}
  for _, item in ipairs(tasks) do
    table.insert(display, format_task_display(item))
  end

  fzf.fzf_exec(display, {
    prompt = shared.colorize(g.ui.list, "info") .. " Manage Tasks> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index", ["--ansi"] = true },
    winopts = { height = 0.60, width = 0.85, row = 0.10 },
    actions = {
      ["default"] = function(sel)
        local choice = sel and sel[1]
        if not choice then return end
        local idx = vim.fn.index(display, choice) + 1
        local item = tasks[idx]
        if not item then return end

        task_actions_menu(item, function()
          vim.schedule(function() manage_tasks_picker() end)
        end)
      end,
      ["ctrl-e"] = function(sel)
        local choice = sel and sel[1]
        if not choice then return end
        local idx = vim.fn.index(display, choice) + 1
        local item = tasks[idx]
        if not item then return end

        -- Quick edit mode - open file and return to picker on exit
        vim.cmd("edit " .. vim.fn.fnameescape(item.path))
        vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })

        -- Set up autocmd to return to tasks picker when buffer is closed
        local group = vim.api.nvim_create_augroup("GtdQuickEdit", { clear = false })
        vim.api.nvim_create_autocmd({ "BufWinLeave", "BufDelete" }, {
          group = group,
          buffer = vim.api.nvim_get_current_buf(),
          once = true,
          callback = function()
            vim.schedule(function()
              manage_tasks_picker()
            end)
          end,
        })
      end,
    },
  })
end

local function manage_projects_picker()
  if not have_fzf() then
    vim.notify("fzf-lua is required for project management", vim.log.levels.WARN)
    return
  end

  local fzf = require("fzf-lua")
  local projects = list_project_files()

  if #projects == 0 then
    vim.notify("No project files found", vim.log.levels.INFO)
    return
  end

  -- Apply GTD workflow sorting
  sort_projects_gtd_workflow(projects)

  local display = {}
  for _, proj in ipairs(projects) do
    local name = proj.title or vim.fn.fnamemodify(proj.path, ":t:r")
    local status_parts = {}

    -- Priority indicator based on activity
    local priority_icon = g.progress.inactive -- Default: inactive
    if proj.next_actions > 0 then
      priority_icon = g.progress.urgent -- High: has next actions
    elseif proj.todo_tasks > 0 then
      priority_icon = g.progress.pending -- Medium: has todos
    elseif proj.tasks > 0 then
      priority_icon = g.progress.blocked -- Low: has waiting/someday
    end

    -- Build status info
    if proj.next_actions > 0 then
      table.insert(status_parts, proj.next_actions .. g.state.NEXT)
    end
    if proj.todo_tasks > 0 then
      table.insert(status_parts, proj.todo_tasks .. g.state.TODO)
    end
    if proj.waiting_tasks > 0 then
      table.insert(status_parts, proj.waiting_tasks .. g.state.WAITING)
    end

    local status_info = #status_parts > 0 and (" [" .. table.concat(status_parts, " ") .. "]") or ""

    -- Deadline indicator
    local deadline_info = proj.earliest_deadline and (" " .. g.ui.warning .. proj.earliest_deadline) or ""

    -- Show area context for files under Areas/… (without breaking old behavior)
    local dirname  = vim.fn.fnamemodify(proj.path, ":h:t")
    local grand    = vim.fn.fnamemodify(proj.path, ":h:h:t")
    local label_name = name
    if grand == M.cfg.areas_dir then
      label_name = string.format("%s › %s", dirname, name)
    end

    table.insert(display, string.format("%s %s %s%s%s",
      priority_icon, g.container.projects, label_name, status_info, deadline_info))
  end

  fzf.fzf_exec(display, {
    prompt = shared.colorize(g.container.projects, "project") .. " Manage Projects> ",
    fzf_opts = {
      ["--no-info"] = true,
      ["--tiebreak"] = "index",
      ["--ansi"] = true,
      ["--header"] = "Enter: Actions • Ctrl-e: Edit • Ctrl-r: Refile • Ctrl-a: Archive • Ctrl-d: Delete",
    },
    winopts = { height = 0.55, width = 0.75, row = 0.15 },
    actions = {
      ["default"] = function(sel)
        local choice = sel and sel[1]
        if not choice then return end
        local idx = vim.fn.index(display, choice) + 1
        local proj = projects[idx]
        if not proj then return end

        project_actions_menu(proj, function()
          vim.schedule(function() manage_projects_picker() end)
        end)
      end,
      ["ctrl-e"] = function(sel)
        local choice = sel and sel[1]
        if not choice then return end
        local idx = vim.fn.index(display, choice) + 1
        local proj = projects[idx]
        if not proj then return end

        -- Quick edit mode - open project file and return to picker on exit
        vim.cmd("edit " .. vim.fn.fnameescape(proj.path))

        -- Set up autocmd to return to projects picker when buffer is closed
        local group = vim.api.nvim_create_augroup("GtdQuickEditProject", { clear = false })
        vim.api.nvim_create_autocmd({ "BufWinLeave", "BufDelete" }, {
          group = group,
          buffer = vim.api.nvim_get_current_buf(),
          once = true,
          callback = function()
            vim.schedule(function()
              manage_projects_picker()
            end)
          end,
        })
      end,
      ["ctrl-a"] = function(sel)
        local choice = sel and sel[1]
        if not choice then return end
        local idx = vim.fn.index(display, choice) + 1
        local proj = projects[idx]
        if not proj then return end

        local proj_name = proj.title or vim.fn.fnamemodify(proj.path, ":t:r")
        ui.select({ "Yes, archive project + ZK notes", "Cancel" },
          { prompt = g.container.someday .. " Archive '" .. proj_name .. "' and linked ZK notes?" },
          function(confirm)
            if confirm and confirm:match("Yes") then
              if archive_whole_project_file(proj.path, { zk_action = "move" }) then
                vim.notify(g.state.DONE .. " Project and ZK notes archived: " .. proj_name, vim.log.levels.INFO)
              else
                vim.notify(g.ui.cross .. " Failed to archive project", vim.log.levels.ERROR)
              end
              vim.schedule(function() manage_projects_picker() end)
            end
          end)
      end,
      ["ctrl-d"] = function(sel)
        local choice = sel and sel[1]
        if not choice then return end
        local idx = vim.fn.index(display, choice) + 1
        local proj = projects[idx]
        if not proj then return end

        local proj_name = proj.title or vim.fn.fnamemodify(proj.path, ":t:r")
        ui.select({ "Yes, delete project + ZK notes", "Yes, delete project only", "Cancel" },
          { prompt = g.ui.warning .. " Delete '" .. proj_name .. "'?" },
          function(confirm)
            if not confirm or confirm == "Cancel" then return end

            local P = paths()
            local delete_zk = confirm:match("ZK notes")

            -- Collect ZK notes before moving project
            local zk_files = {}
            if delete_zk then
              local L = readf(proj.path)
              for _, ln in ipairs(L) do
                local p = ln:match(":ZK_NOTE:%s*%[%[file:(.-)%]%]") or
                         ln:match("^%s*Notes:%s*%[%[file:(.-)%]%]")
                if p then zk_files[xp(p)] = true end
              end
            end

            -- Move project file to ArchiveDeleted
            local ok, dst = move_or_delete_file(proj.path, false, P.deldir)
            if ok then
              -- Handle ZK notes
              local zk_count = 0
              for zk, _ in pairs(zk_files) do
                if vim.fn.filereadable(zk) == 1 then
                  archive_or_delete_zk(zk, "delete")
                  zk_count = zk_count + 1
                end
              end

              local msg = g.container.trash .. " Project moved to ArchiveDeleted: " .. proj_name
              if zk_count > 0 then
                msg = msg .. " (" .. zk_count .. " ZK notes deleted)"
              end
              vim.notify(msg, vim.log.levels.INFO)
            else
              vim.notify(g.ui.cross .. " Failed to delete project", vim.log.levels.ERROR)
            end
            vim.schedule(function() manage_projects_picker() end)
          end)
      end,
      ["ctrl-r"] = function(sel)
        local choice = sel and sel[1]
        if not choice then return end
        local idx = vim.fn.index(display, choice) + 1
        local proj = projects[idx]
        if not proj then return end

        refile_project(proj.path, function()
          vim.schedule(function() manage_projects_picker() end)
        end)
      end,
    },
  })
end

-- ------------------------ Public API ------------------------
function M.manage_tasks()
  manage_tasks_picker()
end

function M.manage_projects()
  manage_projects_picker()
end

-- Convenience functions for specific actions
function M.archive_task_at_cursor(opts)
  opts = opts or {}
  local path = vim.api.nvim_buf_get_name(0)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]

  if not path:match("%.org$") then
    vim.notify("Not in an org file", vim.log.levels.WARN)
    return
  end

  local items = scan_all_tasks()

  -- Find task at cursor
  for _, item in ipairs(items) do
    if item.path == path and item.lnum <= lnum and lnum <= item.hend then
      local P = paths()
      if archive_subtree_to_file(item.path, item.hstart, item.hend, P.archive, "task") then
        remove_subtree_from_file(item.path, item.hstart, item.hend)
        archive_or_delete_zk(item.zk_path, "move")
        vim.notify(g.state.DONE .. " Task archived from cursor position", vim.log.levels.INFO)
      else
        vim.notify(g.ui.cross .. " Failed to archive task", vim.log.levels.ERROR)
      end
      return
    end
  end

  vim.notify("No task found at cursor position", vim.log.levels.WARN)
end

function M.delete_task_at_cursor(opts)
  opts = opts or {}
  local path = vim.api.nvim_buf_get_name(0)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]

  if not path:match("%.org$") then
    vim.notify("Not in an org file", vim.log.levels.WARN)
    return
  end

  local items = scan_all_tasks()

  -- Find task at cursor
  for _, item in ipairs(items) do
    if item.path == path and item.lnum <= lnum and lnum <= item.hend then
      ui.select({ "Yes, delete permanently", "Cancel" },
        { prompt = "⚠️  Really delete this task permanently?" },
        function(choice)
          if choice and choice:match("Yes") then
            if remove_subtree_from_file(item.path, item.hstart, item.hend) then
              archive_or_delete_zk(item.zk_path, "delete")
              vim.notify("🗑️  Task deleted permanently", vim.log.levels.INFO)
            else
              vim.notify("❌ Failed to delete task", vim.log.levels.ERROR)
            end
          end
        end)
      return
    end
  end

  vim.notify("No task found at cursor position", vim.log.levels.WARN)
end

-- Help menu for available management commands
function M.help_menu()
  if not have_fzf() then
    vim.notify("fzf-lua is required", vim.log.levels.WARN)
    return
  end

  local fzf = require("fzf-lua")
  local help_items = {
    g.state.TODO .. " Manage Tasks - Browse and manage all tasks",
    g.container.projects .. " Manage Projects - Browse and manage project files",
    g.container.someday .. " Archive Task at Cursor - Archive the task under cursor",
    g.container.trash .. " Delete Task at Cursor - Delete the task under cursor",
    g.ui.cross .. " Cancel",
  }

  fzf.fzf_exec(help_items, {
    prompt = shared.colorize(g.phase.organize, "accent") .. " GTD Management (C-b=Back)> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index", ["--ansi"] = true },
    winopts = { height = 0.30, width = 0.60, row = 0.10 },
    actions = {
      ["default"] = function(sel)
        local choice = sel and sel[1]
        if not choice then return end

        if choice:match("Manage Tasks") then
          M.manage_tasks()
        elseif choice:match("Manage Projects") then
          M.manage_projects()
        elseif choice:match("Archive Task at Cursor") then
          M.archive_task_at_cursor({})
        elseif choice:match("Delete Task at Cursor") then
          M.delete_task_at_cursor({})
        end
      end,
      ["ctrl-b"] = function(_)
        vim.schedule(function()
          local lists = safe_require("gtd-nvim.gtd.lists")
          if lists and lists.menu then lists.menu() end
        end)
      end,
    },
  })
end

-- ------------------------ Setup & Commands ------------------------
function M.setup(user_cfg)
  if user_cfg then
    M.cfg = vim.tbl_deep_extend("force", M.cfg, user_cfg)
  end

  local P = paths()

  -- Ensure required directories exist
  ensure_dir(P.archive)
  ensure_dir(j(P.deldir, "dummy"))
  ensure_dir(j(P.zk_arch, "dummy"))

  -- Create user commands
  vim.api.nvim_create_user_command("GtdManage", function()
    M.help_menu()
  end, { desc = "GTD Management menu" })

  vim.api.nvim_create_user_command("GtdManageTasks", function()
    M.manage_tasks()
  end, { desc = "Manage GTD tasks" })

  vim.api.nvim_create_user_command("GtdManageProjects", function()
    M.manage_projects()
  end, { desc = "Manage GTD projects" })

  vim.api.nvim_create_user_command("GtdArchiveTask", function()
    M.archive_task_at_cursor({})
  end, { desc = "Archive task at cursor" })

  vim.api.nvim_create_user_command("GtdDeleteTask", function()
    M.delete_task_at_cursor({})
  end, { desc = "Delete task at cursor" })
end

return M