-- ~/.config/nvim/lua/gtd/clarify.lua
-- FIXED: Enhanced Clarify workflow for GTD Org tasks with proper filtering
-- ✅ NO archived files or DONE tasks
-- ✅ Clean display with context icons
-- ✅ GTD-focused sorting prioritizing actionable items

local M = {}

-- ---------- tiny helpers ----------
local function buf_lines(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local function set_buf_lines(buf, L) vim.api.nvim_buf_set_lines(buf, 0, -1, false, L) end
local function heading_level(line) local s = line:match("^(%*+)%s+") return s and #s or nil end
local function safe_require(name) local ok, m = pcall(require, name); return ok and m or nil end
local function notify(msg, lvl, t) vim.notify(msg, lvl or vim.log.levels.INFO, t) end

local task_id  = safe_require("gtd.utils.task_id")
local projects = safe_require("gtd.projects")
local refile   = safe_require("gtd.refile")

-- ---------- enhanced date parsing for smart sorting ----------
local function parse_org_date(date_str)
  if not date_str then return nil end
  local year, month, day = date_str:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if year and month and day then
    return os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
  end
  return nil
end

local function extract_dates_from_lines(lines, start_line, end_line)
  local scheduled, deadline = nil, nil
  for i = start_line, end_line do
    local line = lines[i] or ""
    local sched = line:match("SCHEDULED:%s*<([^>]+)>")
    local dead = line:match("DEADLINE:%s*<([^>]+)>")
    if sched and not scheduled then scheduled = parse_org_date(sched) end
    if dead and not deadline then deadline = parse_org_date(dead) end
  end
  return scheduled, deadline
end

local function calculate_date_priority(scheduled, deadline)
  local now = os.time()
  local today = os.time(os.date("*t", now))
  local priority_boost = 0
  
  -- Overdue deadline = highest boost
  if deadline and deadline < today then
    priority_boost = -3  -- Negative = higher priority
  -- Due today or tomorrow
  elseif deadline and deadline <= (today + 86400) then
    priority_boost = -2
  -- Due this week
  elseif deadline and deadline <= (today + 7 * 86400) then
    priority_boost = -1
  end
  
  -- Overdue scheduled items
  if scheduled and scheduled < today then
    priority_boost = math.min(priority_boost, -2)
  -- Scheduled today
  elseif scheduled and scheduled <= today then
    priority_boost = math.min(priority_boost, -1)
  end
  
  return priority_boost
end

-- ---------- GTD-focused task classification ----------
local function classify_task_for_clarify(state, title, filename, scheduled, deadline)
  local is_inbox = filename and filename:lower():match("inbox")
  local is_someday = filename and filename:lower():match("someday")
  
  local base_priority = 5  -- Default
  local context = "❓ OTHER"
  
  -- High-priority actionable states (need clarification most)
  if state == "NEXT" then
    base_priority = 1
    context = "⚡ NEXT ACTION"
  elseif state == "TODO" then
    base_priority = 2
    context = "📋 TODO"
  elseif state == "WAITING" then
    base_priority = 3
    context = "⏳ WAITING"
  elseif state == "SOMEDAY" or is_someday then
    base_priority = 4
    context = "💭 SOMEDAY"
  elseif state == "PROJECT" then
    base_priority = 2
    context = "📂 PROJECT"
  -- Inbox items need immediate clarification
  elseif is_inbox then
    base_priority = 1
    context = "📥 INBOX"
  else
    -- No state - might need clarification about what it is
    base_priority = 3
    context = "❓ NO STATE"
  end
  
  -- Apply date-based priority boost
  local date_boost = calculate_date_priority(scheduled, deadline)
  local final_priority = base_priority + date_boost
  
  return final_priority, context
end

-- ---------- ROBUST file and task filtering ----------
local function is_archived_file(path, filename)
  local path_lower = path:lower()
  local filename_lower = filename:lower()
  
  -- Comprehensive archive detection
  return filename_lower:match("archive") or 
         path_lower:match("archive") or 
         filename_lower:match("deleted") or 
         path_lower:match("deleted") or
         path_lower:match("/archive/") or
         path_lower:match("/deleted/")
end

local function is_completed_task(state)
  if not state then return false end
  local state_upper = state:upper()
  return state_upper == "DONE" or 
         state_upper == "COMPLETED" or 
         state_upper == "CANCELLED" or
         state_upper == "CLOSED"
end

-- ---------- FIXED: Enhanced scan with proper filtering ----------
local function scan_actionable_tasks(root)
  root = root or vim.fn.expand("~/Documents/GTD")
  local files = vim.fn.globpath(root, "**/*.org", false, true)
  if type(files) == "string" then files = {files} end
  table.sort(files)
  
  local actionable_tasks = {}
  
  for _, path in ipairs(files) do
    local filename = vim.fn.fnamemodify(path, ":t")
    
    -- STEP 1: Skip archived files entirely
    if is_archived_file(path, filename) then
      -- Skip this entire file
    else
      -- STEP 2: Read file safely
      local file_ok, lines = pcall(vim.fn.readfile, path)
      if file_ok and lines then
        
        -- STEP 3: Process each heading
        for i, line in ipairs(lines) do
          if line:match("^%*+%s+") then
            -- Parse heading
            local stars, rest = line:match("^(%*+)%s+(.*)")
            local state = nil
            local title = rest or ""
            
            -- Extract state if present
            if rest then
              local s, t = rest:match("^([A-Z]+)%s+(.*)")
              if s and t then
                state = s
                title = t
              elseif rest:match("^[A-Z]+$") then
                state = rest
                title = "(No title)"
              end
            end
            
            -- STEP 4: Skip completed tasks
            if is_completed_task(state) then
              -- Skip this task
            else
              -- STEP 5: This is an actionable task - extract details
              
              -- Find subtree boundaries
              local h_start = i
              local h_end = i
              local lvl = heading_level(line) or 1
              for j = i + 1, #lines do
                local lv2 = heading_level(lines[j])
                if lv2 and lv2 <= lvl then break end
                h_end = j
              end
              
              -- Extract dates
              local scheduled, deadline = extract_dates_from_lines(lines, h_start, h_end)
              
              -- Calculate priority and context
              local priority, context = classify_task_for_clarify(state, title, filename, scheduled, deadline)
              
              -- Format date info
              local date_info = ""
              if deadline then
                local days_until = math.floor((deadline - os.time()) / 86400)
                if days_until < 0 then
                  date_info = " [OVERDUE]"
                elseif days_until == 0 then
                  date_info = " [DUE TODAY]"
                elseif days_until <= 3 then
                  date_info = " [DUE SOON]"
                end
              elseif scheduled then
                local days_until = math.floor((scheduled - os.time()) / 86400)
                if days_until < 0 then
                  date_info = " [SCHED OVERDUE]"
                elseif days_until == 0 then
                  date_info = " [SCHED TODAY]"
                end
              end
              
              -- Clean title
              local clean_title = title:gsub("%s*:[%w_:%-]+:%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
              if clean_title == "" then clean_title = "(No title)" end
              
              table.insert(actionable_tasks, {
                path = path,
                lnum = i,
                line = line,
                state = state,
                title = clean_title,
                filename = filename,
                priority = priority,
                context = context,
                date_info = date_info,
                scheduled = scheduled,
                deadline = deadline,
              })
            end
          end
        end
      end
    end
  end
  
  -- Sort by GTD priority (actionable first, date-sensitive prioritized)
  table.sort(actionable_tasks, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    if a.filename ~= b.filename then return a.filename < b.filename end
    return a.title < b.title
  end)
  
  return actionable_tasks
end

-- subtree bounds for heading that contains/above lnum
local function find_heading(lines, lnum)
  for i = lnum, 1, -1 do
    local lvl = heading_level(lines[i] or "")
    if lvl then
      local j = i + 1
      while j <= #lines do
        local lv2 = heading_level(lines[j] or "")
        if lv2 and lv2 <= lvl then break end
        j = j + 1
      end
      return i, j - 1, lvl
    end
  end
  return nil
end

-- Insert a PROPERTIES drawer after heading if missing; return drawer start/end
local function ensure_props(lines, h_start)
  local i = h_start + 1
  while i <= #lines and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  if i <= #lines and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= #lines do
      if (lines[j] or ""):match("^%s*:END:%s*$") then return i, j end
      j = j + 1
    end
  end
  local pos = h_start + 1
  table.insert(lines, pos, ":PROPERTIES:")
  table.insert(lines, pos + 1, ":END:")
  return pos, pos + 1
end

-- Ensure ZK link line "ID:: [[zk:<id>]]" appears in subtree (after drawer if present)
local function ensure_zk_link(lines, h_start, h_end, id)
  if not id or id == "" then return end
  for i = h_start, h_end do
    if (lines[i] or ""):find("%[%[zk:" .. id .. "%]%]") then return end
  end
  local i = h_start + 1
  while i <= h_end and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  local p_end = nil
  if i <= h_end and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= h_end do
      if (lines[j] or ""):match("^%s*:END:%s*$") then p_end = j; break end
      j = j + 1
    end
  end
  local insert_pos = (p_end and (p_end + 1)) or (h_start + 1)
  table.insert(lines, insert_pos, ("ID:: [[zk:%s]]"):format(id))
end

-- Promote current line to a heading if no heading is found.
local function promote_line_to_heading(lines, lnum, status_kw)
  local status = status_kw or "TODO"
  local line = lines[lnum] or ""
  if line:match("^%s*$") then
    local title = nil
    vim.ui.input({ prompt = "Task title: " }, function(input) title = input end)
    title = title and title:gsub("^%s+",""):gsub("%s+$","") or ""
    if title == "" then title = "New Task" end
    lines[lnum] = ("* %s %s"):format(status, title)
  else
    lines[lnum] = ("* %s %s"):format(status, line:gsub("^%s+",""))
  end
  if (lines[lnum + 1] or "") ~= "" then
    table.insert(lines, lnum + 1, "")
  end
  return lnum, lnum, 1
end

-- Update/insert SCHEDULED/DEADLINE lines (within subtree, right after drawer if exists)
local function set_dates(lines, h_start, h_end, scheduled, deadline)
  local insert_at = h_start + 1
  local i = h_start + 1
  while i <= h_end and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  if i <= h_end and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= h_end do
      if (lines[j] or ""):match("^%s*:END:%s*$") then insert_at = j + 1; break end
      j = j + 1
    end
  end

  local sched_idx, dead_idx
  for k = h_start + 1, h_end do
    local L = lines[k] or ""
    if L:match("^%s*SCHEDULED:%s*<") then sched_idx = k end
    if L:match("^%s*DEADLINE:%s*<") then dead_idx = k end
  end

  local function fmt_date(d) return ("<%s>"):format(d) end

  if scheduled ~= nil and scheduled ~= "" then
    if scheduled == "-" then
      if sched_idx then table.remove(lines, sched_idx) end
    else
      local sline = "SCHEDULED: " .. fmt_date(scheduled)
      if sched_idx then lines[sched_idx] = sline else
        table.insert(lines, insert_at, sline); insert_at = insert_at + 1; h_end = h_end + 1
      end
    end
  end

  if deadline ~= nil and deadline ~= "" then
    if deadline == "-" then
      if dead_idx then table.remove(lines, dead_idx) end
    else
      local dline = "DEADLINE: " .. fmt_date(deadline)
      if dead_idx then lines[dead_idx] = dline else
        table.insert(lines, insert_at, dline); h_end = h_end + 1
      end
    end
  end

  return lines, h_end
end

-- Set/replace status keyword in heading + :STATUS: property
local function set_status(lines, h_start, p_start, p_end, status_kw)
  if not status_kw or status_kw == "" then return p_end end
  if (lines[h_start] or ""):match("^%*+%s+%u+%s") then
    lines[h_start] = lines[h_start]:gsub("^(%*+)%s+%u+%s", "%1 " .. status_kw .. " ")
  else
    lines[h_start] = lines[h_start]:gsub("^(%*+)%s+", "%1 " .. status_kw .. " ")
  end
  local have = false
  for i = p_start + 1, p_end - 1 do
    if (lines[i] or ""):match("^%s*:STATUS:%s") then
      lines[i] = ":STATUS: " .. status_kw
      have = true
    end
  end
  if not have then
    table.insert(lines, p_end, ":STATUS: " .. status_kw); p_end = p_end + 1
  end
  return p_end
end

-- Append a one-line note right under the heading (after drawer if present)
local function append_note(lines, h_start, h_end, note)
  if not note or note == "" then return h_end end
  local insert_at = h_start + 1
  local i = h_start + 1
  while i <= h_end and (lines[i] or ""):match("^%s*$") do i = i + 1 end
  if i <= h_end and (lines[i] or ""):match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= h_end do
      if (lines[j] or ""):match("^%s*:END:%s*$") then insert_at = j + 1; break end
      j = j + 1
    end
  end
  table.insert(lines, insert_at, note)
  if (lines[insert_at + 1] or "") ~= "" then
    table.insert(lines, insert_at + 1, "")
  end
  return h_end + 1
end

-- ---------- Status picker (fzf-lua first, fallback to vim.ui.select) ----------
local STATES = { "NEXT", "TODO", "WAITING", "SOMEDAY", "DONE" }

local function pick_status(prompt, current, cb)
  local fzf = safe_require("fzf-lua")
  if fzf then
    local header = current and ("Current: " .. current) or ""
    fzf.fzf_exec(STATES, {
      prompt = (prompt or "Status> ") .. " ",
      fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index", ["--header"] = header },
      winopts = { height = 0.30, width = 0.50, row = 0.10 },
      actions = {
        ["default"] = function(sel)
          local s = sel and sel[1]
          if s then cb(s) end
        end,
      },
    })
  else
    vim.ui.select(STATES, { prompt = prompt or "Status" }, function(choice)
      if choice then cb(choice) end
    end)
  end
end

-- ---------- Post-actions (fzf) ----------
local function post_actions_menu(ctx)
  -- ctx: { buf, lines, h_start, h_end, id, path }
  local fzf = safe_require("fzf-lua")
  if not fzf then return end
  local items = {
    "Finish",
    (projects and "Link to project") or nil,
    (refile   and "Refile into project") or nil,
    "Open ZK note",
    "Mark DONE",
  }
  local filtered = {}
  for _, v in ipairs(items) do if v then table.insert(filtered, v) end end

  fzf.fzf_exec(filtered, {
    prompt = "After clarify> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    actions = {
      ["default"] = function(sel)
        local act = sel and sel[1]
        if act == "Link to project" and projects and projects.link_task_to_project_at_cursor then
          projects.link_task_to_project_at_cursor({})
        elseif act == "Refile into project" and refile and refile.to_project_at_cursor then
          refile.to_project_at_cursor({})
        elseif act == "Open ZK note" then
          local id = ctx.id
          if id then
            -- try to find the zk link line we inserted
            local lines = buf_lines(0)
            for i = ctx.h_start, math.min(ctx.h_start + 15, #lines) do
              local lk = (lines[i] or ""):match("%[%[zk:" .. id .. "%]%]")
              local fp = (lines[i] or ""):match("%[%[file:(.-)%]%]")
              if fp then vim.cmd("edit " .. vim.fn.expand(fp)); return end
              if lk then
                notify("You use [[zk:ID]] links; open via your ZK tooling.", vim.log.levels.INFO)
                return
              end
            end
            notify("No ZK link found nearby.", vim.log.levels.WARN)
          end
        elseif act == "Mark DONE" then
          local lines = buf_lines(0)
          local p_s, p_e = ensure_props(lines, ctx.h_start)
          p_e = set_status(lines, ctx.h_start, p_s, p_e, "DONE")
          set_buf_lines(0, lines)
        end
      end
    },
  })
end

-- ---------- Public: quick clarify at cursor ----------
function M.fast(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = buf_lines(buf)

  local h_start, h_end, lvl = find_heading(lines, lnum)
  if not h_start then
    if opts.promote_if_needed then
      h_start, h_end, lvl = promote_line_to_heading(lines, lnum, opts.status or "TODO")
    else
      notify("Clarify: no org heading at/above cursor (won't promote).", vim.log.levels.WARN)
      return
    end
  end

  local p_start, p_end = ensure_props(lines, h_start)
  local new_lines, id = task_id.ensure_in_properties(lines, h_start)
  lines = new_lines

  if opts.status and opts.status ~= "" then
    p_end = set_status(lines, h_start, p_start, p_end, opts.status)
  end

  local j = h_start + 1
  while j <= #lines do
    local lv2 = heading_level(lines[j] or "")
    if lv2 and lv2 <= (lvl or 1) then break end
    j = j + 1
  end
  h_end = j - 1

  ensure_zk_link(lines, h_start, h_end, id)
  set_buf_lines(buf, lines)
  vim.api.nvim_win_set_cursor(0, { h_start, 0 })
  notify("Clarified (ID " .. id .. ")", vim.log.levels.INFO)
  return id
end

-- ---------- Public: full wizard at cursor ----------
function M.clarify(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local lines = buf_lines(buf)

  local h_start, h_end, lvl = find_heading(lines, lnum)
  if not h_start then
    -- wizard always promotes if needed
    h_start, h_end, lvl = promote_line_to_heading(lines, lnum, "TODO")
  end

  local p_start, p_end = ensure_props(lines, h_start)
  local new_lines, id = task_id.ensure_in_properties(lines, h_start)
  lines = new_lines

  local current_status = (lines[h_start] or ""):match("^%*+%s+(%u+)%s") or nil

  pick_status("Clarify status", current_status, function(status_choice)
    if not status_choice then return end
    p_end = set_status(lines, h_start, p_start, p_end, status_choice)

    -- recompute end after drawer edits
    local j = h_start + 1
    while j <= #lines do
      local lv2 = heading_level(lines[j] or "")
      if lv2 and lv2 <= (lvl or 1) then break end
      j = j + 1
    end
    h_end = j - 1

    vim.ui.input({ prompt = "Append note (optional): " }, function(note)
      h_end = append_note(lines, h_start, h_end, note or "")

      local today = os.date("%Y-%m-%d")
      vim.ui.input({ prompt = ("Defer/SCHEDULED (YYYY-MM-DD, empty=keep, -=clear) [e.g. %s]: "):format(today) }, function(sched_in)
        local sched = sched_in or ""

        local plus3 = os.date("%Y-%m-%d", os.time() + 3*24*3600)
        vim.ui.input({ prompt = ("Due/DEADLINE (YYYY-MM-DD, empty=keep, -=clear) [e.g. %s]: "):format(plus3) }, function(dead_in)
          local dead = dead_in or ""
          lines, h_end = set_dates(lines, h_start, h_end, sched, dead)

          ensure_zk_link(lines, h_start, h_end, id)
          set_buf_lines(buf, lines)
          vim.api.nvim_win_set_cursor(0, { h_start, 0 })
          notify(("Clarified → %s (ID %s)"):format(status_choice, id), vim.log.levels.INFO)

          -- Post-actions (fzf): link/refile/open ZK/mark done/finish
          post_actions_menu({
            buf = buf,
            lines = lines,
            h_start = h_start,
            h_end = h_end,
            id = id,
            path = vim.api.nvim_buf_get_name(buf),
          })
        end)
      end)
    end)
  end)
end

-- ---------- Public: pick any actionable task (fzf) and clarify ----------
local function have_fzf() return pcall(require, "fzf-lua") end

function M.clarify_pick_any(opts)
  opts = opts or {}
  if not have_fzf() then
    notify("fzf-lua required for clarify_pick_any()", vim.log.levels.WARN)
    return
  end
  
  local root = opts.root or vim.fn.expand("~/Documents/GTD")
  local actionable_tasks = scan_actionable_tasks(root)

  if #actionable_tasks == 0 then
    notify("No actionable tasks found (all archived or completed)", vim.log.levels.INFO)
    return
  end

  -- Create clean display with context icons
  local display = {}
  for _, task in ipairs(actionable_tasks) do
    local state_tag = task.state and ("[" .. task.state .. "] ") or "[NO STATE] "
    -- Clean format: CONTEXT [STATE] TITLE [DATE_INFO] (FILE)
    local line = string.format("%s %s%s%s (%s)", 
      task.context, 
      state_tag, 
      task.title,
      task.date_info or "",
      task.filename
    )
    table.insert(display, line)
  end

  -- Priority summary
  local counts = {high = 0, medium = 0, low = 0}
  for _, task in ipairs(actionable_tasks) do
    if task.priority <= 2 then
      counts.high = counts.high + 1
    elseif task.priority <= 4 then
      counts.medium = counts.medium + 1
    else
      counts.low = counts.low + 1
    end
  end

  local fzf = require("fzf-lua")
  fzf.fzf_exec(display, {
    prompt = "GTD Clarify> ",
    winopts = { 
      height = 0.80, 
      width = 0.95,
      title = " GTD Clarify - Actionable Tasks Only ",
      title_pos = "center"
    },
    fzf_opts = { 
      ["--no-info"] = true, 
      ["--tiebreak"] = "index",
      ["--header"] = string.format("Actionable: %d high, %d medium, %d low priority • No archived/done items", 
        counts.high, counts.medium, counts.low),
      ["--header-lines"] = "0"
    },
    actions = {
      ["default"] = function(sel)
        local choice = sel and sel[1]; if not choice then return end
        local idx = vim.fn.index(display, choice) + 1
        local task = actionable_tasks[idx]; if not task then return end
        vim.cmd("edit " .. task.path)
        pcall(vim.api.nvim_win_set_cursor, 0, { task.lnum, 0 })
        -- run the full wizard at that location
        vim.schedule(function() M.clarify({}) end)
      end
    }
  })
end

-- ---------- Backward compatibility aliases ----------
function M.at_cursor(opts)
  return M.clarify(opts)
end

return M