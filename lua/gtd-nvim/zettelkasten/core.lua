-- ~/.config/nvim/lua/utils/zettelkasten/core.lua
-- Core Zettelkasten utilities - base functionality for all submodules
-- Enhanced with caching, backlinks, tags, and full GTD integration

local M = {}

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local cfg = {
  notes_dir       = vim.fn.expand("~/Documents/Notes"),
  daily_dir       = vim.fn.expand("~/Documents/Notes/Daily"),
  quick_dir       = vim.fn.expand("~/Documents/Notes/Quick"),
  projects_dir    = vim.fn.expand("~/Documents/Notes/Projects"),
  people_dir      = vim.fn.expand("~/Documents/Notes/People"),
  reading_dir     = vim.fn.expand("~/Documents/Notes/Reading"),
  templates_dir   = vim.fn.expand("~/Documents/Notes/Templates"),
  archive_dir     = vim.fn.expand("~/Documents/Notes/Archive"),
  gtd_dir         = vim.fn.expand("~/Documents/GTD"),
  file_ext        = ".md",

  id_format       = "%Y%m%d%H%M",
  date_format     = "%Y-%m-%d",
  datetime_format = "%Y-%m-%d %H:%M:%S",

  slug_lowercase  = false,

  -- Cache settings
  cache = {
    enabled = true,
    ttl = 300, -- 5 minutes
  },

  -- GTD settings
  gtd = {
    enabled = true,
    inbox_file = vim.fn.expand("~/Documents/GTD/Inbox.org"),
    max_tasks = 600,
  },
}

-- APFS junk patterns to exclude
local JUNK_PATTERNS = {
  ".DS_Store", "._*", ".Trashes", ".Spotlight%-V100",
  ".fseventsd", ".TemporaryItems", ".AppleDouble", ".continuity",
}

----------------------------------------------------------------------
-- Cache System
----------------------------------------------------------------------
local _cache = {
  notes = { data = nil, timestamp = 0 },
  gtd_tasks = { data = nil, timestamp = 0 },
  tags = { data = nil, timestamp = 0 },
  backlinks = {}, -- keyed by filepath
}

local function is_cache_valid(key)
  if not cfg.cache.enabled then return false end
  local entry = _cache[key]
  if not entry then return false end
  if type(entry) == "table" and entry.data then
    return (os.time() - (entry.timestamp or 0)) < cfg.cache.ttl
  end
  return false
end

local function set_cache(key, data)
  if cfg.cache.enabled then
    _cache[key] = { data = data, timestamp = os.time() }
  end
end

function M.clear_cache(key)
  if key then
    if _cache[key] then
      _cache[key] = { data = nil, timestamp = 0 }
    end
  else
    _cache.notes = { data = nil, timestamp = 0 }
    _cache.gtd_tasks = { data = nil, timestamp = 0 }
    _cache.tags = { data = nil, timestamp = 0 }
    _cache.backlinks = {}
  end
  M.notify("Cache cleared")
end


----------------------------------------------------------------------
-- Path Utilities
----------------------------------------------------------------------
local function ensure_dir(path)
  local p = vim.fn.expand(path)
  vim.fn.mkdir(p, "p")
  return p
end

local function file_exists(path)
  return vim.fn.filereadable(vim.fn.expand(path)) == 1
end

local function is_dir(path)
  return vim.fn.isdirectory(vim.fn.expand(path)) == 1
end

local function join(...)
  return vim.fs.joinpath(...)
end

local function abspath(p)
  return vim.fn.fnamemodify(vim.fn.expand(p or ""), ":p")
end

local function to_abs(p)
  if not p or p == "" then return nil end
  p = vim.fn.expand(p)
  if p:sub(1,1) == "/" or p:match("^%a:[/\\]") then
    return abspath(p)
  end
  return join(cfg.notes_dir, p)
end

