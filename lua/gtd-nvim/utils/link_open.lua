-- Enhanced link opener with wiki-link resolution, backlinks, and rename support
-- Backward compatible with all existing functionality

local M = {}

-- Config
M.config = {
  browser = "Safari",
  mutt_cmd = "neomutt",
  float = { border = "rounded", width = 0.85, height = 0.85, winblend = 0 },
  -- Notes resolution config
  notes_dir = "~/Documents/Notes",
  gtd_dir = "~/Documents/GTD",
  extensions = { "md", "org", "txt", "markdown" },
  exclude_patterns = { "%.git", "%.DS_Store", "node_modules", "%.continuity", "%.gpg" },
  -- Link resolution cache
  _cache = {
    files = nil,
    files_by_basename = nil,
    files_by_zk_id = nil,
    timestamp = 0,
    ttl = 30,
  },
}

-- ============================================================================
-- PLATFORM HELPERS
-- ============================================================================

local _is_macos = nil
local function is_macos()
  if _is_macos == nil then
    local s = vim.loop.os_uname().sysname or ""
    _is_macos = s:match("Darwin") ~= nil
  end
  return _is_macos
end

local function sys_open_url(url)
  if is_macos() then
    vim.fn.jobstart({ "open", "-a", M.config.browser, url }, { detach = true })
  else
    if vim.fn.executable("xdg-open") == 1 then
      vim.fn.jobstart({ "xdg-open", url }, { detach = true })
    else
      vim.notify("No URL opener found (xdg-open).", vim.log.levels.WARN, { title = "LinkOpen" })
    end
  end
end

local function urldecode(s)
  if not s then return s end
  s = s:gsub("+", " ")
  s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  return s
end

local function parse_mailto(uri)
  local addr, qs = uri:match("^mailto:([^%?]+)%??(.*)$")
  addr = urldecode(addr or "")
  local q = {}
  if qs and qs ~= "" then
    for kv in qs:gmatch("[^&]+") do
      local k, v = kv:match("^([^=]+)=(.*)$")
      if k then q[k:lower()] = urldecode(v) else q[kv:lower()] = "" end
    end
  end
  return addr, q
end

local function expand_path(path)
  return vim.fn.expand(path)
end

-- ============================================================================
-- FILE DISCOVERY AND RESOLUTION (Core Zettelkasten feature)
-- ============================================================================

--- Build file index for fast resolution
local function build_file_index()
  local notes_dir = expand_path(M.config.notes_dir)
  local files = {}
  local by_basename = {}
  local by_zk_id = {}
  
  if vim.fn.isdirectory(notes_dir) == 0 then
    return files, by_basename, by_zk_id
  end
  
  local name_patterns = {}
  for _, ext in ipairs(M.config.extensions) do
    table.insert(name_patterns, string.format('-name "*.%s"', ext))
  end
  
  local escaped_dir = vim.fn.shellescape(notes_dir)
  local find_cmd = string.format(
    'find %s -type f \\( %s \\) 2>/dev/null',
    escaped_dir,
    table.concat(name_patterns, " -o ")
  )
  
  local output = vim.fn.system(find_cmd)
  local paths = vim.split(output, "\n", { trimempty = true })
  
  for _, path in ipairs(paths) do
    local skip = false
    for _, pattern in ipairs(M.config.exclude_patterns) do
      if path:find(pattern) then
        skip = true
        break
      end
    end
    
    if not skip and vim.fn.filereadable(path) == 1 then
      local basename = vim.fn.fnamemodify(path, ":t:r")
      local dir = vim.fn.fnamemodify(path, ":h:t")
      local rel_path = vim.fn.fnamemodify(path, ":~:.")
      
      local entry = {
        path = path,
        basename = basename,
        basename_lower = basename:lower(),
        dir = dir,
        rel_path = rel_path,
        display = string.format("%s (%s)", basename, dir),
      }
      
      table.insert(files, entry)
      
      -- Index by basename (lowercase for case-insensitive lookup)
      local key = basename:lower()
      if not by_basename[key] then
        by_basename[key] = entry
      end
      
      -- Index by ZK ID if present (YYYYMMDDHHMM format)
      local zk_id = basename:match("^(%d%d%d%d%d%d%d%d%d%d%d%d)")
      if zk_id then
        by_zk_id[zk_id] = entry
      end
    end
  end
  
  return files, by_basename, by_zk_id
end

