-- ~/.config/nvim/lua/utils/zettelkasten/capture.lua
-- Deep Zettelkasten Integration: Daily notes, GTD sync, meetings, actions
-- 
-- Features:
-- 1. GTD Task Sync into Daily Notes (NEXT → TODO → WAITING)
-- 2. Meeting Notes with Action Extraction → GTD Inbox
-- 3. Proper ZK_LINK handling (only when note is created)

local M = {}

----------------------------------------------------------------------
-- Dependencies
----------------------------------------------------------------------
local core = require("utils.zettelkasten.core")

----------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------
M.config = {
  gtd = {
    enabled = true,
    inbox_file = vim.fn.expand("~/Documents/GTD/Inbox.org"),
    max_next_tasks = 5,
    max_todo_tasks = 7,
    max_waiting_tasks = 3,
  },
  
  meeting = {
    extract_actions = true,
    mark_extracted = true,  -- Add [GTD] marker to extracted items
  },
  
  quick = {
    default_tags = "#quick",
  },
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function notify(msg, level)
  core.notify(msg, level)
end

local function file_exists(path)
  return vim.fn.filereadable(vim.fn.expand(path)) == 1
end

local function read_file(path)
  if not file_exists(path) then return {} end
  return vim.fn.readfile(vim.fn.expand(path))
end

local function write_file(path, lines)
  local p = vim.fn.expand(path)
  vim.fn.mkdir(vim.fn.fnamemodify(p, ":h"), "p")
  return vim.fn.writefile(lines, p) == 0
end

local function append_to_file(path, lines)
  local p = vim.fn.expand(path)
  vim.fn.mkdir(vim.fn.fnamemodify(p, ":h"), "p")
  if not file_exists(p) then
    return write_file(p, lines)
  end
  return vim.fn.writefile(lines, p, "a") == 0
end


----------------------------------------------------------------------
-- GTD Task Section Builder (for daily notes)
----------------------------------------------------------------------
local function build_gtd_section()
  local tasks = core.get_gtd_tasks()
  local lines = {}

  if #tasks == 0 then
    return { "", "_No active GTD tasks found_", "" }
  end

  -- Sort by priority: NEXT → TODO → WAITING
  local state_priority = { NEXT = 1, TODO = 2, WAITING = 3, PROJ = 4, SOMEDAY = 5 }
  table.sort(tasks, function(a, b)
    local a_prio = state_priority[a.type] or 50
    local b_prio = state_priority[b.type] or 50
    if a_prio ~= b_prio then return a_prio < b_prio end
    -- Secondary: by deadline if present
    if a.deadline and b.deadline then return a.deadline < b.deadline end
    if a.deadline then return true end
    if b.deadline then return false end
    return a.text < b.text
  end)

  table.insert(lines, "")

  -- NEXT actions (highest priority)
  local next_count = 0
  for _, task in ipairs(tasks) do
    if task.type == "NEXT" and next_count < M.config.gtd.max_next_tasks then
      local deadline_str = ""
      if task.deadline then
        local date_part = task.deadline:match("^[^%s]+")
        if date_part then deadline_str = " 🎯 " .. date_part end
      end
      local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
      table.insert(lines, string.format(
        "- [ ] ⚡ **NEXT** %s%s [[file:%s][%s]]",
        task.display_text, deadline_str, task.file, file_name
      ))
      next_count = next_count + 1
    end
  end

  -- TODO tasks
  local todo_count = 0
  for _, task in ipairs(tasks) do
    if task.type == "TODO" and todo_count < M.config.gtd.max_todo_tasks then
      local deadline_str = ""
      if task.deadline then
        local date_part = task.deadline:match("^[^%s]+")
        if date_part then deadline_str = " 🎯 " .. date_part end
      end
      local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
      table.insert(lines, string.format(
        "- [ ] 📋 **TODO** %s%s [[file:%s][%s]]",
        task.display_text, deadline_str, task.file, file_name
      ))
      todo_count = todo_count + 1
    end
  end

  -- WAITING tasks
  local waiting_count = 0
  if M.config.gtd.max_waiting_tasks > 0 then
    local has_waiting = false
    for _, task in ipairs(tasks) do
      if task.type == "WAITING" then has_waiting = true; break end
    end
    
    if has_waiting then
      table.insert(lines, "")
      table.insert(lines, "**Waiting:**")
    end
    
    for _, task in ipairs(tasks) do
      if task.type == "WAITING" and waiting_count < M.config.gtd.max_waiting_tasks then
        local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
        table.insert(lines, string.format(
          "- [ ] ⏳ **WAITING** %s [[file:%s][%s]]",
          task.display_text, task.file, file_name
        ))
        waiting_count = waiting_count + 1
      end
    end
  end

  local total = next_count + todo_count + waiting_count
  table.insert(lines, "")
  table.insert(lines, string.format(
    "_Synced %d tasks from GTD (%d⚡ %d📋 %d⏳)_",
    total, next_count, todo_count, waiting_count
  ))
  table.insert(lines, "")

  return lines
end


----------------------------------------------------------------------
-- Daily Note with GTD Sync
----------------------------------------------------------------------
function M.daily_note()
  local paths = core.get_paths()
  local cfg = core.get_config()
  local date = os.date(cfg.date_format)
  
  local daily_file = core.join(paths.daily_dir, date .. paths.file_ext)
  local exists = file_exists(daily_file)
  
  if exists then
    vim.cmd("edit " .. vim.fn.fnameescape(daily_file))
    notify("📅 Opened: " .. date)
    return
  end
  
  -- Build GTD task section
  local gtd_section = { "" }
  if M.config.gtd.enabled then
    gtd_section = build_gtd_section()
  end
  
  local template_vars = {
    date = date,
    gtd_tasks = table.concat(gtd_section, "\n"),
    weekday = os.date("%A"),
  }
  
  core.create_note_file({
    title = "Daily " .. date,
    dir = paths.daily_dir,
    template = "daily",
    template_vars = template_vars,
    open = true,
    id = date:gsub("%-", ""),  -- Use date as ID for daily notes
  })
  
  notify("📅 Created daily note: " .. date)
end

----------------------------------------------------------------------
-- Refresh GTD Tasks in Current Daily Note
----------------------------------------------------------------------
function M.refresh_daily_gtd()
  local current = vim.fn.expand("%:p")
  local paths = core.get_paths()
  
  -- Check if in daily note
  if not current:find(vim.fn.expand(paths.daily_dir), 1, true) then
    notify("Not in a daily note", vim.log.levels.WARN)
    return
  end
  
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local new_lines = {}
  local in_tasks = false
  local tasks_start = nil
  local tasks_end = nil
  
  -- Find the Tasks/GTD section
  for i, line in ipairs(lines) do
    if line:match("^##%s+Tasks") or line:match("^##%s+GTD") or line:match("^##%s+Opgaver") then
      in_tasks = true
      tasks_start = i
      table.insert(new_lines, line)
    elseif in_tasks and line:match("^##%s+") then
      tasks_end = i - 1
      in_tasks = false
      -- Insert refreshed GTD section here
      local gtd_section = build_gtd_section()
      for _, gtd_line in ipairs(gtd_section) do
        table.insert(new_lines, gtd_line)
      end
      table.insert(new_lines, line)
    elseif not in_tasks then
      table.insert(new_lines, line)
    end
    -- Skip old task lines (they'll be replaced)
  end
  
  -- Handle case where Tasks is the last section
  if in_tasks and not tasks_end then
    local gtd_section = build_gtd_section()
    for _, gtd_line in ipairs(gtd_section) do
      table.insert(new_lines, gtd_line)
    end
  end
  
  vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
  notify("🔄 Refreshed GTD tasks")
end

----------------------------------------------------------------------
-- Quick Note
----------------------------------------------------------------------
function M.quick_note(title)
  local paths = core.get_paths()
  local timestamp = os.date("%H:%M")
  local note_title = title or (timestamp .. " Quick Note")
  
  core.new_note({
    dir = paths.quick_dir,
    template = "quick",
    title = note_title,
    tags = M.config.quick.default_tags,
  })
end


----------------------------------------------------------------------
-- Meeting Note
----------------------------------------------------------------------
function M.meeting_note(title)
  local paths = core.get_paths()
  local timestamp = os.date("%Y-%m-%d %H:%M")
  
  local function create_meeting(meeting_title)
    if not meeting_title or meeting_title == "" then
      notify("Meeting title required", vim.log.levels.WARN)
      return
    end
    
    local id = core.gen_id()
    local template_vars = {
      title = meeting_title,
      datetime = timestamp,
      date = os.date("%Y-%m-%d"),
      id = id,
      tags = M.config.meeting.default_tags or "#meeting",
    }
    
    local file, _ = core.create_note_file({
      title = "Meeting - " .. meeting_title,
      template = "meeting",
      template_vars = template_vars,
      open = true,
      id = id,
    })
    
    if file then
      notify("📝 Meeting note: " .. meeting_title)
      
      -- Set up autocmd to extract actions on save
      if M.config.meeting.extract_actions then
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_create_autocmd("BufWritePost", {
          buffer = bufnr,
          callback = function()
            M.extract_meeting_actions(file)
          end,
          desc = "Extract meeting actions to GTD",
        })
      end
    end
  end
  
  if title then
    create_meeting(title)
  else
    vim.ui.input({ prompt = "Meeting title: " }, create_meeting)
  end
end

----------------------------------------------------------------------
-- Extract Actions from Meeting → GTD Inbox
-- Only adds ZK_LINK when a note is actually created
----------------------------------------------------------------------
function M.extract_meeting_actions(meeting_file)
  meeting_file = meeting_file or vim.fn.expand("%:p")
  
  if not file_exists(meeting_file) then
    return
  end
  
  local lines = read_file(meeting_file)
  local meeting_title = vim.fn.fnamemodify(meeting_file, ":t:r")
  
  -- Extract title from H1 if present
  for _, line in ipairs(lines) do
    local h1 = line:match("^#%s+Meeting[:%s%-]+(.+)")
    if h1 then
      meeting_title = vim.trim(h1)
      break
    end
  end
  
  -- Find action items (unchecked, not already extracted)
  local in_actions = false
  local actions = {}
  
  for _, line in ipairs(lines) do
    if line:match("^##%s+Action") then
      in_actions = true
    elseif line:match("^##%s+") then
      in_actions = false
    elseif in_actions then
      -- Match unchecked: - [ ] or * [ ], skip if already has [GTD]
      local action = line:match("^%s*[%-%*]%s+%[%s%]%s+(.+)")
      if action and action ~= "" and not action:match("%[GTD%]") then
        table.insert(actions, {
          text = action,
          line = line,
        })
      end
    end
  end
  
  if #actions == 0 then
    return  -- No new actions
  end
  
  -- Create GTD tasks (NO ZK_LINK - just source reference)
  local inbox = M.config.gtd.inbox_file
  local created = 0
  local timestamp = os.date("%Y-%m-%d %H:%M")
  
  for _, action in ipairs(actions) do
    local task_id = os.date("%Y%m%d%H%M%S") .. string.format("%02d", created)
    
    -- Task WITHOUT ZK_LINK (no note created, just reference to meeting file)
    local task_lines = {
      "",
      "* TODO " .. action.text,
      ":PROPERTIES:",
      ":ID:        " .. task_id,
      ":CREATED:   " .. timestamp,
      ":SOURCE:    [[file:" .. meeting_file .. "][Meeting: " .. meeting_title .. "]]",
      ":END:",
      "",
    }
    
    if append_to_file(inbox, task_lines) then
      created = created + 1
    end
  end
  
  if created > 0 then
    notify(string.format("📋 Extracted %d actions → GTD Inbox", created))
    
    -- Mark actions as extracted in meeting note
    if M.config.meeting.mark_extracted then
      local updated_lines = {}
      in_actions = false
      
      for _, line in ipairs(lines) do
        if line:match("^##%s+Action") then
          in_actions = true
          table.insert(updated_lines, line)
        elseif line:match("^##%s+") then
          in_actions = false
          table.insert(updated_lines, line)
        elseif in_actions then
          local action = line:match("^(%s*[%-%*]%s+%[%s%]%s+.+)")
          if action and not line:match("%[GTD%]") then
            table.insert(updated_lines, line .. " [GTD]")
          else
            table.insert(updated_lines, line)
          end
        else
          table.insert(updated_lines, line)
        end
      end
      
      write_file(meeting_file, updated_lines)
      
      -- Reload buffer
      local bufnr = vim.fn.bufnr(meeting_file)
      if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("edit!")
        end)
      end
    end
  end
end

-- Manual trigger for action extraction
function M.extract_actions_now()
  local current = vim.fn.expand("%:p")
  if not current:match("%.md$") then
    notify("Not a markdown file", vim.log.levels.WARN)
    return
  end
  M.extract_meeting_actions(current)
end


----------------------------------------------------------------------
-- Capture to GTD Inbox (with proper ZK_LINK handling)
-- ZK_LINK is ONLY added when user chooses to create a note
----------------------------------------------------------------------
function M.capture_to_gtd(task_text)
  local function do_capture(text)
    if not text or text == "" then
      notify("Task text required", vim.log.levels.WARN)
      return
    end
    
    -- Ask if user wants to create a linked ZK note
    vim.ui.select({ "No, task only", "Yes, create linked note" }, {
      prompt = "Create Zettelkasten note for this task?",
    }, function(choice)
      if not choice then return end  -- Cancelled
      
      local create_note = choice:match("^Yes")
      local inbox = M.config.gtd.inbox_file
      local task_id = os.date("%Y%m%d%H%M%S")
      local timestamp = os.date("%Y-%m-%d %H:%M")
      local task_lines
      
      if create_note then
        -- Create the ZK note first
        local paths = core.get_paths()
        local note_id = core.gen_id()
        local note_file, _ = core.create_note_file({
          title = text:sub(1, 50),
          dir = paths.notes_dir,
          template = "note",
          template_vars = {
            tags = "#gtd #task",
          },
          open = false,  -- Don't open yet
          id = note_id,
        })
        
        if note_file then
          -- Task WITH ZK_LINK (note exists)
          task_lines = {
            "",
            "* TODO " .. text,
            ":PROPERTIES:",
            ":ID:        " .. task_id,
            ":CREATED:   " .. timestamp,
            ":ZK_LINK:   [[zk:" .. note_id .. "]]",
            ":ZK_FILE:   [[file:" .. note_file .. "][" .. vim.fn.fnamemodify(note_file, ":t") .. "]]",
            ":END:",
            "",
          }
          
          if append_to_file(inbox, task_lines) then
            notify("📋 Task created with linked note")
            -- Open the note
            vim.cmd("edit " .. vim.fn.fnameescape(note_file))
          end
        else
          notify("Failed to create note", vim.log.levels.ERROR)
        end
      else
        -- Task WITHOUT ZK_LINK (no note created)
        task_lines = {
          "",
          "* TODO " .. text,
          ":PROPERTIES:",
          ":ID:        " .. task_id,
          ":CREATED:   " .. timestamp,
          ":END:",
          "",
        }
        
        if append_to_file(inbox, task_lines) then
          notify("📋 Task added to GTD Inbox")
        end
      end
    end)
  end
  
  if task_text then
    do_capture(task_text)
  else
    vim.ui.input({ prompt = "Task: " }, do_capture)
  end
end

----------------------------------------------------------------------
-- Convert Current Note to GTD Task (proper ZK_LINK)
----------------------------------------------------------------------
function M.note_to_gtd_task()
  local current_file = vim.fn.expand("%:p")
  local paths = core.get_paths()
  
  -- Must be in notes directory
  if not current_file:find(vim.fn.expand(paths.notes_dir), 1, true) then
    notify("Not in Notes directory", vim.log.levels.WARN)
    return
  end
  
  -- Extract title from note
  local lines = vim.api.nvim_buf_get_lines(0, 0, 20, false)
  local title = vim.fn.fnamemodify(current_file, ":t:r")
  
  for _, line in ipairs(lines) do
    local h1 = line:match("^#%s+(.+)")
    if h1 then
      title = h1
      break
    end
  end
  
  -- Extract ID from filename (format: YYYYMMDDHHMM-title.md)
  local note_id = vim.fn.fnamemodify(current_file, ":t"):match("^(%d%d%d%d%d%d%d%d%d%d%d%d)")
  if not note_id then
    note_id = core.gen_id()  -- Generate new ID if not found
  end
  
  local inbox = M.config.gtd.inbox_file
  local task_id = os.date("%Y%m%d%H%M%S")
  local timestamp = os.date("%Y-%m-%d %H:%M")
  
  -- Task WITH ZK_LINK (note already exists)
  local task_lines = {
    "",
    "* TODO " .. title,
    ":PROPERTIES:",
    ":ID:        " .. task_id,
    ":CREATED:   " .. timestamp,
    ":ZK_LINK:   [[zk:" .. note_id .. "]]",
    ":ZK_FILE:   [[file:" .. current_file .. "][" .. vim.fn.fnamemodify(current_file, ":t") .. "]]",
    ":END:",
    "",
  }
  
  if append_to_file(inbox, task_lines) then
    notify("📋 Created GTD task from note: " .. title)
    
    -- Add backlink to current note
    local backlink_lines = {
      "",
      "---",
      "**GTD Task:** [[file:" .. inbox .. "][Inbox]]",
    }
    
    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, bl in ipairs(backlink_lines) do
      table.insert(buf_lines, bl)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buf_lines)
    vim.cmd("write")
  else
    notify("Failed to create GTD task", vim.log.levels.ERROR)
  end
