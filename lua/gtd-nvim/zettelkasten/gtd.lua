-- ============================================================================
-- ZETTELKASTEN GTD MODULE
-- ============================================================================
-- GTD integration for Zettelkasten - task browsing, daily sync
--
-- @module gtd-nvim.zettelkasten.gtd
-- @version 2.0.0
-- @requires gtd-nvim.zettelkasten.core
-- @requires gtd-nvim.gtd.shared
-- ============================================================================

local M = {}

local core = require("gtd-nvim.zettelkasten.core")
local shared = core.shared
local cfg = core.cfg
local g = core.glyphs

-- ============================================================================
-- GTD TASK EXTRACTION
-- ============================================================================

function M.get_tasks()
  if not cfg.gtd_integration.enabled then return {} end
  if core.is_cache_valid("gtd_tasks") then
    return core._cache.gtd_tasks.data
  end

  local tasks = {}

  if not core.is_dir(cfg.gtd_dir) then
    core.notify("GTD directory not found: " .. cfg.gtd_dir, vim.log.levels.WARN)
    return tasks
  end

  local cmd = string.format(
    'rg -n "^\\*+\\s+(TODO|NEXT|WAITING|DONE|PROJECT|SOMEDAY|MAYBE)" %s --type org 2>/dev/null | head -200',
    vim.fn.shellescape(cfg.gtd_dir)
  )

  local success, result = pcall(vim.fn.systemlist, cmd)
  if success and vim.v.shell_error == 0 then
    for _, line in ipairs(result) do
      local file, line_num, content = line:match("^([^:]+):(%d+):(.*)$")
      if file and content then
        local task_type = content:match("^%*+%s+(%w+)")
        local task_text = content:gsub("^%*+%s+%w+%s*", "")

        -- Clean up task text
        task_text = task_text:gsub("%s*:.-:%s*$", "")
        task_text = task_text:gsub("%s*SCHEDULED:.-$", "")
        task_text = task_text:gsub("%s*DEADLINE:.-$", "")
        task_text = task_text:gsub("%s+", " ")
        task_text = vim.trim(task_text)

        local display_text = task_text
        if #task_text > 80 then
          display_text = task_text:sub(1, 77) .. "..."
        end

        -- Extract tags
        local tags = {}
        for tag in content:gmatch(":([%w_]+):") do
          table.insert(tags, tag)
        end

        -- Get container type for sorting (use shared function)
        local filename = vim.fn.fnamemodify(file, ":t")
        local container_type, container_priority = shared.get_container_type(file, filename)
        local state_priority = shared.get_state_priority(task_type)

        table.insert(tasks, {
          file = file,
          lnum = tonumber(line_num),
          line = tonumber(line_num),  -- Alias
          type = task_type,
          state = task_type,  -- Alias for shared compatibility
          text = task_text,
          title = task_text,  -- Alias
          display_text = display_text,
          tags = tags,
          content = content,
          rel_file = file:gsub("^" .. vim.pesc(cfg.gtd_dir) .. "/", ""),
          filename = filename,
          path = file,  -- Full path
          container_type = container_type,
          container_priority = container_priority,
          state_priority = state_priority,
        })
      end
    end
  end

  -- Sort using shared GTD sort
  shared.gtd_sort(tasks)
  core.update_cache("gtd_tasks", tasks)
  return tasks
end

-- ============================================================================
-- BROWSE GTD TASKS
-- ============================================================================

