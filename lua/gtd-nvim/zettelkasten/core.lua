-- ============================================================================
-- ZETTELKASTEN CORE MODULE
-- ============================================================================
-- Shared utilities, configuration, cache, and path operations
-- All other ZK modules should require this
--
-- @module gtd-nvim.zettelkasten.core
-- @version 1.0.0
-- @requires gtd-nvim.gtd.shared
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-11"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

-- Load shared utilities from GTD (glyphs, colors, sorting)
local shared = require("gtd-nvim.gtd.shared")
M.shared = shared
M.g = shared.glyphs
M.colorize = shared.colorize

-- ============================================================================
-- ZETTELKASTEN GLYPHS (extending shared.glyphs)
-- ============================================================================

M.glyphs = {
  -- Note types
  note = {
    zettel     = "󰎞",  -- nf-md-notebook_outline
    daily      = "",  -- nf-fa-calendar_check_o
    quick      = "󱓧",  -- nf-md-lightning_bolt
    project    = "",  -- nf-cod-project
    reading    = "",  -- nf-fa-book
    person     = "",  -- nf-fa-user
    meeting    = "󰤙",  -- nf-md-account_group
    reference  = "",  -- nf-fa-bookmark
    archive    = "󰀼",  -- nf-md-archive
  },

  -- Zettelkasten workflow
  workflow = {
    link       = "",  -- nf-fa-link
    backlink   = "󰌹",  -- nf-md-link_variant
    tag        = "",  -- nf-fa-tag
    search     = "",  -- nf-fa-search
    index      = "󰉋",  -- nf-md-folder_open
    template   = "󰈙",  -- nf-md-file_document_outline
  },

  -- UI elements
  ui = {
    brain      = "󰧑",  -- nf-md-brain
    clock      = "",  -- nf-fa-clock_o
    calendar   = "",  -- nf-fa-calendar
    filter     = "󰈸",  -- nf-md-filter
    stats      = "󰄪",  -- nf-md-chart_bar
    sync       = "󰑐",  -- nf-md-sync
  },
}

-- ============================================================================
-- COLORS (Zettelkasten-specific)
-- ============================================================================

M.colors = {
  zettel     = { fg = "#89dceb" },        -- Cyan
  daily      = { fg = "#f9e2af" },        -- Yellow
  quick      = { fg = "#fab387" },        -- Peach
  project    = { fg = "#cba6f7" },        -- Purple
  reading    = { fg = "#94e2d5" },        -- Teal
  person     = { fg = "#f5c2e7" },        -- Pink
  backlink   = { fg = "#74c7ec" },        -- Light blue
  tag        = { fg = "#a6e3a1" },        -- Green
  muted      = { fg = "#6c7086" },        -- Dim gray
}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.cfg = {
  notes_dir       = vim.fn.expand("~/Documents/Notes"),
  daily_dir       = vim.fn.expand("~/Documents/Notes/Daily"),
  quick_dir       = vim.fn.expand("~/Documents/Notes/Quick"),
  templates_dir   = vim.fn.expand("~/Documents/Notes/Templates"),
  archive_dir     = vim.fn.expand("~/Documents/Notes/Archive"),
  gtd_dir         = vim.fn.expand("~/Documents/GTD"),
  file_ext        = ".md",

  id_format       = "%Y%m%d%H%M",
  date_format     = "%Y-%m-%d",
  datetime_format = "%Y-%m-%d %H:%M:%S",

  slug_lowercase  = false,

  cache = {
    enabled = true,
    ttl = 300,  -- 5 minutes
  },
  backlinks = {
    enabled = true,
    show_in_buffer = true,
  },
  gtd_integration = {
    enabled = true,
    sync_tags = true,
    create_note_refs = true,
  },
  notifications = {
    enabled = true,
    timeout = 2000,
  },
}

-- ============================================================================
-- JUNK PATTERNS - CRITICAL FOR CLEAN VIEWS
-- ============================================================================

-- Patterns to exclude from ALL views (Lua pattern matching)
M.junk_patterns = {
  "^%.DS_Store$",
  "^%.continuity",
  "^%._",
  "^%.Trashes$",
  "^%.Spotlight%-V100$",
  "^%.fseventsd$",
  "^%.TemporaryItems$",
  "^%.AppleDouble$",
  "^%.localized$",
  "^%.git$",
  "^%.obsidian$",
  "^node_modules$",
  "^%.Trash",
  -- Backup files
  "%.bak$",
  "%.backup%-",
  "~$",
  "%.orig$",
  "^#.*#$",
  -- Archive directories
  "^Archive$",
  "^ArchiveDeleted$",
  "^Templates$",
}