-- Strip ANSI color codes and decoration from fzf output
local function strip_decor(s)
  if type(s) ~= "string" then return s end
  s = s:gsub("\27%[[0-9;]*m", "")
       :gsub("^[%z\1-\31]+", "")
  if vim.fn.strwidth(s) > #s and s:find("%s") then
    s = s:gsub("^[^%s]+%s+", "")
  end
  return s
end

----------------------------------------------------------------------
-- Slug / ID Generation
----------------------------------------------------------------------
local function slugify_keep_unicode(title)
  local s = title or ""
  s = s:gsub("[/\\:%*%?%\"%<%>%|]", "-")
  s = s:gsub("%s+", "-")
  s = s:gsub("^%-+", ""):gsub("%-+$", "")
  if cfg.slug_lowercase then s = vim.fn.tolower(s) end
  if s == "" then s = "note" end
  return s
end

local function gen_id()
  return os.date(cfg.id_format)
end

local function gen_filename(title, id)
  return string.format("%s-%s%s", id or gen_id(), slugify_keep_unicode(title), cfg.file_ext)
end

----------------------------------------------------------------------
-- File Exclusion Patterns (for fzf/fd/rg)
----------------------------------------------------------------------
local FD_EXCLUDE_OPTS = table.concat({
  "--type f",
  "--hidden",
  "--exclude .git",
  "--exclude .DS_Store",
  "--exclude '.continuity'",
  "--exclude node_modules",
  "--exclude '*.tmp'",
  "--exclude '*.bak'",
  "--exclude '.Trash*'",
  "--exclude '__pycache__'",
  "--exclude '._*'",
}, " ")

local RG_EXCLUDE_OPTS = table.concat({
  "--hidden",
  "--glob '!.git'",
  "--glob '!.DS_Store'",
  "--glob '!.continuity/**'",
  "--glob '!node_modules'",
  "--glob '!*.tmp'",
  "--glob '!*.bak'",
  "--glob '!.Trash*'",
  "--glob '!._*'",
}, " ")

function M.get_exclude_opts_string()
  return " " .. table.concat({
    "--exclude .git",
    "--exclude .DS_Store",
    "--exclude '.continuity'",
    "--exclude '._*'",
    "--exclude '*.tmp'",
    "--exclude '*.bak'",
  }, " ")
end


----------------------------------------------------------------------
-- Template System
----------------------------------------------------------------------
local function read_template(kind)
  local p = join(cfg.templates_dir, kind .. cfg.file_ext)
  if file_exists(p) then return vim.fn.readfile(p) end
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
          -- Handle multi-line substitutions (e.g., GTD tasks)
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
            line = line:gsub(placeholder, tostring(v or ""))
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
  local defaults = {
    note = {
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "**ID:** {{id}}",
      "**Tags:** {{tags}}",
      "",
      "## Content",
      "",
      "## Related",
      "",
    },
    daily = {
      "# Daily Note - {{date}}",
      "",
      "## Tasks",
      "{{gtd_tasks}}",
      "",
      "## Notes",
      "",
      "## Reflections",
      "",
    },
    quick = {
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "**Tags:** #quick",
      "",
    },
    project = {
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "**ID:** {{id}}",
      "**Status:** Active",
      "**Tags:** #project {{tags}}",
      "",
      "## Overview",
      "",
      "## Tasks",
      "- [ ] ",
      "",
      "## Notes",
      "",
      "## Related",
      "",
    },
    meeting = {
      "# Meeting: {{title}}",
      "",
      "**Date:** {{datetime}}",
      "**ID:** {{id}}",
      "**Tags:** #meeting {{tags}}",
      "",
      "## Attendees",
      "- ",
      "",
      "## Agenda",
      "",
      "## Notes",
      "",
      "## Action Items",
      "- [ ] ",
      "",
    },
    person = {
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "**ID:** {{id}}",
      "**Relationship:** {{relationship}}",
      "**Email:** {{email}}",
      "**Phone:** {{phone}}",
      "**Company:** {{company}}",
      "**Location:** {{location}}",
      "",
      "## Notes",
      "",
      "## Interactions",
      "",
    },
    book = {
      "# {{title}}",
      "",
      "**Author:** {{author}}",
      "**Created:** {{created}}",
      "**ID:** {{id}}",
      "**Status:** {{status}}",
      "**Rating:** {{rating}}",
      "**Tags:** #book #reading",
      "",
      "## Summary",
      "",
      "## Quotes",
      "",
      "## Notes",
      "",
    },
  }

  local template = defaults[kind] or { "# {{title}}", "", "" }
  return fill(template)
