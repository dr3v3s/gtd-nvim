-- ~/.config/nvim/lua/utils/zettelkasten/core.lua
-- Core Zettelkasten utilities - base functionality for all submodules
-- This is the foundation module that capture.lua, manage.lua, etc. depend on

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
  file_ext        = ".md",

  id_format       = "%Y%m%d%H%M",
  date_format     = "%Y-%m-%d",
  datetime_format = "%Y-%m-%d %H:%M:%S",

  slug_lowercase  = false,  -- keep nordic letters; only downcase if you want
}

----------------------------------------------------------------------
-- Utils
----------------------------------------------------------------------
local function ensure_dir(path)
  vim.fn.mkdir(path, "p")
  return path
end

local function file_exists(path)
  return vim.fn.filereadable(path) == 1
end

local function join(...)
  return vim.fs.joinpath(...)
end

local function slugify_keep_unicode(title)
  local s = title or ""
  s = s:gsub("[/\\:%*%?%\"%<%>%|]", "-")
  s = s:gsub("%s+", "-")
  s = s:gsub("^%-+", ""):gsub("%-+$", "")
  if cfg.slug_lowercase then s = vim.fn.tolower(s) end
  return s
end

local function gen_id()
  return os.date(cfg.id_format)
end

local function gen_filename(title, id)
  return string.format("%s-%s%s", id or gen_id(), slugify_keep_unicode(title), cfg.file_ext)
end

local function read_template(kind)
  local p = join(cfg.templates_dir, kind .. cfg.file_ext)
  if file_exists(p) then return vim.fn.readfile(p) end
  return nil
end

local function apply_template(kind, vars)
  local t = read_template(kind)
  local function fill(lines)
    for i, ln in ipairs(lines) do
      local cur = ln
      for k, v in pairs(vars) do
        cur = cur:gsub("{{" .. k .. "}}", v)
      end
      lines[i] = cur
    end
    return lines
  end
  if t then return fill(t) end
  if kind == "note" then
    return fill({
      "# {{title}}",
      "",
      "**Dato:** {{created}}",
      "**ID:** {{id}}",
      "",
      "## Indhold",
      "",
    })
  elseif kind == "daily" then
    return fill({
      "# Daglig Note - {{date}}",
      "",
      "## Opgaver",
      "- [ ] ",
      "",
      "## Noter",
      "",
      "## Reflektioner",
      "",
    })
  elseif kind == "quick" then
    return fill({
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "",
    })
  elseif kind == "project" then
    return fill({
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "**ID:** {{id}}",
      "**Status:** active",
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
    })
  elseif kind == "person" then
    return fill({
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "**ID:** {{id}}",
      "",
      "## Contact",
      "",
      "## Notes",
      "",
      "## Interactions",
      "",
    })
  elseif kind == "book" then
    return fill({
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "**ID:** {{id}}",
      "**Status:** reading",
      "",
      "## Summary",
      "",
      "## Quotes",
      "",
      "## Notes",
      "",
    })
  end
  return { "" }
end

local function open_and_seed(filepath, lines, cursor_row)
  lines = lines or { "" }
  local existed = file_exists(filepath)
  if not existed then
    ensure_dir(vim.fn.fnamemodify(filepath, ":h"))
    vim.fn.writefile(lines, filepath)
  end
  vim.cmd("edit " .. filepath)
  if existed and vim.fn.line("$") == 1 and vim.fn.getline(1) == "" then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end
  if cursor_row then pcall(vim.api.nvim_win_set_cursor, 0, { cursor_row, 0 }) end
end

