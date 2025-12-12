-- ~/.config/nvim/lua/gtd/lists.lua
-- Enhanced GTD Lists: Next Actions, Projects, Someday/Maybe, Waiting with rich context & search
-- Enhanced WAITING FOR support with full metadata display and management

local M = {}

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

local clarify = safe_require("gtd.clarify")
local shared = safe_require("gtd.shared")

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
  -- Try to match state with title
  local state, rest2 = rest:match("^(%u+)%s+(.*)")
  if state then return state, rest2 end
  -- Handle state-only headings (e.g., "* WAITING" with no title)
  local state_only = rest:match("^(%u+)$")
  if state_only then return state_only, "" end
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
        
        table.insert(out, {
          path=path, lnum=i, s=s, e=e, line=ln,
          level=lv, state=state, title=title,
          project=is_project, scheduled=scheduled, deadline=deadline,
          tags=tags, zk=zk, cb={done=cbdone,total=cbtotal},
          effort=effort, assigned=assigned, context=context,
          waiting_data=waiting_data,
        })
      end
    end
  end
  return out
end

-- ---------------------------- Filters ----------------------------
local function is_next_action(item, L)
  if item.project then return false end
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
  return item.project or (item.level == 1 and (item.title or "") ~= "" and item.state ~= "DONE")
end

local function is_someday_maybe(item)
  return item.state == "SOMEDAY" and not item.project
end

local function is_waiting(item)
  return item.state == "WAITING" and not item.project
end

local function is_stuck_project(item, L)
  if not item.project then return false end
  if item.state == "DONE" then return false end
  
  -- Check if project has any NEXT actions
  local counts = todo_counts(L, item.s, item.e)
  return counts.next == 0 and counts.todo > 0
end

-- WAITING-specific filters
local function is_overdue_waiting(item)
  if not is_waiting(item) or not item.waiting_data then return false end
  return is_overdue(item.waiting_data.follow_up_date, M.cfg.waiting_display.days_overdue_warn)
end

