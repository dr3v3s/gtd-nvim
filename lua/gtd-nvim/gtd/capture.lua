-- ~/.config/nvim/lua/gtd/capture.lua
-- Enhanced capture to Inbox.org with post-capture fzf-lua destination picker + refile
-- Integrated with utils.zettelkasten for solid note linking
-- Aligned with ZK-ID: writes :ID: and :TASK_ID: and adds "ID:: [[zk:<ID>]]"
-- QUIET MODE: Minimal notifications to reduce visual clutter
-- WAITING FOR: Enhanced support for GTD waiting-for items with proper metadata
-- AREAS: Optional Area-of-Focus selection + Area-aware destinations

local M = {}

-- ------------------------------------------------------------
-- Config
-- ------------------------------------------------------------
M.cfg = {
  gtd_dir           = "~/Documents/GTD",
  inbox_file        = "~/Documents/GTD/Inbox.org",
  projects_dir      = "~/Documents/GTD/Projects",
  default_state     = "TODO",
  quiet_capture     = true,  -- Minimize notifications during capture
  show_success_only = true,  -- Only show final success message

  -- WAITING FOR defaults
  waiting_defaults = {
    follow_up_days    = 7,       -- Default follow-up in N days
    default_context   = "",      -- Default context (email, meeting, etc.)
    default_priority  = "medium" -- low, medium, high, urgent
  },
}

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function xp(p) return vim.fn.expand(p) end

local function ensure_dir(p)
  local expanded = xp(p)
  vim.fn.mkdir(expanded, "p")
  return expanded
end

local function file_exists(p)
  return vim.fn.filereadable(xp(p)) == 1
end

local function readfile(p)
  if not file_exists(p) then return {} end
  return vim.fn.readfile(xp(p))
end

local function writefile(p, lines)
  local expanded = xp(p)
  ensure_dir(vim.fn.fnamemodify(expanded, ":h"))
  return vim.fn.writefile(lines, expanded) == 0
end

local function append_lines(p, lines)
  local expanded = xp(p)
  ensure_dir(vim.fn.fnamemodify(expanded, ":h"))
  -- Ensure file exists
  if not file_exists(expanded) then
    writefile(expanded, { "" })
  end
  vim.fn.writefile({ "" }, expanded, "a")
  return vim.fn.writefile(lines, expanded, "a") == 0
end

-- ✅ Removed now_id() - using task_id.generate() instead

-- Focus-mode integration (Sketchybar HUD)
local focus_mode = (function()
  local ok, mod = pcall(require, "utils.focus_mode")
  if ok and mod and type(mod.set) == "function" then
    return mod
  end
  return nil
end)()

local function safe_require(module_name)
  local ok, module = pcall(require, module_name)
  return ok and module or nil
end

-- ✅ Load GTD v2.0 utilities
local task_id = safe_require("gtd.utils.task_id")
local org_dates = safe_require("gtd.utils.org_dates")

-- Fallback if utilities not available
if not task_id then
  task_id = {
    generate = function() return os.date("%Y%m%d%H%M%S") end,
    is_valid = function() return true end
  }
  vim.notify("Warning: task_id utility not found, using fallback", vim.log.levels.WARN)
end

if not org_dates then
  org_dates = {
    format_org_date = function(date) return "<" .. date .. ">" end,
    is_valid_date_format = function(date) return date and date:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil end,
    today = function() return os.date("%Y-%m-%d") end
  }
  vim.notify("Warning: org_dates utility not found, using fallback", vim.log.levels.WARN)
end

-- Date validation helper
local function is_valid_date(date_str)
  if not date_str or date_str == "" then return true end
  return date_str:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

-- Calculate future date
local function future_date(days)
  local future_time = os.time() + (days * 24 * 60 * 60)
  return os.date("%Y-%m-%d", future_time)
end

-- Quiet notification function that respects config
local function quiet_notify(msg, level, title)
  if not M.cfg.quiet_capture then
    vim.notify(msg, level or vim.log.levels.INFO, { title = title or "GTD Capture" })
  end
end

-- Success-only notification (always shows unless completely silent)
local function success_notify(msg, level, title)
  if M.cfg.show_success_only or not M.cfg.quiet_capture then
    vim.notify(msg, level or vim.log.levels.INFO, { title = title or "GTD" })
  end
end

