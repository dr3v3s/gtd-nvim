-- ============================================================================
-- ZETTELKASTEN NOTES MODULE
-- ============================================================================
-- Note creation, templates, and file operations
--
-- @module gtd-nvim.zettelkasten.notes
-- @version 2.0.0
-- @requires gtd-nvim.zettelkasten.core
-- ============================================================================

local M = {}

local core = require("gtd-nvim.zettelkasten.core")
local cfg = core.cfg
local g = core.glyphs

-- ============================================================================
-- TEMPLATES
-- ============================================================================

local function read_template(kind)
  local p = core.join(cfg.templates_dir, kind .. cfg.file_ext)
  if core.file_exists(p) then return vim.fn.readfile(p) end
  return nil
end

local function apply_template(kind, vars)
  local t = read_template(kind)

  local function fill(lines)
    local result = {}
    for _, ln in ipairs(lines) do
      local line = ln
      local modified = false
      for k, v in pairs(vars) do
        local placeholder = "{{" .. k .. "}}"
        if line:find(placeholder, 1, true) then
          if type(v) == "string" and v:find("\n") then
            local split_lines = vim.split(v, "\n", { plain = true })
            local replaced_line = line:gsub(placeholder, split_lines[1] or "")
            table.insert(result, replaced_line)
            for j = 2, #split_lines do
              table.insert(result, split_lines[j])
            end
            modified = true
            break
          else
            line = line:gsub(placeholder, tostring(v))
          end
        end
      end
      if not modified then
        table.insert(result, line)
      end
    end
    return result
  end

  if t then return fill(t) end

  -- Default templates
  if kind == "note" then
    return fill({
      "# {{title}}",
      "",
      "**Dato:** {{created}}",
      "**ID:** {{id}}",
      "**Tags:** {{tags}}",
      "",
      "## Indhold",
      "",
      "## Relaterede Noter",
      "",
      "## Backlinks",
      "<!-- backlinks will be auto-generated -->",
      "",
    })
  elseif kind == "daily" then
    return fill({
      "# " .. g.note.daily .. " Daglig Note - {{date}}",
      "",
      "## Opgaver",
      "- [ ] ",
      "",
      "## Noter",
      "",
      "## GTD Sync",
      "{{gtd_tasks}}",
      "",
      "## Reflektioner",
      "",
    })
  elseif kind == "quick" then
    return fill({
      "# " .. g.note.quick .. " {{title}}",
      "",
      "**Created:** {{created}}",
      "**Tags:** #quick",
      "",
    })
  elseif kind == "project" then
    return fill({
      "# " .. g.note.project .. " {{title}}",
      "",
      "**Created:** {{created}}",
      "**Status:** Active",
      "**Tags:** #project {{tags}}",
      "",
      "## Overview",
      "",
      "## Tasks",
      "",
      "## Resources",
      "",
      "## Notes",
      "",
    })
  elseif kind == "reading" then
    return fill({
      "# " .. g.note.reading .. " {{title}}",
      "",
      "**Author:** {{author}}",
      "**Started:** {{created}}",
      "**Status:** Reading",
      "**Tags:** #reading #book {{tags}}",
      "",
      "## Summary",
      "",
      "## Key Ideas",
      "",
      "## Quotes",
      "",
      "## Notes",
      "",
    })
  elseif kind == "person" then
    return fill({
      "# " .. g.note.person .. " {{title}}",
      "",
      "**Met:** {{created}}",
      "**Tags:** #person {{tags}}",
      "",
      "## Contact",
      "",
      "## Notes",
      "",
      "## Interactions",
      "",
    })
  elseif kind == "meeting" then
    return fill({
      "# " .. g.note.meeting .. " {{title}}",
      "",
      "**Date:** {{date}}",
      "**Attendees:** {{attendees}}",
      "**Tags:** #meeting {{tags}}",
      "",
      "## Agenda",
      "",
      "## Notes",
      "",
      "## Action Items",
      "- [ ] ",
      "",
    })
  end

  return { "" }
end

-- ============================================================================
-- FILE OPERATIONS
-- ============================================================================