end


----------------------------------------------------------------------
-- Note Discovery (with caching)
----------------------------------------------------------------------
function M.get_all_notes()
  if is_cache_valid("notes") then
    return _cache.notes.data
  end

  local notes = {}
  local function scan_dir(dir, prefix)
    prefix = prefix or ""
    local handle = vim.loop.fs_scandir(abspath(dir))
    if not handle then return end

    while true do
      local name, ftype = vim.loop.fs_scandir_next(handle)
      if not name then break end

      -- Skip junk files
      local skip = false
      for _, pattern in ipairs(JUNK_PATTERNS) do
        if name:match(pattern) then skip = true; break end
      end
      if skip then goto continue end

      local full_path = join(dir, name)
      local rel_path = prefix .. name

      if ftype == "directory" then
        if not (name == ".git" or name == "Templates" or name == "Archive" or name:match("^%.")) then
          scan_dir(full_path, rel_path .. "/")
        end
      elseif ftype == "file" and name:match("%.md$") then
        table.insert(notes, {
          path = abspath(full_path),
          rel_path = rel_path,
          name = name,
          title = name:gsub("%.md$", ""):gsub("^%d+%-", ""),
          dir = prefix ~= "" and prefix:gsub("/$", "") or "",
        })
      end
      ::continue::
    end
  end

  scan_dir(cfg.notes_dir)
  table.sort(notes, function(a, b) return a.rel_path < b.rel_path end)
  set_cache("notes", notes)
  return notes
end

----------------------------------------------------------------------
-- GTD Task Extraction (with caching)
----------------------------------------------------------------------
function M.get_gtd_tasks()
  if not cfg.gtd.enabled then return {} end
  if is_cache_valid("gtd_tasks") then
    return _cache.gtd_tasks.data
  end

  local tasks = {}
  if not is_dir(cfg.gtd_dir) then
    return tasks
  end

  -- Use ripgrep for fast task extraction
  local cmd = string.format(
    'rg -n "^\\*+\\s+(TODO|NEXT|WAITING|DONE|PROJ|SOMEDAY|MAYBE)" %s --type org 2>/dev/null | head -%d',
    vim.fn.shellescape(cfg.gtd_dir),
    cfg.gtd.max_tasks
  )

  local success, result = pcall(vim.fn.systemlist, cmd)
  if success and vim.v.shell_error == 0 then
    for _, line in ipairs(result) do
      local file, line_num, content = line:match("^([^:]+):(%d+):(.*)$")
      if file and content then
        local task_type = content:match("^%*+%s+(%w+)")
        local task_text = content:gsub("^%*+%s+%w+%s*", "")

        -- Clean up task text
        task_text = task_text:gsub("%s*:.-:%s*$", "")  -- Remove org tags
        task_text = task_text:gsub("%s*SCHEDULED:.-$", "")
        task_text = task_text:gsub("%s*DEADLINE:.-$", "")
        task_text = task_text:gsub("%s+", " ")
        task_text = vim.trim(task_text)

        -- Truncate for display
        local display_text = task_text
        if #task_text > 80 then
          display_text = task_text:sub(1, 77) .. "..."
        end

        -- Extract deadline if present
        local deadline = content:match("DEADLINE:%s*<([^>]+)>")
        local scheduled = content:match("SCHEDULED:%s*<([^>]+)>")

        table.insert(tasks, {
          file = file,
          line = tonumber(line_num),
          type = task_type,
          text = task_text,
          display_text = display_text,
          deadline = deadline,
          scheduled = scheduled,
          rel_file = file:gsub("^" .. vim.pesc(cfg.gtd_dir) .. "/", ""),
        })
      end
    end
  end

  set_cache("gtd_tasks", tasks)
  return tasks