end


----------------------------------------------------------------------
-- Browse GTD Tasks (with option to create linked note)
----------------------------------------------------------------------
function M.browse_gtd_tasks()
  if not M.config.gtd.enabled then
    notify("GTD integration disabled")
    return
  end
  
  local tasks = core.get_gtd_tasks()
  if #tasks == 0 then
    notify("No GTD tasks found")
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify("fzf-lua required", vim.log.levels.WARN)
    return
  end
  
  -- Sort by priority
  local state_priority = { NEXT = 1, TODO = 2, WAITING = 3, PROJ = 4, SOMEDAY = 5, DONE = 6 }
  table.sort(tasks, function(a, b)
    local a_prio = state_priority[a.type] or 50
    local b_prio = state_priority[b.type] or 50
    if a_prio ~= b_prio then return a_prio < b_prio end
    return a.text < b.text
  end)
  
  local items = {}
  for i, task in ipairs(tasks) do
    local icon = task.type == "NEXT" and "⚡" or 
                 task.type == "WAITING" and "⏳" or "📋"
    table.insert(items, string.format("%d|[%s %s] %s (%s:%d)",
      i, icon, task.type, task.display_text, task.rel_file, task.line
    ))
  end
  
  fzf.fzf_exec(items, {
    prompt = "GTD Tasks> ",
    fzf_opts = {
      ["--header"] = "[Enter] Go to task | [Ctrl-N] Create linked note | [Ctrl-Z] Open in Zettel",
    },
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local idx = tonumber(selected[1]:match("^(%d+)|"))
          if idx and tasks[idx] then
            vim.cmd("edit +" .. tasks[idx].line .. " " .. vim.fn.fnameescape(tasks[idx].file))
          end
        end
      end,
      ["ctrl-n"] = function(selected)
        if selected and selected[1] then
          local idx = tonumber(selected[1]:match("^(%d+)|"))
          if idx and tasks[idx] then
            M.create_note_for_task(tasks[idx])
          end
        end
      end,
    },
  })
