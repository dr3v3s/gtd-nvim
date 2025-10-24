-- ~/.config/nvim/lua/utils/zettelkasten.lua
-- Enhanced Zettelkasten utilities with GTD integration, backlinks, tags, and advanced features

local M = {}

----------------------------------------------------------------------
-- Enhanced Config
----------------------------------------------------------------------
local cfg = {
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
  
  -- New features
  cache = {
    enabled = true,
    ttl = 300, -- 5 minutes
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

-- APFS junk files to ignore
local junk_patterns = {
  ".DS_Store", "._*", ".Trashes", ".Spotlight%-V100",
  ".fseventsd", ".TemporaryItems", ".AppleDouble",
}

-- Cache storage
local _cache = {
  notes_files = { data = nil, timestamp = 0 },
  gtd_tasks = { data = nil, timestamp = 0 },
  backlinks = { data = nil, timestamp = 0 },
  tags = { data = nil, timestamp = 0 },
}

----------------------------------------------------------------------
-- Enhanced utilities
----------------------------------------------------------------------
local function notify(msg, level, opts)
  if not cfg.notifications.enabled then return end
  opts = opts or {}
  opts.title = opts.title or "Zettel"
  opts.timeout = opts.timeout or cfg.notifications.timeout
  vim.notify(msg, level or vim.log.levels.INFO, opts)
end

local function is_cache_valid(cache_key)
  if not cfg.cache.enabled then return false end
  local entry = _cache[cache_key]
  return entry.data and (os.time() - entry.timestamp) < cfg.cache.ttl
end

local function update_cache(cache_key, data)
  if cfg.cache.enabled then
    _cache[cache_key] = { data = data, timestamp = os.time() }
  end
end

local function clear_cache(cache_key)
  if cache_key then
    _cache[cache_key].timestamp = 0
  else
    for key in pairs(_cache) do
      _cache[key].timestamp = 0
    end
  end
  notify("Cache cleared")
end

----------------------------------------------------------------------
-- Path utils (preserved from original)
----------------------------------------------------------------------
local function abspath(p) return vim.fn.fnamemodify(vim.fn.expand(p or ""), ":p") end
local function ensure_dir(path) local p = abspath(path); vim.fn.mkdir(p, "p"); return p end
local function file_exists(path) return vim.fn.filereadable(abspath(path)) == 1 end
local function join(...) return abspath(vim.fs.joinpath(...)) end
local function is_dir(path) return vim.fn.isdirectory(abspath(path)) == 1 end

local function to_abs(p)
  if not p or p == "" then return nil end
  p = vim.fn.expand(p)
  if p:sub(1,1) == "/" or p:match("^%a:[/\\]") then
    return abspath(p)
  end
  return join(cfg.notes_dir, p)
end

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
-- Slug/IDs (preserved)
----------------------------------------------------------------------
local function slugify_keep_unicode(title)
  local s = title or ""
  s = s:gsub("[/\\:%*%?%\"%<%>%|]", "-"):gsub("%s+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if cfg.slug_lowercase then s = vim.fn.tolower(s) end
  if s == "" then s = "note" end
  return s
end

local function gen_id() return os.date(cfg.id_format) end
local function gen_filename(title, id) return string.format("%s-%s%s", id or gen_id(), slugify_keep_unicode(title), cfg.file_ext) end

----------------------------------------------------------------------
-- Enhanced file discovery with caching
----------------------------------------------------------------------
local function get_all_notes()
  if is_cache_valid("notes_files") then
    return _cache.notes_files.data
  end

  local notes = {}
  local function scan_dir(dir, prefix)
    prefix = prefix or ""
    local handle = vim.loop.fs_scandir(abspath(dir))
    if not handle then return end
    
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      -- Skip junk files
      local skip = false
      for _, pattern in ipairs(junk_patterns) do
        if name:match(pattern) then skip = true; break end
      end
      if skip then goto continue end
      
      local full_path = join(dir, name)
      local rel_path = prefix .. name
      
      if type == "directory" then
        if not (name == ".git" or name == "Templates" or name == "Archive") then
          scan_dir(full_path, rel_path .. "/")
        end
      elseif type == "file" and name:match("%.md$") then
        table.insert(notes, {
          path = full_path,
          rel_path = rel_path,
          name = name,
          title = name:gsub("%.md$", ""),
          dir = prefix ~= "" and prefix:gsub("/$", "") or "",
        })
      end
      ::continue::
    end
  end
  
  scan_dir(cfg.notes_dir)
  table.sort(notes, function(a, b) return a.rel_path < b.rel_path end)
  update_cache("notes_files", notes)
  return notes
end

-- GTD task extraction
local function get_gtd_tasks()
  if not cfg.gtd_integration.enabled then return {} end
  if is_cache_valid("gtd_tasks") then
    return _cache.gtd_tasks.data
  end

  local tasks = {}
  if not is_dir(cfg.gtd_dir) then
    notify("GTD directory not found: " .. cfg.gtd_dir, vim.log.levels.WARN)
    return tasks
  end
  
  local cmd = string.format('rg -n "^\\*+\\s+(TODO|NEXT|WAITING|DONE|PROJ|SOMEDAY|MAYBE)" %s --type org 2>/dev/null | head -200', 
    vim.fn.shellescape(cfg.gtd_dir))
  
  local success, result = pcall(vim.fn.systemlist, cmd)
  if success and vim.v.shell_error == 0 then
    for _, line in ipairs(result) do
      local file, line_num, content = line:match("^([^:]+):(%d+):(.*)$")
      if file and content then
        local task_type = content:match("^%*+%s+(%w+)")
        local task_text = content:gsub("^%*+%s+%w+%s*", "")
        
        -- Clean up task text for better display
        task_text = task_text:gsub("%s*:.-:%s*$", "")  -- Remove org tags at end
        task_text = task_text:gsub("%s*SCHEDULED:.-$", "")  -- Remove scheduling info
        task_text = task_text:gsub("%s*DEADLINE:.-$", "")   -- Remove deadline info
        task_text = task_text:gsub("%s+", " ")  -- Normalize spaces
        task_text = vim.trim(task_text)
        
        -- Truncate very long tasks for daily note display
        local display_text = task_text
        if #task_text > 80 then
          display_text = task_text:sub(1, 77) .. "..."
        end
        
        -- Extract tags
        local tags = {}
        for tag in task_text:gmatch(":([%w_]+):") do
          table.insert(tags, tag)
        end
        
        table.insert(tasks, {
          file = file,
          line = tonumber(line_num),
          type = task_type,
          text = task_text,
          display_text = display_text,  -- Shorter version for daily notes
          tags = tags,
          content = content,
          rel_file = file:gsub("^" .. vim.pesc(cfg.gtd_dir) .. "/", ""),
        })
      end
    end
  end
  
  update_cache("gtd_tasks", tasks)
  return tasks
end

-- Backlink detection
local function get_backlinks(file_path)
  if not cfg.backlinks.enabled then return {} end
  if not file_path then file_path = vim.fn.expand("%:p") end
  
  local cache_key = "backlinks"
  local backlinks = {}
  
  -- Get all notes to search through
  local notes = get_all_notes()
  local target_name = vim.fn.fnamemodify(file_path, ":t:r")
  local target_rel = file_path:gsub("^" .. vim.pesc(cfg.notes_dir) .. "/", "")
  
  for _, note in ipairs(notes) do
    if note.path ~= file_path and file_exists(note.path) then
      local content = table.concat(vim.fn.readfile(note.path), "\n")
      
      -- Look for various link formats
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
        })
      end
    end
  end
  
  return backlinks
end

-- Tag extraction from content
local function extract_tags_from_content(content)
  local tags = {}
  -- Markdown style tags
  for tag in content:gmatch("#([%w_]+)") do
    table.insert(tags, tag)
  end
  -- Org style tags
  for tag in content:gmatch(":([%w_]+):") do
    table.insert(tags, tag)
  end
  return tags
end

local function get_all_tags()
  if is_cache_valid("tags") then
    return _cache.tags.data
  end

  local tag_map = {}
  local notes = get_all_notes()
  
  -- Extract tags from notes
  for _, note in ipairs(notes) do
    if file_exists(note.path) then
      local content = table.concat(vim.fn.readfile(note.path), "\n")
      local tags = extract_tags_from_content(content)
      for _, tag in ipairs(tags) do
        if not tag_map[tag] then tag_map[tag] = {} end
        table.insert(tag_map[tag], note)
      end
    end
  end
  
  -- Extract tags from GTD tasks if enabled
  if cfg.gtd_integration.enabled then
    local tasks = get_gtd_tasks()
    for _, task in ipairs(tasks) do
      for _, tag in ipairs(task.tags) do
        if not tag_map[tag] then tag_map[tag] = {} end
        table.insert(tag_map[tag], {
          path = task.file,
          title = task.text:sub(1, 50) .. "...",
          rel_path = task.rel_file,
          type = "gtd_task",
        })
      end
    end
  end
  
  update_cache("tags", tag_map)
  return tag_map
end

----------------------------------------------------------------------
-- Templates (enhanced with new variables)
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
    for i, ln in ipairs(lines) do
      local modified = false
      for k, v in pairs(vars) do
        local placeholder = "{{" .. k .. "}}"
        if ln:find(placeholder) then
          -- Handle multi-line substitutions
          if type(v) == "string" and v:find("\n") then
            -- Split the substitution value into lines
            local split_lines = vim.split(v, "\n", { plain = true })
            -- Replace the placeholder with the first line
            local replaced_line = ln:gsub(placeholder, split_lines[1] or "")
            table.insert(result, replaced_line)
            -- Add the remaining lines
            for j = 2, #split_lines do
              table.insert(result, split_lines[j])
            end
            modified = true
            break
          else
            ln = ln:gsub(placeholder, v)
          end
        end
      end
      if not modified then
        table.insert(result, ln)
      end
    end
    return result
  end
  
  if t then return fill(t) end
  
  -- Enhanced default templates
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
      "# Daglig Note - {{date}}",
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
      "# {{title}}",
      "",
      "**Created:** {{created}}",
      "**Tags:** #quick",
      "",
    })
  elseif kind == "project" then
    return fill({
      "# {{title}}",
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
  end
  return { "" }
end

----------------------------------------------------------------------
-- Enhanced file operations
----------------------------------------------------------------------
local function open_and_seed(filepath, lines, cursor_row)
  local fp = abspath(filepath)
  lines = lines or { "" }
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
  
  -- Auto-generate backlinks if enabled
  if cfg.backlinks.show_in_buffer then
    vim.defer_fn(function() M.update_backlinks_in_buffer() end, 100)
  end
end

local function find_content_row(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, ln in ipairs(lines) do
    if ln:match("^##%s+Indhold%s*$") then return math.min(i + 1, #lines + 1) end
  end
  return #lines + 1
end

----------------------------------------------------------------------
-- Public helpers (preserved + enhanced)
----------------------------------------------------------------------
function M.get_paths()
  return { 
    notes_dir = cfg.notes_dir, 
    templates_dir = cfg.templates_dir, 
    gtd_dir = cfg.gtd_dir,
    file_ext = cfg.file_ext 
  }
end

function M.create_note_file(opts)
  opts = opts or {}
  local title = opts.title
  if not title or title == "" then
    notify("Note title required", vim.log.levels.WARN)
    return nil, nil
  end

  local dir_abs = ensure_dir(opts.dir or cfg.notes_dir)
  local id = opts.id or gen_id()
  local file_abs = join(dir_abs, gen_filename(title, id))

  -- Enhanced template variables
  local template_vars = {
    title = title,
    created = os.date(cfg.datetime_format),
    id = id,
    date = os.date(cfg.date_format),
    tags = opts.tags or "",
    gtd_tasks = "", -- Will be populated for daily notes
  }
  
  -- Add GTD tasks for daily notes
  if opts.template == "daily" and cfg.gtd_integration.enabled then
    local tasks = get_gtd_tasks()
    local today_tasks = {}
    local task_count = 0
    
    -- Sort tasks by priority (state-based)
    local state_priority = { NEXT = 1, TODO = 2, WAITING = 3, PROJECT = 4, SOMEDAY = 5, DONE = 6 }
    table.sort(tasks, function(a, b)
      local a_priority = state_priority[a.type] or 999
      local b_priority = state_priority[b.type] or 999
      return a_priority < b_priority
    end)
    
    -- Add a blank line first
    table.insert(today_tasks, "")
    
    -- Prioritize TODO and NEXT tasks, but limit to prevent overwhelm
    for _, task in ipairs(tasks) do
      if (task.type == "TODO" or task.type == "NEXT") and task_count < 10 then
        local task_line = string.format("- [ ] **%s** %s", task.type, task.display_text)
        -- Add clickable link to source org file (simplified format)
        local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
        local org_link = string.format("[_%s_](%s)", file_name, task.file)
        task_line = task_line .. " " .. org_link
        table.insert(today_tasks, task_line)
        task_count = task_count + 1
      end
    end
    
    -- Add waiting tasks (limited)
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
    
    -- Join with proper newlines - this is the key fix
    template_vars.gtd_tasks = table.concat(today_tasks, "\n")
  end

  local lines = apply_template(opts.template or "note", template_vars)

  ensure_dir(vim.fn.fnamemodify(file_abs, ":h"))
  if not file_exists(file_abs) then
    local ok, err = pcall(vim.fn.writefile, lines, file_abs)
    if not ok then
      notify("Failed to write ZK note: " .. file_abs .. " → " .. tostring(err), vim.log.levels.ERROR)
      return nil, nil
    end
  end

  if opts.open then
    open_and_seed(file_abs, lines)
    local row = find_content_row(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
    vim.cmd("startinsert!")
    notify("Created: " .. vim.fn.fnamemodify(file_abs, ":t"))
  end

  -- Clear cache after creating new note
  clear_cache("notes_files")
  return file_abs, id
end

----------------------------------------------------------------------
-- Enhanced search and navigation
----------------------------------------------------------------------
local function have_fzf() return pcall(require, "fzf-lua") end
local function have_telescope() return pcall(require, "telescope.builtin") end

function M.find_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").files({ 
      cwd = root, 
      prompt = "🧠 ", 
      file_icons = false,
      fzf_opts = { ["--header"] = "Notes | Ctrl-P: Preview | Ctrl-B: Backlinks" },
      actions = {
        ["default"] = require("fzf-lua").actions.file_edit,
        ["ctrl-p"] = require("fzf-lua").actions.file_vsplit,
        ["ctrl-b"] = function(selected)
          if selected and selected[1] then
            local file = to_abs(strip_decor(selected[1]))
            if file then M.show_backlinks(file) end
          end
        end,
      },
    })
  elseif have_telescope() then
    require("telescope.builtin").find_files({
      prompt_title = "Zettelkasten Notes",
      cwd = root,
      file_ignore_patterns = { "%.git/", "node_modules/", ".DS_Store", "/Templates/" },
    })
  else
    notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

function M.search_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").live_grep({ 
      cwd = root, 
      prompt = "🔍 ", 
      file_icons = false,
      fzf_opts = { ["--header"] = "Search Notes & Content" },
    })
  elseif have_telescope() then
    require("telescope.builtin").live_grep({
      prompt_title = "Search Zettelkasten",
      cwd = root,
      additional_args = function() return { "--hidden", "--glob", "!.git" } end,
    })
  else
    notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

-- New: Search across both notes and GTD
function M.search_all()
  if not have_fzf() then
    notify("fzf-lua required for unified search", vim.log.levels.WARN)
    return
  end
  
  local fzf = require("fzf-lua")
  local roots = { cfg.notes_dir }
  if cfg.gtd_integration.enabled and is_dir(cfg.gtd_dir) then
    table.insert(roots, cfg.gtd_dir)
  end
  
  local cmd = string.format("rg --column --line-number --no-heading --color=always --smart-case")
  for _, root in ipairs(roots) do
    cmd = cmd .. " " .. vim.fn.shellescape(root)
  end
  
  fzf.grep({
    prompt = "🔍 All: ",
    cmd = cmd,
    fzf_opts = { ["--header"] = "Search Notes & GTD" },
  })
end

function M.recent_notes()
  local root = cfg.notes_dir
  if have_fzf() then
    require("fzf-lua").oldfiles({ cwd = root, cwd_only = true, prompt = "⏰ ", file_icons = false })
  elseif have_telescope() then
    require("telescope.builtin").oldfiles({
      prompt_title = "Recent Zettelkasten Notes",
      cwd = root,
      cwd_only = true,
    })
  else
    notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

----------------------------------------------------------------------
-- New: Enhanced features
----------------------------------------------------------------------

-- Show backlinks for current or specified file
function M.show_backlinks(file_path)
  file_path = file_path or vim.fn.expand("%:p")
  local backlinks = get_backlinks(file_path)
  
  if #backlinks == 0 then
    notify("No backlinks found")
    return
  end
  
  if not have_fzf() then
    notify("fzf-lua required for backlinks", vim.log.levels.WARN)
    return
  end
  
  local items = {}
  for _, bl in ipairs(backlinks) do
    table.insert(items, bl.rel_path .. " (" .. bl.title .. ")")
  end
  
  require("fzf-lua").fzf_exec(items, {
    prompt = "Backlinks: ",
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

-- Browse by tags
function M.browse_tags()
  local tag_map = get_all_tags()
  
  if not next(tag_map) then
    notify("No tags found")
    return
  end
  
  if not have_fzf() then
    notify("fzf-lua required for tag browsing", vim.log.levels.WARN)
    return
  end
  
  local tags = {}
  for tag, files in pairs(tag_map) do
    table.insert(tags, string.format("%s (%d)", tag, #files))
  end
  table.sort(tags)
  
  require("fzf-lua").fzf_exec(tags, {
    prompt = "Tags: ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local tag = selected[1]:match("^([^%s]+)")
          M.browse_files_by_tag(tag)
        end
      end,
    },
  })
end

function M.browse_files_by_tag(tag)
  local tag_map = get_all_tags()
  local files = tag_map[tag] or {}
  
  if #files == 0 then
    notify("No files found for tag: " .. tag)
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
    prompt = "Tag #" .. tag .. ": ",
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

-- GTD integration functions
function M.browse_gtd_tasks()
  if not cfg.gtd_integration.enabled then
    notify("GTD integration disabled")
    return
  end
  
  local tasks = get_gtd_tasks()
  if #tasks == 0 then
    notify("No GTD tasks found")
    return
  end
  
  -- Sort tasks by priority (state-based)
  local state_priority = { NEXT = 1, TODO = 2, WAITING = 3, PROJECT = 4, SOMEDAY = 5, DONE = 6 }
  table.sort(tasks, function(a, b)
    local a_priority = state_priority[a.type] or 999
    local b_priority = state_priority[b.type] or 999
    if a_priority == b_priority then
      -- If same priority, sort alphabetically by text
      return (a.display_text or a.text) < (b.display_text or b.text)
    end
    return a_priority < b_priority
  end)
  
  local items = {}
  for _, task in ipairs(tasks) do
    local display = string.format("[%s] %s (%s:%d)", 
      task.type, 
      task.display_text or task.text:sub(1,60), 
      task.rel_file, 
      task.line
    )
    table.insert(items, display)
  end
  
  require("fzf-lua").fzf_exec(items, {
    prompt = "GTD Tasks (sorted by priority): ",
    fzf_opts = { 
      ["--header"] = "Keys: [Enter] Create Note [Ctrl-E] Edit Org File [Ctrl-G] Go to Line" 
    },
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local task_text = selected[1]:match("%] (.+) %(")
          if task_text then
            M.create_note_for_gtd_task(task_text)
          end
        end
      end,
      ["ctrl-e"] = function(selected)
        if selected and selected[1] then
          local file, line = selected[1]:match("%((.+):(%d+)%)$")
          if file and line then
            local full_path = join(cfg.gtd_dir, file)
            vim.cmd("edit " .. vim.fn.fnameescape(full_path))
            vim.cmd(line) -- Go to the specific line
          end
        end
      end,
      ["ctrl-g"] = function(selected)
        if selected and selected[1] then
          local file, line = selected[1]:match("%((.+):(%d+)%)$")
          if file and line then
            local full_path = join(cfg.gtd_dir, file)
            vim.cmd("edit +" .. line .. " " .. vim.fn.fnameescape(full_path))
            vim.cmd("normal! zz") -- Center the line on screen
            notify("Jumped to line " .. line .. " in " .. file)
          end
        end
      end,
    },
  })
end

function M.create_note_for_gtd_task(task_text)
  local title = "GTD: " .. task_text:sub(1, 50)
  if task_text:len() > 50 then title = title .. "..." end
  
  vim.ui.input({ 
    prompt = "Note title: ", 
    default = title 
  }, function(input_title)
    if input_title and input_title ~= "" then
      M.new_note({
        title = input_title,
        tags = "#gtd",
        template = "note",
      })
    end
  end)
end

-- Update backlinks in current buffer
function M.update_backlinks_in_buffer()
  if not cfg.backlinks.show_in_buffer then return end
  
  local current_file = vim.fn.expand("%:p")
  if not current_file:match("%.md$") then return end
  
  local backlinks = get_backlinks(current_file)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  -- Find backlinks section
  local backlinks_start = nil
  for i, line in ipairs(lines) do
    if line:match("^## Backlinks") then
      backlinks_start = i
      break
    end
  end
  
  if not backlinks_start then return end
  
  -- Find end of backlinks section
  local backlinks_end = #lines
  for i = backlinks_start + 1, #lines do
    if lines[i]:match("^##%s") then
      backlinks_end = i - 1
      break
    end
  end
  
  -- Generate backlinks content
  local backlinks_content = {}
  if #backlinks > 0 then
    for _, bl in ipairs(backlinks) do
      table.insert(backlinks_content, string.format("- [[%s]]", bl.rel_path))
    end
  else
    table.insert(backlinks_content, "<!-- No backlinks found -->")
  end
  
  -- Update buffer
  vim.api.nvim_buf_set_lines(bufnr, backlinks_start, backlinks_end, false, backlinks_content)
end

----------------------------------------------------------------------
-- Index maintenance (enhanced)
----------------------------------------------------------------------
local function is_note_file(path)
  local p = abspath(path)
  if p:match("/Templates/") or p:match("/Archive/") then return false end
  return p:sub(-#cfg.file_ext) == cfg.file_ext
end

local function list_notes_recursive(root)
  local notes = get_all_notes()
  local paths = {}
  for _, note in ipairs(notes) do
    table.insert(paths, note.path)
  end
  return paths
end

local function write_index()
  local idx = join(cfg.notes_dir, "index.md")
  local notes = list_notes_recursive(cfg.notes_dir)
  local tag_map = get_all_tags()
  
  local lines = {
    "# Notes Index",
    "",
    ("_Updated:_ %s"):format(os.date(cfg.datetime_format)),
    ("_Total Notes:_ %d"):format(#notes),
    ("_Total Tags:_ %d"):format(vim.tbl_count(tag_map)),
    "",
  }
  
  -- Add tag cloud
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
  
  -- Add notes list
  table.insert(lines, "## Notes")
  table.insert(lines, "")
  for _, p in ipairs(notes) do
    local rel = vim.fn.fnamemodify(p, ":.")
    local base = vim.fn.fnamemodify(p, ":t")
    table.insert(lines, ("- [%s](%s)"):format(base, rel))
  end
  
  vim.fn.writefile(lines, idx)
  return idx
end

----------------------------------------------------------------------
-- Selection handling (preserved)
----------------------------------------------------------------------
local function sel_to_paths_fzf(selected)
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
      cand = strip_decor(cand)
      local abs = to_abs(cand)
      if abs then table.insert(out, abs) end
    end
  end
  local uniq, seen = {}, {}
  for _, p in ipairs(out) do
    if p and not seen[p] then seen[p] = true; table.insert(uniq, p) end
  end
  return uniq
end

----------------------------------------------------------------------
-- File operations (preserved + enhanced)
----------------------------------------------------------------------
local function try_delete_file(p)
  local rc = vim.fn.delete(p)
  if rc == 0 then return true end
  local ok_uv, err_uv = pcall(function() return vim.loop.fs_unlink(p) end)
  if ok_uv and err_uv == nil then return true end
  local ok_os, msg = os.remove(p)
  if ok_os then return true end
  return false, ("delete() rc=%s; uv=%s; os.remove=%s"):format(tostring(rc), tostring(err_uv), tostring(msg))
end

local function try_move_file(src, dst)
  pcall(vim.fn.delete, dst)
  local ok = pcall(vim.fn.rename, src, dst)
  if ok and file_exists(dst) and not file_exists(src) then return true end
  local content = vim.fn.readfile(src)
  local okw = pcall(vim.fn.writefile, content, dst)
  if okw and file_exists(dst) then
    local okd = try_delete_file(src)
    return okd == true
  end
  return false
end

local function confirm_yes(msg) return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1 end

local function do_delete(paths)
  if #paths == 0 then
    notify("Nothing to delete (no paths resolved)", vim.log.levels.WARN)
    return
  end
  if not confirm_yes(("Permanently delete %d file(s)?"):format(#paths)) then return end

  local okc, errc = 0, 0
  for _, p in ipairs(paths) do
    if file_exists(p) and not is_dir(p) then
      local ok, msg = try_delete_file(p)
      if ok then okc = okc + 1 else errc = errc + 1; notify("Delete failed: " .. p .. " — " .. (msg or ""), vim.log.levels.ERROR) end
    else
      errc = errc + 1
      notify("Not a file or missing: " .. p, vim.log.levels.ERROR)
    end
  end
  clear_cache() -- Clear all caches after deletion
  write_index()
  notify(("Deleted %d file(s), %d failed."):format(okc, errc))
end

local function do_archive(paths)
  if #paths == 0 then
    notify("Nothing to archive (no paths resolved)", vim.log.levels.WARN)
    return
  end
  ensure_dir(cfg.archive_dir)
  local moved, failed = 0, 0
  for _, p in ipairs(paths) do
    if file_exists(p) and not is_dir(p) then
      local dst = join(cfg.archive_dir, vim.fn.fnamemodify(p, ":t"))
      if try_move_file(p, dst) then moved = moved + 1 else failed = failed + 1 end
    else
      failed = failed + 1
      notify("Not a file or missing: " .. p, vim.log.levels.ERROR)
    end
  end
  clear_cache()
  write_index()
  notify(("Archived %d file(s), %d failed."):format(moved, failed))
end

local function do_move(paths)
  if #paths == 0 then
    notify("Nothing to move (no paths resolved)", vim.log.levels.WARN)
    return
  end
  local dest = vim.fn.input("Move to dir: ", cfg.notes_dir, "dir")
  if dest == nil or dest == "" then return end
  ensure_dir(dest)
  local moved, failed = 0, 0
  for _, p in ipairs(paths) do
    if file_exists(p) and not is_dir(p) then
      local dst = join(dest, vim.fn.fnamemodify(p, ":t"))
      if try_move_file(p, dst) then moved = moved + 1 else failed = failed + 1 end
    else
      failed = failed + 1
      notify("Not a file or missing: " .. p, vim.log.levels.ERROR)
    end
  end
  clear_cache()
  write_index()
  notify(("Moved %d file(s), %d failed."):format(moved, failed))
end

----------------------------------------------------------------------
-- Enhanced help
----------------------------------------------------------------------
local function show_help()
  local lines = {
    "ZettelManage — Enhanced Keys",
    "",
    "  <Enter>   Open file",
    "  Ctrl-D    Delete selected file(s)",
    "  Ctrl-A    Archive selected file(s) → Archive/",
    "  Ctrl-R    Move selected file(s) → choose dir",
    "  Ctrl-B    Show backlinks for selected file",
    "  Ctrl-T    Browse tags in selected file",
    "  ?         Show this help",
    "",
    "Enhanced Features:",
    "  • GTD integration with ~/Documents/GTD",
    "  • Automatic backlink detection",
    "  • Tag extraction and browsing",
    "  • Cross-system search",
  }
  local cols, rows = vim.o.columns, vim.o.lines
  local w, h = math.max(55, math.floor(cols * 0.5)), #lines + 4
  local row, col = math.floor((rows - h) / 2), math.floor((cols - w) / 2)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = w, height = h,
    style = "minimal", border = "rounded", title = " Enhanced Help ", title_pos = "center",
  })
  local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  vim.keymap.set({ "n", "x" }, "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ "n", "x" }, "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

----------------------------------------------------------------------
-- Enhanced manage picker
----------------------------------------------------------------------
function M.manage_notes()
  if not have_fzf() then
    notify("fzf-lua is required for Manage.", vim.log.levels.ERROR)
    return
  end
  local fzf = require("fzf-lua")

  local header = "Keys: [Enter] Open [Ctrl-D] Delete [Ctrl-A] Archive [Ctrl-R] Move [Ctrl-B] Backlinks [?] Help"

  local exclude_opts = {}
  for _, pat in ipairs(junk_patterns) do
    table.insert(exclude_opts, "--exclude"); table.insert(exclude_opts, pat)
  end

  fzf.files({
    cwd = cfg.notes_dir,
    prompt = "ZK ",
    file_icons = false,
    fzf_opts = { ["--header"] = header },
    fd_opts = table.concat({ "--type", "f", unpack(exclude_opts) }, " "),
    actions = {
      ["default"] = fzf.actions.file_edit,
      ["ctrl-d"]  = function(selected) do_delete(sel_to_paths_fzf(selected)) end,
      ["ctrl-a"]  = function(selected) do_archive(sel_to_paths_fzf(selected)) end,
      ["ctrl-r"]  = function(selected) do_move(sel_to_paths_fzf(selected)) end,
      ["ctrl-b"]  = function(selected) 
        local paths = sel_to_paths_fzf(selected)
        if paths[1] then M.show_backlinks(paths[1]) end
      end,
      ["ctrl-t"]  = function(selected)
        local paths = sel_to_paths_fzf(selected)
        if paths[1] and file_exists(paths[1]) then
          local content = table.concat(vim.fn.readfile(paths[1]), "\n")
          local tags = extract_tags_from_content(content)
          if #tags > 0 then
            notify("Tags: " .. table.concat(tags, ", "))
          else
            notify("No tags found in file")
          end
        end
      end,
      ["?"]       = function(_) show_help() end,
      ["alt-?"]   = function(_) show_help() end,
    },
  })
end

----------------------------------------------------------------------
-- Create / Open convenience (preserved + enhanced)
----------------------------------------------------------------------
function M.new_note(opts)
  opts = opts or {}
  local function create(title)
    if not title or title == "" then
      notify("Note title required", vim.log.levels.WARN)
      return
    end
    local dir = ensure_dir(opts.dir or cfg.notes_dir)
    local id = gen_id()
    local file = join(dir, gen_filename(title, id))
    
    local template_vars = {
      title = title,
      created = os.date(cfg.datetime_format),
      id = id,
      date = os.date(cfg.date_format),
      tags = opts.tags or "",
    }
    
    local lines = apply_template(opts.template or "note", template_vars)
    open_and_seed(file, lines)
    local row = find_content_row(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
    vim.cmd("startinsert!")
    notify("Created: " .. vim.fn.fnamemodify(file, ":t"))
    clear_cache("notes_files")
    write_index()
  end

  if opts.title then create(opts.title) else vim.ui.input({ prompt = "Note title: " }, create) end
end

function M.quick_note(title)
  M.new_note({ dir = cfg.quick_dir, template = "quick", title = title or os.date("%H:%M Quick Note") })
end

function M.daily_note()
  local dir = ensure_dir(cfg.daily_dir)
  local date = os.date(cfg.date_format)
  local file = join(dir, date .. cfg.file_ext)
  
  local template_vars = { 
    date = date,
    gtd_tasks = "",
  }
  
  -- Add GTD tasks if integration is enabled
  if cfg.gtd_integration.enabled then
    local tasks = get_gtd_tasks()
    local today_tasks = {}
    local task_count = 0
    
    -- Sort tasks by priority (state-based)
    local state_priority = { NEXT = 1, TODO = 2, WAITING = 3, PROJECT = 4, SOMEDAY = 5, DONE = 6 }
    table.sort(tasks, function(a, b)
      local a_priority = state_priority[a.type] or 999
      local b_priority = state_priority[b.type] or 999
      return a_priority < b_priority
    end)
    
    -- Add a blank line first
    table.insert(today_tasks, "")
    
    -- Prioritize TODO and NEXT tasks, but limit to prevent overwhelm
    for _, task in ipairs(tasks) do
      if (task.type == "TODO" or task.type == "NEXT") and task_count < 10 then
        local task_line = string.format("- [ ] **%s** %s", task.type, task.display_text)
        -- Add clickable link to source org file (simplified format)
        local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
        local org_link = string.format("[_%s_](%s)", file_name, task.file)
        task_line = task_line .. " " .. org_link
        table.insert(today_tasks, task_line)
        task_count = task_count + 1
      end
    end
    
    -- Add waiting tasks (limited)
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
    
    -- Join with proper newlines - this is the key fix
    template_vars.gtd_tasks = table.concat(today_tasks, "\n")
  end
  
  open_and_seed(file, apply_template("daily", template_vars), 4)
  notify("Daily note: " .. date)
  write_index()
end

-- New: Project note
function M.new_project(title)
  local function create(project_title)
    if not project_title or project_title == "" then
      notify("Project title required", vim.log.levels.WARN)
      return
    end
    
    local projects_dir = ensure_dir(join(cfg.notes_dir, "Projects"))
    M.new_note({
      title = project_title,
      dir = projects_dir,
      template = "project",
      tags = "#project",
    })
  end
  
  if title then create(title) else vim.ui.input({ prompt = "Project title: " }, create) end
end

----------------------------------------------------------------------
-- Statistics and info
----------------------------------------------------------------------
function M.show_stats()
  local notes = get_all_notes()
  local tags = get_all_tags()
  local tasks = cfg.gtd_integration.enabled and get_gtd_tasks() or {}
  
  local stats = {
    "# Zettelkasten Statistics",
    "",
    string.format("**Total Notes:** %d", #notes),
    string.format("**Total Tags:** %d", vim.tbl_count(tags)),
    string.format("**GTD Tasks:** %d", #tasks),
    "",
    "**Directory Breakdown:**",
  }
  
  -- Directory breakdown
  local dir_counts = {}
  for _, note in ipairs(notes) do
    local dir = note.dir ~= "" and note.dir or "Root"
    dir_counts[dir] = (dir_counts[dir] or 0) + 1
  end
  
  for dir, count in pairs(dir_counts) do
    table.insert(stats, string.format("- %s: %d", dir, count))
  end
  
  -- Show in floating window
  local cols, rows = vim.o.columns, vim.o.lines
  local w, h = math.max(50, math.floor(cols * 0.4)), #stats + 4
  local row, col = math.floor((rows - h) / 2), math.floor((cols - w) / 2)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, stats)
  vim.bo[buf].filetype = "markdown"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = w, height = h,
    style = "minimal", border = "rounded", title = " Statistics ", title_pos = "center",
  })
  local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

----------------------------------------------------------------------
-- Setup (enhanced)
----------------------------------------------------------------------
function M.setup(opts)
  if opts and type(opts) == "table" then 
    cfg = vim.tbl_deep_extend("force", cfg, opts)
  end
  
  ensure_dir(cfg.notes_dir); ensure_dir(cfg.daily_dir); ensure_dir(cfg.quick_dir)
  ensure_dir(cfg.templates_dir); ensure_dir(cfg.archive_dir)
  
  -- GTD integration setup
  if cfg.gtd_integration.enabled then
    if not is_dir(cfg.gtd_dir) then
      notify("GTD directory not found: " .. cfg.gtd_dir .. ", GTD integration disabled", vim.log.levels.WARN)
      cfg.gtd_integration.enabled = false
    end
  end
  
  write_index()

  -- Preserved commands
  vim.api.nvim_create_user_command("ZettelNew",    function(c) M.new_note({ title = (c.args ~= "" and c.args or nil) }) end, { nargs = "?" })
  vim.api.nvim_create_user_command("ZettelDaily",  M.daily_note, {})
  vim.api.nvim_create_user_command("ZettelQuick",  function(c) M.quick_note(c.args ~= "" and c.args or nil) end, { nargs = "?" })
  vim.api.nvim_create_user_command("ZettelFind",   M.find_notes, {})
  vim.api.nvim_create_user_command("ZettelSearch", M.search_notes, {})
  vim.api.nvim_create_user_command("ZettelRecent", M.recent_notes, {})
  vim.api.nvim_create_user_command("ZettelManage", M.manage_notes, {})
  
  -- New commands
  vim.api.nvim_create_user_command("ZettelProject", function(c) M.new_project(c.args ~= "" and c.args or nil) end, { nargs = "?" })
  vim.api.nvim_create_user_command("ZettelBacklinks", function() M.show_backlinks() end, {})
  vim.api.nvim_create_user_command("ZettelTags", M.browse_tags, {})
  vim.api.nvim_create_user_command("ZettelGTD", M.browse_gtd_tasks, {})
  vim.api.nvim_create_user_command("ZettelSearchAll", M.search_all, {})
  vim.api.nvim_create_user_command("ZettelStats", M.show_stats, {})
  vim.api.nvim_create_user_command("ZettelClearCache", function() clear_cache() end, {})
  vim.api.nvim_create_user_command("ZettelUpdateBacklinks", M.update_backlinks_in_buffer, {})
  
  -- Auto-update backlinks when saving markdown files
  if cfg.backlinks.show_in_buffer then
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = "*.md",
      callback = function()
        if vim.fn.expand("%:p"):match("^" .. vim.pesc(cfg.notes_dir)) then
          vim.defer_fn(M.update_backlinks_in_buffer, 100)
        end
      end,
    })
  end
end

-- Utility functions for external use
function M.clear_all_cache() clear_cache() end
function M.get_stats() 
  return {
    notes_count = #get_all_notes(),
    tags_count = vim.tbl_count(get_all_tags()),
    gtd_tasks_count = #get_gtd_tasks(),
    cache_enabled = cfg.cache.enabled,
  }
end

-- Debug function to inspect GTD tasks
function M.debug_gtd_tasks()
  local tasks = get_gtd_tasks()
  print("=== GTD Tasks Debug ===")
  print("Total tasks found:", #tasks)
  
  -- Count by type
  local type_counts = {}
  for _, task in ipairs(tasks) do
    type_counts[task.type] = (type_counts[task.type] or 0) + 1
  end
  
  print("Task types:", vim.inspect(type_counts))
  
  -- Test daily note formatting exactly as the function does it
  local today_tasks = {}
  local task_count = 0
  
  table.insert(today_tasks, "")  -- blank line
  
  for _, task in ipairs(tasks) do
    if (task.type == "TODO" or task.type == "NEXT") and task_count < 10 then
      local task_line = string.format("- [ ] **%s** %s", task.type, task.display_text or task.text)
      local file_name = vim.fn.fnamemodify(task.rel_file, ":t:r")
      task_line = task_line .. string.format(" _%s_", file_name)
      table.insert(today_tasks, task_line)
      task_count = task_count + 1
    end
  end
  
  if task_count > 0 then
    table.insert(today_tasks, "")
    table.insert(today_tasks, string.format("_Synced %d tasks from GTD_", task_count))
    table.insert(today_tasks, "")
  end
  
  local gtd_content = table.concat(today_tasks, "\n")
  
  print("\n=== Generated GTD Content ===")
  print("Number of lines:", #today_tasks)
  print("Content with line numbers:")
  for i, line in ipairs(today_tasks) do
    print(string.format("%2d: %s", i, line))
  end
  
  print("\n=== Final joined content ===")
  print(string.format("Length: %d characters", #gtd_content))
  print("Content (showing \\n):")
  print(gtd_content:gsub("\n", "\\n"))
  
  -- Test template application
  print("\n=== Template Test ===")
  local template_vars = { gtd_tasks = gtd_content }
  local test_template = { "## GTD Sync", "{{gtd_tasks}}", "## End Test" }
  
  for i, line in ipairs(test_template) do
    for k, v in pairs(template_vars) do
      line = line:gsub("{{" .. k .. "}}", v)
    end
    test_template[i] = line
  end
  
  print("Template result:")
  for i, line in ipairs(test_template) do
    print(string.format("%2d: %s", i, line))
  end
end

return M