end


----------------------------------------------------------------------
-- Tag Extraction
----------------------------------------------------------------------
function M.extract_tags_from_content(content)
  local tags = {}
  local seen = {}
  
  -- Markdown style: #tag
  for tag in content:gmatch("#([%w_%-]+)") do
    if not seen[tag] then
      seen[tag] = true
      table.insert(tags, tag)
    end
  end
  
  -- Org style: :tag:
  for tag in content:gmatch(":([%w_]+):") do
    if not seen[tag] then
      seen[tag] = true
      table.insert(tags, tag)
    end
  end
  
  return tags
end

function M.get_all_tags()
  if is_cache_valid("tags") then
    return _cache.tags.data
  end

  local tag_map = {}
  local notes = M.get_all_notes()

  for _, note in ipairs(notes) do
    if file_exists(note.path) then
      local content = table.concat(vim.fn.readfile(note.path), "\n")
      local tags = M.extract_tags_from_content(content)
      for _, tag in ipairs(tags) do
        if not tag_map[tag] then tag_map[tag] = {} end
        table.insert(tag_map[tag], note)
      end
    end
  end

  -- Also extract from GTD tasks
  if cfg.gtd.enabled then
    local tasks = M.get_gtd_tasks()
    for _, task in ipairs(tasks) do
      local tags = M.extract_tags_from_content(task.text)
      for _, tag in ipairs(tags) do
        if not tag_map[tag] then tag_map[tag] = {} end
        table.insert(tag_map[tag], {
          path = task.file,
          title = task.display_text,
          rel_path = task.rel_file,
          type = "gtd_task",
        })
      end
    end
  end

  set_cache("tags", tag_map)
  return tag_map
end

----------------------------------------------------------------------
-- Backlinks
----------------------------------------------------------------------
function M.get_backlinks(file_path)
  file_path = file_path or vim.fn.expand("%:p")
  
  -- Check cache
  local cache_key = file_path
  if _cache.backlinks[cache_key] and 
     (os.time() - (_cache.backlinks[cache_key].timestamp or 0)) < cfg.cache.ttl then
    return _cache.backlinks[cache_key].data
  end

  local backlinks = {}
  local notes = M.get_all_notes()
  local target_name = vim.fn.fnamemodify(file_path, ":t:r")
  local target_rel = file_path:gsub("^" .. vim.pesc(cfg.notes_dir) .. "/", "")

  for _, note in ipairs(notes) do
    if note.path ~= file_path and file_exists(note.path) then
      local content = table.concat(vim.fn.readfile(note.path), "\n")

      -- Look for various link formats
      if content:match("%[%[" .. vim.pesc(target_name) .. "%]%]") or
         content:match("%[%[" .. vim.pesc(target_name) .. "|") or
         content:match("%[.*%]%(.*" .. vim.pesc(target_name) .. ".*%)") or
         content:match("%[.*%]%(.*" .. vim.pesc(target_rel) .. ".*%)") then
        table.insert(backlinks, {
          file = note.path,
          title = note.title,
          rel_path = note.rel_path,
        })
      end
    end
  end

  -- Cache the result
  _cache.backlinks[cache_key] = { data = backlinks, timestamp = os.time() }
  return backlinks
end

