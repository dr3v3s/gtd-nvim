-- ~/.config/nvim/lua/gtd/manage.lua
-- Manage tasks & projects with enhanced GTD workflow integration
-- - Scan .org files for tasks/projects with full metadata
-- - Present rich fzf-lua action menus: Open / Clarify / Archive / Delete / Refile / Open ZK
-- - Smart sorting: NEXT → TODO → WAITING → SOMEDAY → others
-- - Archive entries shown separately with clear indicators
-- - Persistent pickers that refresh after mutations
-- - Full integration with clarify, organize, and ZK systems

local M = {}

-- ------------------------ Config ------------------------
M.cfg = {
  gtd_root            = "~/Documents/GTD",
  projects_dir        = "Projects",       -- under gtd_root
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
local ui = require("gtd.ui")
local task_id = require("gtd.utils.task_id")

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local clarify = safe_require("gtd.clarify")
local organize = safe_require("gtd.organize")

-- ------------------------ Helpers ------------------------
local function xp(p) return vim.fn.expand(p) end
local function j(a,b) return (a:gsub("/+$","")).."/"..(b:gsub("^/+","")) end
local function ensure_dir(path) vim.fn.mkdir(vim.fn.fnamemodify(path, ":p:h"), "p"); return path end
local function readf(path) if vim.fn.filereadable(path)==1 then return vim.fn.readfile(path) else return {} end end
local function writef(path, L) ensure_dir(path); return vim.fn.writefile(L, path) == 0 end
local function appendf(path, L) ensure_dir(path); vim.fn.writefile({""}, path, "a"); return vim.fn.writefile(L, path, "a") == 0 end
local function now() return os.date(M.cfg.date_format) end
local function have_fzf() return pcall(require, "fzf-lua") end

local function truncate_title(title, max_len)
  max_len = max_len or M.cfg.max_title_length
  if not title or #title <= max_len then return title or "" end
  return title:sub(1, max_len - 3) .. "..."
end

local function paths()
  local root = xp(M.cfg.gtd_root)
  return {
    root     = root,
    inbox    = j(root, M.cfg.inbox_file),
    archive  = j(root, M.cfg.archive_file),
    projdir  = j(root, M.cfg.projects_dir),
    deldir   = j(root, M.cfg.archive_deleted_dir),
    zk_root  = xp(M.cfg.zk_root),
    zk_arch  = j(xp(M.cfg.zk_root), M.cfg.zk_archive_dir),
  }
end

-- ------------------------ Org Helpers ------------------------
local function is_heading(ln) return ln:match("^%*+%s") ~= nil end
local function heading_level(ln) local s=ln:match("^(%*+)%s"); return s and #s or nil end

local function subtree_range(lines, hstart)
  local head = lines[hstart]; if not head then return nil end
  local lvl = heading_level(head) or 1
  local i = hstart + 1
  while i <= #lines do
    local lv2 = heading_level(lines[i] or "")
    if lv2 and lv2 <= lvl then break end
    i = i + 1
  end
  return hstart, i-1
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
  -- Look for ZK_NOTE property first
  local zk_prop = get_property(lines, hstart, hend, "ZK_NOTE")
  if zk_prop then
    local p = zk_prop:match("%[%[file:(.-)%]%]") or zk_prop:match("^file:(.+)")
    if p then return xp(p) end
  end
  
  -- Look for body links
  for i = hstart, hend do
    local p = (lines[i] or ""):match("^%s*Notes:%s*%[%[file:(.-)%]%]")
    if p and p ~= "" then return xp(p) end
    
    -- Also check for ZK ID links
    local zkid = (lines[i] or ""):match("ID::%s*%[%[zk:(%w+)%]%]")
    if zkid then
      -- This is a ZK ID link, could potentially resolve to file path
      -- For now, we'll note that it exists but can't directly open
      -- TODO: Could integrate with ZK system to resolve ID to path
    end
  end
  return nil
end

-- ------------------------ Enhanced Scanners ------------------------
local function scan_all_tasks()
  local P = paths()
  local files = vim.fn.globpath(P.root, "**/*.org", false, true)
  table.sort(files)
  local items = {}
  
  for _, path in ipairs(files) do
    local lines = readf(path)
    for i, ln in ipairs(lines) do
      if is_heading(ln) then
        local hstart, hend = subtree_range(lines, i)
        if not hstart or not hend then goto continue end
        
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
        
        local from_archive = (vim.fn.fnamemodify(path, ":t") == M.cfg.archive_file)
        
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
          zk_path = zk,
          task_id = task_id_val,
          scheduled = scheduled,
          deadline = deadline,
          effort = effort,
          assigned = assigned,
          tags = tags,
          -- Keep from_archive for backward compatibility but use file-based priority
          from_archive = from_archive,
        })
        
        ::continue::
      end
    end
  end
  return items