--- Get cached file index
local function get_file_index()
  local now = os.time()
  local cache = M.config._cache
  
  if cache.files and (now - cache.timestamp) < cache.ttl then
    return cache.files, cache.files_by_basename, cache.files_by_zk_id
  end
  
  local files, by_basename, by_zk_id = build_file_index()
  
  cache.files = files
  cache.files_by_basename = by_basename
  cache.files_by_zk_id = by_zk_id
  cache.timestamp = now
  
  return files, by_basename, by_zk_id
end

--- Invalidate the file index cache
function M.invalidate_cache()
  M.config._cache.files = nil
  M.config._cache.files_by_basename = nil
  M.config._cache.files_by_zk_id = nil
  M.config._cache.timestamp = 0
end

--- Resolve wiki-link target to file path
---@param target string Wiki-link target (e.g., "My Note" or "my-note")
---@return string|nil Absolute path if found
function M.resolve_wiki_link(target)
  if not target or target == "" then return nil end
  
  local _, by_basename, _ = get_file_index()
  
  -- 1. Direct basename match (case-insensitive)
  local key = target:lower()
  if by_basename[key] then
    return by_basename[key].path
  end
  
  -- 2. Try with dashes/underscores normalized
  local normalized = key:gsub("[%s_]", "-")
  if by_basename[normalized] then
    return by_basename[normalized].path
  end
  
  -- 3. Try without dashes/underscores
  local collapsed = key:gsub("[%s_%-]", "")
  for basename_key, entry in pairs(by_basename) do
    if basename_key:gsub("[%s_%-]", "") == collapsed then
      return entry.path
    end
  end
  
  -- 4. Try with common extensions added
  local notes_dir = expand_path(M.config.notes_dir)
  for _, ext in ipairs(M.config.extensions) do
    local test_path = notes_dir .. "/" .. target .. "." .. ext
    if vim.fn.filereadable(test_path) == 1 then
      return test_path
    end
  end
  
  return nil
end

--- Resolve ZK ID to file path
---@param zk_id string ZK ID (YYYYMMDDHHMM format)
---@return string|nil Absolute path if found
function M.resolve_zk_id(zk_id)
  if not zk_id then return nil end
  
  local _, _, by_zk_id = get_file_index()
  
  if by_zk_id[zk_id] then
    return by_zk_id[zk_id].path
  end
  
  return nil
end

-- ============================================================================
-- BACKLINK EXTRACTION (Core Zettelkasten feature)
-- ============================================================================

--- Extract all links from file content
---@param filepath string Path to file
---@return table Array of {target, line_num, line_text, link_type}
function M.extract_links_from_file(filepath)
  local links = {}
  
  if vim.fn.filereadable(filepath) == 0 then
    return links
  end
  
  local lines = vim.fn.readfile(filepath)
  
  for i, line in ipairs(lines) do
    -- Wiki-links: [[target]] or [[target|alias]]
    for target in line:gmatch("%[%[([^%]|]+)") do
      if not target:match("^file:") and not target:match("^https?:") then
        table.insert(links, {
          target = target,
          line_num = i,
          line_text = line,
          link_type = "wiki",
        })
      end
    end
    
    -- Org file links: [[file:path][description]]
    for target in line:gmatch("%[%[file:([^%]]+)%]") do
      table.insert(links, {
        target = target,
        line_num = i,
        line_text = line,
        link_type = "org_file",
      })
    end
    
    -- ZK ID links: [[zk:ID]]
    for zk_id in line:gmatch("%[%[zk:([^%]]+)%]%]") do
      table.insert(links, {
        target = zk_id,
        line_num = i,
        line_text = line,
        link_type = "zk_id",
      })
    end
    
    -- Markdown links: [text](path) - only for local files
    for target in line:gmatch("%[[^%]]+%]%(([^%)]+)%)") do
      if not target:match("^https?://") and not target:match("^mailto:") then
        table.insert(links, {
          target = target,
          line_num = i,
          line_text = line,
          link_type = "markdown",
        })
      end
    end
  end
  
  return links
end