local function find_content_row(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, ln in ipairs(lines) do
    if ln:match("^##%s+Indhold%s*$") or ln:match("^##%s+Notes?%s*$") or ln:match("^##%s+Content%s*$") then
      return math.min(i + 1, #lines + 1)
    end
  end
  return #lines + 1
end

local function open_and_seed(filepath, lines, cursor_row)
  local fp = core.abspath(filepath)
  lines = lines or { "" }
  local existed = core.file_exists(fp)

  if not existed then
    core.ensure_dir(vim.fn.fnamemodify(fp, ":h"))
    vim.fn.writefile(lines, fp)
  end

  vim.cmd("edit " .. vim.fn.fnameescape(fp))

  if existed and vim.fn.line("$") == 1 and vim.fn.getline(1) == "" then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end

  if cursor_row then
    pcall(vim.api.nvim_win_set_cursor, 0, { cursor_row, 0 })
  end
end

-- ============================================================================
-- PUBLIC API - NOTE CREATION
-- ============================================================================

function M.create_note_file(opts)
  opts = opts or {}
  local title = opts.title

  if not title or title == "" then
    core.notify("Note title required", vim.log.levels.WARN)
    return nil, nil
  end

  local dir_abs = core.ensure_dir(opts.dir or cfg.notes_dir)
  local id = opts.id or core.gen_id()
  local file_abs = core.join(dir_abs, core.gen_filename(title, id))

  local template_vars = {
    title = title,
    created = os.date(cfg.datetime_format),
    id = id,
    date = os.date(cfg.date_format),
    tags = opts.tags or "",
    gtd_tasks = opts.gtd_tasks or "",
    author = opts.author or "",
    attendees = opts.attendees or "",
  }

  local lines = apply_template(opts.template or "note", template_vars)

  core.ensure_dir(vim.fn.fnamemodify(file_abs, ":h"))
  if not core.file_exists(file_abs) then
    local ok, err = pcall(vim.fn.writefile, lines, file_abs)
    if not ok then
      core.notify("Failed to write note: " .. tostring(err), vim.log.levels.ERROR)
      return nil, nil
    end
  end

  if opts.open then
    open_and_seed(file_abs, lines)
    local row = find_content_row(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
    vim.cmd("startinsert!")
    core.notify(g.note.zettel .. " Created: " .. vim.fn.fnamemodify(file_abs, ":t"))
  end

  core.clear_cache("notes_files")
  return file_abs, id
end

function M.new_note(opts)
  opts = opts or {}

  local function create(title)
    if not title or title == "" then
      core.notify("Note title required", vim.log.levels.WARN)
      return
    end

    M.create_note_file({
      title = title,
      dir = opts.dir or cfg.notes_dir,
      template = opts.template or "note",
      tags = opts.tags or "",
      open = true,
    })
  end

  if opts.title then
    create(opts.title)
  else
    vim.ui.input({ prompt = g.note.zettel .. " Note title: " }, create)
  end
end

function M.quick_note(title)
  M.new_note({
    dir = cfg.quick_dir,
    template = "quick",
    title = title or os.date("%H:%M Quick Note"),
  })
end

function M.daily_note(gtd_tasks_content)
  local dir = core.ensure_dir(cfg.daily_dir)
  local date = os.date(cfg.date_format)
  local file = core.join(dir, date .. cfg.file_ext)

  local template_vars = {
    date = date,
    gtd_tasks = gtd_tasks_content or "",
  }

  local lines = apply_template("daily", template_vars)
  open_and_seed(file, lines, 4)
  core.notify(g.note.daily .. " Daily note: " .. date)
end

function M.new_project(title)
  local function create(project_title)
    if not project_title or project_title == "" then
      core.notify("Project title required", vim.log.levels.WARN)
      return
    end

    local projects_dir = core.ensure_dir(core.join(cfg.notes_dir, "Projects"))
    M.create_note_file({
      title = project_title,
      dir = projects_dir,
      template = "project",
      tags = "#project",
      open = true,
    })
  end

  if title then
    create(title)
  else
    vim.ui.input({ prompt = g.note.project .. " Project title: " }, create)
  end
end

function M.new_reading(opts)
  opts = opts or {}

  local function create(title)
    if not title or title == "" then
      core.notify("Book title required", vim.log.levels.WARN)
      return
    end

    local reading_dir = core.ensure_dir(core.join(cfg.notes_dir, "Reading"))
    M.create_note_file({
      title = title,
      dir = reading_dir,
      template = "reading",
      tags = opts.tags or "",
      author = opts.author or "",
      open = true,
    })
  end

  if opts.title then
    create(opts.title)
  else
    vim.ui.input({ prompt = g.note.reading .. " Book title: " }, create)
  end
end

function M.new_person(opts)
  opts = opts or {}

  local function create(name)
    if not name or name == "" then
      core.notify("Person name required", vim.log.levels.WARN)
      return
    end

    local people_dir = core.ensure_dir(core.join(cfg.notes_dir, "People"))
    M.create_note_file({
      title = name,
      dir = people_dir,
      template = "person",
      tags = opts.tags or "",
      open = true,
    })
  end

  if opts.title then
    create(opts.title)
  else
    vim.ui.input({ prompt = g.note.person .. " Person name: " }, create)
  end
end

function M.new_meeting(opts)
  opts = opts or {}

  local function create(title)
    if not title or title == "" then
      core.notify("Meeting title required", vim.log.levels.WARN)
      return
    end

    local meetings_dir = core.ensure_dir(core.join(cfg.notes_dir, "Meetings"))
    M.create_note_file({
      title = title,
      dir = meetings_dir,
      template = "meeting",
      tags = opts.tags or "",
      attendees = opts.attendees or "",
      open = true,
    })
  end

  if opts.title then
    create(opts.title)
  else
    vim.ui.input({ prompt = g.note.meeting .. " Meeting title: " }, create)
  end
end

-- ============================================================================
-- BACKLINKS IN BUFFER
-- ============================================================================

function M.update_backlinks_in_buffer()
  if not cfg.backlinks.show_in_buffer then return end

  local current_file = vim.fn.expand("%:p")
  if not current_file:match("%.md$") then return end

  local backlinks = core.get_backlinks(current_file)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local backlinks_start = nil
  for i, line in ipairs(lines) do
    if line:match("^## Backlinks") then
      backlinks_start = i
      break
    end
  end

  if not backlinks_start then return end

  local backlinks_end = #lines
  for i = backlinks_start + 1, #lines do
    if lines[i]:match("^##%s") then
      backlinks_end = i - 1
      break
    end
  end

  local backlinks_content = {}
  if #backlinks > 0 then
    for _, bl in ipairs(backlinks) do
      local glyph = g.note[bl.note_type] or g.workflow.link
      table.insert(backlinks_content, string.format("- %s [[%s]]", glyph, bl.rel_path))
    end
  else
    table.insert(backlinks_content, "<!-- No backlinks found -->")
  end

  vim.api.nvim_buf_set_lines(bufnr, backlinks_start, backlinks_end, false, backlinks_content)
end

-- ============================================================================
-- INDEX
-- ============================================================================

function M.write_index()
  local idx = core.join(cfg.notes_dir, "index.md")
  local notes = core.get_all_notes()
  local tag_map = core.get_all_tags()

  local lines = {
    "# " .. g.workflow.index .. " Notes Index",
    "",
    ("_Updated:_ %s"):format(os.date(cfg.datetime_format)),
    ("_Total Notes:_ %d"):format(#notes),
    ("_Total Tags:_ %d"):format(vim.tbl_count(tag_map)),
    "",
  }

  if next(tag_map) then
    table.insert(lines, "## " .. g.workflow.tag .. " Tags")
    table.insert(lines, "")
    local tag_list = {}
    for tag, files in pairs(tag_map) do
      table.insert(tag_list, string.format("#%s (%d)", tag, #files))
    end
    table.sort(tag_list)
    table.insert(lines, table.concat(tag_list, " • "))
    table.insert(lines, "")
  end

  table.insert(lines, "## " .. g.note.zettel .. " Notes")
  table.insert(lines, "")
  for _, note in ipairs(notes) do
    local rel = vim.fn.fnamemodify(note.path, ":.")
    local glyph = g.note[note.note_type] or g.note.zettel
    table.insert(lines, ("- %s [%s](%s)"):format(glyph, note.title, rel))
  end

  vim.fn.writefile(lines, idx)
  return idx
end

return M