-- Silent command execution to avoid vim's own notifications
local function silent_cmd(cmd)
  local saved_shortmess = vim.o.shortmess
  vim.o.shortmess = vim.o.shortmess .. "F"  -- Suppress file info
  local ok, result = pcall(vim.cmd, cmd)
  vim.o.shortmess = saved_shortmess
  return ok, result
end

-- Compact picker: prefer fzf-lua, fallback to vim.ui.select
local function select_fzf(items, prompt, cb)
  if not items or #items == 0 then
    quiet_notify("No items to select from", vim.log.levels.WARN)
    return
  end

  local fzf = safe_require("fzf-lua")
  if fzf then
    fzf.fzf_exec(items, {
      prompt = (prompt or "Select") .. "> ",
      actions = {
        ["default"] = function(sel)
          local line = sel and sel[1]
          if line and cb then cb(line) end
        end,
      },
      fzf_opts = { ["--no-info"] = true },
      winopts = { height = 0.35, width = 0.55, row = 0.15 },
    })
  else
    vim.ui.select(items, { prompt = prompt or "Select" }, function(choice)
      if choice and cb then cb(choice) end
    end)
  end
end

local function input_nonempty(opts, cb)
  if not opts or not cb then return end
  vim.ui.input(opts, function(s)
    if s and s ~= "" then cb(s) end
  end)
end

local function maybe_input(opts, cb)
  if not opts or not cb then return end
  vim.ui.input(opts, function(s)
    cb(s or "")
  end)
end

-- Return org subtree (start_idx, end_idx) range containing a line index
local function org_subtree_range(lines, head_idx)
  if not head_idx or not lines[head_idx] then return nil end

  local head = lines[head_idx]
  local stars = head:match("^(%*+)%s")
  if not stars then return nil end

  local level = #stars
  local i = head_idx + 1
  while i <= #lines do
    local line = lines[i]
    if line then
      local s = line:match("^(%*+)%s")
      if s and #s <= level then break end
    end
    i = i + 1
  end
  return head_idx, i - 1
end

local function glob_orgs(dir)
  local list = {}
  local pattern = xp(dir) .. "/*.org"
  local files = vim.fn.glob(pattern, false, true)
  for _, f in ipairs(files) do
    table.insert(list, f)
  end
  return list
end

-- Recursively scan for .org files under a root dir
local function scan_orgs_recursive(root)
  local uv = vim.loop
  local results = {}

  local function scan(path)
    local fs = uv.fs_scandir(path)
    if not fs then return end

    while true do
      local name, t = uv.fs_scandir_next(fs)
      if not name then break end
      local full = path .. "/" .. name
      if t == "file" then
        if name:sub(-4) == ".org" then
          table.insert(results, full)
        end
      elseif t == "directory" then
        -- Skip obvious junk dirs
        if name ~= ".git" and name ~= ".DS_Store" and name:sub(1, 1) ~= "." then
          scan(full)
        end
      end
    end
  end

  scan(root)
  return results
end

-- ------------------------------------------------------------
-- Areas support
-- ------------------------------------------------------------
local function get_areas()
  local mod = safe_require("gtd.areas")
  if mod and type(mod.areas) == "table" then
    return mod.areas
  end
  return nil
end

local function pick_area(cb)
  local areas = get_areas()
  if not areas or vim.tbl_isempty(areas) then
    -- No areas configured -> just continue with nil
    cb(nil)
    return
  end

  local items = { "No specific area" }
  for _, a in ipairs(areas) do
    if a.name and a.dir then
      table.insert(items, string.format("%s (%s)", a.name, xp(a.dir)))
    end
  end

  select_fzf(items, "Area of Focus", function(choice)
    if not choice or choice == "No specific area" then
      cb(nil)
      return
    end

    local chosen_name = choice:match("^(.-)%s+%(") or choice
    for _, a in ipairs(areas) do
      if a.name == chosen_name then
        cb(a)
        return
      end
    end
    cb(nil)
  end)
end

-- ------------------------------------------------------------
-- States
-- ------------------------------------------------------------
local STATES = { "TODO", "NEXT", "WAITING", "SOMEDAY", "DONE" }

local function pick_state(cb)
  if not cb then return end
  select_fzf(STATES, "State", function(choice)
    cb(choice or M.cfg.default_state)
  end)