local function is_urgent_waiting(item)
  if not is_waiting(item) or not item.waiting_data then return false end
  return item.waiting_data.priority and (item.waiting_data.priority == "urgent" or item.waiting_data.priority == "high")
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
        
        -- Context indicator
        if M.cfg.waiting_display.show_context and h.waiting_data.context then
          local context_icons = {
            email = "📧", phone = "📞", meeting = "🤝", text = "💬",
            slack = "💻", teams = "💻", verbal = "🗣️", letter = "📮"
          }
          local icon = context_icons[h.waiting_data.context] or "📋"
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
      
      local line = string.format("%s%s  %s  [%s]%s%s%s%s",
        ctx, vim.fn.fnamemodify(h.path, ":t"), 
        trim(h.title or ""), h.state or "-", due, effort, tags, waiting_indicators)
      
      table.insert(filtered, line)
      table.insert(meta, h)
    end
  end
  
  if #filtered == 0 then
    vim.notify("No " .. title:lower() .. " found.", vim.log.levels.INFO)
    -- Return to menu after showing message
    vim.schedule(function() M.menu() end)
    return
  end
  
  -- Base actions for all lists
  local base_actions = {
    -- Enter → open task for editing
    ["default"] = function(selected)
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
    
    -- Ctrl-b → back to menu
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
  
  -- Build header with shared styling
  local header = ""
  if shared and shared.fzf_header then
    header = shared.fzf_header({ clarify = true, refile = false, archive = false, zettel = true, back = true })
  else
    header = "Enter: Open • Ctrl-E: Edit • Ctrl-X: Clarify • Ctrl-Z: ZK Note"
  end
  
  -- Ensure valid cwd for fzf-lua
  if shared and shared.ensure_valid_cwd then
    shared.ensure_valid_cwd()
  end
  
  fzf.fzf_exec(filtered, {
    prompt = title .. "> ",
    fzf_opts = {
      ["--ansi"] = true,  -- CRITICAL: Enable ANSI colors
      ["--no-info"] = true,
      ["--tiebreak"] = "index",
      ["--header"] = header,
    },
    winopts = {
      height = 0.85,
      width = 0.95,
      title = " " .. title .. " ",
      title_pos = "center",
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

-- ---------------------------- Search & Filter ----------------------------
function M.search_all()
  local function all_active_items(item, L)
    return item.state and item.state ~= "DONE"
  end
  
  show_list(all_active_items, "All Active Items", "item", {})
end

-- ---------------------------- Quick Menu ----------------------------
function M.menu()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return vim.notify("fzf-lua required", vim.log.levels.WARN) end
  
  -- Ensure valid cwd for fzf-lua
  if shared and shared.ensure_valid_cwd then
    shared.ensure_valid_cwd()
  end
  
  -- Use shared glyphs and colors if available
  local g = shared and shared.glyphs or {}
  local c = shared and shared.colorize or function(t, _) return t end
  
  -- Build menu items with glyphs and colors
  local menu_items = {}
  local menu_keys = {}  -- Track which function to call
  
  -- Define menu structure: { key, glyph, label, color }
  local menu_def = {
    { key = "next",           glyph = g.state and g.state.NEXT or "⚡",      label = "Next Actions",      color = "next" },
    { key = "projects",       glyph = g.state and g.state.PROJECT or "📂",  label = "Projects",          color = "project" },
    { key = "someday",        glyph = g.state and g.state.SOMEDAY or "💭",  label = "Someday/Maybe",     color = "someday" },
    { key = "waiting",        glyph = g.state and g.state.WAITING or "⏳",  label = "Waiting For",       color = "waiting" },
    { key = "waiting_overdue",glyph = g.progress and g.progress.overdue or "⚠", label = "Waiting - Overdue", color = "error" },
    { key = "waiting_urgent", glyph = g.progress and g.progress.urgent or "🔴", label = "Waiting - Urgent",  color = "warning" },
    { key = "stuck",          glyph = g.progress and g.progress.blocked or "⛔", label = "Stuck Projects",    color = "error" },
    { key = "search",         glyph = g.ui and g.ui.search or "🔍",          label = "Search All Items",  color = "info" },
  }
  
  for _, item in ipairs(menu_def) do
    local colored_glyph = c(item.glyph, item.color)
    local display = colored_glyph .. "  " .. item.label
    table.insert(menu_items, display)
    table.insert(menu_keys, item.key)
  end
  
  local menu_actions = {
    ["default"] = function(selected)
      local selected_line = selected[1]
      if not selected_line then return end
      
      -- Find index in menu_items
      local idx = nil
      for i, item in ipairs(menu_items) do
        if item == selected_line then
          idx = i
          break
        end
      end
      
      if not idx then return end
      local key = menu_keys[idx]
      
      -- CRITICAL: Must defer to allow fzf to close before opening next picker
      vim.schedule(function()
        if key == "next" then M.next_actions()
        elseif key == "projects" then M.projects()
        elseif key == "someday" then M.someday_maybe()
        elseif key == "waiting" then M.waiting()
        elseif key == "waiting_overdue" then M.waiting_overdue()
        elseif key == "waiting_urgent" then M.waiting_urgent()
        elseif key == "stuck" then M.stuck_projects()
        elseif key == "search" then M.search_all()
        end
      end)
    end,
  }
  
  -- Build header with keyboard hints
  local header = ""
  if shared and shared.fzf_header then
    header = shared.fzf_header({ back = false })
  else
    header = "Enter: Select • Esc: Cancel"
  end
  
  fzf.fzf_exec(menu_items, {
    prompt = c(g.ui and g.ui.menu or "☰", "accent") .. " GTD> ",
    fzf_opts = {
      ["--ansi"] = true,  -- CRITICAL: Enable ANSI colors
      ["--no-info"] = true,
      ["--tiebreak"] = "index",
      ["--header"] = header,
    },
    winopts = { 
      height = 0.45, 
      width = 0.50, 
      row = 0.25,
      title = " GTD Lists ",
      title_pos = "center",
    },
    actions = menu_actions,
  })
end

-- ---------------------------- Aliases (backward compatibility) ----------------------------
M.list_next_actions = M.next_actions
M.list_projects = M.projects

-- Debug function to help diagnose issues
function M.debug_scan()
  local headings = scan_all_headings()
  local counts = { total = 0, waiting = 0, todo = 0, next = 0, someday = 0 }
  
  for _, h in ipairs(headings) do
    counts.total = counts.total + 1
    if h.state == "WAITING" then counts.waiting = counts.waiting + 1
    elseif h.state == "TODO" then counts.todo = counts.todo + 1
    elseif h.state == "NEXT" then counts.next = counts.next + 1
    elseif h.state == "SOMEDAY" then counts.someday = counts.someday + 1
    end
  end
  
  vim.notify(string.format(
    "GTD Scan: %d total headings\n  WAITING: %d\n  TODO: %d\n  NEXT: %d\n  SOMEDAY: %d",
    counts.total, counts.waiting, counts.todo, counts.next, counts.someday
  ), vim.log.levels.INFO)
  
  return headings
end

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
  
  -- Backward compatibility
  vim.api.nvim_create_user_command("GtdLists",            function() M.menu() end, {})
end

return M
