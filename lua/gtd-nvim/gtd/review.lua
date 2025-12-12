-- ============================================================================
-- GTD-NVIM WEEKLY REVIEW MODULE
-- ============================================================================
-- Split-based Weekly Review Cockpit with Zettelkasten Integration
-- Phases: GET CLEAR → GET CURRENT → GET CREATIVE
--
-- @module gtd-nvim.gtd.review
-- @version 1.2.0
-- @requires shared (>= 1.0.0)
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2024-12-10"

local function xp(p) return vim.fn.expand(p) end

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local shared = safe_require("gtd-nvim.gtd.shared") or {}
local g = shared.glyphs or {}

-- Glyph helpers with fallbacks
local function glyph(category, name, fallback)
  if g[category] and g[category][name] then
    return g[category][name]
  end
  return fallback or ""
end

-- Shortcuts for common glyphs
local gs = g.state or {}
local gc = g.container or {}
local gr = g.review or {}
local gu = g.ui or {}
local gx = g.checkbox or {}
local gp = g.progress or {}
local gph = g.phase or {}

-- Catppuccin Mocha color palette
local colors = {
  rosewater = "#f5e0dc",
  flamingo  = "#f2cdcd",
  pink      = "#f5c2e7",
  mauve     = "#cba6f7",
  red       = "#f38ba8",
  maroon    = "#eba0ac",
  peach     = "#fab387",
  yellow    = "#f9e2af",
  green     = "#a6e3a1",
  teal      = "#94e2d5",
  sky       = "#89dceb",
  sapphire  = "#74c7ec",
  blue      = "#89b4fa",
  lavender  = "#b4befe",
  text      = "#cdd6f4",
  subtext1  = "#bac2de",
  subtext0  = "#a6adc8",
  overlay2  = "#9399b2",
  overlay1  = "#7f849c",
  overlay0  = "#6c7086",
  surface2  = "#585b70",
  surface1  = "#45475a",
  surface0  = "#313244",
  base      = "#1e1e2e",
  mantle    = "#181825",
  crust     = "#11111b",
}

-- Setup review-specific highlight groups
local function setup_review_highlights()
  local hl = vim.api.nvim_set_hl
  
  -- Headers & titles
  hl(0, "GtdReviewTitle", { fg = colors.mauve, bold = true })
  hl(0, "GtdReviewSubtitle", { fg = colors.subtext0 })
  
  -- Phases
  hl(0, "GtdPhaseClear", { fg = colors.sky, bold = true })
  hl(0, "GtdPhaseCurrent", { fg = colors.teal, bold = true })
  hl(0, "GtdPhaseCreative", { fg = colors.yellow, bold = true })
  
  -- Steps
  hl(0, "GtdStepCurrent", { fg = colors.text, bold = true })
  hl(0, "GtdStepDone", { fg = colors.green })
  hl(0, "GtdStepPending", { fg = colors.subtext0 })
  hl(0, "GtdStepIcon", { fg = colors.blue })
  
  -- Progress
  hl(0, "GtdProgressDone", { fg = colors.green })
  hl(0, "GtdProgressPending", { fg = colors.surface2 })
  hl(0, "GtdProgressText", { fg = colors.subtext1 })
  
  -- Metrics
  hl(0, "GtdMetricInbox", { fg = colors.red })
  hl(0, "GtdMetricNext", { fg = colors.peach, bold = true })
  hl(0, "GtdMetricWaiting", { fg = colors.yellow })
  hl(0, "GtdMetricProjects", { fg = colors.mauve })
  hl(0, "GtdMetricStuck", { fg = colors.red, bold = true })
  
  -- Shortcuts
  hl(0, "GtdShortcutKey", { fg = colors.mauve, bold = true })
  hl(0, "GtdShortcutDesc", { fg = colors.subtext0 })
  hl(0, "GtdShortcutHeader", { fg = colors.lavender, bold = true })
  
  -- Right panel content
  hl(0, "GtdContentTitle", { fg = colors.mauve, bold = true })
  hl(0, "GtdContentBullet", { fg = colors.blue })
  hl(0, "GtdContentText", { fg = colors.text })
  hl(0, "GtdContentHint", { fg = colors.overlay1, italic = true })
  hl(0, "GtdContentNumber", { fg = colors.peach })
  
  -- Checklist
  hl(0, "GtdChecklistChecked", { fg = colors.green })
  hl(0, "GtdChecklistUnchecked", { fg = colors.surface2 })
  hl(0, "GtdChecklistCursor", { fg = colors.mauve, bold = true })
  
  -- Marks section
  hl(0, "GtdMarksHeader", { fg = colors.flamingo, bold = true })
  hl(0, "GtdMarkKey", { fg = colors.peach, bold = true })
end

M.cfg = {
  gtd_root = "~/Documents/GTD",
  zk_root = "~/Documents/Notes",
  reviews_dir = "~/Documents/Notes/Reviews",
  review_history_file = "~/Documents/GTD/.review_history.json",
  custom_checklists_file = "~/Documents/GTD/.review_checklists.json",
  calendar_days_back = 7,
  calendar_days_forward = 14,
  icalbuddy_path = "/opt/homebrew/bin/icalBuddy",
  left_panel_width = 38,
}

local lists = safe_require("gtd-nvim.gtd.lists")
local capture = safe_require("gtd-nvim.gtd.capture")
local zettelkasten = safe_require("gtd-nvim.zettelkasten")

-- ============================================================================
-- REVIEW STEPS
-- ============================================================================

M.steps = {
  -- GET CLEAR - Reflection/capture steps → open note
  { id = "collect",    phase = "CLEAR",    label = "Collect loose papers",     icon = gc.inbox or "", action = "note", note_section = "Clear" },
  { id = "inbox",      phase = "CLEAR",    label = "Process Inbox to zero",    icon = gc.inbox or "", action = "inbox_file" },
  { id = "empty",      phase = "CLEAR",    label = "Empty your head",          icon = gph.capture or "󰐕", action = "note", note_section = "Clear" },
  -- GET CURRENT - Review actual data → open lists
  { id = "actions",    phase = "CURRENT",  label = "Review Action lists",      icon = gs.NEXT or "󱥦", action = "list", list_fn = "next_actions" },
  { id = "past_cal",   phase = "CURRENT",  label = "Review past calendar",     icon = gc.calendar or "", action = "calendar", calendar_type = "past" },
  { id = "future_cal", phase = "CURRENT",  label = "Review upcoming calendar", icon = gc.calendar or "", action = "calendar", calendar_type = "future" },
  { id = "waiting",    phase = "CURRENT",  label = "Review Waiting For",       icon = gs.WAITING or "", action = "list", list_fn = "waiting" },
  { id = "projects",   phase = "CURRENT",  label = "Review Projects",          icon = gc.projects or "󰉋", action = "list", list_fn = "projects" },
  { id = "stuck",      phase = "CURRENT",  label = "Review Stuck Projects",    icon = gp.blocked or "", action = "list", list_fn = "stuck_projects" },
  { id = "checklists", phase = "CURRENT",  label = "Review Checklists",        icon = gx.checked or "", action = "custom_checklists" },
  -- GET CREATIVE - Ideation → mix of list and note
  { id = "someday",    phase = "CREATIVE", label = "Review Someday/Maybe",     icon = gs.SOMEDAY or "󰋊", action = "list", list_fn = "someday_maybe" },
  { id = "brainstorm", phase = "CREATIVE", label = "Be creative & brainstorm", icon = gu.rocket or "", action = "note", note_section = "Creative" },
}

-- ============================================================================
-- STATE
-- ============================================================================

M.state = {
  current_step = 1,
  completed = {},
  start_time = nil,
  metrics = {},
  active = false,
  paused = false,
  buffers = {},
  review_tab = nil,
  review_note_path = nil,
  week_id = nil,
  review_id = nil,  -- Unique ID for this review session (timestamp)
  checklist_items = {},
  active_checklist = nil,
  checklist_cursor = 1,
}

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function read_json(path)
  local expanded = xp(path)
  if vim.fn.filereadable(expanded) ~= 1 then return {} end
  local content = table.concat(vim.fn.readfile(expanded), "\n")
  local ok, data = pcall(vim.fn.json_decode, content)
  return ok and data or {}
end

local function write_json(path, data)
  local expanded = xp(path)
  vim.fn.mkdir(vim.fn.fnamemodify(expanded, ":h"), "p")
  local ok, encoded = pcall(vim.fn.json_encode, data)
  if ok then vim.fn.writefile({ encoded }, expanded) end
end

local function get_week_id()
  return os.date("%Y-W%W")
end

-- Generate unique review ID (timestamp-based)
local function generate_review_id()
  return os.date("%Y%m%d%H%M%S")
end

-- Get review note path - uses review_id for uniqueness
local function get_review_note_path(review_id, week_id)
  week_id = week_id or get_week_id()
  review_id = review_id or generate_review_id()
  local reviews_dir = xp(M.cfg.reviews_dir)
  vim.fn.mkdir(reviews_dir, "p")
  -- Format: WeeklyReview-2025-W49-20251210103045.md
  return reviews_dir .. "/WeeklyReview-" .. week_id .. "-" .. review_id .. ".md"
end

-- Legacy: Get note path by week only (for backward compatibility when scanning)
local function get_legacy_review_note_path(week_id)
  week_id = week_id or get_week_id()
  local reviews_dir = xp(M.cfg.reviews_dir)
  return reviews_dir .. "/WeeklyReview-" .. week_id .. ".md"
end

local function collect_metrics()
  local gtd_root = xp(M.cfg.gtd_root)
  local m = { inbox = 0, next = 0, todo = 0, waiting = 0, someday = 0, projects = 0, stuck = 0 }
  
  local handle = io.popen(string.format("find %q -type f -name '*.org' ! -name 'Archive.org' 2>/dev/null", gtd_root))
  if not handle then return m end
  
  for filepath in handle:lines() do
    local lines = vim.fn.readfile(filepath)
    local in_inbox = filepath:match("Inbox%.org$")
    local is_project = filepath:match("/Projects/") or filepath:match("/Areas/")
    local has_next = false
    
    for _, line in ipairs(lines) do
      local state = line:match("^%*+%s+([A-Z]+)%s")
      if state then
        if state == "NEXT" then m.next = m.next + 1; has_next = true
        elseif state == "TODO" then m.todo = m.todo + 1
        elseif state == "WAITING" then m.waiting = m.waiting + 1
        elseif state == "SOMEDAY" then m.someday = m.someday + 1
        elseif state == "PROJECT" then m.projects = m.projects + 1
        end
        if in_inbox and state ~= "DONE" then m.inbox = m.inbox + 1 end
      end
    end
    if is_project and not has_next then m.stuck = m.stuck + 1 end
  end
  handle:close()
  return m
end