end

-- ------------------------------------------------------------
-- WAITING FOR Support
-- ------------------------------------------------------------
local WAITING_CONTEXTS = {
  "email", "phone", "meeting", "text", "slack", "teams",
  "verbal", "letter", "other"
}

local WAITING_PRIORITIES = {
  "low", "medium", "high", "urgent"
}

-- Collect WAITING FOR metadata
local function collect_waiting_metadata(cb)
  if not cb then return end

  local waiting_data = {}

  -- WHO are we waiting for?
  input_nonempty({ prompt = "Waiting for WHO (person/org): " }, function(who)
    waiting_data.waiting_for = who

    -- WHAT are we waiting for?
    input_nonempty({ prompt = "Waiting for WHAT (deliverable): " }, function(what)
      waiting_data.waiting_what = what

      -- WHEN was it requested?
      local today = os.date("%Y-%m-%d")
      maybe_input({ prompt = "When requested (YYYY-MM-DD) [" .. today .. "]: " }, function(when)
        waiting_data.requested_date = (when ~= "" and when or today)

        if not is_valid_date(waiting_data.requested_date) then
          quiet_notify("Invalid date format, using today", vim.log.levels.WARN)
          waiting_data.requested_date = today
        end

        -- FOLLOW-UP date
        local default_followup = future_date(M.cfg.waiting_defaults.follow_up_days)
        maybe_input({ prompt = "Follow up on (YYYY-MM-DD) [" .. default_followup .. "]: " }, function(followup)
          waiting_data.follow_up_date = (followup ~= "" and followup or default_followup)

          if not is_valid_date(waiting_data.follow_up_date) then
            quiet_notify("Invalid follow-up date, using default", vim.log.levels.WARN)
            waiting_data.follow_up_date = default_followup
          end

          -- CONTEXT (how was it requested?)
          select_fzf(WAITING_CONTEXTS, "How was it requested?", function(context)
            waiting_data.context = context or M.cfg.waiting_defaults.default_context

            -- PRIORITY/URGENCY
            select_fzf(WAITING_PRIORITIES, "Priority level", function(priority)
              waiting_data.priority = priority or M.cfg.waiting_defaults.default_priority

              -- Optional notes about the request
              maybe_input({ prompt = "Additional notes (optional): " }, function(notes)
                waiting_data.notes = notes or ""
                cb(waiting_data)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- Generate WAITING FOR properties for org-mode
local function generate_waiting_properties(waiting_data)
  if not waiting_data then return {} end

  local props = {}

  if waiting_data.waiting_for then
    table.insert(props, ":WAITING_FOR: " .. waiting_data.waiting_for)
  end

  if waiting_data.waiting_what then
    table.insert(props, ":WAITING_WHAT: " .. waiting_data.waiting_what)
  end

  if waiting_data.requested_date then
    table.insert(props, ":REQUESTED: " .. waiting_data.requested_date)
  end

  if waiting_data.follow_up_date then
    table.insert(props, ":FOLLOW_UP: " .. waiting_data.follow_up_date)
  end

  if waiting_data.context then
    table.insert(props, ":CONTEXT: " .. waiting_data.context)
  end

  if waiting_data.priority then
    table.insert(props, ":PRIORITY: " .. waiting_data.priority)
  end

  if waiting_data.notes and waiting_data.notes ~= "" then
    table.insert(props, ":WAITING_NOTES: " .. waiting_data.notes)
  end

  return props
end

-- Format WAITING title to include key info
local function format_waiting_title(original_title, waiting_data)
  if not waiting_data or not waiting_data.waiting_for then
    return original_title
  end

  -- Include who we're waiting for in the title if not already there
  local title = original_title
  local who = waiting_data.waiting_for

  if not title:lower():find(who:lower()) then
    title = title .. " (from " .. who .. ")"
  end

  return title
end

-- ------------------------------------------------------------
-- Destination picker (fzf-lua)
-- ------------------------------------------------------------

-- Build a list of destination items, optionally filtered by a chosen Area
local function list_destinations(selected_area)
  local items = {}

  -- Always offer "Stay in Inbox"
  table.insert(items, { display = "Stay in Inbox", path = xp(M.cfg.inbox_file) })

  local areas = get_areas()

  -- If an Area is selected: only offer that Area's files (plus Inbox)
  if selected_area and selected_area.dir then
    local area_dir = xp(selected_area.dir)

    -- Recursively collect all .org files under this area
    local files = scan_orgs_recursive(area_dir)

    -- If no .org files exist in this area, offer a default Inbox.org there
    if #files == 0 then
      files = { area_dir .. "/Inbox.org" }
    end

    local area_label = selected_area.name or vim.fn.fnamemodify(area_dir, ":t")
    for _, f in ipairs(files) do
      table.insert(items, {
        display = string.format("Areas/%s/%s", area_label, vim.fn.fnamemodify(f, ":t")),
        path = f,
      })
    end

    return items
  end

  -- No Area selected: global list

  -- Add main GTD files (top-level .org under gtd_dir, excluding Inbox)
  for _, f in ipairs(glob_orgs(M.cfg.gtd_dir)) do
    local expanded = xp(f)
    if expanded ~= xp(M.cfg.inbox_file) then
      table.insert(items, {
        display = vim.fn.fnamemodify(f, ":t"),
        path = f,
      })
    end
  end

  -- Add project files
  for _, f in ipairs(glob_orgs(M.cfg.projects_dir)) do
    table.insert(items, {
      display = "Projects/" .. vim.fn.fnamemodify(f, ":t"),
      path = f,
    })
  end

  -- Add Area files for all Areas (when no specific Area was chosen)
  if areas and not vim.tbl_isempty(areas) then
    for _, a in ipairs(areas) do
      if a.dir then
        local area_dir = xp(a.dir)
        local files = scan_orgs_recursive(area_dir)

        if #files == 0 then
          files = { area_dir .. "/Inbox.org" }
        end

        local area_label = a.name or vim.fn.fnamemodify(area_dir, ":t")
        for _, f in ipairs(files) do
          table.insert(items, {
            display = string.format("Areas/%s/%s", area_label, vim.fn.fnamemodify(f, ":t")),
            path = f,
          })
        end
      end
    end
  end

  return items
end

local function pick_destination_fzf(selected_area, cb)
  if not cb then return end

  local items = list_destinations(selected_area)
  if #items == 0 then
    quiet_notify("No destinations available", vim.log.levels.WARN)
    return
  end

  local display = {}
  for _, it in ipairs(items) do
    table.insert(display, it.display)
  end

  local fzf = safe_require("fzf-lua")
  if fzf then
    fzf.fzf_exec(display, {
      prompt = "Move to> ",
      actions = {
        ["default"] = function(sel)
          local line = sel and sel[1]
          if not line then
            return
          end
          local idx = vim.fn.index(display, line) + 1
          local item = items[idx]
          if item then cb(item.path) end
        end,
      },
      fzf_opts = { ["--no-info"] = true },
      winopts = { height = 0.35, width = 0.60, row = 0.15 },
    })
  else
    vim.ui.select(display, { prompt = "Destination" }, function(choice)
      if not choice then return end
      local idx = vim.fn.index(display, choice) + 1
      local item = items[idx]
      if item then cb(item.path) end
    end)
  end
end

-- Move captured subtree (identified by :ID: or :TASK_ID:) from inbox → dest_path
local function refile_captured_id(id, dest_path)
  if not id or not dest_path then return false end

  dest_path = xp(dest_path)
  local inbox_path = xp(M.cfg.inbox_file)

  if dest_path == inbox_path then return true end

  local lines = readfile(inbox_path)
  if #lines == 0 then return false end

  for i = 1, #lines do
    if lines[i] and lines[i]:match("^%*+%s") then
      local s, e = org_subtree_range(lines, i)
      if s and e then
        for j = s, e do
          if lines[j] then
            local idline = lines[j]:match("^%s*:ID:%s*(%S+)") or
                           lines[j]:match("^%s*:TASK_ID:%s*(%S+)")
            if idline == id then
              local chunk, new = {}, {}
              for k = s, e do
                table.insert(chunk, lines[k])
              end
              for k = 1, s - 1 do
                table.insert(new, lines[k])
              end
              for k = e + 1, #lines do
                table.insert(new, lines[k])
              end
              writefile(inbox_path, new)
              append_lines(dest_path, chunk)
              return true
            end
          end
        end
      end
    end
  end
  return false
end

-- ------------------------------------------------------------
-- Capture flow (fzf-lua prompts) - Enhanced with WAITING FOR + Areas
-- ------------------------------------------------------------
function M.capture_quick()
  -- Tell focus-mode HUD that we're in GTD mode
  if focus_mode and focus_mode.set then
    focus_mode.set("gtd")
  end

  -- 0) Optional Area-of-Focus
  pick_area(function(selected_area)
    -- 1) State
    pick_state(function(state)
      local want_dates = (state ~= "SOMEDAY")
      local is_waiting = (state == "WAITING")

      -- 2) Title
      input_nonempty({ prompt = "Title: " }, function(original_title)

        -- Handle WAITING FOR metadata collection
        local function continue_with_waiting_data(waiting_data)
          local title = original_title

          -- Enhance title for WAITING items
          if is_waiting and waiting_data then
            title = format_waiting_title(original_title, waiting_data)
          end

          -- 3) Tags
          maybe_input({ prompt = "Tags (space sep, optional): " }, function(tags)
            local id = task_id.generate()
            local scheduled, deadline = "", ""

            local function create_task_with_zk(zk_path)
              local lines = {}

              -- Heading with tags
              local tag_string = ""
              if tags and tags ~= "" then
                tag_string = "  :" .. tags:gsub("%s+", ":") .. ":"
              end
              table.insert(lines, string.format("* %s %s%s", state, title, tag_string))

              -- Dates - for WAITING, use follow-up date as SCHEDULED if provided
              if want_dates then
                if is_waiting and waiting_data and waiting_data.follow_up_date then
                  table.insert(lines, "SCHEDULED: <" .. waiting_data.follow_up_date .. ">")
                  quiet_notify("Set follow-up as SCHEDULED date", vim.log.levels.INFO)
                else
                  if scheduled ~= "" then
                    table.insert(lines, "SCHEDULED: " .. (org_dates.format_org_date(scheduled) or "<" .. scheduled .. ">"))
                  end
                end

                if deadline ~= "" then
                  table.insert(lines, "DEADLINE: " .. (org_dates.format_org_date(deadline) or "<" .. deadline .. ">"))
                end
              end

              -- Properties + IDs
              table.insert(lines, ":PROPERTIES:")
              -- REMOVED: Redundant :ID: (using TASK_ID only)
              table.insert(lines, ":TASK_ID:   " .. id)

              -- Add WAITING FOR specific properties
              if is_waiting and waiting_data then
                local waiting_props = generate_waiting_properties(waiting_data)
                for _, prop in ipairs(waiting_props) do
                  table.insert(lines, prop)
                end
              end

              if zk_path then
                local zk_filename = vim.fn.fnamemodify(zk_path, ":t")
                table.insert(lines, ":ZK_NOTE:   [[file:" .. zk_path .. "][" .. zk_filename .. "]]")
                quiet_notify("Created ZK note: " .. zk_filename, vim.log.levels.INFO)
              end

              table.insert(lines, ":END:")

              -- Breadcrumb link
              table.insert(lines, string.format("ID:: [[zk:%s]]", id))

              -- Add WAITING summary as body text
              if is_waiting and waiting_data then
                table.insert(lines, "")
                table.insert(lines, string.format("Waiting for: %s", waiting_data.waiting_for or ""))
                table.insert(lines, string.format("Expecting: %s", waiting_data.waiting_what or ""))
                table.insert(lines, string.format("Requested: %s via %s",
                  waiting_data.requested_date or "", waiting_data.context or ""))
                if waiting_data.notes and waiting_data.notes ~= "" then
                  table.insert(lines, "")
                  table.insert(lines, "Notes: " .. waiting_data.notes)
                end
              end

              -- Ensure directories exist
              ensure_dir(M.cfg.gtd_dir)
              ensure_dir(M.cfg.projects_dir)

              -- Write to inbox
              if append_lines(M.cfg.inbox_file, lines) then
                quiet_notify("Task captured to Inbox.org", vim.log.levels.INFO)

                -- Pick destination (with Area-aware list)
                pick_destination_fzf(selected_area, function(dest)
                  if not dest then
                    -- User cancelled destination selection → clear focus
                    if focus_mode and focus_mode.clear then
                      focus_mode.clear()
                    end
                    return
                  end
                  if refile_captured_id(id, dest) then
                    local dest_display = vim.fn.fnamemodify(dest, ":.")
                    local zk_note_text = zk_path and " + ZK note" or ""
                    local waiting_text = is_waiting and " [WAITING FOR]" or ""
                    -- success_notify("📝 " .. original_title .. " → " .. dest_display .. zk_note_text .. waiting_text, vim.log.levels.INFO)
                    silent_cmd("edit " .. xp(dest))

                    -- Clear focus once capture + refile is complete
                    if focus_mode and focus_mode.clear then
                      focus_mode.clear()
                    end
                  else
                    vim.notify("Failed to refile task", vim.log.levels.WARN)
                    -- Clear focus even on failure to avoid stale GTD mode
                    if focus_mode and focus_mode.clear then
                      focus_mode.clear()
                    end
                  end
                end)
              else
                vim.notify("Failed to capture task", vim.log.levels.ERROR)
                -- Clear focus on capture failure
                if focus_mode and focus_mode.clear then
                  focus_mode.clear()
                end
              end
            end

            local function handle_zk_creation()
              select_fzf({ "No note", "Create ZK note" }, "Attach note?", function(sel)
                local zk_path = nil

                if sel == "Create ZK note" then
                  local zk = safe_require("utils.zettelkasten")
                  if zk and zk.create_note_file and zk.get_paths then
                    local paths = zk.get_paths()
                    if paths and paths.notes_dir then
                      local dir = vim.fs.joinpath(paths.notes_dir, "Projects")
                      local note_result, _ = zk.create_note_file({
                        title = title, -- Use enhanced title for ZK note
                        dir = dir,
                        template = "note",
                        id = id,
                        open = false,
                      })
                      if note_result then
                        zk_path = note_result
                        quiet_notify("Created ZK note: " .. vim.fn.fnamemodify(zk_path, ":t"), vim.log.levels.INFO)
                      end
                    end
                  end
                end

                create_task_with_zk(zk_path)
              end)
            end

            -- Handle dates differently for WAITING items
            if want_dates and not is_waiting then
              local today = os.date("%Y-%m-%d")
              local plus3 = os.date("%Y-%m-%d", os.time() + 3 * 24 * 3600)

              maybe_input({ prompt = "Defer (YYYY-MM-DD) [Enter=" .. today .. "]: " }, function(s)
                scheduled = (s ~= "" and s or today)

                maybe_input({ prompt = "Due (YYYY-MM-DD) [Enter=" .. plus3 .. "]: " }, function(d)
                  deadline = (d ~= "" and d or plus3)
                  handle_zk_creation()
                end)
              end)
            else
              -- For WAITING items, we already have the follow-up date
              -- For SOMEDAY items, we skip dates entirely
              handle_zk_creation()
            end
          end)
        end

        -- Collect WAITING FOR metadata if this is a WAITING item
        if is_waiting then
          collect_waiting_metadata(function(waiting_data)
            continue_with_waiting_data(waiting_data)
          end)
        else
          continue_with_waiting_data(nil)
        end
      end)
    end)
  end)
end

-- ------------------------------------------------------------
-- Utilities
-- ------------------------------------------------------------
function M.open_inbox()
  vim.cmd("edit " .. xp(M.cfg.inbox_file))
end

function M.find_files()
  local proj = safe_require("utils.projects")
  if proj and type(proj.find_files) == "function" then
    return proj.find_files()
  end

  local fzf = safe_require("fzf-lua")
  if fzf then
    fzf.files({ cwd = xp(M.cfg.gtd_dir), prompt = "GTD> " })
  else
    silent_cmd("edit " .. xp(M.cfg.gtd_dir))
  end
end

function M.search()
  local proj = safe_require("utils.projects")
  if proj and type(proj.search) == "function" then
    return proj.search()
  end

  local fzf = safe_require("fzf-lua")
  if fzf then
    fzf.live_grep({ cwd = xp(M.cfg.gtd_dir), prompt = "GTD> " })
  else
    quiet_notify("fzf-lua not available for search", vim.log.levels.WARN)
  end
end

function M.agenda()
  if vim.fn.exists(":OrgAgenda") == 2 then
    silent_cmd("OrgAgenda")
  else
    quiet_notify("orgmode not loaded", vim.log.levels.WARN)
  end
end

-- ------------------------------------------------------------
-- WAITING FOR specific utilities
-- ------------------------------------------------------------

-- List all WAITING items across GTD system
function M.list_waiting_items()
  local fzf = safe_require("fzf-lua")
  if not fzf then
    quiet_notify("fzf-lua required for waiting items list", vim.log.levels.WARN)
    return
  end

  local files = vim.tbl_extend("force",
    glob_orgs(M.cfg.gtd_dir),
    glob_orgs(M.cfg.projects_dir)
  )

  local waiting_items = {}

  for _, file in ipairs(files) do
    local lines = readfile(file)
    local current_item = nil

    for i, line in ipairs(lines) do
      -- Check for WAITING heading
      if line:match("^%*+%s+WAITING%s") then
        current_item = {
          file = file,
          line_num = i,
          title = line:match("^%*+%s+WAITING%s+(.+)") or line,
          properties = {},
        }
      elseif current_item and line:match("^%s*:WAITING_FOR:") then
        current_item.waiting_for = line:match("^%s*:WAITING_FOR:%s*(.+)")
      elseif current_item and line:match("^%s*:FOLLOW_UP:") then
        current_item.follow_up = line:match("^%s*:FOLLOW_UP:%s*(.+)")
      elseif current_item and line:match("^%s*:PRIORITY:") then
        current_item.priority = line:match("^%s*:PRIORITY:%s*(.+)")
      elseif current_item and line:match("^%*+%s") and not line:match("^%*+%s+WAITING%s") then
        -- End of current WAITING item
        if current_item.waiting_for then
          table.insert(waiting_items, current_item)
        end
        current_item = nil
      end
    end

    -- Handle last item in file
    if current_item and current_item.waiting_for then
      table.insert(waiting_items, current_item)
    end
  end

  if #waiting_items == 0 then
    success_notify("No WAITING items found", vim.log.levels.INFO)
    return
  end

  -- Create display items
  local display = {}
  for _, item in ipairs(waiting_items) do
    local file_short = vim.fn.fnamemodify(item.file, ":t")
    local priority_indicator = ""
    if item.priority == "urgent" then
      priority_indicator = "🔴 "
    elseif item.priority == "high" then
      priority_indicator = "🟡 "
    end

    local follow_up_text = item.follow_up and (" [" .. item.follow_up .. "]") or ""
    table.insert(display, string.format("%s%s | %s | %s%s",
      priority_indicator,
      item.waiting_for or "Unknown",
      item.title,
      file_short,
      follow_up_text))
  end

  fzf.fzf_exec(display, {
    prompt = "WAITING FOR> ",
    actions = {
      ["default"] = function(sel)
        local line = sel and sel[1]
        if not line then return end
        local idx = vim.fn.index(display, line) + 1
        local item = waiting_items[idx]
        if item then
          silent_cmd("edit " .. item.file)
          vim.api.nvim_win_set_cursor(0, { item.line_num, 0 })
        end
      end,
    },
    fzf_opts = { ["--no-info"] = true },
    winopts = { height = 0.60, width = 0.90, row = 0.10 },
  })
end

-- ------------------------------------------------------------
-- Setup
-- ------------------------------------------------------------
function M.setup(opts)
  if opts then
    M.cfg = vim.tbl_deep_extend("force", M.cfg, opts)
  end

  -- Ensure directories exist
  ensure_dir(M.cfg.gtd_dir)
  ensure_dir(M.cfg.projects_dir)
  ensure_dir(vim.fn.fnamemodify(xp(M.cfg.inbox_file), ":h"))

  -- Ensure inbox file exists
  if not file_exists(M.cfg.inbox_file) then
    writefile(M.cfg.inbox_file, { "#+TITLE: Inbox", "" })
  end

  -- Optionally set vim to be quieter during operations
  if M.cfg.quiet_capture then
    -- Reduce vim's verbosity during file operations
    vim.opt.shortmess:append("F") -- Don't give file info when editing
  end
end

-- Quick config helpers for users
function M.set_quiet(quiet)
  M.cfg.quiet_capture = quiet
  M.cfg.show_success_only = quiet
end

function M.set_verbose()
  M.cfg.quiet_capture = false
  M.cfg.show_success_only = false
end

-- Backward-compat single entry (used by some wrappers): create() -> capture_quick()
function M.create(opts)
  M.setup(opts or {})
  return M.capture_quick()
end

return M
