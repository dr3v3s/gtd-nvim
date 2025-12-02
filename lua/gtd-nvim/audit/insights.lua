-- ~/.config/nvim/lua/utils/gtd-audit/insights.lua
-- Suggest org-mode features and improvements

local M = {}

function M.show(data, config)
  local insights = M.analyze(data, config)
  
  if #insights == 0 then
    vim.notify("Using org-mode features effectively! ✨", vim.log.levels.INFO)
    return
  end
  
  -- Create a floating window with insights
  local buf = vim.api.nvim_create_buf(false, true)
  
  local lines = {
    "╔═══════════════════════════════════════════════════════╗",
    "║         ORG-MODE FEATURE SUGGESTIONS                  ║",
    "╚═══════════════════════════════════════════════════════╝",
    "",
  }
  
  for i, insight in ipairs(insights) do
    table.insert(lines, string.format("📌 %s", insight.title))
    table.insert(lines, "")
    for _, line in ipairs(insight.description) do
      table.insert(lines, "   " .. line)
    end
    if insight.example then
      table.insert(lines, "")
      table.insert(lines, "   Example:")
      for _, line in ipairs(insight.example) do
        table.insert(lines, "   " .. line)
      end
    end
    if i < #insights then
      table.insert(lines, "")
      table.insert(lines, "───────────────────────────────────────────────────────")
      table.insert(lines, "")
    end
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  -- Calculate window size
  local width = 70
  local height = math.min(#lines + 2, vim.o.lines - 4)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })
end

function M.analyze(data, config)
  local insights = {}
  
  -- Check property usage
  local has_effort = false
  local has_custom_id = false
  local has_category = false
  local total_props = 0
  
  for _, heading in ipairs(data.headings) do
    total_props = total_props + vim.tbl_count(heading.properties)
    if heading.properties.Effort then has_effort = true end
    if heading.properties.CUSTOM_ID then has_custom_id = true end
    if heading.properties.CATEGORY then has_category = true end
  end
  
  -- Suggest effort tracking
  if not has_effort and data.stats.projects > 0 then
    table.insert(insights, {
      title = "Effort Estimation",
      description = {
        "You have projects but aren't using :Effort: estimates.",
        "This helps with time management and agenda views.",
      },
      example = {
        "* PROJECT Build GTD auditor",
        ":PROPERTIES:",
        ":Effort: 4:00",
        ":END:",
      },
    })
  end
  
  -- Suggest custom IDs for stable linking
  if not has_custom_id then
    table.insert(insights, {
      title = "Stable Links with CUSTOM_ID",
      description = {
        "Use :CUSTOM_ID: for stable org-mode internal links.",
        "Unlike auto-generated IDs, these won't change.",
        "Link to them with [[#custom-id][description]]",
      },
      example = {
        "* Important Reference Section",
        ":PROPERTIES:",
        ":CUSTOM_ID: important-ref",
        ":END:",
        "",
        "Link from elsewhere: [[#important-ref][See reference]]",
      },
    })
  end
  
  -- Suggest categories for agenda views
  if not has_category then
    table.insert(insights, {
      title = "Categories for Better Agenda Views",
      description = {
        "Use :CATEGORY: to group tasks in agenda views.",
        "Useful for separating Work, Personal, etc.",
      },
      example = {
        "* TODO Weekly review",
        ":PROPERTIES:",
        ":CATEGORY: Personal",
        ":END:",
      },
    })
  end
  
  -- Check for advanced repeater patterns
  local has_plus_repeater = false
  local has_plusplus_repeater = false
  local has_dotplus_repeater = false
  
  for _, heading in ipairs(data.headings) do
    if heading.scheduled then
      if heading.scheduled:match("%+%d+[dwmy]") then has_plus_repeater = true end
      if heading.scheduled:match("%+%+%d+[dwmy]") then has_plusplus_repeater = true end
      if heading.scheduled:match("%.%+%d+[dwmy]") then has_dotplus_repeater = true end
    end
  end
  
  -- Suggest repeater patterns
  if has_plus_repeater and not (has_plusplus_repeater or has_dotplus_repeater) then
    table.insert(insights, {
      title = "Advanced Repeater Patterns",
      description = {
        "You're using +Xd repeaters. Consider these alternatives:",
        "  ++Xd - Strict intervals (if you miss one, next is still X days later)",
        "  .+Xd - From completion (next date is X days from when you finish)",
      },
      example = {
        "* TODO Water plants",
        "SCHEDULED: <2025-01-01 Wed ++3d>  -- Every 3 days (strict)",
        "",
        "* TODO Call mom",
        "SCHEDULED: <2025-01-01 Wed .+1w>  -- 1 week after each call",
      },
    })
  end
  
  -- Suggest agenda custom commands
  table.insert(insights, {
    title = "Custom Agenda Views",
    description = {
      "Create custom agenda commands for your GTD workflow:",
      "- Next actions only (NEXT keyword)",
      "- Waiting for (WAIT keyword)",
      "- Projects overview (PROJECT keyword)",
    },
    example = {
      "In your orgmode config:",
      "org_agenda_custom_commands = {",
      "  n = 'Next Actions',",
      "  w = 'Waiting For',",
      "  p = 'Projects',",
      "}",
    },
  })
  
  -- Suggest archiving if many completed tasks
  if data.stats.done_count > 20 then
    table.insert(insights, {
      title = "Archive Completed Tasks",
      description = {
        string.format("You have %d completed tasks.", data.stats.done_count),
        "Consider archiving to Archive.org to keep files lean.",
        "Use org_archive_subtree or set org_archive_location.",
      },
      example = {
        "In orgmode config:",
        "org_archive_location = '~/Documents/GTD/Archive.org::'",
        "",
        "Then use :OrgArchiveSubtree on completed tasks.",
      },
    })
  end
  
  -- Suggest priorities if not used
  local has_priority = false
  for _, heading in ipairs(data.headings) do
    if heading.raw:match("%[#[ABC]%]") then
      has_priority = true
      break
    end
  end
  
  if not has_priority and data.stats.todo_count > 10 then
    table.insert(insights, {
      title = "Priority Levels [#A] [#B] [#C]",
      description = {
        "Add priorities to tasks for better agenda sorting.",
        "[#A] = High priority, [#B] = Normal, [#C] = Low",
      },
      example = {
        "* NEXT [#A] Critical bug fix",
        "* NEXT [#B] Code review",
        "* TODO [#C] Update documentation",
      },
    })
  end
  
  -- Suggest clock tables for time tracking
  table.insert(insights, {
    title = "Time Tracking with Clocking",
    description = {
      "Org-mode can track time spent on tasks:",
      "- :OrgClockIn to start",
      "- :OrgClockOut to stop",
      "- Generate clock reports with #+BEGIN: clocktable",
    },
    example = {
      "#+BEGIN: clocktable :maxlevel 2 :scope file",
      "#+END:",
      "",
      "This creates a table of time spent per heading.",
    },
  })
  
  return insights
end

return M