local function get_calendar_events(days_offset, days_count)
  local events = {}
  local icalbuddy = M.cfg.icalbuddy_path
  if vim.fn.executable(icalbuddy) ~= 1 then 
    return { "(icalBuddy not found - brew install ical-buddy)" }
  end
  
  local cmd
  if days_offset < 0 then
    local start_date = os.date("%Y-%m-%d", os.time() + days_offset * 86400)
    local end_date = os.date("%Y-%m-%d")
    cmd = string.format("%s -nc -nrd -df '%%Y-%%m-%%d' -tf '%%H:%%M' eventsFrom:%s to:%s 2>/dev/null", icalbuddy, start_date, end_date)
  else
    cmd = string.format("%s -nc -nrd -df '%%Y-%%m-%%d' -tf '%%H:%%M' eventsToday+%d 2>/dev/null", icalbuddy, days_count)
  end
  
  local handle = io.popen(cmd)
  if handle then
    for line in handle:lines() do
      if line ~= "" then 
        local cleaned = line:gsub("^%s*•%s*", "")
        table.insert(events, cleaned)
      end
    end
    handle:close()
  end
  
  return #events > 0 and events or { "(No events)" }
end

-- ============================================================================
-- TASK FETCHERS FOR RIGHT PANEL (Zen Mode)
-- ============================================================================

local function fetch_tasks_by_state(states, exclude_done)
  local gtd_root = xp(M.cfg.gtd_root)
  local tasks = {}
  
  local state_set = {}
  for _, s in ipairs(states) do state_set[s] = true end
  
  local handle = io.popen(string.format("find %q -type f -name '*.org' ! -name 'Archive.org' 2>/dev/null", gtd_root))
  if not handle then return tasks end
  
  for filepath in handle:lines() do
    local lines = vim.fn.readfile(filepath)
    local container = filepath:match("/Projects/([^/]+)") or filepath:match("/Areas/([^/]+)") or "Inbox"
    container = container:gsub("%.org$", "")
    
    for lnum, line in ipairs(lines) do
      local level, state, title = line:match("^(%*+)%s+([A-Z]+)%s+(.+)")
      if state and state_set[state] then
        -- Get context if any
        local context = line:match(":@(%w+):") or ""
        local priority = line:match("%[#([ABC])%]") or ""
        
        table.insert(tasks, {
          state = state,
          title = title:gsub("%s*:.*:", ""):gsub("%[#[ABC]%]%s*", ""), -- Clean title
          container = container,
          context = context,
          priority = priority,
          filepath = filepath,
          lnum = lnum,
        })
      end
    end
  end
  handle:close()
  
  -- Sort by priority then state
  table.sort(tasks, function(a, b)
    local pri_order = { A = 1, B = 2, C = 3, [""] = 4 }
    local state_order = { NEXT = 1, TODO = 2, WAITING = 3, SOMEDAY = 4 }
    if pri_order[a.priority] ~= pri_order[b.priority] then
      return pri_order[a.priority] < pri_order[b.priority]
    end
    return (state_order[a.state] or 9) < (state_order[b.state] or 9)
  end)
  
  return tasks
end

local function fetch_projects()
  local gtd_root = xp(M.cfg.gtd_root)
  local projects = {}
  
  local projects_dir = gtd_root .. "/Projects"
  local handle = io.popen(string.format("find %q -type f -name '*.org' 2>/dev/null", projects_dir))
  if not handle then return projects end
  
  for filepath in handle:lines() do
    local name = vim.fn.fnamemodify(filepath, ":t:r")
    local lines = vim.fn.readfile(filepath)
    local next_count, todo_count, waiting_count, done_count = 0, 0, 0, 0
    
    for _, line in ipairs(lines) do
      local state = line:match("^%*+%s+([A-Z]+)%s")
      if state == "NEXT" then next_count = next_count + 1
      elseif state == "TODO" then todo_count = todo_count + 1
      elseif state == "WAITING" then waiting_count = waiting_count + 1
      elseif state == "DONE" then done_count = done_count + 1
      end
    end
    
    local status = "active"
    if next_count == 0 and todo_count == 0 and waiting_count == 0 then
      status = "stuck"
    elseif next_count > 0 then
      status = "has_next"
    end
    
    table.insert(projects, {
      name = name,
      filepath = filepath,
      next = next_count,
      todo = todo_count,
      waiting = waiting_count,
      done = done_count,
      status = status,
    })
  end
  handle:close()
  
  -- Sort: stuck first, then by name
  table.sort(projects, function(a, b)
    if a.status == "stuck" and b.status ~= "stuck" then return true end
    if a.status ~= "stuck" and b.status == "stuck" then return false end
    return a.name < b.name
  end)
  
  return projects
end

local function fetch_inbox()
  local inbox_path = xp(M.cfg.gtd_root) .. "/Inbox.org"
  local items = {}
  
  if vim.fn.filereadable(inbox_path) ~= 1 then return items end
  
  local lines = vim.fn.readfile(inbox_path)
  for lnum, line in ipairs(lines) do
    local level, state, title = line:match("^(%*+)%s+([A-Z]+)%s+(.+)")
    if state and state ~= "DONE" then
      table.insert(items, {
        state = state,
        title = title:gsub("%s*:.*:", ""),
        lnum = lnum,
      })
    end
  end
  
  return items
end

-- ============================================================================
-- REVIEW INDEX
-- ============================================================================

-- Scan all reviews from history file
-- Returns list sorted by date (newest first)
local function scan_reviews()
  local history = read_json(M.cfg.review_history_file)
  local reviews = {}
  local current_week = get_week_id()
  
  -- Also scan for files without history entries (legacy files)
  local reviews_dir = xp(M.cfg.reviews_dir)
  local known_paths = {}
  
  -- First, add all history entries
  for _, h in ipairs(history) do
    local steps_done = h.steps or 0
    local steps_total = h.total or #M.steps
    local pct = steps_total > 0 and math.floor((steps_done / steps_total) * 100) or 0
    
    -- Check if note file exists
    local note_exists = h.note_path and vim.fn.filereadable(h.note_path) == 1
    
    -- Detect if note has user content (look for timestamped entries)
    local has_notes = false
    if note_exists then
      local lines = vim.fn.readfile(h.note_path)
      for _, line in ipairs(lines) do
        if line:match("^%- %d%d:%d%d") then
          has_notes = true
          break
        end
      end
    end
    
    table.insert(reviews, {
      review_id = h.review_id,  -- Keep original (may be nil for legacy)
      review_id_display = h.review_id or h.week,  -- For display purposes
      week_id = h.week,
      filepath = h.note_path,
      date = h.date or "?",
      time = h.time or "",
      steps = steps_done,
      total = steps_total,
      pct = pct,
      duration = h.duration or 0,
      is_current = h.week == current_week,
      is_complete = pct == 100,
      has_notes = has_notes,
      completed_ids = h.completed_ids or {},
      current_step = h.current_step or 1,
    })
    
    if h.note_path then
      known_paths[h.note_path] = true
    end
  end
  
  -- Scan for orphan files (notes without history entries)
  local handle = io.popen(string.format("ls -1 %q/WeeklyReview-*.md %q/Weekly-*.md 2>/dev/null | sort -r", reviews_dir, reviews_dir))
  if handle then
    for filepath in handle:lines() do
      if not known_paths[filepath] then
        -- Parse week_id from filename - only capture YYYY-Www pattern
        local week_id = filepath:match("WeeklyReview%-(%d%d%d%d%-W%d%d)")
          or filepath:match("Weekly%-(%d%d%d%d%-W%d%d)")
        
        if week_id then
          table.insert(reviews, {
            review_id = nil,  -- No history entry
            week_id = week_id,
            filepath = filepath,
            date = "?",
            time = "",
            steps = 0,
            total = #M.steps,
            pct = 0,
            duration = 0,
            is_current = week_id == current_week,
            is_complete = false,
            has_notes = true,  -- Has a file, so assume notes
            completed_ids = {},
            current_step = 1,
            is_orphan = true,  -- Mark as orphan
          })
        end
      end
    end
    handle:close()
  end
  
  -- Sort by date+time descending (newest first)
  table.sort(reviews, function(a, b)
    local a_key = (a.date or "0000-00-00") .. (a.time or "00:00")
    local b_key = (b.date or "0000-00-00") .. (b.time or "00:00")
    return a_key > b_key
  end)
  
  return reviews
end