--- Find all files that link to a given file (backlinks)
---@param target_path string Path to the target file
---@return table Array of {source_path, line_num, line_text, link_type, source_basename}
function M.find_backlinks(target_path)
  local backlinks = {}
  
  if not target_path then return backlinks end
  
  local target_basename = vim.fn.fnamemodify(target_path, ":t:r"):lower()
  local target_zk_id = target_basename:match("^(%d%d%d%d%d%d%d%d%d%d%d%d)")
  
  local files, _, _ = get_file_index()
  
  for _, file in ipairs(files) do
    if file.path ~= target_path then
      local links = M.extract_links_from_file(file.path)
      
      for _, link in ipairs(links) do
        local link_target_lower = link.target:lower()
        local matches = false
        
        if link_target_lower == target_basename then
          matches = true
        elseif link_target_lower:find(target_basename, 1, true) then
          matches = true
        elseif target_zk_id and link.target == target_zk_id then
          matches = true
        elseif link.target:lower() == target_path:lower() then
          matches = true
        end
        
        if matches then
          table.insert(backlinks, {
            source_path = file.path,
            source_basename = file.basename,
            line_num = link.line_num,
            line_text = link.line_text,
            link_type = link.link_type,
          })
        end
      end
    end
  end
  
  return backlinks
end

--- Show backlinks for current file in fzf picker
function M.show_backlinks()
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file == "" then
    return vim.notify("No file open", vim.log.levels.WARN, { title = "Backlinks" })
  end
  
  local backlinks = M.find_backlinks(current_file)
  
  if #backlinks == 0 then
    return vim.notify("No backlinks found for: " .. vim.fn.fnamemodify(current_file, ":t"), 
      vim.log.levels.INFO, { title = "Backlinks" })
  end
  
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    print("Backlinks for: " .. vim.fn.fnamemodify(current_file, ":t"))
    for _, bl in ipairs(backlinks) do
      print(string.format("  %s:%d", bl.source_basename, bl.line_num))
    end
    return
  end
  
  local items = {}
  local backlink_map = {}
  
  for _, bl in ipairs(backlinks) do
    local display = string.format("%s:%d  %s", 
      bl.source_basename, bl.line_num, 
      vim.trim(bl.line_text):sub(1, 60))
    table.insert(items, display)
    backlink_map[display] = bl
  end
  
  fzf_lua.fzf_exec(items, {
    prompt = "Backlinks> ",
    preview = function(selected)
      local bl = backlink_map[selected[1]]
      if bl then return bl.source_path end
      return nil
    end,
    actions = {
      ['default'] = function(selected)
        local bl = backlink_map[selected[1]]
        if bl then
          vim.cmd("edit " .. vim.fn.fnameescape(bl.source_path))
          vim.api.nvim_win_set_cursor(0, { bl.line_num, 0 })
        end
      end,
    },
  })
end

-- ============================================================================
-- RENAME WITH LINK UPDATE (Safe refactoring)
-- ============================================================================

--- Generate replacement for a link based on its type
local function generate_link_replacement(line, old_basename, new_basename, old_path, new_path, link_type)
  local new_line = line
  
  if link_type == "wiki" then
    -- [[old-name]] → [[new-name]]
    -- [[old-name|alias]] → [[new-name|alias]] (preserve alias)
    
    -- Exact match: [[old-name]]
    local pattern1 = "%[%[" .. vim.pesc(old_basename) .. "%]%]"
    local replacement1 = "[[" .. new_basename .. "]]"
    new_line = new_line:gsub(pattern1, replacement1)
    
    -- With alias: [[old-name|alias]]
    local pattern2 = "%[%[" .. vim.pesc(old_basename) .. "|([^%]]+)%]%]"
    local replacement2 = "[[" .. new_basename .. "|%1]]"
    new_line = new_line:gsub(pattern2, replacement2)
    
    -- Case insensitive fallback
    new_line = new_line:gsub("(%[%[)([^%]|]+)(%]%])", function(open, target, close)
      if target:lower() == old_basename:lower() then
        return open .. new_basename .. close
      end
      return open .. target .. close
    end)
    
  elseif link_type == "org_file" then
    -- [[file:old-path][label]] → [[file:new-path][label]]
    local old_patterns = {
      vim.pesc(old_path),
      vim.pesc(old_basename .. ".md"),
      vim.pesc(old_basename .. ".org"),
      vim.pesc(old_basename),
    }
    
    local new_rel_path = vim.fn.fnamemodify(new_path, ":t")
    
    for _, old_pat in ipairs(old_patterns) do
      -- With label
      local pattern = "%[%[file:" .. old_pat .. "%]%[([^%]]+)%]%]"
      local replacement = "[[file:" .. new_rel_path .. "][%1]]"
      local updated = new_line:gsub(pattern, replacement)
      if updated ~= new_line then
        new_line = updated
        break
      end
      
      -- Without label
      pattern = "%[%[file:" .. old_pat .. "%]%]"
      replacement = "[[file:" .. new_rel_path .. "]]"
      updated = new_line:gsub(pattern, replacement)
      if updated ~= new_line then
        new_line = updated
        break
      end
    end
    
  elseif link_type == "markdown" then
    -- [text](old-path) → [text](new-path)
    local old_patterns = {
      vim.pesc(old_path),
      vim.pesc(vim.fn.fnamemodify(old_path, ":.")),
      vim.pesc(old_basename .. ".md"),
      vim.pesc(old_basename),
    }
    
    local new_rel = vim.fn.fnamemodify(new_path, ":t")
    
    for _, old_pat in ipairs(old_patterns) do
      local pattern = "(%[[^%]]+%]%()(" .. old_pat .. ")(%)?)"
      local updated = new_line:gsub(pattern, "%1" .. new_rel .. "%3")
      if updated ~= new_line then
        new_line = updated
        break
      end
    end
    
  elseif link_type == "zk_id" then
    -- [[zk:ID]] - DO NOT CHANGE (IDs are permanent)
    return nil
  end
  
  if new_line ~= line then
    return new_line
  end
  return nil
