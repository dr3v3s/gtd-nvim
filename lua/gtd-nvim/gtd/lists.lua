-- Enhanced GTD Lists: Next Actions, Projects, Someday/Maybe, Waiting with rich context & search
-- Enhanced WAITING FOR support with full metadata display and management
-- RECURRING TASKS: View and manage recurring tasks with due date tracking
-- Focused on actionable items - DONE and ARCHIVED have dedicated views

local M = {}

-- Load shared utilities with glyph system
local shared = require("gtd-nvim.gtd.shared")
local g = shared.glyphs  -- Glyph shortcuts

-- ---------------------------- Config ----------------------------
M.cfg = {
  gtd_root     = "~/Documents/GTD",
  inbox_file   = "Inbox.org",
  projects_dir = "Projects",
  archive_file = "Archive.org",
  zk_root      = "~/Documents/Notes",
  
  -- WAITING display options
  waiting_display = {
    show_overdue     = true,  -- Highlight overdue follow-ups
    show_priority    = true,  -- Show priority indicators
    show_context     = true,  -- Show request context
    days_overdue_warn = 3,    -- Days past follow-up to show warning
  }
}

-- ---------------------------- Helpers ---------------------------
local function xp(p) return vim.fn.expand(p) end
local function j(a,b) return (a:gsub("/+$","")).."/"..(b:gsub("^/+","")) end
local function readf(path) if vim.fn.filereadable(path)==1 then return vim.fn.readfile(path) else return {} end end
local function is_heading(ln) return ln:match("^%*+%s") ~= nil end
local function hlevel(ln) local s=ln:match("^(%*+)%s"); return s and #s or nil end
local function trim(s) return (s or ""):gsub("^%s+",""):gsub("%s+$","") end
local function safe_require(name) local ok, m = pcall(require, name); return ok and m or nil end

-- ✅ Load GTD v2.0 utilities
local task_id = safe_require("gtd-nvim.gtd.utils.task_id")
local org_dates = safe_require("gtd-nvim.gtd.utils.org_dates")
local clarify = safe_require("gtd-nvim.gtd.clarify")
local areas_mod = safe_require("gtd-nvim.gtd.areas")

-- Date helpers for WAITING support
local function parse_date(date_str)
  if not date_str or date_str == "" then return nil end
  local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if year and month and day then
    return os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
  end
  return nil
end

local function days_until(date_str)
  local target_time = parse_date(date_str)
  if not target_time then return nil end
  local now = os.time()
  local diff = target_time - now
  return math.floor(diff / (24 * 60 * 60))
end

local function is_overdue(date_str, grace_days)
  local days = days_until(date_str)
  if not days then return false end
  return days < -(grace_days or 0)
end

local function format_days_until(date_str)
  local days = days_until(date_str)
  if not days then return "" end
  if days < 0 then
    return string.format("(%d days ago)", math.abs(days))
  elseif days == 0 then
    return "(today)"
  elseif days == 1 then
    return "(tomorrow)"
  else
    return string.format("(%d days)", days)
  end
end

local function paths()
  local root = xp(M.cfg.gtd_root)
  return {
    root = root,
    inbox = j(root, M.cfg.inbox_file),
    archive = j(root, M.cfg.archive_file),
    projdir = j(root, M.cfg.projects_dir),
  }
end

local function subtree_range(L, hstart)
  local head = L[hstart]; if not head then return nil end
  local lvl = hlevel(head) or 1
  local i = hstart + 1
  while i <= #L do
    local lv2 = hlevel(L[i] or "")
    if lv2 and lv2 <= lvl then break end
    i = i + 1
  end
  return hstart, i-1
end

local function parse_state_title(ln)
  local stars, rest = ln:match("^(%*+)%s+(.*)")
  if not rest then return nil, nil end
  local state, rest2 = rest:match("^(%u+)%s+(.*)")
  if state then return state, rest2 end
  return nil, rest
end

local function find_properties(L, s, e)
  s = s or 1; e = e or #L
  local ps, pe = nil, nil
  for i=s,e do
    if not ps and (L[i] or ""):match("^%s*:PROPERTIES:%s*$") then ps=i
    elseif ps and (L[i] or ""):match("^%s*:END:%s*$") then pe=i; break end
  end
  return ps, pe
end

local function prop_in(L, s, e, key)
  local ps, pe = find_properties(L, s, e)
  if not ps or not pe then return nil end
  for i=ps+1, pe-1 do
    local k, v = (L[i] or ""):match("^%s*:(%w+):%s*(.*)%s*$")
    if k and k:upper() == key:upper() then return v end
  end
  return nil
end

-- Enhanced WAITING properties extraction
local function extract_waiting_properties(L, s, e)
  local waiting_data = {}
  waiting_data.waiting_for = prop_in(L, s, e, "WAITING_FOR")
  waiting_data.waiting_what = prop_in(L, s, e, "WAITING_WHAT")
  waiting_data.requested_date = prop_in(L, s, e, "REQUESTED")
  waiting_data.follow_up_date = prop_in(L, s, e, "FOLLOW_UP")
  waiting_data.context = prop_in(L, s, e, "CONTEXT")
  waiting_data.priority = prop_in(L, s, e, "PRIORITY")
  waiting_data.notes = prop_in(L, s, e, "WAITING_NOTES")
  return waiting_data
end

local function find_dates_in_subtree(L, s, e)
  local scheduled, deadline
  for i=s, e do
    local ln = L[i] or ""
    local sch = ln:match("SCHEDULED:%s*<([^>]+)>")
    local ddl = ln:match("DEADLINE:%s*<([^>]+)>")
    if sch and not scheduled then scheduled = sch end
    if ddl and not deadline  then deadline  = ddl end
  end
  return scheduled, deadline
end

local function find_tags_on_heading(ln)
  local tags = {}
  local tagblock = ln:match("%s+:([%w_:%-]+):%s*$")
  if tagblock then
    for t in tagblock:gmatch("([^:]+)") do table.insert(tags, t) end
  end
  return tags
end

local function zk_path_in_subtree(L, s, e)
  local zk = prop_in(L, s, e, "ZK_NOTE")
  if zk then
    local p = zk:match("%[%[file:(.-)%]%]") or zk:match("^file:(.+)")
    if p then return xp(p) end
  end
  for i=s,e do
    local p = (L[i] or ""):match("^%s*Notes:%s*%[%[file:(.-)%]%]")
    if p and p ~= "" then return xp(p) end
  end
  return nil
end

local function checkbox_counts(L, s, e)
  local done, total = 0, 0
  for i=s,e do
    local ln = L[i] or ""
    local cb = ln:match("%[([ %-%/xX])%]")
    if cb then
      total = total + 1
      if cb:lower() == "x" then done = done + 1 end
    end
  end
  return done, total
