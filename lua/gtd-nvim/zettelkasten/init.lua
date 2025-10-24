-- ~/.config/nvim/lua/utils/zettelkasten.lua
-- Minimal, solid Zettelkasten utilities (fzf-lua first, telescope fallback)

local M = {}

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local cfg = {
  notes_dir       = vim.fn.expand("~/Documents/Notes"),
  daily_dir       = vim.fn.expand("~/Documents/Notes/Daily"),
  quick_dir       = vim.fn.expand("~/Documents/Notes/Quick"),
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
    if ln:match("^##%s+Indhold%s*$") then return math.min(i + 1, #lines + 1) end
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
-- Public helpers for other modules (capture, projects)
----------------------------------------------------------------------
-- Read-only paths a caller may need.
function M.get_paths()
  return {
    notes_dir     = cfg.notes_dir,
    templates_dir = cfg.templates_dir,
    file_ext      = cfg.file_ext,
  }
end

-- Create a note on disk using your templates and return (filepath, id).
-- opts = {
--   title     = string (required),
--   dir       = string (optional; defaults to cfg.notes_dir),
--   template  = "note" | "daily" | "quick" | ... (optional; defaults "note"),
--   id        = string (optional; default gen_id()),
--   open      = boolean (optional; if true, open buffer & place cursor)
-- }
function M.create_note_file(opts)
  opts = opts or {}
  local title = opts.title
  if not title or title == "" then
    vim.notify("Note title required", vim.log.levels.WARN, { title = "Zettel" })
    return nil, nil
  end

  local dir = ensure_dir(opts.dir or cfg.notes_dir)
  local id  = opts.id or gen_id()
  local file = join(dir, gen_filename(title, id))

  local lines = apply_template(opts.template or "note", {
    title   = title,
    created = os.date(cfg.datetime_format),
    id      = id,
  })

  if not file_exists(file) then
    ensure_dir(vim.fn.fnamemodify(file, ":h"))
    vim.fn.writefile(lines, file)
  end

  if opts.open then
    open_and_seed(file, lines)
    local row = find_content_row(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
    vim.cmd("startinsert!")
    vim.notify("Created: " .. vim.fn.fnamemodify(file, ":t"), vim.log.levels.INFO, { title = "Zettel" })
  end

  return file, id
end

----------------------------------------------------------------------
-- Create / Open
----------------------------------------------------------------------
function M.new_note(opts)
  opts = opts or {}
  local function create(title)
    if not title or title == "" then
      vim.notify("Note title required", vim.log.levels.WARN, { title = "Zettel" })
      return
    end
    local dir = ensure_dir(opts.dir or cfg.notes_dir)
    local id  = gen_id()
    local file = join(dir, gen_filename(title, id))
    local lines = apply_template(opts.template or "note", {
      title = title,
      created = os.date(cfg.datetime_format),
      id = id,
    })
    open_and_seed(file, lines)
    local row = find_content_row(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
    vim.cmd("startinsert!")
    vim.notify("Created: " .. vim.fn.fnamemodify(file, ":t"), vim.log.levels.INFO, { title = "Zettel" })
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
  vim.notify("Daily note: " .. date, vim.log.levels.INFO, { title = "Zettel" })
end

----------------------------------------------------------------------
-- Find / Search
----------------------------------------------------------------------
function M.find_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").files({ cwd = root, prompt = "🧠 " })
  elseif have_telescope() then
    require("telescope.builtin").find_files({
      prompt_title = "Zettelkasten Notes",
      cwd = root,
      file_ignore_patterns = { "%.git/", "node_modules/", ".DS_Store", "/Templates/" },
    })
  else
    vim.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN, { title = "Zettel" })
  end
end

function M.search_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").live_grep({ cwd = root, prompt = "🔍 " })
  elseif have_telescope() then
    require("telescope.builtin").live_grep({
      prompt_title = "Search Zettelkasten",
      cwd = root,
      additional_args = function() return { "--hidden", "--glob", "!.git" } end,
    })
  else
    vim.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN, { title = "Zettel" })
  end
end

function M.recent_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").oldfiles({ cwd = root, cwd_only = true, prompt = "⏰ " })
  elseif have_telescope() then
    require("telescope.builtin").oldfiles({
      prompt_title = "Recent Zettelkasten Notes",
      cwd = root,
      cwd_only = true,
    })
  else
    vim.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN, { title = "Zettel" })
  end
end

----------------------------------------------------------------------
-- Manage (multi-select with fzf-lua actions)
----------------------------------------------------------------------
local function sel_to_paths(sel)
  local out = {}
  for _, v in ipairs(sel or {}) do
    if type(v) == "table" and v.path then
      table.insert(out, v.path)
    elseif type(v) == "table" and v[1] then
      table.insert(out, v[1])
    elseif type(v) == "string" then
      table.insert(out, v)
    end
  end
  return out
end

local function confirm_yes(msg)
  return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

local function do_delete(paths)
  if #paths == 0 then return end
  if not confirm_yes("Permanently delete " .. #paths .. " file(s)?") then return end
  for _, p in ipairs(paths) do
    pcall(vim.fn.delete, p)
  end
  vim.notify("Deleted " .. #paths .. " file(s).", vim.log.levels.INFO, { title = "Zettel" })
end

local function do_archive(paths)
  if #paths == 0 then return end
  ensure_dir(cfg.archive_dir)
  for _, p in ipairs(paths) do
    local dst = join(cfg.archive_dir, vim.fn.fnamemodify(p, ":t"))
    pcall(vim.fn.rename, p, dst)
  end
  vim.notify("Archived " .. #paths .. " file(s).", vim.log.levels.INFO, { title = "Zettel" })
end

local function do_move(paths)
  if #paths == 0 then return end
  local default = cfg.notes_dir
  local dest = vim.fn.input("Move to dir: ", default, "dir")
  if dest == nil or dest == "" then return end
  ensure_dir(dest)
  for _, p in ipairs(paths) do
    local dst = join(dest, vim.fn.fnamemodify(p, ":t"))
    pcall(vim.fn.rename, p, dst)
  end
  vim.notify("Moved " .. #paths .. " file(s).", vim.log.levels.INFO, { title = "Zettel" })
end

function M.manage_notes()
  if not have_fzf() then
    vim.notify("fzf-lua is required for Manage.", vim.log.levels.ERROR, { title = "Zettel" })
    return
  end
  local fzf = require("fzf-lua")
  fzf.files({
    cwd = cfg.notes_dir,
    prompt = "ZK ",
    actions = {
      -- open (default) keeps fzf behaviour
      ["default"] = fzf.actions.file_edit,
      -- multi-select with <Tab>, then:
      ["ctrl-d"] = function(selected) do_delete(sel_to_paths(selected)) end,
      ["ctrl-a"] = function(selected) do_archive(sel_to_paths(selected)) end,
      ["ctrl-m"] = function(selected) do_move(sel_to_paths(selected)) end,
    },
  })
end

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------
function M.setup(opts)
  if opts and type(opts) == "table" then
    for k, v in pairs(opts) do cfg[k] = v end
  end
  ensure_dir(cfg.notes_dir)
  ensure_dir(cfg.daily_dir)
  ensure_dir(cfg.quick_dir)
  ensure_dir(cfg.templates_dir)
  ensure_dir(cfg.archive_dir)

  vim.api.nvim_create_user_command("ZettelNew",    function(c) M.new_note({ title = (c.args ~= "" and c.args or nil) }) end, { nargs = "?" })
  vim.api.nvim_create_user_command("ZettelDaily",  M.daily_note, {})
  vim.api.nvim_create_user_command("ZettelQuick",  function(c) M.quick_note(c.args ~= "" and c.args or nil) end, { nargs = "?" })
  vim.api.nvim_create_user_command("ZettelFind",   M.find_notes, {})
  vim.api.nvim_create_user_command("ZettelSearch", M.search_notes, {})
  vim.api.nvim_create_user_command("ZettelRecent", M.recent_notes, {})
  vim.api.nvim_create_user_command("ZettelManage", M.manage_notes, {})
end

return M