-- fd/rg exclude patterns (glob style for command line)
-- NOTE: Keep these simple - avoid complex wildcards like *.backup-*
M.fd_excludes = {
  ".DS_Store",
  ".git",
  ".obsidian",
  "node_modules",
  ".Trash",
  "Archive",
  "ArchiveDeleted",
  "Templates",
}

-- Build fd exclude string for fzf-lua
function M.get_fd_excludes()
  local parts = { "--type", "f", "--extension", "md" }
  for _, pattern in ipairs(M.fd_excludes) do
    table.insert(parts, "--exclude")
    table.insert(parts, pattern)
  end
  return table.concat(parts, " ")
end

-- Alias for backward compatibility with old manage.lua
function M.get_exclude_opts_string()
  local parts = {}
  for _, pattern in ipairs(M.fd_excludes) do
    table.insert(parts, "--exclude " .. pattern)
  end
  return " " .. table.concat(parts, " ")
end

-- Build rg exclude args
function M.get_rg_excludes()
  local parts = {}
  for _, pattern in ipairs(M.fd_excludes) do
    table.insert(parts, "--glob")
    table.insert(parts, "!" .. pattern)
  end
  return parts
end

-- Check if filename matches junk pattern
function M.is_junk(name)
  if not name then return true end
  for _, pattern in ipairs(M.junk_patterns) do
    if name:match(pattern) then return true end
  end
  return false
end

-- ============================================================================
-- PUBLIC HELPERS
-- ============================================================================

-- Get paths configuration (for external modules)
function M.get_paths()
  return {
    notes_dir     = M.cfg.notes_dir,
    daily_dir     = M.cfg.daily_dir,
    quick_dir     = M.cfg.quick_dir,
    templates_dir = M.cfg.templates_dir,
    archive_dir   = M.cfg.archive_dir,
    gtd_dir       = M.cfg.gtd_dir,
    file_ext      = M.cfg.file_ext,
  }
end

-- ============================================================================
-- CACHE
-- ============================================================================

M._cache = {
  notes_files = { data = nil, timestamp = 0 },
  gtd_tasks   = { data = nil, timestamp = 0 },
  backlinks   = { data = nil, timestamp = 0 },
  tags        = { data = nil, timestamp = 0 },
}

function M.is_cache_valid(cache_key)
  if not M.cfg.cache.enabled then return false end
  local entry = M._cache[cache_key]
  return entry and entry.data and (os.time() - entry.timestamp) < M.cfg.cache.ttl
end

function M.update_cache(cache_key, data)
  if M.cfg.cache.enabled then
    M._cache[cache_key] = { data = data, timestamp = os.time() }
  end
end

function M.clear_cache(cache_key)
  if cache_key then
    M._cache[cache_key].timestamp = 0
  else
    for key in pairs(M._cache) do
      M._cache[key].timestamp = 0
    end
  end
end

-- ============================================================================
-- PATH UTILITIES
-- ============================================================================

function M.abspath(p)
  return vim.fn.fnamemodify(vim.fn.expand(p or ""), ":p")
end

function M.ensure_dir(path)
  local p = M.abspath(path)
  vim.fn.mkdir(p, "p")
  return p
end

function M.file_exists(path)
  return vim.fn.filereadable(M.abspath(path)) == 1
end

function M.is_dir(path)
  return vim.fn.isdirectory(M.abspath(path)) == 1
end

function M.join(...)
  return M.abspath(vim.fs.joinpath(...))
end

function M.to_abs(p)
  if not p or p == "" then return nil end
  p = vim.fn.expand(p)
  if p:sub(1,1) == "/" or p:match("^%a:[/\\]") then
    return M.abspath(p)
  end
  return M.join(M.cfg.notes_dir, p)
end

-- Strip ANSI codes and decoration from fzf selection
function M.strip_decor(s)
  if type(s) ~= "string" then return s end
  -- Remove ANSI escape codes
  s = s:gsub("\27%[[0-9;]*m", "")
  -- Remove control characters
  s = s:gsub("^[%z\1-\31]+", "")
  return s
end