local function find_content_row(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, ln in ipairs(lines) do
    if ln:match("^##%s+Indhold%s*$") or ln:match("^##%s+Notes%s*$") or ln:match("^##%s+Content%s*$") then
      return math.min(i + 1, #lines + 1)
    end
  end
  return #lines + 1
end

local function have_fzf()
  return pcall(require, "fzf-lua")
end

local function have_telescope()
  return pcall(require, "telescope.builtin")
end

----------------------------------------------------------------------
-- Notification helper
----------------------------------------------------------------------
function M.notify(msg, level, title)
  vim.notify(msg, level or vim.log.levels.INFO, { title = title or "Zettel" })
end

----------------------------------------------------------------------
-- Public Config Accessors
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
  }
end

----------------------------------------------------------------------
-- Public Utilities (for submodules)
----------------------------------------------------------------------
M.ensure_dir = ensure_dir
M.file_exists = file_exists
M.join = join
M.slugify = slugify_keep_unicode
M.gen_id = gen_id
M.gen_filename = gen_filename
M.apply_template = apply_template
M.open_and_seed = open_and_seed
M.find_content_row = find_content_row
M.have_fzf = have_fzf
M.have_telescope = have_telescope

----------------------------------------------------------------------
-- Create note file (for GTD integration)
----------------------------------------------------------------------
function M.create_note_file(opts)
  opts = opts or {}
  local title = opts.title
  if not title or title == "" then
    M.notify("Note title required", vim.log.levels.WARN)
    return nil, nil
  end

  local dir = ensure_dir(opts.dir or cfg.notes_dir)
  local id  = opts.id or gen_id()
  local file = join(dir, gen_filename(title, id))

  -- Build base vars, then merge with opts.template_vars
  local base_vars = {
    title   = title,
    created = os.date(cfg.datetime_format),
    date    = os.date(cfg.date_format),
    id      = id,
  }
  
  -- Merge template_vars if provided (allows people.lua, reading.lua etc. to pass custom vars)
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

  return file, id
end

----------------------------------------------------------------------
-- Core Note Functions
----------------------------------------------------------------------
function M.new_note(opts)
  opts = opts or {}
  local function create(title)
    if not title or title == "" then
      M.notify("Note title required", vim.log.levels.WARN)
      return
    end
    local dir = ensure_dir(opts.dir or cfg.notes_dir)
    local id  = gen_id()
    local file = join(dir, gen_filename(title, id))
    
    -- Build base vars, then merge with opts.template_vars
    local base_vars = {
      title = title,
      created = os.date(cfg.datetime_format),
      date = os.date(cfg.date_format),
      id = id,
    }
    local vars = vim.tbl_extend("force", base_vars, opts.template_vars or {})
    
    local lines = apply_template(opts.template or "note", vars)
    open_and_seed(file, lines)
    local row = find_content_row(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
    vim.cmd("startinsert!")
    M.notify("Created: " .. vim.fn.fnamemodify(file, ":t"))
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
  open_and_seed(file, apply_template("daily", { date = date }), 4)
  M.notify("Daily note: " .. date)
end

----------------------------------------------------------------------
-- Find / Search
----------------------------------------------------------------------

-- Common exclusion patterns for file searches
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
}, " ")

-- Common exclusion patterns for grep searches
local RG_EXCLUDE_OPTS = table.concat({
  "--hidden",
  "--glob '!.git'",
  "--glob '!.DS_Store'",
  "--glob '!.continuity/**'",
  "--glob '!node_modules'",
  "--glob '!*.tmp'",
  "--glob '!*.bak'",
  "--glob '!.Trash*'",
}, " ")

function M.find_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").files({
      cwd = root,
      prompt = "🧠 ",
      fd_opts = FD_EXCLUDE_OPTS,
    })
  elseif have_telescope() then
    require("telescope.builtin").find_files({
      prompt_title = "Zettelkasten Notes",
      cwd = root,
      file_ignore_patterns = {
        "%.git/", "node_modules/", ".DS_Store", "/Templates/",
        "%.continuity/", "%.tmp$", "%.bak$",
      },
    })
  else
    M.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

function M.search_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").live_grep({
      cwd = root,
      prompt = "🔍 ",
      rg_opts = RG_EXCLUDE_OPTS .. " --column --line-number --no-heading --color=always --smart-case",
    })
  elseif have_telescope() then
    require("telescope.builtin").live_grep({
      prompt_title = "Search Zettelkasten",
      cwd = root,
      additional_args = function()
        return {
          "--hidden",
          "--glob", "!.git",
          "--glob", "!.DS_Store",
          "--glob", "!.continuity/**",
        }
      end,
    })
  else
    M.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

function M.recent_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").oldfiles({
      cwd = root,
      cwd_only = true,
      prompt = "⏰ ",
      file_ignore_patterns = { "%.DS_Store$", "continuity", "%.tmp$", "%.bak$" },
    })
  elseif have_telescope() then
    require("telescope.builtin").oldfiles({
      prompt_title = "Recent Zettelkasten Notes",
      cwd = root,
      cwd_only = true,
      file_ignore_patterns = { "%.DS_Store", "%.continuity/", "%.tmp$" },
    })
  else
    M.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

function M.search_all()
  M.search_notes()
end