end

--- Build a list of changes that would be made
local function build_rename_changeset(old_path, new_path)
  local changes = {}
  
  local old_basename = vim.fn.fnamemodify(old_path, ":t:r")
  local new_basename = vim.fn.fnamemodify(new_path, ":t:r")
  
  local backlinks = M.find_backlinks(old_path)
  
  local by_file = {}
  for _, bl in ipairs(backlinks) do
    if not by_file[bl.source_path] then
      by_file[bl.source_path] = {}
    end
    table.insert(by_file[bl.source_path], bl)
  end
  
  for file_path, file_backlinks in pairs(by_file) do
    local lines = vim.fn.readfile(file_path)
    
    for _, bl in ipairs(file_backlinks) do
      local line_num = bl.line_num
      local old_line = lines[line_num]
      
      if old_line then
        local new_line = generate_link_replacement(
          old_line, old_basename, new_basename, old_path, new_path, bl.link_type
        )
        
        if new_line then
          table.insert(changes, {
            file = file_path,
            line_num = line_num,
            old_line = old_line,
            new_line = new_line,
            link_type = bl.link_type,
          })
        end
      end
    end
  end
  
  return changes
end

--- Apply changes to files
local function apply_rename_changes(changes, create_backup)
  local by_file = {}
  for _, change in ipairs(changes) do
    if not by_file[change.file] then
      by_file[change.file] = {}
    end
    table.insert(by_file[change.file], change)
  end
  
  local modified_count = 0
  
  for file_path, file_changes in pairs(by_file) do
    local lines = vim.fn.readfile(file_path)
    
    if create_backup then
      local backup_path = file_path .. ".bak"
      vim.fn.writefile(lines, backup_path)
    end
    
    table.sort(file_changes, function(a, b) return a.line_num > b.line_num end)
    
    for _, change in ipairs(file_changes) do
      if lines[change.line_num] == change.old_line then
        lines[change.line_num] = change.new_line
      end
    end
    
    vim.fn.writefile(lines, file_path)
    modified_count = modified_count + 1
    
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if buf_name == file_path then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("edit!")
          end)
        end
      end
    end
  end
  
  return modified_count
end