-- Extract path from formatted display string (after glyph)
function M.extract_path(s)
  if not s then return nil end
  s = M.strip_decor(s)
  -- Skip leading glyph (non-ASCII) and whitespace
  local path = s:match("^[^%w/~%.]*%s*(.+)$")
  return path and vim.trim(path) or s
end

-- ============================================================================
-- SLUG/ID GENERATION
-- ============================================================================

function M.slugify(title)
  local s = title or ""
  s = s:gsub("[/\\:%*%?%\"%<%>%|]", "-")
  s = s:gsub("%s+", "-")
  s = s:gsub("^%-+", "")
  s = s:gsub("%-+$", "")
  if M.cfg.slug_lowercase then s = vim.fn.tolower(s) end
  if s == "" then s = "note" end
  return s
end

function M.gen_id()
  return os.date(M.cfg.id_format)
end

function M.gen_filename(title, id)
  return string.format("%s-%s%s", id or M.gen_id(), M.slugify(title), M.cfg.file_ext)
end

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

function M.notify(msg, level, opts)
  if not M.cfg.notifications.enabled then return end
  opts = opts or {}
  opts.title = opts.title or (M.glyphs.ui.brain .. " Zettel")
  opts.timeout = opts.timeout or M.cfg.notifications.timeout
  vim.notify(msg, level or vim.log.levels.INFO, opts)
end

-- ============================================================================
-- NOTE TYPE DETECTION
-- ============================================================================

function M.detect_note_type(path)
  local lower = (path or ""):lower()
  if lower:match("/daily/") or lower:match("^daily/") then return "daily" end
  if lower:match("/quick/") or lower:match("^quick/") then return "quick" end
  if lower:match("/projects?/") or lower:match("^projects?/") then return "project" end
  if lower:match("/reading/") or lower:match("^reading/") then return "reading" end
  if lower:match("/people/") or lower:match("^people/") then return "person" end
  if lower:match("/meetings?/") or lower:match("^meetings?/") then return "meeting" end
  if lower:match("/archive/") or lower:match("^archive/") then return "archive" end
  return "zettel"
end

-- ============================================================================
-- FORMATTING HELPERS
-- ============================================================================

-- Colorize text for fzf-lua
function M.zk_colorize(text, color_name)
  local color = M.colors[color_name]
  if not color then return text end
  local r = tonumber(color.fg:sub(2, 3), 16)
  local g = tonumber(color.fg:sub(4, 5), 16)
  local b = tonumber(color.fg:sub(6, 7), 16)
  return string.format("\27[38;2;%d;%d;%dm%s\27[0m", r, g, b, text)
end

-- Get colored note type glyph
function M.colored_note_glyph(note_type)
  local glyph = M.glyphs.note[note_type] or M.glyphs.note.zettel
  return M.zk_colorize(glyph, note_type or "zettel")
end

-- Format note for fzf display
function M.format_note(note, opts)
  opts = opts or {}
  local colored = opts.colored ~= false
  local note_type = note.note_type or M.detect_note_type(note.rel_path or note.path or "")

  local type_glyph = colored and M.colored_note_glyph(note_type) or M.glyphs.note[note_type]
  local title = note.title or vim.fn.fnamemodify(note.path or "", ":t:r")
  local dir_display = ""

  if opts.show_dir and note.dir and note.dir ~= "" then
    dir_display = colored
      and " " .. M.zk_colorize(note.dir, "muted")
      or " " .. note.dir
  end

  return string.format("%s %s%s", type_glyph, title, dir_display)
end

-- Create fzf header with ZK actions
function M.fzf_header(opts)
  opts = opts or {}
  local parts = {}
  local g = M.g

  table.insert(parts, M.zk_colorize("Enter", "muted") .. " " .. M.zk_colorize(g.ui.arrow_right, "tag") .. " Open")

  if opts.edit then
    table.insert(parts, M.zk_colorize("C-e", "muted") .. " " .. M.zk_colorize(g.ui.edit, "zettel") .. " Edit")
  end
  if opts.preview then
    table.insert(parts, M.zk_colorize("C-p", "muted") .. " " .. M.zk_colorize(M.glyphs.workflow.search, "zettel") .. " Preview")
  end
  if opts.backlinks then
    table.insert(parts, M.zk_colorize("C-b", "muted") .. " " .. M.zk_colorize(M.glyphs.workflow.backlink, "backlink") .. " Links")
  end
  if opts.tags then
    table.insert(parts, M.zk_colorize("C-t", "muted") .. " " .. M.zk_colorize(M.glyphs.workflow.tag, "tag") .. " Tags")
  end
  if opts.delete then
    table.insert(parts, M.zk_colorize("C-d", "muted") .. " " .. M.zk_colorize(g.container.trash, "muted") .. " Delete")
  end
  if opts.archive then
    table.insert(parts, M.zk_colorize("C-a", "muted") .. " " .. M.zk_colorize(M.glyphs.note.archive, "muted") .. " Archive")
  end
  if opts.zettel then
    table.insert(parts, M.zk_colorize("C-z", "muted") .. " " .. M.zk_colorize(M.glyphs.note.zettel, "zettel") .. " Zettel")
  end

  return table.concat(parts, " " .. M.zk_colorize("│", "muted") .. " ")
