-- ~/.config/nvim/lua/utils/zettelkasten/capture.lua
-- Quick capture: daily notes, quick notes, GTD capture

local M = {}

-- Get core zettelkasten module
local core = require("utils.zettelkasten")

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
    tags = "#quick",
  })
end

----------------------------------------------------------------------
-- Daily Note with GTD Sync
----------------------------------------------------------------------
function M.daily_note()
  local paths = core.get_paths()
  local date = os.date(core.get_config().date_format)
  
  -- Check if today's daily note already exists
  local daily_file = vim.fs.joinpath(paths.daily_dir, date .. paths.file_ext)
  local exists = vim.fn.filereadable(daily_file) == 1
  
  if exists then
    vim.cmd("edit " .. vim.fn.fnameescape(daily_file))
    core.notify("Opened daily note: " .. date)
    return
  end
  
  -- Create new daily note with GTD tasks
  local template_vars = {
    date = date,
    gtd_tasks = "",
  }
  
  -- Get GTD tasks if enabled
  local cfg = core.get_config()
  if cfg.gtd_integration.enabled then
    local tasks = core.get_gtd_tasks()
    local today_tasks = {}
    local task_count = 0
    
    -- Sort by priority
    local state_priority = { NEXT = 1, TODO = 2, WAITING = 3, PROJECT = 4, SOMEDAY = 5, DONE = 6 }
    table.sort(tasks, function(a, b)
      local a_priority = state_priority[a.type] or 999
      local b_priority = state_priority[b.type] or 999
      return a_priority < b_priority
    end)
    
    table.insert(today_tasks, "")
    
    -- Add TODO and NEXT tasks
    for _, task in ipairs(tasks) do
      if (task.type == "TODO" or task.type == "NEXT") and task_count < 10 then
        local task_line = string.format("- [ ] **%s** %s", task.type, task.display_text)
        local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
        local org_link = string.format("[_%s_](%s)", file_name, task.file)
        task_line = task_line .. " " .. org_link
        table.insert(today_tasks, task_line)
        task_count = task_count + 1
      end
    end
    
    -- Add WAITING tasks
    local waiting_count = 0
    for _, task in ipairs(tasks) do
      if task.type == "WAITING" and waiting_count < 5 and task_count < 15 then
        local task_line = string.format("- [ ] **WAITING** %s", task.display_text)
        local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
        local org_link = string.format("[_%s_](%s)", file_name, task.file)
        task_line = task_line .. " " .. org_link
        table.insert(today_tasks, task_line)
        waiting_count = waiting_count + 1
        task_count = task_count + 1
      end
    end
    
    if task_count > 0 then
      table.insert(today_tasks, "")
      table.insert(today_tasks, string.format("_Synced %d tasks from GTD_", task_count))
      table.insert(today_tasks, "")
    else
      today_tasks = { "", "_No active GTD tasks found_", "" }
    end
    
    template_vars.gtd_tasks = table.concat(today_tasks, "\n")
  end
  
  -- Create the daily note
  core.create_note_file({
    title = "Daily " .. date,
    dir = paths.daily_dir,
    template = "daily",
    open = true,
    template_vars = template_vars,
  })
  
  core.notify("Daily note: " .. date)
end

----------------------------------------------------------------------
-- Meeting Notes Capture
----------------------------------------------------------------------
function M.meeting_note(title)
  local paths = core.get_paths()
  local timestamp = os.date("%Y-%m-%d %H:%M")
  
  local function create_meeting(meeting_title)
    if not meeting_title or meeting_title == "" then
      core.notify("Meeting title required", vim.log.levels.WARN)
      return
    end
    
    local template_vars = {
      title = meeting_title,
      datetime = timestamp,
      attendees = "",
      agenda = "",
      notes = "",
      actions = "",
    }
    
    core.create_note_file({
      title = "Meeting: " .. meeting_title,
      template = "meeting",
      template_vars = template_vars,
      tags = "#meeting",
      open = true,
    })
  end
  
  if title then
    create_meeting(title)
  else
    vim.ui.input({ prompt = "Meeting title: " }, create_meeting)
  end
end

----------------------------------------------------------------------
-- Setup Commands
----------------------------------------------------------------------
function M.setup_commands()
  vim.api.nvim_create_user_command("ZettelQuick", function(c)
    M.quick_note(c.args ~= "" and c.args or nil)
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command("ZettelDaily", M.daily_note, {})
  
  vim.api.nvim_create_user_command("ZettelMeeting", function(c)
    M.meeting_note(c.args ~= "" and c.args or nil)
  end, { nargs = "?" })
end

----------------------------------------------------------------------
-- Setup Keymaps
----------------------------------------------------------------------
function M.setup_keymaps()
  vim.keymap.set("n", "<leader>zq", M.quick_note, { desc = "Quick note" })
  vim.keymap.set("n", "<leader>zd", M.daily_note, { desc = "Daily note" })
  vim.keymap.set("n", "<leader>zM", M.meeting_note, { desc = "Meeting note" })
end

return M