----------------------------------------------------------------------
-- FZF Selection Helpers
----------------------------------------------------------------------
function M.sel_to_paths_fzf(selected)
  local out = {}
  for _, s in ipairs(selected or {}) do
    local cand = nil
    if type(s) == "string" then
      cand = s
    elseif type(s) == "table" then
      cand = s.path or s[1] or s.text or s.filename
    end
    if cand and cand ~= "" then
      cand = strip_decor(cand)
      local abs = to_abs(cand)
      if abs then table.insert(out, abs) end
    end
  end
  
  -- Deduplicate
  local uniq, seen = {}, {}
  for _, p in ipairs(out) do
    if p and not seen[p] then
      seen[p] = true
      table.insert(uniq, p)
    end
  end
  return uniq
end


----------------------------------------------------------------------
-- File Operations
----------------------------------------------------------------------
local function open_and_seed(filepath, lines, cursor_row)
  lines = lines or { "" }
  local fp = abspath(filepath)
  local existed = file_exists(fp)
  if not existed then
    ensure_dir(vim.fn.fnamemodify(fp, ":h"))
    vim.fn.writefile(lines, fp)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(fp))
  if existed and vim.fn.line("$") == 1 and vim.fn.getline(1) == "" then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end
  if cursor_row then pcall(vim.api.nvim_win_set_cursor, 0, { cursor_row, 0 }) end
end