end

-- ============================================================================
-- FZF-LUA HELPERS
-- ============================================================================

function M.have_fzf()
  local ok, fzf = pcall(require, "fzf-lua")
  return ok and fzf or nil
end

function M.have_telescope()
  return pcall(require, "telescope.builtin")
end

-- Standard fzf config with proper excludes
function M.fzf_files_config(opts)
  opts = opts or {}
  return {
    cwd = opts.cwd or M.cfg.notes_dir,
    prompt = opts.prompt or (M.glyphs.ui.brain .. " "),
    file_icons = false,
    git_icons = false,
    fd_opts = M.get_fd_excludes(),
    fzf_opts = vim.tbl_extend("force", {
      ["--ansi"] = true,
      ["--header"] = opts.header or M.fzf_header(opts.header_opts or {}),
    }, opts.fzf_opts or {}),
  }
end

-- ============================================================================
-- FILE DISCOVERY
-- ============================================================================

function M.get_all_notes()
  if M.is_cache_valid("notes_files") then
    return M._cache.notes_files.data
  end

  local notes = {}

  local function scan_dir(dir, prefix)
    prefix = prefix or ""
    local handle = vim.loop.fs_scandir(M.abspath(dir))
    if not handle then return end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end

      -- Skip junk files
      if M.is_junk(name) then goto continue end

      local full_path = M.join(dir, name)
      local rel_path = prefix .. name

      if type == "directory" then
        -- Skip special directories
        if not (name == "Templates" or name == "Archive") then
          scan_dir(full_path, rel_path .. "/")
        end
      elseif type == "file" and name:match("%.md$") then
        local note_type = M.detect_note_type(rel_path)
        table.insert(notes, {
          path = full_path,
          rel_path = rel_path,
          name = name,
          title = name:gsub("%.md$", ""),
          dir = prefix ~= "" and prefix:gsub("/$", "") or "",
          note_type = note_type,
        })
      end
      ::continue::
    end
  end

  scan_dir(M.cfg.notes_dir)
  table.sort(notes, function(a, b) return a.rel_path < b.rel_path end)
  M.update_cache("notes_files", notes)
  return notes
end

-- ============================================================================
-- TAG EXTRACTION
-- ============================================================================

function M.extract_tags(content)
  local tags = {}
  local seen = {}
  -- Markdown style tags
  for tag in content:gmatch("#([%w_%-]+)") do
    if not seen[tag] and not tag:match("^%d+$") then  -- Exclude pure numbers
      seen[tag] = true
      table.insert(tags, tag)
    end
  end
  -- Org style tags
  for tag in content:gmatch(":([%w_]+):") do
    if not seen[tag] then
      seen[tag] = true
      table.insert(tags, tag)
    end
  end
  return tags
end

function M.get_all_tags()
  if M.is_cache_valid("tags") then
    return M._cache.tags.data
  end

  local tag_map = {}
  local notes = M.get_all_notes()

  for _, note in ipairs(notes) do
    if M.file_exists(note.path) then
      local content = table.concat(vim.fn.readfile(note.path), "\n")
      local tags = M.extract_tags(content)
      for _, tag in ipairs(tags) do
        if not tag_map[tag] then tag_map[tag] = {} end
        table.insert(tag_map[tag], note)
      end
    end
  end

  M.update_cache("tags", tag_map)
  return tag_map
end

-- ============================================================================
-- BACKLINKS
-- ============================================================================