end

local function list_project_files()
  local P = paths()
  local files = vim.fn.globpath(P.projdir, "*.org", false, true)
  table.sort(files)
  
  -- Enhanced project file metadata with detailed task analysis
  local enhanced = {}
  for _, path in ipairs(files) do
    local lines = readf(path)
    local first_heading = nil
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
        if not first_heading then
          first_heading = ln
          local _, title = parse_state_title(ln)
          project_info.title = title
        end
        
        -- Analyze task states and dates
        local hstart, hend = subtree_range(lines, i)
        if hstart and hend then
          local state = select(1, parse_state_title(ln))
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
    
    table.insert(enhanced, project_info)
  end
  
  return enhanced
end

-- GTD Project Sorting: Active projects first, then by urgency
local function sort_projects_gtd_workflow(projects)
  table.sort(projects, function(a, b)
    -- Projects with NEXT actions get highest priority
    if a.next_actions ~= b.next_actions then
      return a.next_actions > b.next_actions
    end
    
    -- Projects with deadlines come before those without
    if a.has_deadlines ~= b.has_deadlines then
      return a.has_deadlines
    end
    
    -- Among projects with deadlines, sort by earliest deadline
    if a.earliest_deadline and b.earliest_deadline then
      return a.earliest_deadline < b.earliest_deadline
    end
    
    -- Projects with more active tasks (TODO) come first
    if a.todo_tasks ~= b.todo_tasks then
      return a.todo_tasks > b.todo_tasks
    end
    
    -- Projects with any active tasks come before inactive ones
    if a.tasks ~= b.tasks then
      return a.tasks > b.tasks
    end
    
    -- Recently modified projects first
    if a.last_modified ~= b.last_modified then
      return a.last_modified > b.last_modified
    end
    
    -- Finally, alphabetical by title
    local title_a = a.title or vim.fn.fnamemodify(a.path, ":t:r")
    local title_b = b.title or vim.fn.fnamemodify(b.path, ":t:r")
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
  local dirname = vim.fn.fnamemodify(item.path, ":h:t")
  
  -- Inbox gets highest priority
  if filename == M.cfg.inbox_file then
    return 1
  end
  
  -- Projects directory gets second priority
  if dirname == M.cfg.projects_dir then
    return 2
  end
  
  -- Archive gets lowest priority
  if filename == M.cfg.archive_file then
    return 4
  end
  
  -- Everything else gets middle priority
  return 3
end

local function sort_items_gtd_workflow(items)
  table.sort(items, function(a, b)
    -- First by file/location priority (Inbox → Projects → Others → Archive)
    local file_pa, file_pb = get_file_priority(a), get_file_priority(b)
    if file_pa ~= file_pb then return file_pa < file_pb end
    
    -- Then by state priority within same file type
    local state_pa, state_pb = get_state_priority(a.state), get_state_priority(b.state)
    if state_pa ~= state_pb then return state_pa < state_pb end
    
    -- Then by deadline (sooner first)
    if a.deadline and b.deadline then
      return a.deadline < b.deadline
    elseif a.deadline then return true
    elseif b.deadline then return false
    end
    
    -- Then by title
    local ta, tb = a.title or "", b.title or ""
    if ta ~= tb then return ta < tb end
    
    -- Finally by line number within same file
    return (a.lnum or 0) < (b.lnum or 0)
  end)
end

-- ------------------------ Enhanced Display Formatting ------------------------
local function format_task_display(item)
  local parts = {}
  
  -- File indicator with clear priority
  local filename = vim.fn.fnamemodify(item.path, ":t")
  local dirname = vim.fn.fnamemodify(item.path, ":h:t")
  local file_indicator = ""
  
  if filename == M.cfg.inbox_file then
    file_indicator = "📥 Inbox"
  elseif dirname == M.cfg.projects_dir then
    file_indicator = "📂 " .. vim.fn.fnamemodify(item.path, ":t:r")
  elseif filename == M.cfg.archive_file then
    file_indicator = "📦 Archive"
  else
    file_indicator = "📄 " .. vim.fn.fnamemodify(item.path, ":t:r")
  end
  
  -- State indicator
  local state_icon = ""
  if item.state == "NEXT" then state_icon = "⚡"
  elseif item.state == "TODO" then state_icon = "📋"
  elseif item.state == "WAITING" then state_icon = "⏳"
  elseif item.state == "SOMEDAY" then state_icon = "💭"
  elseif item.state == "DONE" then state_icon = "✅"
  end
  
  -- Title with truncation
  local title = truncate_title(item.title or item.line or "")
  
  -- Date indicators
  local date_info = ""
  if item.deadline then
    date_info = " 🎯" .. item.deadline
  elseif item.scheduled then
    date_info = " 📅" .. item.scheduled
  end
  
  -- ZK indicator
  local zk_indicator = item.zk_path and " 🧠" or ""
  
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
      vim.notify("⚠️  Failed to delete ZK note: " .. zk_path, vim.log.levels.WARN)
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

-- ------------------------ Enhanced Action Menus ------------------------
local function task_actions_menu(item, on_done)
  if not have_fzf() then
    vim.notify("fzf-lua is required for task management", vim.log.levels.WARN)
    return
  end
  
  local fzf = require("fzf-lua")
  local actions = { "Open", "Clarify", "Archive", "Delete", "Refile", "Open ZK", "Cancel" }
  
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
  
  local title_display = format_task_display(item)
  
  fzf.fzf_exec(actions, {
    prompt = "Task Action> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
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
          
        elseif action == "Archive" then
          local P = paths()
          if archive_subtree_to_file(item.path, item.hstart, item.hend, P.archive, "task") then
            remove_subtree_from_file(item.path, item.hstart, item.hend)
            archive_or_delete_zk(item.zk_path, "move")
            vim.notify("✅ Task archived successfully", vim.log.levels.INFO)
          else
            vim.notify("❌ Failed to archive task", vim.log.levels.ERROR)
          end
          if on_done then on_done() end
          
        elseif action == "Delete" then
          ui.select({"Yes, delete permanently", "Cancel"}, 
            { prompt = "⚠️  Really delete this task?" }, 
            function(choice)
              if choice and choice:match("Yes") then
                if remove_subtree_from_file(item.path, item.hstart, item.hend) then
                  archive_or_delete_zk(item.zk_path, "delete")
                  vim.notify("🗑️  Task deleted permanently", vim.log.levels.INFO)
                else
                  vim.notify("❌ Failed to delete task", vim.log.levels.ERROR)
                end
                if on_done then on_done() end
              end
            end)
            
        elseif action == "Refile" and organize then
          vim.cmd("edit " .. vim.fn.fnameescape(item.path))
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
          organize.refile_at_cursor({})
          
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

local function project_actions_menu(proj_info, on_done)
  if not have_fzf() then
    vim.notify("fzf-lua is required for project management", vim.log.levels.WARN)
    return
  end
  
  local fzf = require("fzf-lua")
  local actions = { "Open", "Archive", "Delete", "Open ZK", "Stats", "Cancel" }
  local title = proj_info.title or vim.fn.fnamemodify(proj_info.path, ":t")
  
  fzf.fzf_exec(actions, {
    prompt = "Project Action> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    winopts = { 
      height = 0.30, 
      width = 0.50, 
      row = 0.10,
      title = string.format("%s (%d⚡ %d📋 %d⏳)", 
        title, proj_info.next_actions, proj_info.todo_tasks, proj_info.waiting_tasks),
      title_pos = "center",
    },
    actions = {
      ["default"] = function(sel)
        local action = sel and sel[1]
        if not action then return end
        
        if action == "Open" then
          vim.cmd("edit " .. vim.fn.fnameescape(proj_info.path))
          
        elseif action == "Archive" then
          ui.select({"Yes, archive project", "Cancel"}, 
            { prompt = "Archive this entire project?" },
            function(choice)
              if choice and choice:match("Yes") then
                if archive_whole_project_file(proj_info.path, { zk_action = "move" }) then
                  vim.notify("📦 Project archived successfully", vim.log.levels.INFO)
                else
                  vim.notify("❌ Failed to archive project", vim.log.levels.ERROR)
                end
                if on_done then on_done() end
              end
            end)
            
        elseif action == "Delete" then
          ui.select({"Yes, delete permanently", "Cancel"}, 
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
            string.format("📂 Project: %s", proj_info.title or vim.fn.fnamemodify(proj_info.path, ":t:r")),
            string.format("📊 Headings: %d", proj_info.headings),
            string.format("⚡ Next Actions: %d", proj_info.next_actions),
            string.format("📋 TODO Tasks: %d", proj_info.todo_tasks), 
            string.format("⏳ Waiting Tasks: %d", proj_info.waiting_tasks),
            string.format("✅ Done Tasks: %d", proj_info.done_tasks),
          }
          
          if proj_info.earliest_deadline then
            table.insert(stats, string.format("🎯 Earliest Deadline: %s", proj_info.earliest_deadline))
          end
          
          table.insert(stats, string.format("📁 File: %s", vim.fn.fnamemodify(proj_info.path, ":~:.")))
          table.insert(stats, string.format("📅 Modified: %s", os.date("%Y-%m-%d %H:%M", proj_info.last_modified)))
          
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
  
  -- Apply archive filter if configured
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
    prompt = "Manage Tasks> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
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
        vim.api.nvim_create_autocmd({"BufWinLeave", "BufDelete"}, {
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
    local priority_icon = "🟢" -- Default: inactive
    if proj.next_actions > 0 then
      priority_icon = "🔴" -- High: has next actions
    elseif proj.todo_tasks > 0 then
      priority_icon = "🟡" -- Medium: has todos
    elseif proj.tasks > 0 then
      priority_icon = "🟠" -- Low: has waiting/someday
    end
    
    -- Build status info
    if proj.next_actions > 0 then
      table.insert(status_parts, proj.next_actions .. "⚡")
    end
    if proj.todo_tasks > 0 then
      table.insert(status_parts, proj.todo_tasks .. "📋")
    end
    if proj.waiting_tasks > 0 then
      table.insert(status_parts, proj.waiting_tasks .. "⏳")
    end
    
    local status_info = #status_parts > 0 and (" [" .. table.concat(status_parts, " ") .. "]") or ""
    
    -- Deadline indicator
    local deadline_info = proj.earliest_deadline and (" 🎯" .. proj.earliest_deadline) or ""
    
    table.insert(display, string.format("%s 📂 %s%s%s", 
      priority_icon, name, status_info, deadline_info))
  end
  
  fzf.fzf_exec(display, {
    prompt = "Manage Projects> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
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
        vim.api.nvim_create_autocmd({"BufWinLeave", "BufDelete"}, {
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
    },
  })
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
  
  -- Move project file to archive directory
  local ok, dst = move_or_delete_file(proj_path, opts.delete, P.deldir)
  return ok
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
  
  local lines = readf(path)
  local items = scan_all_tasks()
  
  -- Find task at cursor
  for _, item in ipairs(items) do
    if item.path == path and item.lnum <= lnum and lnum <= item.hend then
      local P = paths()
      if archive_subtree_to_file(item.path, item.hstart, item.hend, P.archive, "task") then
        remove_subtree_from_file(item.path, item.hstart, item.hend)
        archive_or_delete_zk(item.zk_path, "move")
        vim.notify("✅ Task archived from cursor position", vim.log.levels.INFO)
      else
        vim.notify("❌ Failed to archive task", vim.log.levels.ERROR)
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
      ui.select({"Yes, delete permanently", "Cancel"}, 
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
    "📋 Manage Tasks - Browse and manage all tasks",
    "📂 Manage Projects - Browse and manage project files", 
    "📦 Archive Task at Cursor - Archive the task under cursor",
    "🗑️  Delete Task at Cursor - Delete the task under cursor",
    "❌ Cancel",
  }
  
  fzf.fzf_exec(help_items, {
    prompt = "GTD Management> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
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