end

----------------------------------------------------------------------
-- Create Note for Existing GTD Task (adds ZK_LINK to task)
----------------------------------------------------------------------
function M.create_note_for_task(task)
  local paths = core.get_paths()
  local note_id = core.gen_id()
  
  -- Create the note
  local note_file, _ = core.create_note_file({
    title = task.text:sub(1, 60),
    dir = paths.notes_dir,
    template = "note",
    template_vars = {
      tags = "#gtd",
    },
    open = false,
    id = note_id,
  })
  
  if not note_file then
    notify("Failed to create note", vim.log.levels.ERROR)
    return
  end
  
  -- Update the GTD task with ZK_LINK
  local task_lines = read_file(task.file)
  local updated = false
  local in_properties = false
  local new_lines = {}
  
  for i, line in ipairs(task_lines) do
    table.insert(new_lines, line)
    
    if i == task.line then
      -- Check if next line is :PROPERTIES:
      if task_lines[i + 1] and task_lines[i + 1]:match("^:PROPERTIES:") then
        -- Properties block exists, we'll add ZK_LINK inside it
      else
        -- No properties block, create one
        table.insert(new_lines, ":PROPERTIES:")
        table.insert(new_lines, ":ZK_LINK:   [[zk:" .. note_id .. "]]")
        table.insert(new_lines, ":ZK_FILE:   [[file:" .. note_file .. "][" .. vim.fn.fnamemodify(note_file, ":t") .. "]]")
        table.insert(new_lines, ":END:")
        updated = true
      end
    elseif line:match("^:PROPERTIES:") and i > task.line and not updated then
      in_properties = true
    elseif in_properties and line:match("^:END:") then
      -- Insert ZK_LINK before :END:
      new_lines[#new_lines] = nil  -- Remove :END: temporarily
      table.insert(new_lines, ":ZK_LINK:   [[zk:" .. note_id .. "]]")
      table.insert(new_lines, ":ZK_FILE:   [[file:" .. note_file .. "][" .. vim.fn.fnamemodify(note_file, ":t") .. "]]")
      table.insert(new_lines, ":END:")
      in_properties = false
      updated = true
    end
  end
  
  if updated then
    write_file(task.file, new_lines)
    notify("📝 Created note and linked to task")
  end
  
  -- Open the note
  vim.cmd("edit " .. vim.fn.fnameescape(note_file))
end


----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
function M.setup_commands()
  -- Daily note
  vim.api.nvim_create_user_command("ZettelDaily", M.daily_note, {
    desc = "Open/create daily note with GTD sync",
  })
  
  -- Quick note
  vim.api.nvim_create_user_command("ZettelQuick", function(c)
    M.quick_note(c.args ~= "" and c.args or nil)
  end, { nargs = "?", desc = "Create quick note" })
  
  -- Meeting note
  vim.api.nvim_create_user_command("ZettelMeeting", function(c)
    M.meeting_note(c.args ~= "" and c.args or nil)
  end, { nargs = "?", desc = "Create meeting note" })
  
  -- Capture to GTD
  vim.api.nvim_create_user_command("ZettelCapture", function(c)
    M.capture_to_gtd(c.args ~= "" and c.args or nil)
  end, { nargs = "?", desc = "Capture task to GTD Inbox" })
  
  -- Note to GTD task
  vim.api.nvim_create_user_command("ZettelToGtd", M.note_to_gtd_task, {
    desc = "Convert current note to GTD task",
  })
  
  -- Extract actions from meeting
  vim.api.nvim_create_user_command("ZettelExtractActions", M.extract_actions_now, {
    desc = "Extract actions from meeting to GTD",
  })
  
  -- Refresh GTD in daily note
  vim.api.nvim_create_user_command("ZettelRefreshGtd", M.refresh_daily_gtd, {
    desc = "Refresh GTD tasks in daily note",
  })
  
  -- Browse GTD tasks
  vim.api.nvim_create_user_command("ZettelGTD", M.browse_gtd_tasks, {
    desc = "Browse GTD tasks",
  })
end

----------------------------------------------------------------------
-- Keymaps
----------------------------------------------------------------------
function M.setup_keymaps()
  local opts = { silent = true, noremap = true }
  
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, vim.tbl_extend("force", opts, { desc = desc }))
  end
  
  map("<leader>zd", M.daily_note,        "Zettel: Daily note")
  map("<leader>zq", M.quick_note,        "Zettel: Quick note")
  map("<leader>zM", M.meeting_note,      "Zettel: Meeting note")
  map("<leader>zc", M.capture_to_gtd,    "Zettel: Capture to GTD")
  map("<leader>zG", M.note_to_gtd_task,  "Zettel: Note → GTD task")
  map("<leader>zg", M.browse_gtd_tasks,  "Zettel: Browse GTD")
  map("<leader>zX", M.extract_actions_now, "Zettel: Extract actions")
  map("<leader>zR", M.refresh_daily_gtd, "Zettel: Refresh GTD")
end

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  
  M.setup_commands()
  -- Note: keymaps are set up separately via init.lua or mappings/zettel.lua
end

return M