----------------------------------------------------------------------
-- Tags
----------------------------------------------------------------------
function M.browse_tags()
  local root = cfg.notes_dir
  if not have_fzf() then
    M.notify("fzf-lua required for tag browsing", vim.log.levels.WARN)
    return
  end
  
  -- Search for #tags in notes (with exclusions)
  require("fzf-lua").grep({
    cwd = root,
    search = "#[a-zA-Z0-9_-]+",
    no_esc = true,
    prompt = "🏷️  Tags> ",
    rg_opts = RG_EXCLUDE_OPTS .. " --column --line-number --no-heading --color=always",
  })
end

----------------------------------------------------------------------
-- Backlinks
----------------------------------------------------------------------
function M.show_backlinks()
  local current = vim.fn.expand("%:t:r")
  if current == "" then
    M.notify("No file open", vim.log.levels.WARN)
    return
  end
  
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").grep({
      cwd = root,
      search = current,
      prompt = "🔗 Backlinks> ",
    })
  else
    M.notify("fzf-lua required for backlinks", vim.log.levels.WARN)
  end
end

----------------------------------------------------------------------
-- Stats
----------------------------------------------------------------------
function M.show_stats()
  local root = cfg.notes_dir
  local count = 0
  local dirs = {}
  
  local function scan(path)
    local handle = vim.loop.fs_scandir(path)
    if not handle then return end
    
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      local full = path .. "/" .. name
      if type == "file" and name:match("%.md$") then
        count = count + 1
      elseif type == "directory" and not name:match("^%.") then
        local dir_name = vim.fn.fnamemodify(full, ":t")
        dirs[dir_name] = (dirs[dir_name] or 0) + 1
        scan(full)
      end
    end
  end
  
  scan(root)
  
  local lines = {
    "📊 Zettelkasten Stats",
    "─────────────────────",
    string.format("Total notes: %d", count),
    "",
    "Directories:",
  }
  
  for dir, _ in pairs(dirs) do
    table.insert(lines, "  • " .. dir)
  end
  
  M.notify(table.concat(lines, "\n"))
end

----------------------------------------------------------------------
-- Index
----------------------------------------------------------------------
function M.write_index()
  local root = cfg.notes_dir
  local index_file = join(root, "INDEX.md")
  
  local notes = {}
  local function scan(path, prefix)
    prefix = prefix or ""
    local handle = vim.loop.fs_scandir(path)
    if not handle then return end
    
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      local full = path .. "/" .. name
      if type == "file" and name:match("%.md$") and name ~= "INDEX.md" then
        local rel = prefix .. name
        local title = name:gsub("%.md$", ""):gsub("^%d+%-", "")
        table.insert(notes, { path = rel, title = title })
      elseif type == "directory" and not name:match("^%.") and name ~= "Templates" and name ~= "Archive" then
        scan(full, prefix .. name .. "/")
      end
    end
  end
  
  scan(root, "")
  table.sort(notes, function(a, b) return a.path < b.path end)
  
  local lines = {
    "# Zettelkasten Index",
    "",
    string.format("*Generated: %s*", os.date(cfg.datetime_format)),
    string.format("*Total: %d notes*", #notes),
    "",
  }
  
  local current_dir = ""
  for _, note in ipairs(notes) do
    local dir = vim.fn.fnamemodify(note.path, ":h")
    if dir ~= current_dir then
      current_dir = dir
      if dir ~= "." then
        table.insert(lines, "")
        table.insert(lines, "## " .. dir)
        table.insert(lines, "")
      end
    end
    table.insert(lines, string.format("- [[%s|%s]]", note.path:gsub("%.md$", ""), note.title))
  end
  
  vim.fn.writefile(lines, index_file)
  M.notify("Index written: " .. #notes .. " notes")
end

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------
function M.setup(opts)
  if opts and type(opts) == "table" then
    for k, v in pairs(opts) do
      if cfg[k] ~= nil then
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

  -- Create commands
  vim.api.nvim_create_user_command("ZettelNew", function(c)
    M.new_note({ title = (c.args ~= "" and c.args or nil) })
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command("ZettelDaily", M.daily_note, {})
  
  vim.api.nvim_create_user_command("ZettelQuick", function(c)
    M.quick_note(c.args ~= "" and c.args or nil)
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command("ZettelFind", M.find_notes, {})
  vim.api.nvim_create_user_command("ZettelSearch", M.search_notes, {})
  vim.api.nvim_create_user_command("ZettelRecent", M.recent_notes, {})
  vim.api.nvim_create_user_command("ZettelTags", M.browse_tags, {})
  vim.api.nvim_create_user_command("ZettelBacklinks", M.show_backlinks, {})
  vim.api.nvim_create_user_command("ZettelStats", M.show_stats, {})
  vim.api.nvim_create_user_command("ZettelIndex", M.write_index, {})
end

return M