function M.browse_tasks()
  if not cfg.gtd_integration.enabled then
    core.notify("GTD integration disabled")
    return
  end

  local tasks = M.get_tasks()
  if #tasks == 0 then
    core.notify(shared.glyphs.container.inbox .. " No GTD tasks found")
    return
  end

  local fzf = core.have_fzf()
  if not fzf then
    core.notify("fzf-lua required", vim.log.levels.WARN)
    return
  end

  local items = {}
  local meta = {}

  for _, task in ipairs(tasks) do
    local state_glyph = shared.colored_state_glyph(task.type)
    local container_glyph = shared.colored_container_glyph(task.filename or "")
    local display = string.format("%s %s %s %s",
      state_glyph,
      task.display_text or task.text:sub(1, 60),
      container_glyph,
      core.zk_colorize(task.rel_file, "muted")
    )
    table.insert(items, display)
    table.insert(meta, task)
  end

  local header = table.concat({
    core.zk_colorize("Enter", "muted") .. " " .. core.zk_colorize(shared.glyphs.ui.arrow_right, "tag") .. " Open",
    core.zk_colorize("C-e", "muted") .. " " .. core.zk_colorize(shared.glyphs.ui.edit, "zettel") .. " Edit org",
    core.zk_colorize("C-z", "muted") .. " " .. core.zk_colorize(g.note.zettel, "zettel") .. " Create note",
  }, " " .. core.zk_colorize("│", "muted") .. " ")

  fzf.fzf_exec(items, {
    prompt = shared.glyphs.container.inbox .. " GTD> ",
    fzf_opts = {
      ["--ansi"] = true,
      ["--header"] = header,
    },
    actions = {
      -- Default: Open org file at line
      ["default"] = function(selected)
        if selected and selected[1] then
          local idx = vim.fn.index(items, selected[1]) + 1
          local task = meta[idx]
          if task and task.file and task.lnum then
            vim.cmd("edit +" .. task.lnum .. " " .. vim.fn.fnameescape(task.file))
            vim.cmd("normal! zz")
          end
        end
      end,
      -- Ctrl-E: Edit org file
      ["ctrl-e"] = function(selected)
        if selected and selected[1] then
          local idx = vim.fn.index(items, selected[1]) + 1
          local task = meta[idx]
          if task and task.file and task.lnum then
            vim.cmd("edit +" .. task.lnum .. " " .. vim.fn.fnameescape(task.file))
            vim.cmd("normal! zz")
          end
        end
      end,
      -- Ctrl-Z: Create Zettel note for task
      ["ctrl-z"] = function(selected)
        if selected and selected[1] then
          local idx = vim.fn.index(items, selected[1]) + 1
          local task = meta[idx]
          if task then
            M.create_note_for_task(task)
          end
        end
      end,
    },
  })
end

-- ============================================================================
-- CREATE NOTE FOR GTD TASK
-- ============================================================================

function M.create_note_for_task(task)
  local title = "GTD: " .. (task.text or task.display_text or "Task"):sub(1, 50)
  if #(task.text or "") > 50 then title = title .. "..." end

  vim.ui.input({
    prompt = g.note.zettel .. " Note title: ",
    default = title,
  }, function(input_title)
    if input_title and input_title ~= "" then
      local notes = require("gtd-nvim.zettelkasten.notes")
      notes.new_note({
        title = input_title,
        tags = "#gtd",
        template = "note",
      })
    end
  end)
end

-- ============================================================================
-- DAILY NOTE GTD CONTENT
-- ============================================================================

function M.generate_daily_content()
  if not cfg.gtd_integration.enabled then
    return ""
  end

  local tasks = M.get_tasks()
  local today_tasks = {}
  local task_count = 0

  table.insert(today_tasks, "")

  -- NEXT and TODO tasks
  for _, task in ipairs(tasks) do
    if (task.type == "TODO" or task.type == "NEXT") and task_count < 10 then
      local state_glyph = shared.glyphs.state[task.type] or shared.glyphs.ui.bullet
      local task_line = string.format("- [ ] **%s** %s %s", state_glyph, task.type, task.display_text)
      local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
      task_line = task_line .. " [_" .. file_name .. "_](" .. task.file .. ")"
      table.insert(today_tasks, task_line)
      task_count = task_count + 1
    end
  end

  -- WAITING tasks
  local waiting_count = 0
  for _, task in ipairs(tasks) do
    if task.type == "WAITING" and waiting_count < 5 and task_count < 15 then
      local state_glyph = shared.glyphs.state.WAITING or shared.glyphs.ui.bullet
      local task_line = string.format("- [ ] **%s** WAITING %s", state_glyph, task.display_text)
      local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
      task_line = task_line .. " [_" .. file_name .. "_](" .. task.file .. ")"
      table.insert(today_tasks, task_line)
      waiting_count = waiting_count + 1
      task_count = task_count + 1
    end
  end

  if task_count > 0 then
    table.insert(today_tasks, "")
    table.insert(today_tasks, string.format("_%s Synced %d tasks from GTD_", g.ui.sync, task_count))
    table.insert(today_tasks, "")
  else
    today_tasks = { "", "_No active GTD tasks found_", "" }
  end

  return table.concat(today_tasks, "\n")
end

-- ============================================================================
-- DAILY NOTE WITH GTD
-- ============================================================================

function M.daily_note_with_gtd()
  local notes = require("gtd-nvim.zettelkasten.notes")
  local gtd_content = M.generate_daily_content()
  notes.daily_note(gtd_content)
end

return M