--- Show preview of changes before applying
local function show_rename_preview(old_path, new_path, changes)
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  
  if #changes == 0 then
    vim.notify("No links to update - safe to rename directly", vim.log.levels.INFO, { title = "Rename" })
    return function(cb) cb(true, false) end
  end
  
  if not ok then
    print("=== Rename Preview ===")
    print(string.format("From: %s", old_path))
    print(string.format("To:   %s", new_path))
    print(string.format("Links to update: %d", #changes))
    for _, c in ipairs(changes) do
      print(string.format("  %s:%d [%s]", vim.fn.fnamemodify(c.file, ":t"), c.line_num, c.link_type))
    end
    return function(cb)
      vim.ui.input({ prompt = "Apply changes? (y/n): " }, function(input)
        cb(input and input:lower() == "y", false)
      end)
    end
  end
  
  return function(cb)
    local items = {
      string.format("── Rename: %s → %s ──", 
        vim.fn.fnamemodify(old_path, ":t:r"),
        vim.fn.fnamemodify(new_path, ":t:r")),
      string.format("Links to update: %d", #changes),
      "",
    }
    
    for _, c in ipairs(changes) do
      table.insert(items, string.format("[%s] %s:%d", 
        c.link_type, vim.fn.fnamemodify(c.file, ":t"), c.line_num))
      table.insert(items, "  - " .. vim.trim(c.old_line):sub(1, 70))
      table.insert(items, "  + " .. vim.trim(c.new_line):sub(1, 70))
      table.insert(items, "")
    end
    
    table.insert(items, "─────────────────────────────")
    table.insert(items, "Press: y=apply  n=cancel  b=apply+backup")
    
    fzf_lua.fzf_exec(items, {
      prompt = "Rename Preview> ",
      actions = {
        ['y'] = function() cb(true, false) end,
        ['n'] = function() cb(false, false) end,
        ['b'] = function() cb(true, true) end,
        ['default'] = function() cb(false, false) end,
      },
      fzf_opts = {
        ['--no-info'] = true,
        ['--header'] = 'y=apply | n=cancel | b=backup+apply',
      },
      winopts = { height = 0.7, width = 0.8 },
    })
  end
end

--- Rename a note and update all incoming links
---@param old_path string|nil Path to rename (defaults to current file)
---@param new_name string|nil New name (prompts if nil)
function M.rename_note(old_path, new_name)
  old_path = old_path or vim.api.nvim_buf_get_name(0)
  
  if old_path == "" then
    return vim.notify("No file to rename", vim.log.levels.WARN, { title = "Rename" })
  end
  
  local notes_dir = expand_path(M.config.notes_dir)
  if not old_path:find(notes_dir, 1, true) then
    return vim.notify("File not in notes directory", vim.log.levels.WARN, { title = "Rename" })
  end
  
  local old_basename = vim.fn.fnamemodify(old_path, ":t:r")
  local old_ext = vim.fn.fnamemodify(old_path, ":e")
  local old_dir = vim.fn.fnamemodify(old_path, ":h")
  
  local function do_rename(new_basename)
    if not new_basename or new_basename == "" or new_basename == old_basename then
      return vim.notify("Rename cancelled", vim.log.levels.INFO, { title = "Rename" })
    end
    
    local new_path = old_dir .. "/" .. new_basename .. "." .. old_ext
    
    if vim.fn.filereadable(new_path) == 1 then
      return vim.notify("Target file already exists: " .. new_basename, vim.log.levels.ERROR, { title = "Rename" })
    end
    
    local changes = build_rename_changeset(old_path, new_path)
    
    local preview_fn = show_rename_preview(old_path, new_path, changes)
    preview_fn(function(apply, backup)
      if not apply then
        return vim.notify("Rename cancelled", vim.log.levels.INFO, { title = "Rename" })
      end
      
      -- Apply link updates first
      if #changes > 0 then
        local modified = apply_rename_changes(changes, backup)
        vim.notify(string.format("Updated %d files", modified), vim.log.levels.INFO, { title = "Rename" })
      end
      
      -- Rename the actual file
      local rename_ok = vim.fn.rename(old_path, new_path) == 0
      if not rename_ok then
        return vim.notify("Failed to rename file!", vim.log.levels.ERROR, { title = "Rename" })
      end
      
      -- Update current buffer
      local current_buf = vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_get_name(current_buf) == old_path then
        vim.cmd("edit " .. vim.fn.fnameescape(new_path))
        vim.api.nvim_buf_delete(current_buf, { force = true })
      end
      
      -- Invalidate cache
      M.invalidate_cache()
      
      vim.notify(string.format("Renamed: %s → %s (%d links updated)", 
        old_basename, new_basename, #changes), vim.log.levels.INFO, { title = "Rename" })
    end)
  end
  
  if new_name then
    do_rename(new_name)
  else
    vim.ui.input({ prompt = "New name: ", default = old_basename }, do_rename)
  end
end

-- ============================================================================
-- ORIGINAL LINK OPENING (Preserved functionality)
-- ============================================================================

local function open_mailto(uri)
  local addr, q = parse_mailto(uri)
  if addr == "" then
    vim.notify("Malformed mailto URI", vim.log.levels.WARN, { title = "LinkOpen" })
    return
  end
  
  local cmd = M.config.mutt_cmd
  local args = { cmd, addr }
  
  if q.subject then table.insert(args, "-s"); table.insert(args, q.subject) end
  
  local term_ok, term = pcall(require, "toggleterm")
  if term_ok and term.exec then
    term.exec(table.concat(args, " "), 1, nil, nil, "float")
  else
    vim.cmd("split | terminal " .. table.concat(args, " "))
  end
end

local function open_file_link(path)
  local expanded = expand_path(path)
  if vim.fn.filereadable(expanded) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(expanded))
  elseif vim.fn.isdirectory(expanded) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(expanded))
  else
    vim.notify("File not found: " .. expanded, vim.log.levels.WARN, { title = "LinkOpen" })
  end
end

--- Extract link under cursor
local function get_link_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  
  -- Wiki-link: [[target]] or [[target|alias]]
  for link_start, target, link_end in line:gmatch("()%[%[([^%]|]+)[^%]]*%]%]()") do
    if col >= link_start and col <= link_end then
      return { type = "wiki", target = target }
    end
  end
  
  -- ZK ID link: [[zk:ID]]
  for link_start, zk_id, link_end in line:gmatch("()%[%[zk:([^%]]+)%]%]()") do
    if col >= link_start and col <= link_end then
      return { type = "zk", target = zk_id }
    end
  end
  
  -- Org file link: [[file:path][desc]] or [[file:path]]
  for link_start, path, link_end in line:gmatch("()%[%[file:([^%]]+)%][^%]]*%]()") do
    if col >= link_start and col <= link_end then
      return { type = "file", target = path }
    end
  end
  
  -- Markdown link: [text](url)
  for link_start, url, link_end in line:gmatch("()%[[^%]]+%]%(([^%)]+)%)()") do
    if col >= link_start and col <= link_end then
      if url:match("^https?://") then
        return { type = "url", target = url }
      elseif url:match("^mailto:") then
        return { type = "mailto", target = url }
      else
        return { type = "file", target = url }
      end
    end
  end
  
  -- Plain URL
  for link_start, url, link_end in line:gmatch("()(https?://[%w%.%-_~:/?#%[%]@!$&'%(%)%*%+,;=]+)()") do
    if col >= link_start and col <= link_end then
      return { type = "url", target = url }
    end
  end
  
  -- Plain mailto
  for link_start, mailto, link_end in line:gmatch("()(mailto:[^%s>\"']+)()") do
    if col >= link_start and col <= link_end then
      return { type = "mailto", target = mailto }
    end
  end
  
  return nil
end

--- Open link under cursor (main entry point)
function M.open()
  local link = get_link_under_cursor()
  
  if not link then
    vim.notify("No link under cursor", vim.log.levels.INFO, { title = "LinkOpen" })
    return
  end
  
  if link.type == "url" then
    sys_open_url(link.target)
  elseif link.type == "mailto" then
    open_mailto(link.target)
  elseif link.type == "file" then
    open_file_link(link.target)
  elseif link.type == "wiki" then
    local resolved = M.resolve_wiki_link(link.target)
    if resolved then
      vim.cmd("edit " .. vim.fn.fnameescape(resolved))
    else
      vim.notify("Wiki-link not found: " .. link.target, vim.log.levels.WARN, { title = "LinkOpen" })
    end
  elseif link.type == "zk" then
    local resolved = M.resolve_zk_id(link.target)
    if resolved then
      vim.cmd("edit " .. vim.fn.fnameescape(resolved))
    else
      vim.notify("ZK note not found: " .. link.target, vim.log.levels.WARN, { title = "LinkOpen" })
    end
  end
end

--- Open URL in browser
function M.open_url(url)
  if url and url ~= "" then
    sys_open_url(url)
  end
end

--- Setup keymaps
function M.setup_keymaps()
  local opts = { noremap = true, silent = true }
  
  -- Open link under cursor
  vim.keymap.set('n', 'gx', M.open, vim.tbl_extend('force', opts, { desc = "Open link under cursor" }))
  vim.keymap.set('n', '<CR>', function()
    local link = get_link_under_cursor()
    if link then M.open() else vim.cmd("normal! <CR>") end
  end, vim.tbl_extend('force', opts, { desc = "Open link or normal enter" }))
  
  -- Backlinks
  vim.keymap.set('n', '<leader>lb', M.show_backlinks, vim.tbl_extend('force', opts, { desc = "Show backlinks" }))
  
  -- Rename with link update
  vim.keymap.set('n', '<leader>lr', M.rename_note, vim.tbl_extend('force', opts, { desc = "Rename note + update links" }))
end

-- Backward compatibility alias
M.open_at_point = function(opts)
  -- opts.floating_preview is ignored in this implementation
  M.open()
end

return M