function M.get_backlinks(file_path)
  if not M.cfg.backlinks.enabled then return {} end
  if not file_path then file_path = vim.fn.expand("%:p") end

  local backlinks = {}
  local notes = M.get_all_notes()
  local target_name = vim.fn.fnamemodify(file_path, ":t:r")
  local target_rel = file_path:gsub("^" .. vim.pesc(M.cfg.notes_dir) .. "/", "")

  for _, note in ipairs(notes) do
    if note.path ~= file_path and M.file_exists(note.path) then
      local content = table.concat(vim.fn.readfile(note.path), "\n")

      local found = false
      if content:match("%[%[" .. vim.pesc(target_name) .. "%]%]") or
         content:match("%[.*%]%(.*" .. vim.pesc(target_name) .. ".*%)") or
         content:match("%[.*%]%(.*" .. vim.pesc(target_rel) .. ".*%)") then
        found = true
      end

      if found then
        table.insert(backlinks, {
          file = note.path,
          title = note.title,
          rel_path = note.rel_path,
          note_type = note.note_type,
        })
      end
    end
  end

  return backlinks
end

-- ============================================================================
-- SETUP HELPERS
-- ============================================================================

function M.setup_config(opts)
  if opts and type(opts) == "table" then
    M.cfg = vim.tbl_deep_extend("force", M.cfg, opts)
  end

  -- Ensure directories exist
  M.ensure_dir(M.cfg.notes_dir)
  M.ensure_dir(M.cfg.daily_dir)
  M.ensure_dir(M.cfg.quick_dir)
  M.ensure_dir(M.cfg.templates_dir)
  M.ensure_dir(M.cfg.archive_dir)

  -- Check GTD integration
  if M.cfg.gtd_integration.enabled then
    if not M.is_dir(M.cfg.gtd_dir) then
      M.notify("GTD directory not found: " .. M.cfg.gtd_dir, vim.log.levels.WARN)
      M.cfg.gtd_integration.enabled = false
    end
  end
end

-- ============================================================================
-- BACKWARD COMPATIBILITY FUNCTIONS
-- ============================================================================
-- These exist for legacy modules (manage.lua, people.lua, etc.)

-- Convert fzf selection to file paths
function M.sel_to_paths_fzf(selected)
  local out = {}
  for _, s in ipairs(selected or {}) do
    local cand = nil
    if type(s) == "string" then
      cand = s
    elseif type(s) == "table" then
      if s.path and type(s.path) == "string" then
        cand = s.path
      elseif s[1] and type(s[1]) == "string" then
        cand = s[1]
      elseif s.text and type(s.text) == "string" then
        cand = s.text
      elseif s.filename and type(s.filename) == "string" then
        cand = s.filename
      end
    end
    if cand and cand ~= "" then
      cand = M.strip_decor(cand)
      -- Extract path after any glyph
      local path_part = cand:match("%s+(.+)$") or cand
      local abs = M.to_abs(path_part)
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

-- Delegate to notes module (lazy loaded to avoid circular deps)
function M.write_index()
  local ok, notes = pcall(require, "gtd-nvim.zettelkasten.notes")
  if ok and notes.write_index then
    return notes.write_index()
  end
end

-- Delegate to search module (lazy loaded)
function M.show_backlinks(file_path)
  local ok, search = pcall(require, "gtd-nvim.zettelkasten.search")
  if ok and search.show_backlinks then
    return search.show_backlinks(file_path)
  end
end

-- ============================================================================
-- LEGACY PROXY FUNCTIONS (for backward compatibility with old modules)
-- ============================================================================

-- Delegate to notes module
function M.create_note_file(opts)
  local ok, notes = pcall(require, "gtd-nvim.zettelkasten.notes")
  if ok and notes.create_note_file then
    return notes.create_note_file(opts)
  end
  M.notify("notes module not available", vim.log.levels.ERROR)
end

function M.new_note(opts)
  local ok, notes = pcall(require, "gtd-nvim.zettelkasten.notes")
  if ok and notes.new_note then
    return notes.new_note(opts)
  end
  M.notify("notes module not available", vim.log.levels.ERROR)
end

-- Delegate to gtd module
function M.get_gtd_tasks()
  local ok, gtd = pcall(require, "gtd-nvim.zettelkasten.gtd")
  if ok and gtd.get_tasks then
    return gtd.get_tasks()
  end
  return {}
end

-- Simple config getter
function M.get_config()
  return M.cfg
end

return M