function M.index()
  local reviews = scan_reviews()
  local current_week = get_week_id()
  
  if #reviews == 0 then
    vim.ui.select({"Start new review", "Cancel"}, {
      prompt = (gu.list or "") .. " No reviews found. Start one?",
    }, function(choice)
      if choice == "Start new review" then
        M.start()
      end
    end)
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    M.start()
    return
  end
  
  -- Use shared for coloring
  local colorize = shared.colorize or function(t) return t end
  
  local display = {}
  local meta = {}
  
  -- Always offer to start a new review
  local new_line = colorize((gr.current or "󰔚") .. " Start new review (" .. current_week .. ")", "accent")
  table.insert(display, new_line)
  table.insert(meta, { action = "new" })
  
  -- Add separator
  table.insert(display, colorize("─── Past Reviews ───", "muted"))
  table.insert(meta, { action = "separator" })
  
  for _, r in ipairs(reviews) do
    -- Skip empty reviews (0 progress, not orphan) - likely test/abandoned
    if r.steps == 0 and not r.is_orphan and not r.has_notes then
      goto continue
    end
    
    local status_glyph, status_color
    if not r.is_complete and r.steps > 0 then
      -- In progress
      status_glyph = gp.active or ""
      status_color = "next"
    elseif r.is_complete then
      status_glyph = gx.checked or ""
      status_color = "done"
    elseif r.is_orphan then
      -- Orphan file (no history)
      status_glyph = gu.note or "󰝗"
      status_color = "warning"
    else
      status_glyph = gp.inactive or "󰏤"
      status_color = "muted"
    end
    
    -- Use has_notes from scan
    local note_indicator = r.has_notes and (" " .. (gu.note or "󰝗")) or ""
    
    local week_display = colorize(r.week_id, "info")
    local status_display = colorize(status_glyph, status_color)
    local pct_display = r.is_complete and "" or (r.steps > 0 and colorize(" " .. r.pct .. "%", "muted") or "")
    local duration_display = r.duration > 0 and colorize(" " .. r.duration .. "m", "muted") or ""
    local note_display = colorize(note_indicator, "warning")
    local time_display = r.time ~= "" and colorize(" " .. r.time, "muted") or ""
    
    -- Format: ✓ 2025-W49  2024-12-10 10:30  12/12  45m 󰝗
    local line = string.format("%s %s  %s%s  %d/%d%s%s%s",
      status_display, week_display, r.date, time_display, r.steps, r.total, pct_display, duration_display, note_display)
    
    table.insert(display, line)
    table.insert(meta, r)
    ::continue::
  end
  
  -- Add separator and archive option at the end
  table.insert(display, colorize("────────────────────────────────", "muted"))
  table.insert(meta, { action = "separator" })
  table.insert(display, colorize((gu.archive or "󰀼") .. " Archive completed reviews", "muted"))
  table.insert(meta, { action = "archive" })
  
  local header_lines = {
    "Enter: open cockpit │ Ctrl-E: edit note │ Ctrl-D: delete │ Ctrl-B: back",
    (gx.checked or "") .. " complete  " .. (gp.active or "") .. " in progress  " .. (gu.note or "󰝗") .. " has notes"
  }
  
  -- Create index mapping for reliable selection
  local idx_map = {}
  for i, line in ipairs(display) do
    idx_map[line] = i
  end
  
  fzf.fzf_exec(display, {
    prompt = colorize((gu.list or "") .. " Reviews", "accent") .. "> ",
    winopts = { height = 0.60, width = 0.70, row = 0.15 },
    fzf_opts = { 
      ["--ansi"] = true,
      ["--header"] = table.concat(header_lines, "\n"),
    },
    actions = {
      ["default"] = function(sel)
        if not sel or #sel == 0 then return end
        local selected = sel[1]
        local idx = idx_map[selected]
        
        -- If not found, try stripping ANSI codes
        if not idx then
          local stripped = selected:gsub("\27%[[%d;]*m", "")
          for i, d in ipairs(display) do
            local d_stripped = d:gsub("\27%[[%d;]*m", "")
            if d_stripped == stripped then
              idx = i
              break
            end
          end
        end
        
        if not idx or not meta[idx] then 
          vim.notify("Could not find selected item", vim.log.levels.WARN)
          return 
        end
        
        local entry = meta[idx]
        if entry.action == "new" then
          vim.schedule(function() M.start() end)
        elseif entry.action == "separator" then
          -- Do nothing for separator
        elseif entry.action == "archive" then
          vim.schedule(function() M.archive_completed() end)
        elseif entry.review_id or entry.week_id then
          -- Always open cockpit for any review (complete or not)
          vim.schedule(function()
            M.start({ 
              review_id = entry.review_id, 
              week_id = entry.week_id, 
              resume = true 
            })
          end)
        elseif entry.filepath then
          -- Fallback: just open the note file (orphan without history)
          vim.schedule(function()
            vim.cmd("edit " .. entry.filepath)
            vim.cmd("normal! mN")
            vim.notify((gu.note or "󰝗") .. " Opened review note: " .. (entry.week_id or "?"), vim.log.levels.INFO)
          end)
        end
      end,
      ["ctrl-e"] = function(sel)
        if not sel or #sel == 0 then return end
        local selected = sel[1]
        local idx = idx_map[selected]
        if not idx then
          local stripped = selected:gsub("\27%[[%d;]*m", "")
          for i, d in ipairs(display) do
            if d:gsub("\27%[[%d;]*m", "") == stripped then idx = i; break end
          end
        end
        if idx and meta[idx] and meta[idx].filepath then
          vim.schedule(function()
            vim.cmd("edit " .. meta[idx].filepath)
            vim.cmd("normal! mN")
          end)
        end
      end,
      ["ctrl-r"] = function(sel)
        if not sel or #sel == 0 then return end
        local selected = sel[1]
        local idx = idx_map[selected]
        if not idx then
          local stripped = selected:gsub("\27%[[%d;]*m", "")
          for i, d in ipairs(display) do
            if d:gsub("\27%[[%d;]*m", "") == stripped then idx = i; break end
          end
        end
        if not idx or not meta[idx] then return end
        
        local entry = meta[idx]
        if entry.action == "new" or entry.action == "separator" or entry.action == "archive" then
          return
        end
        
        vim.schedule(function()
          if entry.review_id then
            M.start({ review_id = entry.review_id, week_id = entry.week_id, resume = true })
          elseif entry.week_id then
            -- Orphan file or no history - start fresh with that week
            M.start({ week_id = entry.week_id })
          end
        end)
      end,
      ["ctrl-d"] = function(sel)
        if not sel or #sel == 0 then return end
        local selected = sel[1]
        local idx = idx_map[selected]
        if not idx then
          local stripped = selected:gsub("\27%[[%d;]*m", "")
          for i, d in ipairs(display) do
            if d:gsub("\27%[[%d;]*m", "") == stripped then idx = i; break end
          end
        end
        if idx and meta[idx] and meta[idx].filepath then
          local entry = meta[idx]
          local label = entry.week_id .. (entry.time ~= "" and " " .. entry.time or "")
          vim.ui.select({"Yes, delete", "Cancel"}, {
            prompt = "Delete review " .. label .. "?",
          }, function(choice)
            if choice and choice:match("Yes") then
              -- Delete file
              if entry.filepath then
                vim.fn.delete(entry.filepath)
              end
              -- Remove from history
              if entry.review_id then
                local history = read_json(M.cfg.review_history_file)
                local new_history = {}
                for _, h in ipairs(history) do
                  if h.review_id ~= entry.review_id then
                    table.insert(new_history, h)
                  end
                end
                write_json(M.cfg.review_history_file, new_history)
              end
              vim.notify((gu.bullet or "") .. " Deleted " .. label, vim.log.levels.INFO)
              -- Refresh index
              vim.defer_fn(function() M.index() end, 100)
            end
          end)
        end
      end,
      ["ctrl-b"] = function(_)
        -- Go back to Lists Menu
        vim.schedule(function()
          local lists = safe_require("gtd-nvim.gtd.lists")
          if lists and lists.menu then
            lists.menu()
          end
        end)
      end,
    },
  })
end

-- Archive completed reviews older than current week
function M.archive_completed()
  local reviews = scan_reviews()
  local current_week = get_week_id()
  local reviews_dir = xp(M.cfg.reviews_dir)
  local archive_dir = reviews_dir .. "/archive"
  
  -- Find reviews to archive (complete, not current week)
  local to_archive = {}
  for _, r in ipairs(reviews) do
    if r.is_complete and not r.is_current then
      table.insert(to_archive, r)
    end
  end
  
  if #to_archive == 0 then
    vim.notify((gu.bullet or "") .. " No completed reviews to archive", vim.log.levels.INFO)
    return
  end
  
  vim.ui.select({"Archive " .. #to_archive .. " reviews", "Cancel"}, {
    prompt = (gu.archive or "󰀼") .. " Archive completed reviews?",
  }, function(choice)
    if not choice or not choice:match("Archive") then return end
    
    -- Create archive directory
    vim.fn.mkdir(archive_dir, "p")
    
    local moved = 0
    for _, r in ipairs(to_archive) do
      local filename = vim.fn.fnamemodify(r.filepath, ":t")
      local dest = archive_dir .. "/" .. filename
      if vim.fn.rename(r.filepath, dest) == 0 then
        moved = moved + 1
      end
    end
    
    vim.notify((gu.archive or "󰀼") .. " Archived " .. moved .. " reviews to archive/", vim.log.levels.INFO)
    
    -- Refresh index
    vim.defer_fn(function() M.index() end, 100)
  end)
end

-- ============================================================================
-- REVIEW NOTE
-- ============================================================================

local function create_review_note(week_id, review_id)
  week_id = week_id or get_week_id()
  review_id = review_id or generate_review_id()
  local filepath = get_review_note_path(review_id, week_id)
  
  if vim.fn.filereadable(filepath) == 1 then
    return filepath, false
  end
  
  local m = collect_metrics()
  
  -- Simple, clean template using shared glyphs
  local lines = {
    "---",
    "id: " .. review_id,
    "title: Review " .. week_id,
    "date: " .. os.date("%Y-%m-%d"),
    "time: " .. os.date("%H:%M"),
    "tags: [gtd, review]",
    "---",
    "",
    "# " .. (gu.list or "") .. " " .. week_id,
    "",
    (gu.clock or "") .. " " .. os.date("%Y-%m-%d %H:%M"),
    "",
    "## " .. (gr.clear or "󰃢") .. " Clear",
    "",
    "",
    "## " .. (gr.current or "󰔚") .. " Current",
    "",
    "",
    "## " .. (gr.creative or "󰌵") .. " Creative",
    "",
    "",
    "## " .. (gs.NEXT or "󱥦") .. " Actions",
    "",
    "",
    "---",
    "",
    "## " .. (gx.checked or "") .. " Done",
    "",
    "_auto-updated_",
    "",
  }
  
  vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")
  vim.fn.writefile(lines, filepath)
  return filepath, true
end