end

local function todo_counts(L, s, e)
  local counts = {done=0, todo=0, next=0, waiting=0, someday=0, total=0}
  for i=s,e do
    local ln = L[i] or ""
    if is_heading(ln) then
      local st = select(1, parse_state_title(ln))
      if st then
        counts.total = counts.total + 1
        if st == "DONE" then counts.done = counts.done + 1
        elseif st == "NEXT" then counts.next = counts.next + 1
        elseif st == "TODO" then counts.todo = counts.todo + 1
        elseif st == "WAITING" then counts.waiting = counts.waiting + 1
        elseif st == "SOMEDAY" then counts.someday = counts.someday + 1 end
      end
    end
  end
  return counts
end

local function extract_context_from_path(path)
  local P = paths()
  if path == P.inbox then return "inbox"
  elseif path:find(P.archive, 1, true) then return "archive"
  elseif path:find(P.projdir, 1, true) then return "project"
  else return "gtd"
  end
end

-- ---------------------------- Scanner ----------------------------
local function scan_all_headings()
  local P = paths()
  local files = vim.fn.globpath(P.root, "**/*.org", false, true)
  table.sort(files)
  local out = {}
  
  for _,path in ipairs(files) do
    local L = readf(path)
    local context = extract_context_from_path(path)
    
    for i,ln in ipairs(L) do
      if is_heading(ln) then
        local s,e = subtree_range(L, i)
        local state, title = parse_state_title(ln)
        local lv = hlevel(ln) or 1
        local is_project = ln:match("^%*+%s+PROJECT%s") ~= nil
        local scheduled, deadline = find_dates_in_subtree(L, s, e)
        local tags = find_tags_on_heading(ln)
        local zk = zk_path_in_subtree(L, s, e)
        local cbdone, cbtotal = checkbox_counts(L, s, e)
        local effort = prop_in(L, s, e, "EFFORT") or prop_in(L, s, e, "Effort")
        local assigned = prop_in(L, s, e, "ASSIGNED") or prop_in(L, s, e, "Assigned")
        
        -- Extract WAITING metadata if this is a WAITING item
        local waiting_data = nil
        if state == "WAITING" then
          waiting_data = extract_waiting_properties(L, s, e)
        end
        
        -- Extract AREA property
        local area = prop_in(L, s, e, "AREA")
        
        -- Also try to infer area from file path if not set
        if not area then
          local area_match = path:match("/Areas/[%d%-]+([^/]+)/")
          if area_match then
            area = area_match
          end
        end
        
        table.insert(out, {
          path=path, lnum=i, s=s, e=e, line=ln,
          level=lv, state=state, title=title,
          project=is_project, scheduled=scheduled, deadline=deadline,
          tags=tags, zk=zk, cb={done=cbdone,total=cbtotal},
          effort=effort, assigned=assigned, context=context,
          waiting_data=waiting_data,
          area=area,
        })
      end
    end
  end
  return out
end

-- ---------------------------- Filters ----------------------------
-- Helper: check if item is completed or archived (not actionable)
local function is_completed(item)
  -- Check state OR context (items in Archive.org have context="archive")
  return item.state == "DONE" 
      or item.state == "ARCHIVED" 
      or item.context == "archive"
end

local function is_next_action(item, L)
  if item.project then return false end
  if is_completed(item) then return false end  -- Exclude DONE/ARCHIVED
  if item.state == "NEXT" then return true end
  if item.state == "TODO" then
    -- Check if it's a leaf (no sub-headings)
    local i = item.lnum + 1
    while i <= #L do
      local ln = L[i] or ""
      if is_heading(ln) then
        local lv = hlevel(ln) or 1
        if lv <= (item.level or 1) then break end
        if lv > (item.level or 1) then return false end -- has children
      end
      i = i + 1
    end
    return true
  end
  return false
end

local function is_project_item(item)
  if is_completed(item) then return false end  -- Exclude DONE/ARCHIVED
  return item.project or (item.level == 1 and (item.title or "") ~= "" and item.state ~= "DONE" and item.state ~= "ARCHIVED")
end

local function is_someday_maybe(item)
  if is_completed(item) then return false end  -- Exclude DONE/ARCHIVED
  return item.state == "SOMEDAY" and not item.project
end

local function is_waiting(item)
  if is_completed(item) then return false end  -- Exclude DONE/ARCHIVED
  return item.state == "WAITING" and not item.project
end

local function is_stuck_project(item, L)
  if not item.project then return false end
  if is_completed(item) then return false end  -- Exclude DONE/ARCHIVED
  
  -- Check if project has any NEXT actions
  local counts = todo_counts(L, item.s, item.e)
  return counts.next == 0 and counts.todo > 0
end

-- WAITING-specific filters
local function is_overdue_waiting(item)
  if is_completed(item) then return false end
  if not is_waiting(item) or not item.waiting_data then return false end
  return is_overdue(item.waiting_data.follow_up_date, M.cfg.waiting_display.days_overdue_warn)
end

local function is_urgent_waiting(item)
  if is_completed(item) then return false end
  if not is_waiting(item) or not item.waiting_data then return false end
  return item.waiting_data.priority and (item.waiting_data.priority == "urgent" or item.waiting_data.priority == "high")
end

-- NEW: Filters for DONE and ARCHIVED
local function is_done_item(item)
  return item.state == "DONE" and not item.project
end

local function is_archived_item(item)
  return item.state == "ARCHIVED" or item.context == "archive"
end