local function find_content_row(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, ln in ipairs(lines) do
    if ln:match("^##%s+Content%s*$") or 
       ln:match("^##%s+Notes%s*$") or 
       ln:match("^##%s+Indhold%s*$") then
      return math.min(i + 1, #lines + 1)
    end
  end
  return #lines + 1
end

----------------------------------------------------------------------
-- Notification Helper
----------------------------------------------------------------------
function M.notify(msg, level, title)
  vim.notify(msg, level or vim.log.levels.INFO, { title = title or "Zettel" })
end

----------------------------------------------------------------------
-- Config Accessors
----------------------------------------------------------------------
function M.get_paths()
  return {
    notes_dir     = cfg.notes_dir,
    daily_dir     = cfg.daily_dir,
    quick_dir     = cfg.quick_dir,
    projects_dir  = cfg.projects_dir,
    people_dir    = cfg.people_dir,
    reading_dir   = cfg.reading_dir,
    templates_dir = cfg.templates_dir,
    archive_dir   = cfg.archive_dir,
    gtd_dir       = cfg.gtd_dir,
    file_ext      = cfg.file_ext,
  }
end

function M.get_config()
  return {
    id_format       = cfg.id_format,
    date_format     = cfg.date_format,
    datetime_format = cfg.datetime_format,
    slug_lowercase  = cfg.slug_lowercase,
    file_ext        = cfg.file_ext,
    gtd_enabled     = cfg.gtd.enabled,
    cache_ttl       = cfg.cache.ttl,
  }
end

----------------------------------------------------------------------
-- Public Utility Exports (for submodules)
----------------------------------------------------------------------
M.ensure_dir = ensure_dir
M.file_exists = file_exists
M.is_dir = is_dir
M.join = join
M.abspath = abspath
M.to_abs = to_abs
M.strip_decor = strip_decor
M.slugify = slugify_keep_unicode
M.gen_id = gen_id
M.gen_filename = gen_filename
M.apply_template = apply_template
M.open_and_seed = open_and_seed
M.find_content_row = find_content_row

-- Exclusion pattern strings
M.FD_EXCLUDE_OPTS = FD_EXCLUDE_OPTS
M.RG_EXCLUDE_OPTS = RG_EXCLUDE_OPTS

----------------------------------------------------------------------
-- Fuzzy Finder Detection
----------------------------------------------------------------------
function M.have_fzf()
  return pcall(require, "fzf-lua")
end

function M.have_telescope()
  return pcall(require, "telescope.builtin")
end


----------------------------------------------------------------------
-- Note Creation
----------------------------------------------------------------------
function M.create_note_file(opts)
  opts = opts or {}
  local title = opts.title
  if not title or title == "" then
    M.notify("Note title required", vim.log.levels.WARN)
    return nil, nil
  end

  local dir = ensure_dir(opts.dir or cfg.notes_dir)
  local id = opts.id or gen_id()
  local file = join(dir, gen_filename(title, id))

  -- Build template variables
  local base_vars = {
    title = title,
    created = os.date(cfg.datetime_format),
    date = os.date(cfg.date_format),
    datetime = os.date(cfg.datetime_format),
    id = id,
    tags = opts.tags or "",
  }
  local vars = vim.tbl_extend("force", base_vars, opts.template_vars or {})

  local lines = apply_template(opts.template or "note", vars)

  if not file_exists(file) then
    ensure_dir(vim.fn.fnamemodify(file, ":h"))
    vim.fn.writefile(lines, file)
  end

  if opts.open then
    open_and_seed(file, lines)
    local row = find_content_row(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
    vim.cmd("startinsert!")
    M.notify("Created: " .. vim.fn.fnamemodify(file, ":t"))
  end

  M.clear_cache("notes")
  return file, id
end

function M.new_note(opts)
  opts = opts or {}
  local function create(title)
    if not title or title == "" then
      M.notify("Note title required", vim.log.levels.WARN)
      return
    end
    M.create_note_file({
      title = title,
      dir = opts.dir or cfg.notes_dir,
      template = opts.template or "note",
      template_vars = opts.template_vars,
      tags = opts.tags,
      open = true,
    })
  end

  if opts.title then
    create(opts.title)
  else
    vim.ui.input({ prompt = "Note title: " }, create)
  end
end

function M.quick_note(title)
  M.new_note({
    dir = cfg.quick_dir,
    template = "quick",
    title = title or os.date("%H:%M Quick Note"),
  })
end

function M.daily_note()
  local dir = ensure_dir(cfg.daily_dir)
  local date = os.date(cfg.date_format)
  local file = join(dir, date .. cfg.file_ext)
  
  -- Basic daily note (capture.lua provides the enhanced GTD version)
  open_and_seed(file, apply_template("daily", { 
    date = date,
    gtd_tasks = "- [ ] ",
  }), 4)
  M.notify("Daily note: " .. date)
end


----------------------------------------------------------------------
-- Search & Navigation
----------------------------------------------------------------------
function M.find_notes()
  local root = cfg.notes_dir
  if M.have_fzf() then
    require("fzf-lua").files({
      cwd = root,
      prompt = "🧠 Notes> ",
      fd_opts = FD_EXCLUDE_OPTS,
    })
  elseif M.have_telescope() then
    require("telescope.builtin").find_files({
      prompt_title = "Zettelkasten Notes",
      cwd = root,
      file_ignore_patterns = { "%.git/", "node_modules/", ".DS_Store", "/Templates/", "%.continuity/" },
    })
  else
    M.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

function M.search_notes()
  local root = cfg.notes_dir
  if M.have_fzf() then
    require("fzf-lua").live_grep({
      cwd = root,
      prompt = "🔍 Search> ",
      rg_opts = RG_EXCLUDE_OPTS .. " --column --line-number --no-heading --color=always --smart-case",
    })
  elseif M.have_telescope() then
    require("telescope.builtin").live_grep({
      prompt_title = "Search Zettelkasten",
      cwd = root,
      additional_args = function()
        return { "--hidden", "--glob", "!.git", "--glob", "!.DS_Store" }
      end,
    })
  else
    M.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

function M.search_all()
  -- Search both notes and GTD
  if not M.have_fzf() then
    M.notify("fzf-lua required for unified search", vim.log.levels.WARN)
    return
  end

  local roots = { cfg.notes_dir }
  if cfg.gtd.enabled and is_dir(cfg.gtd_dir) then
    table.insert(roots, cfg.gtd_dir)
  end

  local cmd = "rg --column --line-number --no-heading --color=always --smart-case"
  for _, root in ipairs(roots) do
    cmd = cmd .. " " .. vim.fn.shellescape(root)
  end

  require("fzf-lua").grep({
    prompt = "🔍 All> ",
    cmd = cmd,
    fzf_opts = { ["--header"] = "Search Notes & GTD" },
  })
end

function M.recent_notes()
  local root = cfg.notes_dir
  if M.have_fzf() then
    require("fzf-lua").oldfiles({
      cwd = root,
      cwd_only = true,
      prompt = "⏰ Recent> ",
    })
  elseif M.have_telescope() then
    require("telescope.builtin").oldfiles({
      prompt_title = "Recent Notes",
      cwd = root,
      cwd_only = true,
    })
  else
    M.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

----------------------------------------------------------------------
-- Browse Tags
----------------------------------------------------------------------
function M.browse_tags()
  if not M.have_fzf() then
    M.notify("fzf-lua required for tag browsing", vim.log.levels.WARN)
    return
  end

  local tag_map = M.get_all_tags()
  if not next(tag_map) then
    M.notify("No tags found")
    return
  end

  local tags = {}
  for tag, files in pairs(tag_map) do
    table.insert(tags, string.format("#%s (%d)", tag, #files))
  end
  table.sort(tags)

  require("fzf-lua").fzf_exec(tags, {
    prompt = "🏷️  Tags> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local tag = selected[1]:match("^#([%w_%-]+)")
          if tag then M.browse_files_by_tag(tag) end
        end
      end,
    },
  })
end

function M.browse_files_by_tag(tag)
  local tag_map = M.get_all_tags()
  local files = tag_map[tag] or {}

  if #files == 0 then
    M.notify("No files found for tag: #" .. tag)
    return
  end

  local items = {}
  for _, file in ipairs(files) do
    local display = file.rel_path or file.title
    if file.type == "gtd_task" then
      display = display .. " [GTD]"
    end
    table.insert(items, display)
  end

  require("fzf-lua").fzf_exec(items, {
    prompt = "#" .. tag .. "> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local item = selected[1]:gsub(" %[GTD%]$", "")
          local full_path = item:match("^/") and item or join(cfg.notes_dir, item)
          vim.cmd("edit " .. vim.fn.fnameescape(full_path))
        end
      end,
    },
  })
end

----------------------------------------------------------------------
-- Show Backlinks
----------------------------------------------------------------------
function M.show_backlinks(file_path)
  file_path = file_path or vim.fn.expand("%:p")
  local backlinks = M.get_backlinks(file_path)

  if #backlinks == 0 then
    M.notify("No backlinks found")
    return
  end

  if not M.have_fzf() then
    M.notify("fzf-lua required for backlinks", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, bl in ipairs(backlinks) do
    table.insert(items, bl.rel_path .. " (" .. bl.title .. ")")
  end

  require("fzf-lua").fzf_exec(items, {
    prompt = "🔗 Backlinks> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local rel_path = selected[1]:match("^([^%s]+)")
          local full_path = join(cfg.notes_dir, rel_path)
          vim.cmd("edit " .. vim.fn.fnameescape(full_path))
        end
      end,
    },
  })
end


----------------------------------------------------------------------
-- Statistics
----------------------------------------------------------------------
function M.show_stats()
  local notes = M.get_all_notes()
  local tags = M.get_all_tags()
  local tasks = cfg.gtd.enabled and M.get_gtd_tasks() or {}

  local dir_counts = {}
  for _, note in ipairs(notes) do
    local dir = note.dir ~= "" and note.dir or "Root"
    dir_counts[dir] = (dir_counts[dir] or 0) + 1
  end

  local lines = {
    "📊 Zettelkasten Statistics",
    "─────────────────────────",
    string.format("Total notes: %d", #notes),
    string.format("Total tags: %d", vim.tbl_count(tags)),
    string.format("GTD tasks: %d", #tasks),
    "",
    "Directories:",
  }

  for dir, count in pairs(dir_counts) do
    table.insert(lines, string.format("  • %s: %d", dir, count))
  end

  M.notify(table.concat(lines, "\n"))
end

----------------------------------------------------------------------
-- Index Writing
----------------------------------------------------------------------
function M.write_index()
  local notes = M.get_all_notes()
  local tag_map = M.get_all_tags()
  local index_file = join(cfg.notes_dir, "INDEX.md")

  local lines = {
    "# Zettelkasten Index",
    "",
    string.format("*Generated: %s*", os.date(cfg.datetime_format)),
    string.format("*Total: %d notes*", #notes),
    string.format("*Tags: %d*", vim.tbl_count(tag_map)),
    "",
  }

  -- Tags section
  if next(tag_map) then
    table.insert(lines, "## Tags")
    table.insert(lines, "")
    local tag_list = {}
    for tag, files in pairs(tag_map) do
      table.insert(tag_list, string.format("#%s (%d)", tag, #files))
    end
    table.sort(tag_list)
    table.insert(lines, table.concat(tag_list, " • "))
    table.insert(lines, "")
  end

  -- Notes by directory
  table.insert(lines, "## Notes")
  table.insert(lines, "")

  local current_dir = ""
  for _, note in ipairs(notes) do
    local dir = note.dir ~= "" and note.dir or "."
    if dir ~= current_dir then
      current_dir = dir
      if dir ~= "." then
        table.insert(lines, "")
        table.insert(lines, "### " .. dir)
        table.insert(lines, "")
      end
    end
    table.insert(lines, string.format("- [[%s|%s]]", note.rel_path:gsub("%.md$", ""), note.title))
  end

  vim.fn.writefile(lines, index_file)
  M.notify("Index written: " .. #notes .. " notes")
end

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------
function M.setup(opts)
  if opts and type(opts) == "table" then
    -- Merge config
    for k, v in pairs(opts) do
      if k == "gtd" and type(v) == "table" then
        cfg.gtd = vim.tbl_extend("force", cfg.gtd, v)
      elseif k == "cache" and type(v) == "table" then
        cfg.cache = vim.tbl_extend("force", cfg.cache, v)
      elseif cfg[k] ~= nil then
        cfg[k] = v
      end
    end
  end

  -- Ensure directories exist
  ensure_dir(cfg.notes_dir)
  ensure_dir(cfg.daily_dir)
  ensure_dir(cfg.quick_dir)
  ensure_dir(cfg.projects_dir)
  ensure_dir(cfg.people_dir)
  ensure_dir(cfg.reading_dir)
  ensure_dir(cfg.templates_dir)
  ensure_dir(cfg.archive_dir)

  -- Core commands
  vim.api.nvim_create_user_command("ZettelNew", function(c)
    M.new_note({ title = (c.args ~= "" and c.args or nil) })
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("ZettelDaily", M.daily_note, {})
  vim.api.nvim_create_user_command("ZettelQuick", function(c)
    M.quick_note(c.args ~= "" and c.args or nil)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("ZettelFind", M.find_notes, {})
  vim.api.nvim_create_user_command("ZettelSearch", M.search_notes, {})
  vim.api.nvim_create_user_command("ZettelSearchAll", M.search_all, {})
  vim.api.nvim_create_user_command("ZettelRecent", M.recent_notes, {})
  vim.api.nvim_create_user_command("ZettelTags", M.browse_tags, {})
  vim.api.nvim_create_user_command("ZettelBacklinks", function() M.show_backlinks() end, {})
  vim.api.nvim_create_user_command("ZettelStats", M.show_stats, {})
  vim.api.nvim_create_user_command("ZettelIndex", M.write_index, {})
  vim.api.nvim_create_user_command("ZettelClearCache", function() M.clear_cache() end, {})
end

return M