local function update_review_note_completion()
  if not M.state.review_note_path then return end
  if vim.fn.filereadable(M.state.review_note_path) ~= 1 then return end
  
  local lines = vim.fn.readfile(M.state.review_note_path)
  local new_lines = {}
  local in_done = false
  
  for _, line in ipairs(lines) do
    -- Match the "Done" section header (## ✓ Done or ## 󰸟 Done)
    if line:match("^## .*Done") then
      in_done = true
      table.insert(new_lines, line)
      table.insert(new_lines, "")
      -- Add completion summary
      local pct = math.floor((vim.tbl_count(M.state.completed) / #M.steps) * 100)
      table.insert(new_lines, (gu.bullet or "") .. " " .. vim.tbl_count(M.state.completed) .. "/" .. #M.steps .. " steps (" .. pct .. "%)")
      if M.state.start_time then
        table.insert(new_lines, (gu.clock or "") .. " " .. math.floor((os.time() - M.state.start_time) / 60) .. " min")
      end
      table.insert(new_lines, "")
    elseif in_done and line:match("^#") then
      -- Hit next section
      in_done = false
      table.insert(new_lines, line)
    elseif in_done and line:match("^%-%-%-$") then
      in_done = false
      table.insert(new_lines, line)
    elseif not in_done then
      table.insert(new_lines, line)
    end
  end
  
  vim.fn.writefile(new_lines, M.state.review_note_path)
end

function M.capture_to_note()
  if not M.state.review_note_path then
    vim.notify("No review note active", vim.log.levels.WARN)
    return
  end
  
  local step = M.steps[M.state.current_step]
  local phase = step and step.phase or "Current"
  
  -- Map phase to section header
  local section_map = {
    CLEAR = "Clear",
    CURRENT = "Current", 
    CREATIVE = "Creative",
  }
  local section_name = section_map[phase] or "Current"
  
  vim.ui.input({ prompt = (gu.note or "󰝗") .. " " .. section_name .. ": " }, function(input)
    if not input or input == "" then return end
    
    local lines = vim.fn.readfile(M.state.review_note_path)
    local new_lines = {}
    local inserted = false
    
    for i, line in ipairs(lines) do
      table.insert(new_lines, line)
      -- Match section headers like "## 󰃢 Clear" or "## 󰔚 Current"
      if not inserted and line:match("^## .* " .. section_name .. "$") then
        -- Skip any existing empty lines after header
        local j = i + 1
        while j <= #lines and lines[j] == "" do
          j = j + 1
        end
        -- Add the note with timestamp
        table.insert(new_lines, "")
        table.insert(new_lines, "- " .. os.date("%H:%M") .. " " .. input)
        inserted = true
      end
    end
    
    -- If no section found, append to Actions section
    if not inserted then
      for i, line in ipairs(new_lines) do
        if line:match("^## .* Actions") then
          table.insert(new_lines, i + 1, "")
          table.insert(new_lines, i + 2, "- " .. os.date("%H:%M") .. " " .. input)
          inserted = true
          break
        end
      end
    end
    
    if inserted then
      vim.fn.writefile(new_lines, M.state.review_note_path)
      vim.notify((gu.note or "󰝗") .. " Added to " .. section_name, vim.log.levels.INFO)
    else
      vim.notify("Could not find section", vim.log.levels.WARN)
    end
  end)
end

function M.open_review_note()
  if not M.state.review_note_path then
    vim.notify("No review note active", vim.log.levels.WARN)
    return
  end
  -- Move to right split first, then open the note there
  vim.cmd("wincmd l")
  vim.cmd("edit " .. M.state.review_note_path)
  -- Set global mark N for review Note (must use normal mode mN)
  vim.cmd("normal! mN")
  vim.notify((gu.note or "󰝗") .. " Mark 'N set for review note", vim.log.levels.INFO)
end

-- ============================================================================
-- CHECKLISTS
-- ============================================================================

local function load_checklists()
  local data = read_json(M.cfg.custom_checklists_file)
  if vim.tbl_isempty(data) then
    data = {
      weekly = { 
        name = "Weekly Review Prep", 
        items = {
          { id = "desk", label = "Clear physical desk/workspace" },
          { id = "downloads", label = "Process Downloads folder" },
          { id = "notes", label = "Review notes & Zettelkasten", action = "zettelkasten" },
          { id = "wallet", label = "Empty wallet receipts" },
          { id = "voice", label = "Process voice memos" },
          { id = "email", label = "Inbox zero (email)" },
        }
      },
      monthly = { 
        name = "Monthly Review", 
        items = {
          { id = "goals", label = "Review monthly goals" },
          { id = "habits", label = "Evaluate habits & routines" },
          { id = "finances", label = "Review financial summaries" },
          { id = "subscriptions", label = "Review subscriptions" },
        }
      },
      triggers = {
        name = "Trigger List (Mind Sweep)",
        items = {
          { id = "projects_work", label = "Professional projects" },
          { id = "projects_personal", label = "Personal projects" },
          { id = "meetings", label = "Upcoming meetings/events" },
          { id = "people", label = "People to contact" },
          { id = "errands", label = "Errands to run" },
          { id = "home", label = "Home improvements" },
          { id = "health", label = "Health/medical" },
          { id = "family", label = "Family commitments" },
          { id = "learning", label = "Learning/courses" },
          { id = "finances", label = "Financial tasks" },
          { id = "travel", label = "Travel plans" },
          { id = "creative", label = "Creative projects" },
        }
      },
    }
    write_json(M.cfg.custom_checklists_file, data)
  end
  return data
end

-- ============================================================================
-- HISTORY
-- ============================================================================

local function get_last_review()
  local history = read_json(M.cfg.review_history_file)
  return history[#history]
end

local function save_review_history()
  local history = read_json(M.cfg.review_history_file)
  
  -- Validate week_id - must be YYYY-Www format
  local function validate_week(wid)
    if wid and wid:match("^%d%d%d%d%-W%d%d$") then return wid end
    if wid then
      local extracted = wid:match("(%d%d%d%d%-W%d%d)")
      if extracted then return extracted end
    end
    return get_week_id()
  end
  
  local week_id = validate_week(M.state.week_id)
  local review_id = M.state.review_id or generate_review_id()
  
  -- Find existing entry by review_id (unique per session)
  local existing_idx
  for i, entry in ipairs(history) do
    if entry.review_id == review_id then existing_idx = i; break end
  end
  
  -- Convert completed table to list of step IDs for persistence
  local completed_ids = {}
  for step_id, _ in pairs(M.state.completed) do
    table.insert(completed_ids, step_id)
  end
  
  local entry = {
    review_id = review_id,  -- Unique ID for this session
    date = os.date("%Y-%m-%d"),
    time = os.date("%H:%M"),
    week = week_id,  -- Validated week ID
    duration = M.state.start_time and math.floor((os.time() - M.state.start_time) / 60) or 0,
    steps = vim.tbl_count(M.state.completed),
    total = #M.steps,
    note_path = M.state.review_note_path,
    completed_ids = completed_ids,
    current_step = M.state.current_step,
  }
  
  if existing_idx then
    -- Update existing session (accumulate duration)
    entry.duration = (history[existing_idx].duration or 0) + entry.duration
    history[existing_idx] = entry
  else
    -- New session
    table.insert(history, entry)
  end
  
  -- Keep last 100 reviews (not just 52 weeks)
  while #history > 100 do table.remove(history, 1) end
  write_json(M.cfg.review_history_file, history)
end

-- Helper to load saved progress for a specific review session
local function load_saved_progress(review_id, week_id)
  local history = read_json(M.cfg.review_history_file)
  
  -- First try exact review_id match
  if review_id then
    for _, entry in ipairs(history) do
      if entry.review_id == review_id then
        return entry
      end
    end
  end
  
  -- Fallback: match by week_id for legacy entries without review_id
  if week_id then
    for _, entry in ipairs(history) do
      if not entry.review_id and entry.week == week_id then
        return entry
      end
    end
  end
  
  return nil
end

-- Find the most recent incomplete review (any week)
local function find_incomplete_review()
  local history = read_json(M.cfg.review_history_file)
  -- Search from most recent
  for i = #history, 1, -1 do
    local entry = history[i]
    if entry.steps < entry.total then
      return entry
    end
  end
  return nil
end

-- ============================================================================
-- UI RENDERING
-- ============================================================================

local function render_left()
  local buf = M.state.buffers.left
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local lines = {}
  local phase = nil
  
  -- Header
  table.insert(lines, "")
  table.insert(lines, "  " .. (gu.list or "") .. " GTD WEEKLY REVIEW")
  table.insert(lines, "  " .. (M.state.week_id or get_week_id()) .. " " .. (gu.bullet or "") .. " " .. os.date("%Y-%m-%d"))
  table.insert(lines, "")
  
  -- Steps with phase headers
  for i, step in ipairs(M.steps) do
    if step.phase ~= phase then
      phase = step.phase
      table.insert(lines, "")
      if phase == "CLEAR" then 
        table.insert(lines, "  " .. (gr.clear or "󰃢") .. " GET CLEAR")
      elseif phase == "CURRENT" then 
        table.insert(lines, "  " .. (gr.current or "󰔚") .. " GET CURRENT")
      elseif phase == "CREATIVE" then 
        table.insert(lines, "  " .. (gr.creative or "󰌵") .. " GET CREATIVE")
      end
    end
    local done = M.state.completed[step.id] and (gx.checked or "") or (gx.unchecked or "")
    local cursor = i == M.state.current_step and (gu.arrow_right or "") or " "
    table.insert(lines, "  " .. cursor .. " " .. done .. " " .. step.icon .. " " .. step.label)
  end
  
  -- Progress
  table.insert(lines, "")
  local completed = vim.tbl_count(M.state.completed)
  local pct = math.floor((completed / #M.steps) * 100)
  local bar = string.rep("█", math.floor(completed / #M.steps * 16)) .. string.rep("░", 16 - math.floor(completed / #M.steps * 16))
  table.insert(lines, "  " .. bar .. " " .. pct .. "%")
  table.insert(lines, "  Steps: " .. completed .. "/" .. #M.steps)
  
  if M.state.start_time then
    table.insert(lines, "  " .. (gu.clock or "") .. " " .. math.floor((os.time() - M.state.start_time) / 60) .. " min")
  end
  
  local last = get_last_review()
  if last and last.week ~= M.state.week_id then
    table.insert(lines, "  Last: " .. (last.date or "?"))
  end
  
  -- Metrics
  table.insert(lines, "")
  local m = M.state.metrics
  table.insert(lines, "  " .. (gc.inbox or "") .. " " .. (m.inbox or 0) .. "  " .. (gs.NEXT or "󱥦") .. " " .. (m.next or 0) .. "  " .. (gs.WAITING or "") .. " " .. (m.waiting or 0))
  table.insert(lines, "  " .. (gc.projects or "󰉋") .. " " .. (m.projects or 0) .. "  " .. (gp.blocked or "") .. " " .. (m.stuck or 0))
  
  -- Shortcuts
  table.insert(lines, "")
  table.insert(lines, "  **Shortcuts**")
  table.insert(lines, "  j/k       Navigate")
  table.insert(lines, "  Space     Toggle done")
  table.insert(lines, "  Enter     Execute")
  table.insert(lines, "  n         Next incomplete")
  table.insert(lines, "")
  table.insert(lines, "  c         Capture note")
  table.insert(lines, "  o         Open note (sets 'N)")
  table.insert(lines, "  r         Refresh")
  table.insert(lines, "  i         Index")
  table.insert(lines, "")
  table.insert(lines, "  **Marks** (persist across buffers)")
  table.insert(lines, "  'R        Review cockpit")
  table.insert(lines, "  'N        Review Note")
  table.insert(lines, "  'W        Last Worked item")
  table.insert(lines, "")
  table.insert(lines, "  Ctrl-B    Return here")
  table.insert(lines, "  m         Mark all done")
  table.insert(lines, "  s         Save & close")
  table.insert(lines, "  S         All done + Save")
  table.insert(lines, "  W         " .. (gx.checked or "") .. " Review Complete")
  table.insert(lines, "  q         Quit")
  
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  
  -- Apply syntax highlighting
  local ns = vim.api.nvim_create_namespace("gtd_review_left")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  
  for i, line in ipairs(lines) do
    local row = i - 1
    -- Title
    if line:match("GTD WEEKLY REVIEW") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdReviewTitle", row, 0, -1)
    -- Week ID line
    elseif line:match("^%s+%d%d%d%d%-W%d+") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdReviewSubtitle", row, 0, -1)
    -- Phase headers
    elseif line:match("GET CLEAR") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdPhaseClear", row, 0, -1)
    elseif line:match("GET CURRENT") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdPhaseCurrent", row, 0, -1)
    elseif line:match("GET CREATIVE") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdPhaseCreative", row, 0, -1)
    -- Progress bar
    elseif line:match("█") or line:match("░") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdProgressText", row, 0, -1)
    -- Steps counter
    elseif line:match("^%s+Steps:") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdProgressText", row, 0, -1)
    -- Time
    elseif line:match("min$") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdProgressText", row, 0, -1)
    -- Shortcuts header
    elseif line:match("%*%*Shortcuts%*%*") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdShortcutHeader", row, 0, -1)
    -- Marks header
    elseif line:match("%*%*Marks%*%*") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMarksHeader", row, 0, -1)
    -- Mark keys ('R, 'N, 'W)
    elseif line:match("^%s+'[RNW]") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMarkKey", row, 0, 5)
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdShortcutDesc", row, 5, -1)
    -- Shortcut keys
    elseif line:match("^%s+[jknorics]%s") or line:match("^%s+Space") or line:match("^%s+Enter") or line:match("^%s+Ctrl") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdShortcutKey", row, 0, 12)
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdShortcutDesc", row, 12, -1)
    -- Metrics line with inbox
    elseif line:match(gc.inbox or "") and line:match(gs.NEXT or "󱥦") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMetricInbox", row, 0, -1)
    -- Metrics line with projects
    elseif line:match(gc.projects or "󰉋") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMetricProjects", row, 0, -1)
    -- Current step (has arrow)
    elseif line:match(gu.arrow_right or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdStepCurrent", row, 0, -1)
    -- Completed step (has check)
    elseif line:match(gx.checked or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdStepDone", row, 0, -1)
    -- Pending step
    elseif line:match(gx.unchecked or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdStepPending", row, 0, -1)
    end
  end
end

local function render_right(content)
  local buf = M.state.buffers.right
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  local lines = {}
  local step = M.steps[M.state.current_step]
  
  -- Header
  local title = step and (step.icon .. " " .. step.label) or "GTD Review"
  table.insert(lines, "")
  table.insert(lines, "  # " .. title)
  table.insert(lines, "")
  
  if content == "checklist" or content == "collect_note" then
    table.insert(lines, "  Gather all loose materials into your inbox:")
    table.insert(lines, "")
    table.insert(lines, "  " .. (gx.unchecked or "") .. " Business cards & receipts")
    table.insert(lines, "  " .. (gx.unchecked or "") .. " Paper notes & post-its")
    table.insert(lines, "  " .. (gx.unchecked or "") .. " Meeting notes")
    table.insert(lines, "  " .. (gx.unchecked or "") .. " Items from bags, pockets, wallet")
    table.insert(lines, "  " .. (gx.unchecked or "") .. " Desktop & Downloads folder")
    table.insert(lines, "  " .. (gx.unchecked or "") .. " Voice memos & photos")
    table.insert(lines, "")
    table.insert(lines, "  *Enter to open note, c for quick capture*")
    
  elseif content == "inbox" then
    local items = fetch_inbox()
    table.insert(lines, "  " .. (gc.inbox or "") .. " **" .. #items .. " items** to process")
    table.insert(lines, "")
    
    if #items == 0 then
      table.insert(lines, "  " .. (gx.checked or "") .. " Inbox is empty!")
    else
      for i, item in ipairs(items) do
        if i > 20 then 
          table.insert(lines, "  " .. (gu.bullet or "") .. " ... and " .. (#items - 20) .. " more")
          break
        end
        local state_glyph = gs[item.state] or ""
        table.insert(lines, "  " .. state_glyph .. " " .. item.title)
      end
    end
    table.insert(lines, "")
    table.insert(lines, "  *Enter to open Inbox list*")

  elseif content == "capture" or content == "empty_note" then
    table.insert(lines, "  What's on your mind that hasn't been captured?")
    table.insert(lines, "")
    table.insert(lines, "  " .. (gu.bullet or "") .. " Things you've been procrastinating")
    table.insert(lines, "  " .. (gu.bullet or "") .. " Commitments you've made")
    table.insert(lines, "  " .. (gu.bullet or "") .. " Nagging ideas or worries")
    table.insert(lines, "  " .. (gu.bullet or "") .. " Anything causing mental clutter")
    table.insert(lines, "")
    table.insert(lines, "  *Enter to open note, c for quick capture*")

  elseif content == "next_actions" then
    local tasks = fetch_tasks_by_state({"NEXT", "TODO"})
    local next_count = 0
    local todo_count = 0
    for _, t in ipairs(tasks) do
      if t.state == "NEXT" then next_count = next_count + 1 else todo_count = todo_count + 1 end
    end
    
    table.insert(lines, "  " .. (gs.NEXT or "󱥦") .. " **" .. next_count .. "** NEXT  " .. (gs.TODO or "") .. " **" .. todo_count .. "** TODO")
    table.insert(lines, "")
    
    -- Group by container
    local by_container = {}
    for _, t in ipairs(tasks) do
      by_container[t.container] = by_container[t.container] or {}
      table.insert(by_container[t.container], t)
    end
    
    local containers = {}
    for c in pairs(by_container) do table.insert(containers, c) end
    table.sort(containers)
    
    local shown = 0
    for _, container in ipairs(containers) do
      if shown >= 25 then
        table.insert(lines, "")
        table.insert(lines, "  " .. (gu.bullet or "") .. " ... more items (Enter to see all)")
        break
      end
      table.insert(lines, "  ## " .. container)
      for _, t in ipairs(by_container[container]) do
        if shown >= 25 then break end
        local glyph = gs[t.state] or ""
        local pri = t.priority ~= "" and "[#" .. t.priority .. "] " or ""
        local ctx = t.context ~= "" and " @" .. t.context or ""
        table.insert(lines, "  " .. glyph .. " " .. pri .. t.title .. ctx)
        shown = shown + 1
      end
      table.insert(lines, "")
    end
    
    table.insert(lines, "  *Enter to open in fzf, c to capture note*")
    
  elseif content == "calendar_past" then
    table.insert(lines, "  Review last " .. M.cfg.calendar_days_back .. " days for follow-ups:")
    table.insert(lines, "")
    local events = get_calendar_events(-M.cfg.calendar_days_back, M.cfg.calendar_days_back)
    for _, e in ipairs(events) do
      table.insert(lines, "  " .. (gc.calendar or "") .. " " .. e)
    end
    table.insert(lines, "")
    table.insert(lines, "  *c to capture follow-up tasks*")
    
  elseif content == "calendar_future" then
    table.insert(lines, "  Prepare for next " .. M.cfg.calendar_days_forward .. " days:")
    table.insert(lines, "")
    local events = get_calendar_events(0, M.cfg.calendar_days_forward)
    for _, e in ipairs(events) do
      table.insert(lines, "  " .. (gc.calendar or "") .. " " .. e)
    end
    table.insert(lines, "")
    table.insert(lines, "  *c to capture preparation tasks*")
    
  elseif content == "waiting" then
    local tasks = fetch_tasks_by_state({"WAITING"})
    table.insert(lines, "  " .. (gs.WAITING or "") .. " **" .. #tasks .. "** items waiting")
    table.insert(lines, "")
    
    if #tasks == 0 then
      table.insert(lines, "  " .. (gx.checked or "") .. " Nothing waiting!")
    else
      -- Group by container
      local by_container = {}
      for _, t in ipairs(tasks) do
        by_container[t.container] = by_container[t.container] or {}
        table.insert(by_container[t.container], t)
      end
      
      for container, ctasks in pairs(by_container) do
        table.insert(lines, "  ## " .. container)
        for i, t in ipairs(ctasks) do
          if i > 10 then
            table.insert(lines, "  " .. (gu.bullet or "") .. " ... and " .. (#ctasks - 10) .. " more")
            break
          end
          table.insert(lines, "  " .. (gs.WAITING or "") .. " " .. t.title)
        end
        table.insert(lines, "")
      end
    end
    
    table.insert(lines, "  *Enter to open Waiting list*")
    
  elseif content == "projects" then
    local projects = fetch_projects()
    local active = 0
    local stuck = 0
    for _, p in ipairs(projects) do
      if p.status == "stuck" then stuck = stuck + 1 else active = active + 1 end
    end
    
    table.insert(lines, "  " .. (gc.projects or "󰉋") .. " **" .. #projects .. "** projects (" .. (gp.blocked or "") .. " " .. stuck .. " stuck)")
    table.insert(lines, "")
    
    for i, p in ipairs(projects) do
      if i > 20 then
        table.insert(lines, "  " .. (gu.bullet or "") .. " ... and " .. (#projects - 20) .. " more")
        break
      end
      local status_glyph
      if p.status == "stuck" then
        status_glyph = gp.blocked or ""
      elseif p.next > 0 then
        status_glyph = gs.NEXT or "󱥦"
      else
        status_glyph = gc.projects or "󰉋"
      end
      local stats = string.format("(%d/%d/%d)", p.next, p.todo, p.waiting)
      table.insert(lines, "  " .. status_glyph .. " " .. p.name .. " " .. stats)
    end
    table.insert(lines, "")
    table.insert(lines, "  *Enter to open Projects list*")

  elseif content == "stuck" then
    local projects = fetch_projects()
    local stuck = {}
    for _, p in ipairs(projects) do
      if p.status == "stuck" then table.insert(stuck, p) end
    end
    
    table.insert(lines, "  " .. (gp.blocked or "") .. " **" .. #stuck .. "** stuck projects (no NEXT action)")
    table.insert(lines, "")
    
    if #stuck == 0 then
      table.insert(lines, "  " .. (gx.checked or "") .. " All projects have NEXT actions!")
    else
      for _, p in ipairs(stuck) do
        table.insert(lines, "  " .. (gp.blocked or "") .. " " .. p.name)
        table.insert(lines, "     " .. (gu.bullet or "") .. " What's the very next action?")
      end
    end
    table.insert(lines, "")
    table.insert(lines, "  *Enter to open Stuck Projects list*")
    
  elseif content == "custom_checklists" then
    local checklists = load_checklists()
    
    if M.state.active_checklist then
      local cl = checklists[M.state.active_checklist]
      if cl then
        table.insert(lines, "  ## " .. cl.name)
        table.insert(lines, "")
        
        local items = cl.items or {}
        local checked = M.state.checklist_items[M.state.active_checklist] or {}
        
        for i, item in ipairs(items) do
          local is_current = (i == M.state.checklist_cursor)
          local is_checked = checked[item.id or item.label]
          local checkbox = is_checked and (gx.checked or "") or (gx.unchecked or "")
          local cursor = is_current and (gu.arrow_right or "") .. " " or "  "
          local action_hint = item.action and " " .. (gu.link or "") or ""
          table.insert(lines, "  " .. cursor .. checkbox .. " " .. item.label .. action_hint)
        end
        
        table.insert(lines, "")
        table.insert(lines, "  *j/k: move, Space: toggle, b: back, a: all*")
      end
    else
      table.insert(lines, "  Select a checklist:")
      table.insert(lines, "")
      
      local keys = {}
      for k in pairs(checklists) do table.insert(keys, k) end
      table.sort(keys)
      
      for i, k in ipairs(keys) do
        local cl = checklists[k]
        local checked = M.state.checklist_items[k] or {}
        local total = #(cl.items or {})
        local done = 0
        for _, item in ipairs(cl.items or {}) do
          if checked[item.id or item.label] then done = done + 1 end
        end
        local status = done == total and (gx.checked or "") or string.format("(%d/%d)", done, total)
        table.insert(lines, "  " .. i .. ". " .. cl.name .. " " .. status)
      end
      
      table.insert(lines, "")
      table.insert(lines, "  *Press 1, 2, or 3 to select*")
    end
    
  elseif content == "someday" then
    local tasks = fetch_tasks_by_state({"SOMEDAY"})
    table.insert(lines, "  " .. (gs.SOMEDAY or "󰋊") .. " **" .. #tasks .. "** someday/maybe items")
    table.insert(lines, "")
    
    if #tasks == 0 then
      table.insert(lines, "  " .. (gu.bullet or "") .. " No someday items")
    else
      -- Group by container
      local by_container = {}
      for _, t in ipairs(tasks) do
        by_container[t.container] = by_container[t.container] or {}
        table.insert(by_container[t.container], t)
      end
      
      local shown = 0
      for container, ctasks in pairs(by_container) do
        if shown >= 20 then break end
        table.insert(lines, "  ## " .. container)
        for i, t in ipairs(ctasks) do
          if shown >= 20 then
            table.insert(lines, "  " .. (gu.bullet or "") .. " ... more")
            break
          end
          table.insert(lines, "  " .. (gs.SOMEDAY or "󰋊") .. " " .. t.title)
          shown = shown + 1
        end
        table.insert(lines, "")
      end
    end
    
    table.insert(lines, "  *Enter to open Someday list, c to capture*")
    
  elseif content == "brainstorm" or content == "brainstorm_note" then
    table.insert(lines, "  " .. (gr.creative or "󰌵") .. " Creative thinking time...")
    table.insert(lines, "")
    table.insert(lines, "  Ask yourself:")
    table.insert(lines, "")
    table.insert(lines, "  " .. (gu.bullet or "") .. " What would make the biggest difference?")
    table.insert(lines, "  " .. (gu.bullet or "") .. " What am I avoiding?")
    table.insert(lines, "  " .. (gu.bullet or "") .. " What would I do if I couldn't fail?")
    table.insert(lines, "  " .. (gu.bullet or "") .. " What's draining my energy?")
    table.insert(lines, "  " .. (gu.bullet or "") .. " What am I most excited about?")
    table.insert(lines, "  " .. (gu.bullet or "") .. " Any new projects brewing?")
    table.insert(lines, "")
    table.insert(lines, "  *Enter to open note, c for quick capture*")
    
  else
    -- Welcome / default
    table.insert(lines, "  *\"Your mind is for having ideas, not holding them.\"*")
    table.insert(lines, "  — David Allen")
    table.insert(lines, "")
    table.insert(lines, "  Navigate with j/k, Enter to act, Space to complete")
    if M.state.review_note_path then
      table.insert(lines, "  Press 'o' to open review note")
    end
  end
  
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  
  -- Apply syntax highlighting to right panel
  local ns = vim.api.nvim_create_namespace("gtd_review_right")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  
  for i, line in ipairs(lines) do
    local row = i - 1
    -- Title (# header)
    if line:match("^%s+# ") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdContentTitle", row, 0, -1)
    -- Section header (##)
    elseif line:match("^%s+## ") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdReviewSubtitle", row, 0, -1)
    -- NEXT tasks
    elseif line:match(gs.NEXT or "󱥦") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMetricNext", row, 0, -1)
    -- WAITING tasks
    elseif line:match(gs.WAITING or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMetricWaiting", row, 0, -1)
    -- SOMEDAY tasks
    elseif line:match(gs.SOMEDAY or "󰋊") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdStepPending", row, 0, -1)
    -- Stuck/blocked
    elseif line:match(gp.blocked or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMetricStuck", row, 0, -1)
    -- Calendar events
    elseif line:match(gc.calendar or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMetricProjects", row, 0, -1)
    -- Bullet points
    elseif line:match("^%s+" .. (gu.bullet or "")) then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdContentBullet", row, 0, 4)
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdContentText", row, 4, -1)
    -- Numbered items
    elseif line:match("^%s+%d+%.") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdContentNumber", row, 0, 5)
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdContentText", row, 5, -1)
    -- Italic hints (*text*)
    elseif line:match("^%s+%*.*%*$") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdContentHint", row, 0, -1)
    -- Bold metrics (**X items**)
    elseif line:match("%*%*%d+") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdMetricNext", row, 0, -1)
    -- Quote (—)
    elseif line:match("^%s+—") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdContentHint", row, 0, -1)
    -- Checklist checked
    elseif line:match(gx.checked or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdChecklistChecked", row, 0, -1)
    -- Checklist unchecked with cursor
    elseif line:match(gu.arrow_right or "") and line:match(gx.unchecked or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdChecklistCursor", row, 0, -1)
    -- Checklist unchecked
    elseif line:match(gx.unchecked or "") then
      vim.api.nvim_buf_add_highlight(buf, ns, "GtdChecklistUnchecked", row, 0, -1)
    end
  end
end

local function refresh_ui()
  render_left()
  local step = M.steps[M.state.current_step]
  if not step then
    render_right("welcome")
    return
  end
  
  -- Map step action to content type for render_right preview
  local content
  if step.action == "note" then
    -- For note steps, show guidance based on step
    if step.id == "collect" then
      content = "collect_note"
    elseif step.id == "empty" then
      content = "empty_note"
    elseif step.id == "brainstorm" then
      content = "brainstorm_note"
    else
      content = "note_generic"
    end
  elseif step.action == "inbox_file" then
    content = "inbox"
  elseif step.action == "list" then
    -- For list steps, show preview of the data
    content = step.list_fn or step.id
  elseif step.action == "calendar" then
    content = step.calendar_type == "past" and "calendar_past" or "calendar_future"
  elseif step.action == "custom_checklists" then
    content = "custom_checklists"
  else
    content = step.action or "welcome"
  end
  
  render_right(content)
end

-- ============================================================================
-- STEP CONTENT DISPLAY (Clean Implementation)
-- ============================================================================

-- Ensure right panel has a valid scratch buffer
local function ensure_right_scratch_buffer()
  local buf = M.state.buffers.right
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local ok, buftype = pcall(vim.api.nvim_buf_get_option, buf, "buftype")
    if ok and buftype == "nofile" then
      return buf
    end
  end
  vim.cmd("wincmd l")
  local new_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(new_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(new_buf, "bufhidden", "hide")
  vim.api.nvim_buf_set_name(new_buf, "GTD-Review-Content-" .. os.time())
  vim.api.nvim_set_current_buf(new_buf)
  M.state.buffers.right = new_buf
  vim.cmd("wincmd h")
  return new_buf
end

-- Navigate: show preview only, Enter triggers action
function M.show_step_content()
  render_left()
  local step = M.steps[M.state.current_step]
  if not step then
    ensure_right_scratch_buffer()
    render_right("welcome")
    return
  end
  ensure_right_scratch_buffer()
  local content
  if step.action == "note" then
    if step.id == "collect" then content = "collect_note"
    elseif step.id == "empty" then content = "empty_note"
    elseif step.id == "brainstorm" then content = "brainstorm_note"
    else content = "note_generic" end
  elseif step.action == "inbox_file" then
    content = "inbox"
  elseif step.action == "list" then
    content = step.list_fn or step.id
  elseif step.action == "calendar" then
    content = step.calendar_type == "past" and "calendar_past" or "calendar_future"
  elseif step.action == "custom_checklists" then
    content = "custom_checklists"
  else
    content = step.action or "welcome"
  end
  render_right(content)
end

-- Execute action on Enter
function M.execute_step_action()
  local step = M.steps[M.state.current_step]
  if not step then return end
  local action = step.action
  
  -- Save any unsaved changes in right panel before switching
  M.save_right_panel()
  
  if action == "note" then
    M.open_note_in_right_panel(step)
    vim.cmd("wincmd l")
    M.setup_return_keymap()
    vim.notify((gu.note or "󰝗") .. " Edit note - Ctrl-B to return", vim.log.levels.INFO)
  elseif action == "inbox_file" then
    M.open_file_in_right_panel(xp(M.cfg.gtd_root) .. "/Inbox.org")
    vim.cmd("wincmd l")
    M.setup_return_keymap()
    vim.notify((gc.inbox or "") .. " Process inbox - Ctrl-B to return", vim.log.levels.INFO)
  elseif action == "list" then
    -- Move to right panel first, then open fzf so files open there
    vim.cmd("wincmd l")
    local list_fn = step.list_fn
    if list_fn and lists and lists[list_fn] then
      -- Set up autocmd to add Ctrl-B after fzf opens a file
      M.setup_fzf_return_hook()
      -- Use floating fzf (reliable)
      lists[list_fn]()
    else
      vim.notify("List function not available: " .. (list_fn or "nil"), vim.log.levels.WARN)
    end
  elseif action == "calendar" then
    -- Calendar is already shown in preview - just notify
    vim.notify((gc.calendar or "") .. " Review calendar events above, press 'c' to capture notes", vim.log.levels.INFO)
  elseif action == "custom_checklists" then
    if not M.state.active_checklist then
      vim.notify("Press 1, 2, or 3 to select a checklist", vim.log.levels.INFO)
    end
  end
end

-- Set up Ctrl-B keymap in current buffer to return to review
function M.setup_return_keymap()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-b>", 
    ":lua require('gtd-nvim.gtd.review').return_to_cockpit()<CR>", 
    { noremap = true, silent = true, desc = "Return to Review" })
end

-- Set up autocmd to add Ctrl-B after fzf opens a file
function M.setup_fzf_return_hook()
  local group = vim.api.nvim_create_augroup("GtdReviewFzfReturn", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      -- Skip fzf buffers and scratch buffers
      local bt = vim.api.nvim_buf_get_option(ev.buf, "buftype")
      if bt == "nofile" or bt == "prompt" then 
        return  -- Keep waiting for real file
      end
      
      -- This is a real file - set up return keymap and clear autocmd
      vim.schedule(function()
        M.setup_return_keymap()
        vim.notify((gu.bullet or "•") .. " Editing task - Ctrl-B to return", vim.log.levels.INFO)
      end)
      
      -- Clear the autocmd group now that we've set up the keymap
      vim.api.nvim_del_augroup_by_name("GtdReviewFzfReturn")
    end,
  })
end

-- Return to review cockpit at same step
function M.return_to_cockpit()
  -- Save current buffer if modified
  local bufnr = vim.api.nvim_get_current_buf()
  local modified = vim.api.nvim_buf_get_option(bufnr, "modified")
  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
  
  if modified and buftype == "" then
    vim.cmd("write")
  end
  
  -- Rebuild cockpit UI at same step
  M.rebuild_cockpit()
end

-- Rebuild the cockpit UI preserving current step
function M.rebuild_cockpit()
  -- Close any existing review buffers
  for _, buf in pairs(M.state.buffers or {}) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  M.state.buffers = {}
  
  -- Create fresh split layout
  vim.cmd("vsplit")
  vim.cmd("wincmd h")
  vim.cmd("vertical resize " .. M.cfg.left_panel_width)
  
  -- Left panel (cockpit)
  local left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(left_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(left_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(left_buf, "GTD-Review-Steps")
  vim.api.nvim_set_current_buf(left_buf)
  vim.wo.number = false
  vim.wo.relativenumber = false
  M.state.buffers.left = left_buf
  
  -- Right panel
  vim.cmd("wincmd l")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(right_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(right_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(right_buf, "GTD-Review-Content")
  vim.api.nvim_set_current_buf(right_buf)
  vim.wo.number = false
  vim.wo.relativenumber = false
  M.state.buffers.right = right_buf
  
  -- Set up keymaps and render
  M.setup_keymaps()
  M.show_step_content()
  
  -- Return focus to left panel
  vim.cmd("wincmd h")
  vim.notify((gu.list or "") .. " Returned to review", vim.log.levels.INFO)
end

-- Save any modified buffer in the right panel
function M.save_right_panel()
  -- Move to right window
  vim.cmd("wincmd l")
  -- Check if current buffer is modified and has a file
  local bufnr = vim.api.nvim_get_current_buf()
  local modified = vim.api.nvim_buf_get_option(bufnr, "modified")
  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
  local filename = vim.api.nvim_buf_get_name(bufnr)
  
  if modified and buftype == "" and filename ~= "" then
    vim.cmd("write")
    vim.notify((gu.save or "💾") .. " Saved: " .. vim.fn.fnamemodify(filename, ":t"), vim.log.levels.INFO)
  end
  -- Return to left panel
  vim.cmd("wincmd h")
end

function M.open_note_in_right_panel(step)
  if not M.state.review_note_path then return end
  vim.cmd("wincmd l")
  vim.cmd("edit " .. M.state.review_note_path)
  local section = step and step.note_section
  if section then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line:match("##.*" .. section) then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        vim.cmd("normal! jj")
        break
      end
    end
  end
  vim.cmd("wincmd h")
  render_left()
end

function M.open_file_in_right_panel(filepath)
  if not filepath or vim.fn.filereadable(filepath) ~= 1 then return end
  vim.cmd("wincmd l")
  vim.cmd("edit " .. filepath)
  vim.cmd("wincmd h")
  render_left()
end

function M.next_step()
  if M.state.current_step < #M.steps then
    M.state.current_step = M.state.current_step + 1
    M.state.active_checklist = nil
    M.show_step_content()
  end
end

function M.prev_step()
  if M.state.current_step > 1 then
    M.state.current_step = M.state.current_step - 1
    M.state.active_checklist = nil
    M.show_step_content()
  end
end

function M.next_incomplete()
  for i = 1, #M.steps do
    local idx = ((M.state.current_step - 1 + i) % #M.steps) + 1
    if not M.state.completed[M.steps[idx].id] then
      M.state.current_step = idx
      M.state.active_checklist = nil
      M.show_step_content()
      return
    end
  end
  vim.notify((gr.complete or "") .. " All steps complete!", vim.log.levels.INFO)
end

function M.toggle_complete()
  local step = M.steps[M.state.current_step]
  if step then
    M.state.completed[step.id] = not M.state.completed[step.id] or nil
    refresh_ui()
    
    if vim.tbl_count(M.state.completed) == #M.steps then
      vim.notify((gr.complete or "") .. " Review complete! Press 's' to save", vim.log.levels.INFO)
    else
      local icon = M.state.completed[step.id] and (gx.checked or "") or (gx.unchecked or "")
      vim.notify(icon .. " " .. step.label, vim.log.levels.INFO)
    end
  end
end

-- ============================================================================
-- CHECKLIST NAVIGATION
-- ============================================================================

function M.checklist_next()
  if not M.state.active_checklist then return end
  local cl = load_checklists()[M.state.active_checklist]
  if cl and M.state.checklist_cursor < #(cl.items or {}) then
    M.state.checklist_cursor = M.state.checklist_cursor + 1
    refresh_ui()
  end
end

function M.checklist_prev()
  if M.state.checklist_cursor > 1 then
    M.state.checklist_cursor = M.state.checklist_cursor - 1
    refresh_ui()
  end
end

function M.checklist_toggle()
  if not M.state.active_checklist then return end
  local cl = load_checklists()[M.state.active_checklist]
  if not cl then return end
  
  local item = (cl.items or {})[M.state.checklist_cursor]
  if not item then return end
  
  local key = M.state.active_checklist
  M.state.checklist_items[key] = M.state.checklist_items[key] or {}
  local item_id = item.id or item.label
  M.state.checklist_items[key][item_id] = not M.state.checklist_items[key][item_id]
  refresh_ui()
end

function M.checklist_action()
  if not M.state.active_checklist then return end
  local cl = load_checklists()[M.state.active_checklist]
  if not cl then return end
  
  local item = (cl.items or {})[M.state.checklist_cursor]
  if not item or not item.action then return end
  
  if item.action == "zettelkasten" then
    M.pause_for_action(function()
      if zettelkasten and zettelkasten.find then
        zettelkasten.find()
      else
        vim.cmd("edit " .. xp(M.cfg.zk_root))
      end
    end, "Reviewing Notes")
  end
end

function M.checklist_mark_all()
  if not M.state.active_checklist then return end
  local cl = load_checklists()[M.state.active_checklist]
  if not cl then return end
  
  local key = M.state.active_checklist
  M.state.checklist_items[key] = M.state.checklist_items[key] or {}
  
  for _, item in ipairs(cl.items or {}) do
    M.state.checklist_items[key][item.id or item.label] = true
  end
  
  refresh_ui()
  vim.notify((gx.checked or "") .. " All items marked done", vim.log.levels.INFO)
end

function M.checklist_back()
  M.state.active_checklist = nil
  M.state.checklist_cursor = 1
  refresh_ui()
end

function M.select_checklist(num)
  local checklists = load_checklists()
  local keys = {}
  for k in pairs(checklists) do table.insert(keys, k) end
  table.sort(keys)
  
  if keys[num] then
    M.state.active_checklist = keys[num]
    M.state.checklist_cursor = 1
    M.state.checklist_items[keys[num]] = M.state.checklist_items[keys[num]] or {}
    refresh_ui()
  end
end

-- Smart navigation
function M.nav_down()
  local step = M.steps[M.state.current_step]
  if step and step.action == "custom_checklists" and M.state.active_checklist then
    M.checklist_next()
  else
    M.next_step()
  end
end

function M.nav_up()
  local step = M.steps[M.state.current_step]
  if step and step.action == "custom_checklists" and M.state.active_checklist then
    M.checklist_prev()
  else
    M.prev_step()
  end
end

function M.smart_toggle()
  local step = M.steps[M.state.current_step]
  if step and step.action == "custom_checklists" and M.state.active_checklist then
    M.checklist_toggle()
  else
    M.toggle_complete()
  end
end

function M.smart_action()
  local step = M.steps[M.state.current_step]
  if step and step.action == "custom_checklists" and M.state.active_checklist then
    M.checklist_action()
  else
    M.execute_step_action()
  end
end

-- ============================================================================
-- PAUSE & RESUME
-- ============================================================================

function M.pause_for_action(action_fn, action_name)
  M.state.paused = true
  M.state.active = false
  M.state.review_tab = vim.fn.tabpagenr()
  
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  M.state.buffers = {}
  
  local group = vim.api.nvim_create_augroup("GtdReviewReturn", { clear = true })
  
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local bt = vim.api.nvim_buf_get_option(ev.buf, "buftype")
      if bt == "nofile" or bt == "prompt" then return end
      
      -- Set global mark W for last worked item (must use normal mode mW)
      pcall(function() vim.cmd("normal! mW") end)
      
      pcall(vim.api.nvim_buf_set_keymap, ev.buf, "n", "<C-b>", 
        ":lua require('gtd-nvim.gtd.review').resume()<CR>", 
        { noremap = true, silent = true, desc = "Return to Review" })
    end,
  })
  
  action_fn()
  
  vim.defer_fn(function()
    vim.notify((gu.list or "") .. " " .. (action_name or "Working") .. " - 'R/'N/'W marks set, Ctrl-B to return", vim.log.levels.INFO)
  end, 100)
end

function M.resume()
  -- If state has a review_id, we're resuming an in-session review
  if M.state.review_id and M.state.active then
    vim.notify("Review already open", vim.log.levels.WARN)
    return
  end
  
  -- If we have in-memory state with progress, rebuild UI
  if M.state.review_id and vim.tbl_count(M.state.completed) > 0 then
    pcall(vim.api.nvim_del_augroup_by_name, "GtdReviewReturn")
    setup_review_highlights()
    
    M.state.active = true
    M.state.paused = false
    M.state.metrics = collect_metrics()
    
    vim.cmd("vsplit")
    
    vim.cmd("wincmd h")
    vim.cmd("vertical resize " .. M.cfg.left_panel_width)
    local left_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(left_buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(left_buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_name(left_buf, "GTD-Review-Steps")
    vim.api.nvim_set_current_buf(left_buf)
    vim.wo.number = false
    vim.wo.relativenumber = false
    M.state.buffers.left = left_buf
    
    vim.cmd("normal! mR")
    
    vim.cmd("wincmd l")
    local right_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(right_buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(right_buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_name(right_buf, "GTD-Review-Content")
    vim.api.nvim_set_current_buf(right_buf)
    vim.wo.number = false
    vim.wo.relativenumber = false
    M.state.buffers.right = right_buf
    
    M.setup_keymaps()
    refresh_ui()
    vim.cmd("wincmd h")
    vim.notify((gu.list or "") .. " Returned to review", vim.log.levels.INFO)
    return
  end
  
  -- No in-memory state - try to find incomplete review from disk
  local incomplete = find_incomplete_review()
  
  if incomplete then
    -- Found incomplete progress - resume it
    M.start({ review_id = incomplete.review_id, week_id = incomplete.week, resume = true })
  else
    -- No incomplete review - offer to start new or view index
    vim.ui.select({"Start new review", "Open Index"}, {
      prompt = (gu.list or "") .. " No incomplete review found",
    }, function(choice)
      if choice == "Start new review" then
        M.start()
      elseif choice == "Open Index" then
        M.index()
      end
    end)
  end
end

-- ============================================================================
-- ACTIONS
-- ============================================================================

function M.refresh()
  M.state.metrics = collect_metrics()
  refresh_ui()
  vim.notify((gc.recurring or "󰑖") .. " Refreshed", vim.log.levels.INFO)
end

-- ============================================================================
-- SESSION
-- ============================================================================

function M.close()
  if not M.state.active then return end
  M.state.active = false
  
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  M.state.buffers = {}
end

-- Mark all steps complete
function M.mark_all_complete()
  for _, step in ipairs(M.steps) do
    M.state.completed[step.id] = true
  end
  refresh_ui()
  vim.notify((gx.checked or "") .. " All steps marked complete", vim.log.levels.INFO)
end

-- Mark all complete AND save (one-key finish)
function M.complete_and_save()
  M.mark_all_complete()
  vim.defer_fn(function()
    M.save_and_close()
  end, 100)
end

function M.save_and_close()
  update_review_note_completion()
  
  if vim.tbl_count(M.state.completed) > 0 then
    save_review_history()
    vim.notify((gx.checked or "") .. " Review saved", vim.log.levels.INFO)
  end
  
  M.state.paused = false
  M.state.start_time = nil
  M.state.completed = {}
  M.close()
  
  if vim.fn.tabpagenr('$') > 1 then
    vim.cmd("tabclose")
  else
    vim.cmd("enew")
  end
  
  if M.state.review_note_path then
    vim.ui.select({"Yes", "No"}, { prompt = "Open review note?" }, function(choice)
      if choice == "Yes" then
        vim.cmd("edit " .. M.state.review_note_path)
      end
    end)
  end
end

-- Weekly Review Complete: Save all and return to normal editing
function M.weekly_review_complete()
  -- First mark all steps complete
  for _, step in ipairs(M.steps) do
    M.state.completed[step.id] = true
  end
  
  -- Update the review note with completion status
  update_review_note_completion()
  
  -- Save review history
  save_review_history()
  
  -- Save the review note if it's open in a buffer
  if M.state.review_note_path then
    local note_bufnr = vim.fn.bufnr(M.state.review_note_path)
    if note_bufnr ~= -1 and vim.api.nvim_buf_is_valid(note_bufnr) then
      if vim.api.nvim_buf_get_option(note_bufnr, "modified") then
        vim.api.nvim_buf_call(note_bufnr, function()
          vim.cmd("write")
        end)
      end
    end
  end
  
  -- Save any other modified buffers in the review tab
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      if vim.api.nvim_buf_get_option(buf, "modified") then
        pcall(function()
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("write")
          end)
        end)
      end
    end
  end
  
  -- Clean up state
  M.state.paused = false
  M.state.start_time = nil
  M.state.active = false
  
  -- Close review UI
  M.close()
  
  -- Calculate final stats
  local duration = M.state.start_time and math.floor((os.time() - M.state.start_time) / 60) or 0
  local completed_count = vim.tbl_count(M.state.completed)
  
  -- Reset state
  M.state.completed = {}
  M.state.current_step = 1
  M.state.checklist_items = {}
  M.state.active_checklist = nil
  
  -- Close the review tab and return to normal buffers
  if vim.fn.tabpagenr('$') > 1 then
    vim.cmd("tabclose")
  else
    vim.cmd("enew")
  end
  
  -- Clear the autocommand group
  pcall(vim.api.nvim_del_augroup_by_name, "GtdReviewReturn")
  
  -- Show completion message
  local note_name = M.state.review_note_path and vim.fn.fnamemodify(M.state.review_note_path, ":t") or "review"
  vim.notify(
    (gx.checked or "") .. " Weekly Review Complete!\n" ..
    (gu.bullet or "") .. " " .. completed_count .. "/" .. #M.steps .. " steps\n" ..
    (gu.clock or "") .. " " .. duration .. " minutes\n" ..
    (gu.note or "󰝗") .. " " .. note_name,
    vim.log.levels.INFO
  )
end

function M.quit()
  M.state.paused = false
  M.state.start_time = nil
  M.state.completed = {}
  M.state.current_step = 1
  M.state.checklist_items = {}
  M.state.active_checklist = nil
  M.close()
  
  if vim.fn.tabpagenr('$') > 1 then
    vim.cmd("tabclose")
  else
    vim.cmd("enew")
  end
end

-- ============================================================================
-- KEYMAPS
-- ============================================================================

function M.setup_keymaps()
  local kopts = { noremap = true, silent = true }
  for _, buf in pairs(M.state.buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_keymap(buf, "n", "j", ":lua require('gtd-nvim.gtd.review').nav_down()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "k", ":lua require('gtd-nvim.gtd.review').nav_up()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<Down>", ":lua require('gtd-nvim.gtd.review').nav_down()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<Up>", ":lua require('gtd-nvim.gtd.review').nav_up()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "n", ":lua require('gtd-nvim.gtd.review').next_incomplete()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<Space>", ":lua require('gtd-nvim.gtd.review').smart_toggle()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", ":lua require('gtd-nvim.gtd.review').smart_action()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "c", ":lua require('gtd-nvim.gtd.review').capture_to_note()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "o", ":lua require('gtd-nvim.gtd.review').open_review_note()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "r", ":lua require('gtd-nvim.gtd.review').refresh()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "i", ":lua require('gtd-nvim.gtd.review').index()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "m", ":lua require('gtd-nvim.gtd.review').mark_all_complete()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "s", ":lua require('gtd-nvim.gtd.review').save_and_close()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "S", ":lua require('gtd-nvim.gtd.review').complete_and_save()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "W", ":lua require('gtd-nvim.gtd.review').weekly_review_complete()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "q", ":lua require('gtd-nvim.gtd.review').quit()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "b", ":lua require('gtd-nvim.gtd.review').checklist_back()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "a", ":lua require('gtd-nvim.gtd.review').checklist_mark_all()<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "1", ":lua require('gtd-nvim.gtd.review').select_checklist(1)<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "2", ":lua require('gtd-nvim.gtd.review').select_checklist(2)<CR>", kopts)
      vim.api.nvim_buf_set_keymap(buf, "n", "3", ":lua require('gtd-nvim.gtd.review').select_checklist(3)<CR>", kopts)
    end
  end
end

-- ============================================================================
-- START
-- ============================================================================

function M.start(opts)
  opts = opts or {}
  
  if M.state.active then
    vim.notify("Review already open", vim.log.levels.WARN)
    return
  end
  
  -- Always derive a clean week_id from current date or validate provided one
  local function validate_week_id(wid)
    -- Week ID must be exactly YYYY-Www format
    if wid and wid:match("^%d%d%d%d%-W%d%d$") then
      return wid
    end
    -- Try to extract valid week from corrupted string
    if wid then
      local extracted = wid:match("(%d%d%d%d%-W%d%d)")
      if extracted then return extracted end
    end
    return get_week_id()
  end
  
  local week_id = validate_week_id(opts.week_id)
  local review_id = opts.review_id or generate_review_id()
  
  -- Check if we're resuming with a specific review_id
  local resuming_session = opts.resume and (opts.review_id or opts.week_id)
  local saved = nil
  
  if resuming_session then
    saved = load_saved_progress(opts.review_id, validate_week_id(opts.week_id))
  end
  
  -- If no specific review_id but resume requested, find incomplete review
  if opts.resume and not opts.review_id and not saved then
    local incomplete = find_incomplete_review()
    if incomplete then
      saved = incomplete
      review_id = incomplete.review_id or generate_review_id()
      -- Validate the week from incomplete review
      week_id = validate_week_id(incomplete.week)
    end
  end
  
  -- Generate note path with review_id for uniqueness
  local note_path
  if saved and saved.note_path and vim.fn.filereadable(saved.note_path) == 1 then
    -- Use existing note path
    note_path = saved.note_path
  else
    -- Create new note with unique ID
    note_path = get_review_note_path(review_id, week_id)
  end
  
  -- Create note if it doesn't exist
  local is_new = false
  if vim.fn.filereadable(note_path) ~= 1 then
    note_path, is_new = create_review_note(week_id, review_id)
  end
  
  -- Initialize state
  M.state = {
    current_step = 1,
    completed = {},
    start_time = os.time(),
    metrics = collect_metrics(),
    active = true,
    paused = false,
    buffers = {},
    review_tab = nil,
    review_note_path = note_path,
    week_id = week_id,
    review_id = review_id,
    checklist_items = {},
    active_checklist = nil,
    checklist_cursor = 1,
  }
  
  -- RESTORE PROGRESS if resuming
  if saved then
    -- Restore completed steps
    if saved.completed_ids then
      for _, step_id in ipairs(saved.completed_ids) do
        M.state.completed[step_id] = true
      end
    end
    -- Restore position
    if saved.current_step and saved.current_step >= 1 and saved.current_step <= #M.steps then
      M.state.current_step = saved.current_step
    end
    vim.notify((gu.list or "") .. " Resumed: " .. (saved.steps or 0) .. "/" .. #M.steps .. " steps done", vim.log.levels.INFO)
  elseif is_new then
    vim.notify((gu.note or "󰝗") .. " New review: " .. vim.fn.fnamemodify(note_path, ":t"), vim.log.levels.INFO)
  else
    vim.notify((gu.note or "󰝗") .. " Continuing: " .. vim.fn.fnamemodify(note_path, ":t"), vim.log.levels.INFO)
  end
  
  -- Setup Catppuccin Mocha highlight groups
  setup_review_highlights()
  
  vim.cmd("tabnew")
  M.state.review_tab = vim.fn.tabpagenr()
  vim.cmd("vsplit")
  
  vim.cmd("wincmd h")
  vim.cmd("vertical resize " .. M.cfg.left_panel_width)
  local left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(left_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(left_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(left_buf, "GTD-Review-Steps")
  vim.api.nvim_set_current_buf(left_buf)
  vim.wo.number = false
  vim.wo.relativenumber = false
  M.state.buffers.left = left_buf
  
  -- Set global mark R for quick return with 'R (must use normal mode mR)
  vim.cmd("normal! mR")
  
  vim.cmd("wincmd l")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(right_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(right_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(right_buf, "GTD-Review-Content")
  vim.api.nvim_set_current_buf(right_buf)
  vim.wo.number = false
  vim.wo.relativenumber = false
  M.state.buffers.right = right_buf
  
  M.setup_keymaps()
  refresh_ui()
  vim.cmd("wincmd h")
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(opts)
  if opts then
    for k, v in pairs(opts) do M.cfg[k] = v end
  end
  
  vim.fn.mkdir(xp(M.cfg.reviews_dir), "p")
  
  vim.api.nvim_create_user_command("GtdReview", function() M.start() end, { desc = "GTD Weekly Review" })
  vim.api.nvim_create_user_command("GtdReviewIndex", function() M.index() end, { desc = "Reviews Index" })
  vim.api.nvim_create_user_command("GtdReviewHistory", function() M.index() end, { desc = "Reviews Index (alias)" })
  vim.api.nvim_create_user_command("GtdReviewResume", function() M.resume() end, { desc = "Resume review" })
  vim.api.nvim_create_user_command("GtdReviewChecklists", function()
    vim.cmd("edit " .. xp(M.cfg.custom_checklists_file))
  end, { desc = "Edit review checklists" })
end

return M