-- ---------------------------- Enhanced Preview ----------------------------
local function render_preview_item(item, item_type)
  local L = readf(item.path)
  local lines = {}
  
  local header = string.format("%s  %s:%d  %s",
    item_type:upper(), vim.fn.fnamemodify(item.path, ":."), item.lnum, 
    trim(item.title or item.line or ""))
  
  table.insert(lines, header)
  table.insert(lines, string.rep("─", #header))
  
  -- Basic metadata
  table.insert(lines, ("State     : %s"):format(item.state or "-"))
  table.insert(lines, ("Context   : %s"):format(item.context or "-"))
  if item.effort then table.insert(lines, ("Effort    : %s"):format(item.effort)) end
  if item.assigned and item.assigned ~= "" then table.insert(lines, ("Assigned  : %s"):format(item.assigned)) end
  if item.deadline then table.insert(lines, ("Deadline  : %s"):format(item.deadline)) end
  if item.scheduled then table.insert(lines, ("Scheduled : %s"):format(item.scheduled)) end
  if item.tags and #item.tags > 0 then table.insert(lines, ("Tags      : %s"):format(table.concat(item.tags, ", "))) end
  if item.zk then table.insert(lines, ("ZK Note   : %s"):format(vim.fn.fnamemodify(item.zk, ":t"))) end
  
  -- WAITING-specific metadata
  if item.waiting_data and item.state == "WAITING" then
    table.insert(lines, "")
    table.insert(lines, "WAITING FOR DETAILS:")
    table.insert(lines, string.rep("─", 20))
    
    if item.waiting_data.waiting_for then
      table.insert(lines, ("Who       : %s"):format(item.waiting_data.waiting_for))
    end
    if item.waiting_data.waiting_what then
      table.insert(lines, ("What      : %s"):format(item.waiting_data.waiting_what))
    end
    if item.waiting_data.requested_date then
      table.insert(lines, ("Requested : %s"):format(item.waiting_data.requested_date))
    end
    if item.waiting_data.follow_up_date then
      local days_text = format_days_until(item.waiting_data.follow_up_date)
      local overdue_warning = is_overdue(item.waiting_data.follow_up_date, M.cfg.waiting_display.days_overdue_warn) and " ⚠️  OVERDUE" or ""
      table.insert(lines, ("Follow-up : %s %s%s"):format(item.waiting_data.follow_up_date, days_text, overdue_warning))
    end
    if item.waiting_data.context then
      table.insert(lines, ("Via       : %s"):format(item.waiting_data.context))
    end
    if item.waiting_data.priority then
      local priority_icon = ""
      if item.waiting_data.priority == "urgent" then priority_icon = " 🔴"
      elseif item.waiting_data.priority == "high" then priority_icon = " 🟡"
      elseif item.waiting_data.priority == "medium" then priority_icon = " 🔵"
      else priority_icon = " ⚪"
      end
      table.insert(lines, ("Priority  : %s%s"):format(item.waiting_data.priority, priority_icon))
    end
    if item.waiting_data.notes and item.waiting_data.notes ~= "" then
      table.insert(lines, ("Notes     : %s"):format(item.waiting_data.notes))
    end
  end
  
  -- Project-specific stats
  if item.project then
    local stats = todo_counts(L, item.s, item.e)
    local cbtxt = ""
    if item.cb.total > 0 then cbtxt = string.format("  Checkboxes %d/%d", item.cb.done, item.cb.total) end
    table.insert(lines, string.format("Tasks     : NEXT=%d TODO=%d WAIT=%d SOME=%d DONE=%d%s",
      stats.next, stats.todo, stats.waiting, stats.someday, stats.done, cbtxt))
    
    if is_stuck_project(item, L) then
      table.insert(lines, "⚠️  STUCK PROJECT (no NEXT actions)")
    end
  elseif item.cb.total > 0 then
    table.insert(lines, string.format("Checkboxes: %d/%d", item.cb.done, item.cb.total))
  end
  
  table.insert(lines, string.format("Subtree   : lines %d..%d", item.s, item.e))
  table.insert(lines, "")
  table.insert(lines, "Actions:")
  table.insert(lines, "  Enter/Ctrl-e → Edit task")
  table.insert(lines, "  Ctrl-x → Run clarify wizard")
  table.insert(lines, "  Ctrl-f → Fast clarify")
  if item.zk then
    table.insert(lines, "  Ctrl-z → Open ZK note ✔")
  else
    table.insert(lines, "  Ctrl-z → Open ZK note (none linked)")
  end
  table.insert(lines, "  Ctrl-s → Split open")
  table.insert(lines, "  Ctrl-t → Tab open")
  table.insert(lines, "  Ctrl-b → Back to menu")
  
  -- Add specific actions based on item type
  if item_type == "task" then
    table.insert(lines, "  Ctrl-n → Mark as NEXT")
  elseif item_type == "project" then
    table.insert(lines, "  Ctrl-r → Review (jump to next action)")
  elseif item_type == "someday" then
    table.insert(lines, "  Ctrl-a → Activate (SOMEDAY→TODO)")
    table.insert(lines, "  Ctrl-n → Make NEXT action")
  elseif item_type == "waiting" then
    table.insert(lines, "  Ctrl-a → Activate (WAITING→TODO)")
    table.insert(lines, "  Ctrl-w → Update WAITING details")
    table.insert(lines, "  Ctrl-c → Convert from WAITING")
  elseif item_type == "stuck-project" then
    table.insert(lines, "  Ctrl-n → Add next action")
  elseif item_type == "done" then
    table.insert(lines, "  Ctrl-r → Restore to TODO")
    table.insert(lines, "  Ctrl-a → Archive permanently")
  elseif item_type == "archived" then
    table.insert(lines, "  Ctrl-r → Restore to TODO")
  end
  table.insert(lines, "")
  
  -- Show subtree content (limited)
  local max_lines = 50
  local count = 0
  for i=item.s, math.min(item.e, item.s + max_lines - 1) do
    local ln = L[i] or ""
    table.insert(lines, ln)
    count = count + 1
  end
  if item.e - item.s + 1 > max_lines then
    table.insert(lines, string.format("... (%d more lines)", item.e - item.s + 1 - max_lines))
  end
  
  return table.concat(lines, "\n")
end

-- ---------------------------- Generic List Function ----------------------------
local function show_list(filter_fn, title, item_type, extra_actions)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return vim.notify("fzf-lua required", vim.log.levels.WARN) end
  
  extra_actions = extra_actions or {}
  
  -- Filter and build display
  local filtered, meta = {}, {}
  local headings = scan_all_headings()
  
  for _, h in ipairs(headings) do
    local L = readf(h.path)
    if filter_fn(h, L) then
      local due = h.deadline and (" 📅" .. h.deadline) or ""
      local tags = (#h.tags > 0) and (" :" .. table.concat(h.tags, ":") .. ":") or ""
      local effort = h.effort and (" ⏱️" .. h.effort) or ""
      local ctx = h.context and ("[" .. h.context .. "] ") or ""
      
      -- Enhanced WAITING display
      local waiting_indicators = ""
      if h.state == "WAITING" and h.waiting_data then
        -- Priority indicator
        if M.cfg.waiting_display.show_priority and h.waiting_data.priority then
          if h.waiting_data.priority == "urgent" then
            waiting_indicators = waiting_indicators .. " 🔴"
          elseif h.waiting_data.priority == "high" then
            waiting_indicators = waiting_indicators .. " 🟡"
          end
        end
        
        -- Overdue indicator
        if M.cfg.waiting_display.show_overdue and h.waiting_data.follow_up_date then
          if is_overdue(h.waiting_data.follow_up_date, M.cfg.waiting_display.days_overdue_warn) then
            waiting_indicators = waiting_indicators .. " ⚠️"
          end
        end
        
        -- Context indicator (using glyphs)
        if M.cfg.waiting_display.show_context and h.waiting_data.context then
          local context_icons = {
            email = g.ui.note, phone = g.ui.user, meeting = g.container.calendar,
            text = g.ui.note, slack = g.ui.link, teams = g.ui.link, 
            verbal = g.ui.user, letter = g.container.inbox
          }
          local icon = context_icons[h.waiting_data.context] or g.ui.bullet
          waiting_indicators = waiting_indicators .. " " .. icon
        end
        
        -- Who we're waiting for
        if h.waiting_data.waiting_for then
          waiting_indicators = waiting_indicators .. " (" .. h.waiting_data.waiting_for .. ")"
        end
        
        -- Follow-up date
        if h.waiting_data.follow_up_date then
          local days_text = format_days_until(h.waiting_data.follow_up_date)
          if days_text ~= "" then
            waiting_indicators = waiting_indicators .. " " .. days_text
          end
        end
      end
      
      -- State indicator for DONE/ARCHIVED (using glyphs)
      local state_indicator = ""
      if h.state == "DONE" then
        state_indicator = " " .. g.state.DONE
      elseif h.state == "ARCHIVED" then
        state_indicator = " " .. g.container.someday
      end
      
      local line = string.format("%s%s  %s  [%s]%s%s%s%s%s",
        ctx, vim.fn.fnamemodify(h.path, ":t"), 
        trim(h.title or ""), h.state or "-", due, effort, tags, waiting_indicators, state_indicator)
      
      table.insert(filtered, line)
      table.insert(meta, h)
    end
  end
  
  if #filtered == 0 then
    return vim.notify("No " .. title:lower() .. " found.", vim.log.levels.INFO)
  end
  
  -- Base actions for all lists
  local base_actions = {
    -- Enter → open task for editing
    default = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      -- Find the index of the selected line in our filtered array
      local idx = nil
      for i, line in ipairs(filtered) do
        if line == selected_line then
          idx = i
          break
        end
      end
      
      if not idx or not meta[idx] then 
        vim.notify("Could not find selected task", vim.log.levels.ERROR)
        return 
      end
      
      local item = meta[idx]
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      vim.notify(string.format("Opened: %s", trim(item.title or item.line or "")), vim.log.levels.INFO)
    end,
    
    -- Ctrl-e → explicit edit (same as Enter, but more obvious)
    ["ctrl-e"] = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      local idx = nil
      for i, line in ipairs(filtered) do
        if line == selected_line then
          idx = i
          break
        end
      end
      
      if not idx or not meta[idx] then return end
      
      local item = meta[idx]
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      vim.notify(string.format("Editing: %s", trim(item.title or item.line or "")), vim.log.levels.INFO)
    end,
    
    -- Ctrl-x → clarify (run clarify wizard)
    ["ctrl-x"] = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      local idx = nil
      for i, line in ipairs(filtered) do
        if line == selected_line then idx = i; break end
      end
      
      if not idx or not meta[idx] then return end
      local item = meta[idx]
      
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.clarify then
        vim.schedule(function() clarify.clarify({}) end)
      else
        vim.notify("Clarify module not available", vim.log.levels.WARN)
      end
    end,
    
    -- Ctrl-f → fast clarify (just ensure ID and status)
    ["ctrl-f"] = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      local idx = nil
      for i, line in ipairs(filtered) do
        if line == selected_line then idx = i; break end
      end
      
      if not idx or not meta[idx] then return end
      local item = meta[idx]
      
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ promote_if_needed = false })
      else
        vim.notify("Fast clarify not available", vim.log.levels.WARN)
      end
    end,
    
    -- Ctrl-z → open ZK note
    ["ctrl-z"] = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      local idx = nil
      for i, line in ipairs(filtered) do
        if line == selected_line then idx = i; break end
      end
      
      if not idx or not meta[idx] then return end
      local item = meta[idx]
      
      if item.zk then
        vim.cmd("edit " .. item.zk)
      else
        vim.notify("No ZK note linked to this " .. item_type, vim.log.levels.INFO)
      end
    end,
    
    -- Ctrl-s → split open
    ["ctrl-s"] = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      local idx = nil
      for i, line in ipairs(filtered) do
        if line == selected_line then idx = i; break end
      end
      
      if not idx or not meta[idx] then return end
      local item = meta[idx]
      
      vim.cmd("split " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
    end,
    
    -- Ctrl-t → tab open
    ["ctrl-t"] = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      local idx = nil
      for i, line in ipairs(filtered) do
        if line == selected_line then idx = i; break end
      end
      
      if not idx or not meta[idx] then return end
      local item = meta[idx]
      
      vim.cmd("tabedit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
    end,
    
    -- Ctrl-b → back to Lists menu
    ["ctrl-b"] = function(_)
      vim.schedule(function() M.menu() end)
    end,
  }
  
  -- Merge extra actions
  for k, v in pairs(extra_actions) do
    base_actions[k] = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      local idx = nil
      for i, line in ipairs(filtered) do
        if line == selected_line then idx = i; break end
      end
      
      if not idx or not meta[idx] then return end
      local item = meta[idx]
      v(item)
    end
  end
  
  fzf.fzf_exec(filtered, {
    prompt = title .. " (C-b=Back)> ",
    winopts = {
      height = 0.85,
      width = 0.95,
      preview = {
        type = "cmd",
        fn = function(items)
          -- In fzf-lua, items is the selected line string for preview
          local selected_line = tostring(items)
          
          -- Find the index in our filtered array
          local idx = nil
          for i, line in ipairs(filtered) do
            if line == selected_line then
              idx = i
              break
            end
          end
          
          if not idx or not meta[idx] then 
            return "Preview: Item not found\nSelected: " .. selected_line
          end
          return render_preview_item(meta[idx], item_type)
        end
      },
    },
    actions = base_actions,
  })
end

-- ---------------------------- Public List Functions ----------------------------
function M.next_actions()
  show_list(is_next_action, "Next Actions", "task", {
    -- Ctrl-n → mark as NEXT (promote TODO to NEXT)
    ["ctrl-n"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "NEXT" })
        vim.notify("Promoted to NEXT: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
  })
end

function M.projects()
  show_list(is_project_item, "Projects", "project", {
    -- Ctrl-r → review (open and go to first NEXT or TODO)
    ["ctrl-r"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      
      -- Find first NEXT or TODO in project
      local L = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local found = false
      for i = item.s, item.e do
        local ln = L[i] or ""
        if is_heading(ln) then
          local st = select(1, parse_state_title(ln))
          if st == "NEXT" or st == "TODO" then
            vim.api.nvim_win_set_cursor(0, { i, 0 })
            vim.notify("Found next action in: " .. trim(item.title or ""), vim.log.levels.INFO)
            found = true
            break
          end
        end
      end
      if not found then
        vim.notify("No next actions found in: " .. trim(item.title or ""), vim.log.levels.WARN)
      end
    end,
  })
end

function M.someday_maybe()
  show_list(is_someday_maybe, "Someday/Maybe", "someday", {
    -- Ctrl-a → activate (change from SOMEDAY to TODO)
    ["ctrl-a"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "TODO" })
        vim.notify("Activated to TODO: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
    -- Ctrl-n → next action (change to NEXT)
    ["ctrl-n"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "NEXT" })
        vim.notify("Activated to NEXT: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
  })
end

function M.waiting()
  show_list(is_waiting, "Waiting For", "waiting", {
    -- Ctrl-a → activate (change from WAITING to TODO)
    ["ctrl-a"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.convert_from_waiting_at_cursor then
        clarify.convert_from_waiting_at_cursor()
      elseif clarify and clarify.fast then
        clarify.fast({ status = "TODO" })
        vim.notify("Activated from WAITING to TODO: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
    
    -- Ctrl-w → update WAITING details
    ["ctrl-w"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.update_waiting_at_cursor then
        clarify.update_waiting_at_cursor()
      else
        vim.notify("WAITING update not available", vim.log.levels.WARN)
      end
    end,
    
    -- Ctrl-c → convert from WAITING
    ["ctrl-c"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.convert_from_waiting_at_cursor then
        clarify.convert_from_waiting_at_cursor()
      else
        vim.notify("Convert from WAITING not available", vim.log.levels.WARN)
      end
    end,
  })
end

function M.stuck_projects()
  show_list(is_stuck_project, "Stuck Projects", "stuck-project", {
    -- Ctrl-n → add next action (go to project and add TODO)
    ["ctrl-n"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.e, 0 }) -- Go to end of project
      -- Insert new TODO
      vim.api.nvim_put({"", "** TODO Next action for this project"}, "l", true, true)
      vim.api.nvim_win_set_cursor(0, { item.e + 2, 7 }) -- Position for editing
      vim.notify("Added next action to: " .. trim(item.title or ""), vim.log.levels.INFO)
      vim.cmd("startinsert!")
    end,
  })
end

-- ---------------------------- Enhanced WAITING views ----------------------------

-- Show overdue WAITING items
function M.waiting_overdue()
  show_list(is_overdue_waiting, "Overdue WAITING Items", "waiting", {
    ["ctrl-a"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.convert_from_waiting_at_cursor then
        clarify.convert_from_waiting_at_cursor()
      end
    end,
    ["ctrl-w"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.update_waiting_at_cursor then
        clarify.update_waiting_at_cursor()
      end
    end,
  })
end

-- Show urgent WAITING items
function M.waiting_urgent()
  show_list(is_urgent_waiting, "Urgent WAITING Items", "waiting", {
    ["ctrl-a"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.convert_from_waiting_at_cursor then
        clarify.convert_from_waiting_at_cursor()
      end
    end,
    ["ctrl-w"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.update_waiting_at_cursor then
        clarify.update_waiting_at_cursor()
      end
    end,
  })
end

-- ---------------------------- NEW: DONE and ARCHIVED Views ----------------------------

-- Show completed (DONE) tasks
function M.done()
  show_list(is_done_item, "Completed Tasks", "done", {
    -- Ctrl-r → restore to TODO
    ["ctrl-r"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "TODO" })
        vim.notify("Restored to TODO: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
    -- Ctrl-a → archive
    ["ctrl-a"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "ARCHIVED" })
        vim.notify("Archived: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
    -- Ctrl-n → restore to NEXT
    ["ctrl-n"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "NEXT" })
        vim.notify("Restored to NEXT: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
  })
end

-- Show archived tasks
function M.archived()
  show_list(is_archived_item, "Archived Tasks", "archived", {
    -- Ctrl-r → restore to TODO
    ["ctrl-r"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "TODO" })
        vim.notify("Restored to TODO: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
    -- Ctrl-n → restore to NEXT
    ["ctrl-n"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "NEXT" })
        vim.notify("Restored to NEXT: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
  })
end

-- ---------------------------- Areas of Responsibility ----------------------------

-- Get all areas with their task counts
local function get_areas_with_counts()
  local areas = areas_mod and areas_mod.areas or {}
  local headings = scan_all_headings()
  
  local area_counts = {}
  
  -- Initialize counts for each defined area
  for _, a in ipairs(areas) do
    area_counts[a.name] = {
      name = a.name,
      icon = a.icon or "📁",
      dir = a.dir,
      total = 0,
      next = 0,
      todo = 0,
      waiting = 0,
      someday = 0,
      done = 0,
      projects = 0,
    }
  end
  
  -- Count tasks per area
  for _, h in ipairs(headings) do
    local area_name = h.area
    if area_name and area_counts[area_name] then
      local counts = area_counts[area_name]
      counts.total = counts.total + 1
      
      if h.state == "NEXT" then counts.next = counts.next + 1
      elseif h.state == "TODO" then counts.todo = counts.todo + 1
      elseif h.state == "WAITING" then counts.waiting = counts.waiting + 1
      elseif h.state == "SOMEDAY" then counts.someday = counts.someday + 1
      elseif h.state == "DONE" then counts.done = counts.done + 1
      end
      
      if h.project then counts.projects = counts.projects + 1 end
    end
  end
  
  return area_counts, areas
end

-- Filter for tasks belonging to a specific area
local function make_area_filter(area_name)
  return function(item, L)
    if is_completed(item) then return false end
    return item.area == area_name
  end
end

-- Render preview for area overview
local function render_area_preview(area_data)
  local lines = {}
  
  local header = string.format("%s  %s", area_data.icon, area_data.name)
  table.insert(lines, header)
  table.insert(lines, string.rep("─", #header + 2))
  table.insert(lines, "")
  
  -- Directory
  if area_data.dir then
    table.insert(lines, "Directory: " .. vim.fn.expand(area_data.dir))
    table.insert(lines, "")
  end
  
  -- Task counts
  table.insert(lines, "TASK COUNTS:")
  table.insert(lines, string.rep("─", 20))
  table.insert(lines, string.format("  NEXT     : %d", area_data.next or 0))
  table.insert(lines, string.format("  TODO     : %d", area_data.todo or 0))
  table.insert(lines, string.format("  WAITING  : %d", area_data.waiting or 0))
  table.insert(lines, string.format("  SOMEDAY  : %d", area_data.someday or 0))
  table.insert(lines, string.format("  DONE     : %d", area_data.done or 0))
  table.insert(lines, string.rep("─", 20))
  table.insert(lines, string.format("  Total    : %d", area_data.total or 0))
  table.insert(lines, string.format("  Projects : %d", area_data.projects or 0))
  
  -- Active items (NEXT + TODO + WAITING)
  local active = (area_data.next or 0) + (area_data.todo or 0) + (area_data.waiting or 0)
  table.insert(lines, "")
  if active > 0 then
    table.insert(lines, string.format("🔥 Active items: %d", active))
  else
    table.insert(lines, "✨ No active items in this area")
  end
  
  table.insert(lines, "")
  table.insert(lines, "Actions:")
  table.insert(lines, "  Enter   → View tasks in this area")
  table.insert(lines, "  Ctrl-o  → Open area directory")
  table.insert(lines, "  Ctrl-f  → Find files in area")
  table.insert(lines, "  Ctrl-b  → Back to menu")
  
  return table.concat(lines, "\n")
end

-- Show all Areas of Responsibility with task counts
function M.areas()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return vim.notify("fzf-lua required", vim.log.levels.WARN) end
  
  local area_counts, areas = get_areas_with_counts()
  
  if not areas or #areas == 0 then
    return vim.notify("No areas configured. Check areas.lua", vim.log.levels.WARN)
  end
  
  -- Build display list
  local display = {}
  local meta = {}
  
  for _, a in ipairs(areas) do
    local counts = area_counts[a.name] or { next = 0, todo = 0, waiting = 0, total = 0 }
    local icon = a.icon or "📁"
    local active = counts.next + counts.todo + counts.waiting
    
    -- Format: icon name [NEXT/TODO/WAIT] total
    local active_str = ""
    if active > 0 then
      active_str = string.format(" [N:%d T:%d W:%d]", counts.next, counts.todo, counts.waiting)
    end
    
    local line = string.format("%s %s%s  (%d tasks)",
      icon, a.name, active_str, counts.total)
    
    table.insert(display, line)
    table.insert(meta, {
      name = a.name,
      icon = icon,
      dir = a.dir,
      next = counts.next,
      todo = counts.todo,
      waiting = counts.waiting,
      someday = counts.someday,
      done = counts.done,
      total = counts.total,
      projects = counts.projects,
    })
  end
  
  fzf.fzf_exec(display, {
    prompt = "Areas of Responsibility (C-b=Back)> ",
    winopts = {
      height = 0.70,
      width = 0.80,
      preview = {
        type = "cmd",
        fn = function(items)
          local selected_line = tostring(items)
          
          local idx = nil
          for i, line in ipairs(display) do
            if line == selected_line then
              idx = i
              break
            end
          end
          
          if not idx or not meta[idx] then
            return "Area not found"
          end
          
          return render_area_preview(meta[idx])
        end
      },
    },
    actions = {
      -- Enter → drill down into area tasks
      default = function(selected)
        local selected_line = selected[1]
        if not selected_line then return end
        
        local idx = nil
        for i, line in ipairs(display) do
          if line == selected_line then
            idx = i
            break
          end
        end
        
        if not idx or not meta[idx] then return end
        
        local area_name = meta[idx].name
        vim.schedule(function()
          M.area_tasks(area_name)
        end)
      end,
      
      -- Ctrl-o → open area directory
      ["ctrl-o"] = function(selected)
        local selected_line = selected[1]
        if not selected_line then return end
        
        local idx = nil
        for i, line in ipairs(display) do
          if line == selected_line then idx = i; break end
        end
        
        if not idx or not meta[idx] or not meta[idx].dir then return end
        
        vim.cmd("edit " .. vim.fn.expand(meta[idx].dir))
      end,
      
      -- Ctrl-f → find files in area
      ["ctrl-f"] = function(selected)
        local selected_line = selected[1]
        if not selected_line then return end
        
        local idx = nil
        for i, line in ipairs(display) do
          if line == selected_line then idx = i; break end
        end
        
        if not idx or not meta[idx] or not meta[idx].dir then return end
        
        local fzf_files = safe_require("fzf-lua")
        if fzf_files then
          fzf_files.files({ cwd = vim.fn.expand(meta[idx].dir) })
        end
      end,
      
      -- Ctrl-b → back to menu
      ["ctrl-b"] = function(_)
        vim.schedule(function() M.menu() end)
      end,
    },
  })
end

-- Show tasks for a specific area
function M.area_tasks(area_name)
  if not area_name then
    return vim.notify("No area specified", vim.log.levels.WARN)
  end
  
  local filter = make_area_filter(area_name)
  local area_icon = "📁"
  
  -- Get icon from areas config
  if areas_mod and areas_mod.areas then
    for _, a in ipairs(areas_mod.areas) do
      if a.name == area_name then
        area_icon = a.icon or "📁"
        break
      end
    end
  end
  
  show_list(filter, area_icon .. " " .. area_name .. " Tasks", "area-task", {
    -- Ctrl-n → promote to NEXT
    ["ctrl-n"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "NEXT" })
        vim.notify("Promoted to NEXT: " .. trim(item.title or ""), vim.log.levels.INFO)
      end
    end,
    
    -- Ctrl-a → back to areas list
    ["ctrl-a"] = function(_)
      vim.schedule(function() M.areas() end)
    end,
  })
end

-- Show all tasks with :AREA: property (orphaned or not)
function M.all_area_tasks()
  local function has_area(item, L)
    if is_completed(item) then return false end
    return item.area ~= nil
  end
  
  show_list(has_area, "All Area-Tagged Tasks", "area-task", {
    ["ctrl-n"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      if clarify and clarify.fast then
        clarify.fast({ status = "NEXT" })
      end
    end,
  })
end

-- Show tasks without an area (need to be assigned)
function M.unassigned_tasks()
  local function no_area(item, L)
    if is_completed(item) then return false end
    if item.project then return false end
    return item.area == nil and item.state ~= nil
  end
  
  show_list(no_area, "Unassigned Tasks (No Area)", "task", {
    -- Ctrl-a → assign area (opens file for editing)
    ["ctrl-a"] = function(item)
      vim.cmd("edit " .. item.path)
      vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      vim.notify("Add :AREA: property to assign this task", vim.log.levels.INFO)
    end,
  })
end

-- ---------------------------- Search & Filter ----------------------------
function M.search_all()
  local function all_active_items(item, L)
    -- Exclude completed items from active search
    return item.state and not is_completed(item)
  end
  
  show_list(all_active_items, "All Active Items", "item", {})
end

-- ---------------------------- Recurring Tasks ----------------------------
-- Check if item is a recurring task (has :RECUR: property or +repeater in date)
local function is_recurring(item, L)
  if not L then L = readf(item.path) end
  if not item.s or not item.e then return false end
  
  -- Check for RECUR property
  local recur_prop = prop_in(L, item.s, item.e, "RECUR")
  if recur_prop then return true end
  
  -- Check for org-mode repeater in SCHEDULED or DEADLINE
  if item.scheduled and item.scheduled:match("%+%d+[dwmy]") then return true end
  if item.deadline and item.deadline:match("%+%d+[dwmy]") then return true end
  
  -- Check for :recurring: tag
  if item.tags then
    for _, tag in ipairs(item.tags) do
      if tag:lower() == "recurring" then return true end
    end
  end
  
  return false
end

-- Extract recurring metadata
local function extract_recurring_properties(L, s, e)
  local recur_data = {}
  recur_data.frequency = prop_in(L, s, e, "RECUR")
  recur_data.interval = prop_in(L, s, e, "RECUR_INTERVAL")
  recur_data.recur_from = prop_in(L, s, e, "RECUR_FROM")
  recur_data.recur_day = prop_in(L, s, e, "RECUR_DAY")
  recur_data.created = prop_in(L, s, e, "RECUR_CREATED")
  recur_data.last_done = prop_in(L, s, e, "RECUR_LAST_DONE")
  return recur_data
end

-- Parse org date to extract just the date part (without repeater)
local function parse_org_date_only(date_str)
  if not date_str then return nil end
  -- Extract YYYY-MM-DD from various formats
  local date = date_str:match("(%d%d%d%d%-%d%d%-%d%d)")
  return date
end

-- Check if recurring task is due today or overdue
local function is_recurring_due_today(item)
  if not item.scheduled then return false end
  local date = parse_org_date_only(item.scheduled)
  if not date then return false end
  
  local today = os.date("%Y-%m-%d")
  return date <= today
end

-- Show all recurring tasks
function M.recurring()
  local function filter_recurring(item, L)
    return is_recurring(item, L) and not is_completed(item)
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return vim.notify("fzf-lua required", vim.log.levels.WARN) end
  
  local headings = scan_all_headings()
  local filtered = {}
  
  for _, h in ipairs(headings) do
    local L = readf(h.path)
    if filter_recurring(h, L) then
      -- Add recurring-specific data
      h.recur_data = extract_recurring_properties(L, h.s, h.e)
      h.is_due = is_recurring_due_today(h)
      table.insert(filtered, h)
    end
  end
  
  if #filtered == 0 then
    return vim.notify("No recurring tasks found", vim.log.levels.INFO)
  end
  
  -- Sort: due first, then by scheduled date
  table.sort(filtered, function(a, b)
    if a.is_due ~= b.is_due then return a.is_due end
    local date_a = parse_org_date_only(a.scheduled) or "9999-99-99"
    local date_b = parse_org_date_only(b.scheduled) or "9999-99-99"
    return date_a < date_b
  end)
  
  -- Build display
  local display = {}
  local meta = {}
  
  for _, h in ipairs(filtered) do
    local state_icon = ({
      NEXT = g.state.NEXT, TODO = g.state.TODO, WAITING = g.state.WAITING, SOMEDAY = g.state.SOMEDAY
    })[h.state] or g.state.TODO
    
    local freq = h.recur_data and h.recur_data.frequency or ""
    local freq_icon = ({
      daily = g.container.calendar, weekly = g.container.calendar, biweekly = g.container.calendar, 
      monthly = g.container.calendar, yearly = g.container.calendar
    })[freq] or g.container.recurring
    
    local due_marker = ""
    if h.is_due then
      due_marker = g.state.NEXT .. " "
    end
    
    local date_str = ""
    if h.scheduled then
      date_str = " [" .. parse_org_date_only(h.scheduled) .. "]"
    end
    
    local area_str = h.area and (" @" .. h.area) or ""
    
    local line = string.format("%s%s %s %s%s%s  %s",
      due_marker, freq_icon, state_icon, 
      trim(h.title or h.line), date_str, area_str,
      vim.fn.fnamemodify(h.path, ":t"))
    
    table.insert(display, line)
    table.insert(meta, h)
  end
  
  fzf.fzf_exec(display, {
    prompt = g.container.recurring .. " Recurring Tasks (C-b=Back)> ",
    winopts = { height = 0.70, width = 0.85 },
    actions = {
      default = function(selected)
        local idx = vim.fn.index(display, selected[1]) + 1
        local item = meta[idx]
        if item then
          vim.cmd("edit " .. item.path)
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
        end
      end,
      
      -- Ctrl-d → Mark done (org-mode handles regeneration)
      ["ctrl-d"] = function(selected)
        local idx = vim.fn.index(display, selected[1]) + 1
        local item = meta[idx]
        if item then
          vim.cmd("edit " .. item.path)
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
          -- Use org-mode's todo cycling or our clarify
          if vim.fn.exists(":OrgTodoKeyword") == 2 then
            vim.cmd("OrgTodoKeyword DONE")
            vim.notify("Completed! Org-mode will regenerate next occurrence.", vim.log.levels.INFO)
          elseif clarify and clarify.fast then
            clarify.fast({ status = "DONE" })
          end
        end
      end,
      
      -- Ctrl-e → Edit and return
      ["ctrl-e"] = function(selected)
        local idx = vim.fn.index(display, selected[1]) + 1
        local item = meta[idx]
        if item then
          vim.cmd("edit " .. item.path)
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
        end
      end,
      
      -- Ctrl-b → back to menu
      ["ctrl-b"] = function(_)
        vim.schedule(function() M.menu() end)
      end,
    },
  })
end

-- Show recurring tasks due today (or overdue)
function M.recurring_today()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return vim.notify("fzf-lua required", vim.log.levels.WARN) end
  
  local headings = scan_all_headings()
  local filtered = {}
  
  for _, h in ipairs(headings) do
    local L = readf(h.path)
    if is_recurring(h, L) and not is_completed(h) and is_recurring_due_today(h) then
      h.recur_data = extract_recurring_properties(L, h.s, h.e)
      table.insert(filtered, h)
    end
  end
  
  if #filtered == 0 then
    return vim.notify("🎉 No recurring tasks due today!", vim.log.levels.INFO)
  end
  
  -- Sort by scheduled date
  table.sort(filtered, function(a, b)
    local date_a = parse_org_date_only(a.scheduled) or "9999-99-99"
    local date_b = parse_org_date_only(b.scheduled) or "9999-99-99"
    return date_a < date_b
  end)
  
  -- Build display
  local display = {}
  local meta = {}
  
  local today = os.date("%Y-%m-%d")
  
  for _, h in ipairs(filtered) do
    local freq = h.recur_data and h.recur_data.frequency or ""
    local freq_icon = ({
      daily = "📅", weekly = "📆", biweekly = "📆", monthly = "🗓️", yearly = "🎂"
    })[freq] or "🔁"
    
    local date = parse_org_date_only(h.scheduled)
    local overdue_marker = ""
    if date and date < today then
      local days = days_until(date)
      overdue_marker = string.format(" ⚠️ %d days overdue", math.abs(days or 0))
    end
    
    local area_str = h.area and (" @" .. h.area) or ""
    
    local line = string.format("%s %s%s%s  %s",
      freq_icon, trim(h.title or h.line), overdue_marker, area_str,
      vim.fn.fnamemodify(h.path, ":t"))
    
    table.insert(display, line)
    table.insert(meta, h)
  end
  
  fzf.fzf_exec(display, {
    prompt = g.state.NEXT .. " Recurring Due Today (C-d=Done, C-b=Back)> ",
    winopts = { height = 0.60, width = 0.80 },
    actions = {
      default = function(selected)
        local idx = vim.fn.index(display, selected[1]) + 1
        local item = meta[idx]
        if item then
          vim.cmd("edit " .. item.path)
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
        end
      end,
      
      -- Ctrl-d → Mark done
      ["ctrl-d"] = function(selected)
        local idx = vim.fn.index(display, selected[1]) + 1
        local item = meta[idx]
        if item then
          vim.cmd("edit " .. item.path)
          vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
          if vim.fn.exists(":OrgTodoKeyword") == 2 then
            vim.cmd("OrgTodoKeyword DONE")
            vim.notify("✓ Completed! Date shifted to next occurrence.", vim.log.levels.INFO)
            -- Refresh the list
            vim.schedule(function() M.recurring_today() end)
          elseif clarify and clarify.fast then
            clarify.fast({ status = "DONE" })
          end
        end
      end,
      
      -- Ctrl-b → back to menu
      ["ctrl-b"] = function(_)
        vim.schedule(function() M.menu() end)
      end,
    },
  })
end

-- ---------------------------- Quick Menu ----------------------------
function M.menu()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return vim.notify("fzf-lua required", vim.log.levels.WARN) end
  
  local menu_items = {
    -- Actionable lists (GTD focus)
    g.state.NEXT .. " Next Actions",
    g.container.projects .. " Projects", 
    g.state.SOMEDAY .. " Someday/Maybe",
    g.state.WAITING .. " Waiting For",
    g.ui.warning .. " Stuck Projects",
    g.ui.search .. " Search All Active",
    -- Recurring tasks
    "────────────────",
    g.container.recurring .. " Recurring Tasks",
    g.state.NEXT .. " Recurring Due Today",
    -- Areas of Responsibility
    "────────────────",
    g.container.areas .. " Areas of Responsibility",
    g.ui.question .. " Unassigned Tasks",
    -- Waiting sub-views
    "────────────────",
    g.ui.warning .. " Waiting - Overdue",
    g.priority.high .. " Waiting - Urgent",
    -- Reference/History lists
    "────────────────",
    g.state.DONE .. " Completed (DONE)",
    g.container.someday .. " Archived",
  }
  
  local menu_actions = {
    default = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      -- Skip separator
      if selected_line:match("^─+$") then return end
      
      -- Find index in menu_items
      local idx = nil
      for i, item in ipairs(menu_items) do
        if item == selected_line then
          idx = i
          break
        end
      end
      
      if not idx then return end
      local choice = menu_items[idx]
      
      if choice == "Next Actions" then M.next_actions()
      elseif choice == "Projects" then M.projects()
      elseif choice == "Someday/Maybe" then M.someday_maybe()
      elseif choice == "Waiting For" then M.waiting()
      elseif choice == "Waiting - Overdue" then M.waiting_overdue()
      elseif choice == "Waiting - Urgent" then M.waiting_urgent()
      elseif choice == "Stuck Projects" then M.stuck_projects()
      elseif choice == "Search All Active" then M.search_all()
      elseif choice == "🔁 Recurring Tasks" then M.recurring()
      elseif choice == "⚡ Recurring Due Today" then M.recurring_today()
      elseif choice == "📁 Areas of Responsibility" then M.areas()
      elseif choice == "Unassigned Tasks" then M.unassigned_tasks()
      elseif choice == "Completed (DONE)" then M.done()
      elseif choice == "Archived" then M.archived()
      end
    end,
  }
  
  fzf.fzf_exec(menu_items, {
    prompt = "GTD Lists> ",
    winopts = { height = 0.50, width = 0.60, row = 0.20 },
    actions = menu_actions,
  })
end

-- ---------------------------- Aliases (backward compatibility) ----------------------------
M.list_next_actions = M.next_actions
M.list_projects = M.projects
M.list_done = M.done
M.list_archived = M.archived
M.list_areas = M.areas
M.list_recurring = M.recurring
M.list_recurring_today = M.recurring_today

-- ---------------------------- Setup ----------------------------
function M.setup(user_cfg)
  if user_cfg then 
    for k,v in pairs(user_cfg) do M.cfg[k] = v end 
  end
  
  -- Create commands
  vim.api.nvim_create_user_command("GtdListsMenu",        function() M.menu() end, {})
  vim.api.nvim_create_user_command("GtdNextActions",      function() M.next_actions() end, {})
  vim.api.nvim_create_user_command("GtdProjects",         function() M.projects() end, {})
  vim.api.nvim_create_user_command("GtdSomedayMaybe",     function() M.someday_maybe() end, {})
  vim.api.nvim_create_user_command("GtdWaiting",          function() M.waiting() end, {})
  vim.api.nvim_create_user_command("GtdWaitingOverdue",   function() M.waiting_overdue() end, {})
  vim.api.nvim_create_user_command("GtdWaitingUrgent",    function() M.waiting_urgent() end, {})
  vim.api.nvim_create_user_command("GtdStuckProjects",    function() M.stuck_projects() end, {})
  vim.api.nvim_create_user_command("GtdSearchAll",        function() M.search_all() end, {})
  -- NEW: DONE and ARCHIVED commands
  vim.api.nvim_create_user_command("GtdDone",             function() M.done() end, {})
  vim.api.nvim_create_user_command("GtdArchived",         function() M.archived() end, {})
  
  -- NEW: Areas of Responsibility commands
  vim.api.nvim_create_user_command("GtdAreas",            function() M.areas() end, {})
  vim.api.nvim_create_user_command("GtdUnassigned",       function() M.unassigned_tasks() end, {})
  
  -- NEW: Recurring tasks commands
  vim.api.nvim_create_user_command("GtdRecurring",        function() M.recurring() end, {})
  vim.api.nvim_create_user_command("GtdRecurringToday",   function() M.recurring_today() end, {})
  
  -- Backward compatibility
  vim.api.nvim_create_user_command("GtdLists",            function() M.menu() end, {})
end

return M
