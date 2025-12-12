-- Enhanced link insertion with wiki-link completion
-- Backward compatible with all existing functionality

local M = {}

-- Config
M.config = {
  notes_dir = "~/Documents/Notes",
  gtd_dir = "~/Documents/GTD",
  link_formats = {
    markdown = {
      file = "[%s](%s)",
      wiki = "[[%s]]",           -- NEW: wiki-link format
      wiki_aliased = "[[%s|%s]]", -- NEW: wiki-link with alias
      url = "[%s](%s)", 
      mailto = "[%s](mailto:%s)",
      tag = "#%s",
      date = "[[%s]]",
    },
    org = {
      file = "[[file:%s][%s]]",
      wiki = "[[file:%s][%s]]",   -- Org uses file: links
      wiki_aliased = "[[file:%s][%s]]",
      url = "[[%s][%s]]",
      mailto = "[[mailto:%s][%s]]",
      tag = ":%s:",
      date = "[%s]",
    }
  },
  extensions = { "md", "org", "txt", "markdown" },
  exclude_patterns = { "%.git", "%.DS_Store", "node_modules", "^#.*#$", "%.gpg$", "%.continuity" },
  -- NEW: Wiki-link completion settings
  wiki_link = {
    trigger = "[[",              -- Trigger sequence for completion
    use_relative_paths = true,   -- Use relative paths in links
    prefer_basename = true,      -- Link by basename, not full path
    auto_extension = false,      -- Don't add .md extension in links
  },
  -- NEW: Notes file cache
  _cache = {
    files = nil,
    timestamp = 0,
    ttl = 30,  -- 30 second cache
  },
}

-- Setup function  
function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end
end

-- Helpers (preserved from original)
local function get_filetype()
  local ft = vim.bo.filetype
  if ft == "org" then return "org" end
  if ft:match("markdown") then return "markdown" end
  return "markdown"
end

local function expand_path(path)
  return vim.fn.expand(path)
end

local function build_fd_exclude_opts()
  local exclude_opts = {}
  for _, pat in ipairs(M.config.exclude_patterns) do
    table.insert(exclude_opts, "--exclude")
    table.insert(exclude_opts, pat)
  end
  return exclude_opts
end


-- ============================================================================
-- CACHED FILE DISCOVERY (NEW - performance optimization)
-- ============================================================================

local function get_notes_files_cached()
  local now = os.time()
  local cache = M.config._cache
  
  if cache.files and (now - cache.timestamp) < cache.ttl then
    return cache.files
  end
  
  -- Refresh cache
  cache.files = M.get_notes_files()
  cache.timestamp = now
  return cache.files
end

function M.invalidate_cache()
  M.config._cache.files = nil
  M.config._cache.timestamp = 0
end

-- ============================================================================
-- FILE DISCOVERY (preserved from original, no limits)
-- ============================================================================

function M.get_notes_files()
  local notes_dir = expand_path(M.config.notes_dir)
  local files = {}
  
  if vim.fn.isdirectory(notes_dir) == 0 then
    vim.notify("Notes directory does not exist: " .. notes_dir, vim.log.levels.ERROR)
    return files
  end
  
  local name_patterns = {}
  for _, ext in ipairs(M.config.extensions) do
    table.insert(name_patterns, string.format('-name "*.%s"', ext))
  end
  
  local escaped_dir = vim.fn.shellescape(notes_dir)
  local find_cmd = string.format(
    'find %s -type f \\( %s \\)',
    escaped_dir,
    table.concat(name_patterns, " -o ")
  )
  
  local handle = io.popen(find_cmd)
  if handle then
    for line in handle:lines() do
      local skip = false
      for _, pattern in ipairs(M.config.exclude_patterns) do
        if line:match(pattern) then
          skip = true
          break
        end
      end
      if not skip then
        local rel_path = line:gsub("^" .. vim.pesc(notes_dir) .. "/", "")
        local basename = vim.fn.fnamemodify(rel_path, ":t:r")
        local dir_part = vim.fn.fnamemodify(rel_path, ":h")
        if dir_part == "." then dir_part = "" end
        
        -- NEW: Extract ZK ID if present (YYYYMMDDHHMM format at start)
        local zk_id = basename:match("^(%d%d%d%d%d%d%d%d%d%d%d%d)")
        
        table.insert(files, {
          path = line,
          rel_path = rel_path,
          basename = basename,
          display = basename .. (dir_part ~= "" and " (" .. dir_part .. ")" or ""),
          zk_id = zk_id,
          dir = dir_part,
        })
      end
    end
    handle:close()
  end
  
  return files
end


-- ============================================================================
-- CORE INSERTION HELPERS (preserved from original)
-- ============================================================================

local function insert_at_cursor(text)
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local new_line = line:sub(1, pos[2]) .. text .. line:sub(pos[2] + 1)
  vim.api.nvim_set_current_line(new_line)
  vim.api.nvim_win_set_cursor(0, {pos[1], pos[2] + #text})
end

local function format_link(link_type, content, target, ft)
  ft = ft or get_filetype()
  local format = M.config.link_formats[ft] and M.config.link_formats[ft][link_type]
  if not format then
    format = M.config.link_formats.markdown[link_type] or "[%s](%s)"
  end
  
  if link_type == "tag" or link_type == "date" or link_type == "wiki" then
    return string.format(format, content)
  else
    return string.format(format, content, target)
  end
end

-- ============================================================================
-- WIKI-LINK COMPLETION (NEW - Core Zettelkasten feature)
-- ============================================================================

--- Get the wiki-link target from basename
---@param file table File entry from get_notes_files()
---@return string Link target (basename without extension)
local function get_wiki_target(file)
  if M.config.wiki_link.prefer_basename then
    return file.basename
  else
    local target = file.rel_path
    if not M.config.wiki_link.auto_extension then
      target = target:gsub("%.%w+$", "")
    end
    return target
  end
end

--- Check if cursor is inside a wiki-link trigger
---@return boolean, number, number is_triggered, start_col, end_col
local function check_wiki_trigger()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  
  -- Look backward for [[ that isn't closed
  local before = line:sub(1, col + 1)
  local trigger_start = nil
  local search_start = 1
  
  while true do
    local s = before:find("%[%[", search_start)
    if not s then break end
    
    -- Check if this [[ is closed before cursor
    local close = before:find("%]%]", s + 2)
    if not close or close > col then
      trigger_start = s
      break
    end
    search_start = s + 2
  end
  
  if trigger_start then
    -- Extract what's been typed after [[
    local typed = before:sub(trigger_start + 2)
    return true, trigger_start, typed
  end
  
  return false, 0, ""
end

--- Complete wiki-link with fzf picker
function M.complete_wiki_link()
  local triggered, start_col, typed = check_wiki_trigger()
  
  local files = get_notes_files_cached()
  if #files == 0 then
    return vim.notify("No notes found in " .. M.config.notes_dir, vim.log.levels.WARN)
  end
  
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.ERROR)
    return
  end
  
  local items = {}
  local file_map = {}
  
  for _, file in ipairs(files) do
    table.insert(items, file.display)
    file_map[file.display] = file
  end
  
  fzf_lua.fzf_exec(items, {
    prompt = "Wiki Link> ",
    query = typed or "",  -- Pre-fill with what user has typed
    preview = function(selected)
      local file = file_map[selected[1]]
      if file and vim.fn.filereadable(file.path) == 1 then
        return file.path
      end
      return nil
    end,
    actions = {
      ['default'] = function(selected)
        local file = file_map[selected[1]]
        if file then
          local target = get_wiki_target(file)
          local ft = get_filetype()
          local link
          
          if ft == "org" then
            -- Org uses file: links
            link = string.format("[[file:%s][%s]]", file.rel_path, file.basename)
          else
            -- Markdown wiki-link
            link = string.format("[[%s]]", target)
          end
          
          -- If triggered, replace from [[ to cursor
          if triggered then
            local line = vim.api.nvim_get_current_line()
            local col = vim.api.nvim_win_get_cursor(0)[2]
            local new_line = line:sub(1, start_col - 1) .. link .. line:sub(col + 2)
            vim.api.nvim_set_current_line(new_line)
            vim.api.nvim_win_set_cursor(0, {vim.api.nvim_win_get_cursor(0)[1], start_col - 1 + #link})
          else
            insert_at_cursor(link)
          end
        end
      end,
      ['ctrl-e'] = function(selected)
        local file = file_map[selected[1]]
        if file then
          vim.cmd("edit " .. vim.fn.fnameescape(file.path))
        end
      end,
    },
  })
end


--- Setup auto-trigger for wiki-link completion
--- Call this in ftplugin/markdown.lua or after/ftplugin/markdown.lua
function M.setup_wiki_completion()
  -- Create autocommand for markdown and org files
  local group = vim.api.nvim_create_augroup("WikiLinkCompletion", { clear = true })
  
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    pattern = { "*.md", "*.markdown", "*.org" },
    callback = function()
      local char = vim.v.char
      if char == "[" then
        -- Check if previous char is also [
        local col = vim.api.nvim_win_get_cursor(0)[2]
        if col > 0 then
          local line = vim.api.nvim_get_current_line()
          local prev_char = line:sub(col, col)
          if prev_char == "[" then
            -- Schedule picker to run after insert
            vim.schedule(function()
              -- Small delay to let the second [ be inserted
              vim.defer_fn(function()
                M.complete_wiki_link()
              end, 50)
            end)
          end
        end
      end
    end,
  })
end

--- Manual trigger for wiki-link (when auto isn't desired)
function M.insert_wiki_link()
  M.complete_wiki_link()
end

-- ============================================================================
-- ORIGINAL LINK INSERTION FUNCTIONS (fully preserved)
-- ============================================================================

function M.insert_file_link()
  local files = M.get_notes_files()
  if #files == 0 then
    return vim.notify("No notes found in " .. M.config.notes_dir, vim.log.levels.WARN)
  end
  
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.ERROR)
    return
  end
  
  local items = {}
  local file_map = {}
  
  for _, file in ipairs(files) do
    table.insert(items, file.display)
    file_map[file.display] = file
  end
  
  fzf_lua.fzf_exec(items, {
    prompt = "Notes> ",
    preview = function(selected)
      local file = file_map[selected[1]]
      if file and vim.fn.filereadable(file.path) == 1 then
        return file.path
      end
      return nil
    end,
    actions = {
      ['default'] = function(selected)
        local file = file_map[selected[1]]
        if file then
          local link_text = file.basename
          local link_target = file.rel_path
          local link = format_link("file", link_text, link_target)
          insert_at_cursor(link)
        end
      end,
      ['ctrl-e'] = function(selected)
        local file = file_map[selected[1]]
        if file then
          vim.cmd("edit " .. vim.fn.fnameescape(file.path))
        end
      end,
    },
  })
end

function M.insert_url_link()
  vim.ui.input({ prompt = "URL: " }, function(url)
    if url and url ~= "" then
      vim.ui.input({ prompt = "Link text: ", default = url }, function(text)
        if text and text ~= "" then
          local link = format_link("url", text, url)
          insert_at_cursor(link)
        end
      end)
    end
  end)
end

function M.insert_mailto_link()
  vim.ui.input({ prompt = "Email address: " }, function(email)
    if email and email ~= "" then
      vim.ui.input({ prompt = "Link text: ", default = email }, function(text)
        if text and text ~= "" then
          local link = format_link("mailto", text, email)
          insert_at_cursor(link)
        end
      end)
    end
  end)
end

function M.insert_tag()
  vim.ui.input({ prompt = "Tag: " }, function(tag)
    if tag and tag ~= "" then
      tag = tag:gsub("^#", "")
      local formatted_tag = format_link("tag", tag)
      insert_at_cursor(formatted_tag)
    end
  end)
end

function M.insert_date_link(date_format)
  date_format = date_format or "%Y-%m-%d"
  local date_str = os.date(date_format)
  local link = format_link("date", date_str)
  insert_at_cursor(link)
end


function M.insert_task_ref()
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.ERROR)
    return
  end
  
  local gtd_dir = expand_path(M.config.gtd_dir)
  
  if vim.fn.isdirectory(gtd_dir) == 0 then
    return vim.ui.input({ prompt = "Task ID/Reference: " }, function(task_ref)
      if task_ref and task_ref ~= "" then
        local link_text = "Task: " .. task_ref
        local link_target = "task:" .. task_ref
        local link = format_link("url", link_text, link_target)
        insert_at_cursor(link)
      end
    end)
  end
  
  local cmd = string.format(
    'rg -n "TODO|NEXT|WAITING|DONE|PROJ|SOMEDAY|MAYBE|\\*" %s 2>/dev/null || echo "No tasks found"',
    vim.fn.shellescape(gtd_dir)
  )
  
  fzf_lua.fzf_exec(cmd, {
    prompt = "GTD Tasks> ",
    actions = {
      ['default'] = function(selected)
        if not selected or not selected[1] or selected[1] == "No tasks found" then 
          return vim.notify("No task selected", vim.log.levels.INFO)
        end
        
        local line = selected[1]
        local content = line:match("^[^:]+:%d+:(.*)$") or line:match("^[^:]+:(.*)$")
        
        if content then
          local task_text = content:gsub("^%s*%*+%s*", "")
          task_text = task_text:gsub("^TODO%s*", "")
          task_text = task_text:gsub("^NEXT%s*", "")
          task_text = task_text:gsub("^WAITING%s*", "")
          task_text = task_text:gsub("^SOMEDAY%s*", "")
          task_text = task_text:gsub("^MAYBE%s*", "")
          task_text = task_text:gsub("%s*:.-:%s*$", "")
          task_text = task_text:match("^%s*(.-)%s*$") or "Task"
          
          local timestamp = os.date("%Y%m%d%H%M")
          local task_ref = "task-" .. timestamp
          
          local link = format_link("url", task_text, "gtd:" .. task_ref)
          insert_at_cursor(link)
        end
      end,
    },
  })
end

function M.insert_person_link()
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.ERROR)
    return
  end
  
  local notes_dir = expand_path(M.config.notes_dir)
  local people_dir = notes_dir .. "/People"
  
  if vim.fn.isdirectory(people_dir) == 0 then
    return vim.ui.input({ prompt = "Person name: " }, function(person)
      if person and person ~= "" then
        local filename = person:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
        local rel_path = "People/" .. filename .. ".md"
        local link = format_link("file", person, rel_path)
        insert_at_cursor(link)
      end
    end)
  end
  
  local exclude_opts = build_fd_exclude_opts()
  
  fzf_lua.files({
    cwd = people_dir,
    prompt = "People> ",
    file_icons = true,
    fd_opts = table.concat({ "--type", "f", "--hidden", unpack(exclude_opts) }, " "),
    actions = {
      ['default'] = function(selected)
        local file_path = selected[1]
        local basename = vim.fn.fnamemodify(file_path, ":t:r")
        local rel_path = "People/" .. file_path
        local link = format_link("file", basename, rel_path)
        insert_at_cursor(link)
      end,
      ['ctrl-e'] = function(selected)
        local full_path = people_dir .. "/" .. selected[1]
        vim.cmd("edit " .. vim.fn.fnameescape(full_path))
      end,
    },
    preview = function(selected)
      local file_path = people_dir .. "/" .. selected[1]
      if vim.fn.filereadable(file_path) == 1 then
        return file_path
      end
      return nil
    end,
  })
end

function M.insert_project_link()
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.ERROR)
    return
  end
  
  local notes_dir = expand_path(M.config.notes_dir)
  local projects_dir = notes_dir .. "/Projects"
  
  if vim.fn.isdirectory(projects_dir) == 0 then
    return vim.ui.input({ prompt = "Project name: " }, function(project)
      if project and project ~= "" then
        local filename = project:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
        local rel_path = "Projects/" .. filename .. ".md"
        local link = format_link("file", project, rel_path)
        insert_at_cursor(link)
      end
    end)
  end
  
  local exclude_opts = build_fd_exclude_opts()
  
  fzf_lua.files({
    cwd = projects_dir,
    prompt = "Projects> ",
    file_icons = true,
    fd_opts = table.concat({ "--type", "f", "--hidden", unpack(exclude_opts) }, " "),
    actions = {
      ['default'] = function(selected)
        local file_path = selected[1]
        local basename = vim.fn.fnamemodify(file_path, ":t:r")
        local rel_path = "Projects/" .. file_path
        local link = format_link("file", basename, rel_path)
        insert_at_cursor(link)
      end,
      ['ctrl-e'] = function(selected)
        local full_path = projects_dir .. "/" .. selected[1]
        vim.cmd("edit " .. vim.fn.fnameescape(full_path))
      end,
    },
    preview = function(selected)
      local file_path = projects_dir .. "/" .. selected[1]
      if vim.fn.filereadable(file_path) == 1 then
        return file_path
      end
      return nil
    end,
  })
end


function M.insert_timestamp_note()
  local timestamp = os.date("%Y%m%d%H%M")
  vim.ui.input({ prompt = "Note title: " }, function(title)
    if title and title ~= "" then
      local filename = timestamp .. "-" .. title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
      local rel_path = filename .. ".md"
      local link = format_link("file", title, rel_path)
      insert_at_cursor(link)
      
      vim.ui.select({"Yes", "No"}, {
        prompt = "Create the note file?",
      }, function(choice)
        if choice == "Yes" then
          local notes_dir = expand_path(M.config.notes_dir)
          local full_path = notes_dir .. "/" .. rel_path
          vim.cmd("edit " .. vim.fn.fnameescape(full_path))
        end
      end)
    end
  end)
end

-- ============================================================================
-- LINK MENU (enhanced with wiki-link option)
-- ============================================================================

function M.link_menu()
  local ok, fzf_lua = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.ERROR)
    return
  end
  
  local options = {
    "wiki         🔗 Wiki-link [[note]]",  -- NEW
    "file         📄 File/Note link",
    "url          🌐 URL link", 
    "mailto       📧 Email link",
    "tag          🏷️  Tag",
    "date         📅 Today's date",
    "task         ✅ Task reference", 
    "person       👤 Person link",
    "project      📁 Project link",
    "timestamp    🕐 New timestamped note",
  }
  
  local actions = {
    wiki = M.insert_wiki_link,  -- NEW
    file = M.insert_file_link,
    url = M.insert_url_link,
    mailto = M.insert_mailto_link,
    tag = M.insert_tag,
    date = M.insert_date_link,
    task = M.insert_task_ref,
    person = M.insert_person_link,
    project = M.insert_project_link,
    timestamp = M.insert_timestamp_note,
  }
  
  fzf_lua.fzf_exec(options, {
    prompt = "Link> ",
    actions = {
      ['default'] = function(selected)
        local key = selected[1]:match("^(%w+)")
        if actions[key] then
          actions[key]()
        end
      end,
    },
  })
end

-- ============================================================================
-- DEBUG HELPERS
-- ============================================================================

function M.debug_notes_scan()
  local notes_dir = expand_path(M.config.notes_dir)
  print("Notes directory: " .. notes_dir)
  print("Directory exists: " .. (vim.fn.isdirectory(notes_dir) == 1 and "YES" or "NO"))
  
  local files = M.get_notes_files()
  print("Files found: " .. #files)
  
  for i, file in ipairs(files) do
    local zk_info = file.zk_id and (" [ZK:" .. file.zk_id .. "]") or ""
    print(string.format("%d. %s%s -> %s", i, file.display, zk_info, file.rel_path))
    if i >= 10 then 
      print("... (showing first 10)")
      break 
    end
  end
end

-- ============================================================================
-- KEYMAP SETUP (enhanced with wiki-link bindings)
-- ============================================================================

function M.setup_keymaps()
  -- Wiki-link completion (NEW)
  vim.keymap.set({"n", "i"}, "<leader>lw", M.insert_wiki_link, { desc = "Insert wiki-link [[]]" })
  vim.keymap.set("i", "<C-]>", M.complete_wiki_link, { desc = "Complete wiki-link" })
  
  -- Core link insertion (preserved)
  vim.keymap.set({"n", "i"}, "<leader>ll", M.link_menu, { desc = "Insert link menu" })
  vim.keymap.set({"n", "i"}, "<leader>lf", M.insert_file_link, { desc = "Insert file link" })
  vim.keymap.set({"n", "i"}, "<leader>lu", M.insert_url_link, { desc = "Insert URL link" })
  vim.keymap.set({"n", "i"}, "<leader>lm", M.insert_mailto_link, { desc = "Insert mailto link" })
  vim.keymap.set({"n", "i"}, "<leader>lt", M.insert_tag, { desc = "Insert tag" })
  vim.keymap.set({"n", "i"}, "<leader>ld", M.insert_date_link, { desc = "Insert date" })
  
  -- GTD workflow (preserved)
  vim.keymap.set({"n", "i"}, "<leader>lp", M.insert_person_link, { desc = "Insert person link" })
  vim.keymap.set({"n", "i"}, "<leader>lP", M.insert_project_link, { desc = "Insert project link" })
  vim.keymap.set({"n", "i"}, "<leader>lk", M.insert_task_ref, { desc = "Insert task reference" })
  vim.keymap.set({"n", "i"}, "<leader>ln", M.insert_timestamp_note, { desc = "New timestamped note" })
  
  -- Debug functions
  vim.keymap.set("n", "<leader>lD", M.debug_notes_scan, { desc = "Debug notes scan" })
end

return M
