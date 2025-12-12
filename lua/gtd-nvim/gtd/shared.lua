-- ============================================================================
-- GTD-NVIM SHARED UTILITIES
-- ============================================================================
-- Core utilities for the GTD Neovim plugin
-- All modules should require this for consistent behavior
--
-- @module gtd-nvim.gtd.shared
-- @author Michael
-- @license MIT
-- ============================================================================

local M = {}

-- ============================================================================
-- VERSION INFORMATION
-- ============================================================================
M.VERSION = {
  major = 1,
  minor = 0,
  patch = 0,
  pre = "alpha",  -- "alpha", "beta", "rc1", or nil for release
  string = "1.0.0-alpha",
  date = "2024-12-08",
}

-- Module versions (updated when module changes significantly)
M.MODULE_VERSIONS = {
  shared    = "1.0.0",  -- This file - foundation
  capture   = "0.9.0",  -- Needs glyph/color update
  clarify   = "0.9.0",  -- Needs glyph/color update
  organize  = "1.0.0",  -- Updated with gtd_sort
  manage    = "1.0.0",  -- Updated with gtd_sort
  lists     = "1.0.0",  -- Updated with gtd_sort, partial colors
  review    = "0.8.0",  -- Needs glyph/color update
  projects  = "0.8.0",  -- Needs audit
  areas     = "0.8.0",  -- Needs audit
  calendar  = "0.8.0",  -- Needs audit
  reminders = "0.8.0",  -- Needs audit
  ui        = "0.8.0",  -- Needs audit
  status    = "0.8.0",  -- Needs audit
}

-- Changelog entries (latest first)
M.CHANGELOG = {
  ["1.0.0-alpha"] = {
    date = "2024-12-08",
    changes = {
      "Added comprehensive glyph system (50+ Nerd Font icons)",
      "Added ANSI color system for fzf-lua",
      "Added highlight groups for Neovim buffers",
      "Added GTD hierarchy sorting (Inbox → Areas → Projects)",
      "Added get_container_type(), get_state_priority(), gtd_sort()",
      "Fixed create_fzf_config() missing --ansi flag",
      "Added fzf_header() with refile, archive, delete options",
    },
    zk_note = "202512081430-GTD-Nvim-Shared-Module-Audit",
  },
}

-- ============================================================================
-- COLOR SYSTEM (ANSI for fzf-lua, highlight groups for buffers)
-- ============================================================================

-- ANSI 256 color codes for terminal/fzf-lua
M.colors = {
  -- GTD State colors
  next     = { fg = "#f7c67f", bold = true },  -- Bright amber/gold
  todo     = { fg = "#89b4fa" },                -- Soft blue
  waiting  = { fg = "#fab387" },                -- Peach/orange
  someday  = { fg = "#a6adc8" },                -- Muted gray
  done     = { fg = "#a6e3a1" },                -- Green
  project  = { fg = "#cba6f7" },                -- Purple/mauve
  cancelled = { fg = "#6c7086" },               -- Dim gray
  
  -- Container colors
  inbox    = { fg = "#f38ba8" },                -- Red/pink (attention)
  projects = { fg = "#cba6f7" },                -- Purple (same as project state)
  areas    = { fg = "#89dceb" },                -- Cyan
  someday_container = { fg = "#a6adc8" },       -- Muted gray
  calendar = { fg = "#f9e2af" },                -- Yellow
  recurring = { fg = "#94e2d5" },               -- Teal
  archive  = { fg = "#585b70" },                -- Dark gray
  reference = { fg = "#74c7ec" },               -- Light blue
  
  -- UI colors
  warning  = { fg = "#f9e2af", bold = true },   -- Yellow
  error    = { fg = "#f38ba8", bold = true },   -- Red
  info     = { fg = "#89b4fa" },                -- Blue
  success  = { fg = "#a6e3a1" },                -- Green
  muted    = { fg = "#6c7086" },                -- Dim
  accent   = { fg = "#cba6f7" },                -- Purple
}

-- Convert hex to ANSI escape code
local function hex_to_ansi(hex)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  return string.format("\27[38;2;%d;%d;%dm", r, g, b)
end

local function ansi_reset()
  return "\27[0m"
end

local function ansi_bold()
  return "\27[1m"
end

-- Colorize text for fzf-lua (ANSI)
function M.colorize(text, color_name)
  local color = M.colors[color_name]
  if not color then return text end
  
  local prefix = ""
  if color.bold then prefix = ansi_bold() end
  prefix = prefix .. hex_to_ansi(color.fg)
  
  return prefix .. text .. ansi_reset()
end

-- Colorize glyph based on state
function M.colored_state_glyph(state)
  local glyph = M.glyphs.state[state] or M.glyphs.ui.bullet
  local color_map = {
    NEXT = "next", TODO = "todo", WAITING = "waiting",
    SOMEDAY = "someday", DONE = "done", PROJECT = "project",
    CANCELLED = "cancelled",
  }
  return M.colorize(glyph, color_map[state] or "muted")
end

-- Colorize container glyph
function M.colored_container_glyph(name)
  local glyph = M.container_glyph(name)
  local lower = (name or ""):lower()
  
  local color = "muted"
  if lower:match("inbox") then color = "inbox"
  elseif lower:match("project") then color = "projects"
  elseif lower:match("area") then color = "areas"
  elseif lower:match("someday") or lower:match("maybe") then color = "someday_container"
  elseif lower:match("recurring") then color = "recurring"
  elseif lower:match("calendar") then color = "calendar"
  elseif lower:match("archive") then color = "archive"
  elseif lower:match("reference") then color = "reference"
  end
  
  return M.colorize(glyph, color)
end

-- Setup highlight groups for Neovim buffers (call in setup)
function M.setup_highlights()
  local hl = vim.api.nvim_set_hl
  
  -- GTD States
  hl(0, "GtdNext", { fg = "#f7c67f", bold = true })
  hl(0, "GtdTodo", { fg = "#89b4fa" })
  hl(0, "GtdWaiting", { fg = "#fab387" })
  hl(0, "GtdSomeday", { fg = "#a6adc8" })
  hl(0, "GtdDone", { fg = "#a6e3a1" })
  hl(0, "GtdProject", { fg = "#cba6f7" })
  hl(0, "GtdCancelled", { fg = "#6c7086", strikethrough = true })
  
  -- Containers
  hl(0, "GtdInbox", { fg = "#f38ba8", bold = true })
  hl(0, "GtdProjects", { fg = "#cba6f7" })
  hl(0, "GtdAreas", { fg = "#89dceb" })
  hl(0, "GtdCalendar", { fg = "#f9e2af" })
  hl(0, "GtdRecurring", { fg = "#94e2d5" })
  hl(0, "GtdArchive", { fg = "#585b70" })
  hl(0, "GtdReference", { fg = "#74c7ec" })
  hl(0, "GtdSomedayContainer", { fg = "#a6adc8" })
  
  -- UI
  hl(0, "GtdWarning", { fg = "#f9e2af", bold = true })
  hl(0, "GtdError", { fg = "#f38ba8", bold = true })
  hl(0, "GtdInfo", { fg = "#89b4fa" })
  hl(0, "GtdSuccess", { fg = "#a6e3a1" })
  hl(0, "GtdMuted", { fg = "#6c7086" })
  hl(0, "GtdAccent", { fg = "#cba6f7" })
  
  -- Review phases
  hl(0, "GtdClear", { fg = "#89dceb", bold = true })
  hl(0, "GtdCurrent", { fg = "#94e2d5", bold = true })
  hl(0, "GtdCreative", { fg = "#f9e2af", bold = true })
  
  -- Progress bar
  hl(0, "GtdProgressDone", { fg = "#a6e3a1" })
  hl(0, "GtdProgressPending", { fg = "#45475a" })
end

-- ============================================================================
-- GLYPH SYSTEM (Nerd Font icons for consistent UI)
-- ============================================================================
-- Uses Nerd Fonts: https://www.nerdfonts.com/cheat-sheet
-- Requires a Nerd Font patched terminal font

M.glyphs = {
  -- GTD States (task status)
  state = {
    NEXT      = "󱥦", -- lightning / next action
    TODO      = "", -- empty circle
    WAITING   = "", -- sand timer
    SOMEDAY   = "󰋊", -- bookmark / future
    DONE      = "󰸟", -- checked circle
    PROJECT   = "", -- project
    CANCELLED = "󰅚", -- close-circle
  },

  -- GTD Workflow phases
  phase = {
    capture  = "󰐕", -- clipboard-plus
    clarify  = "󰈸", -- filter
    organize = "󰙅", -- view-list
    reflect  = "󰈈", -- eye
    engage   = "", -- play
  },

  -- GTD Containers/Locations
  container = {
    inbox     = "", -- inbox tray
    projects  = "󰉋", -- folder-open
    areas     = "󰕰", -- grid / areas
    someday   = "󰋚", -- archive
    reference = "", -- book
    trash     = "", -- trash
    calendar  = "", -- calendar
    recurring = "󰑖", -- loop/refresh
  },

  -- Review phases
  review = {
    clear    = "󰃢", -- eraser
    current  = "󰔚", -- refresh/sync
    creative = "󰌵", -- lightbulb
    complete = "", -- check-circle
  },

  -- UI Elements
  ui = {
    arrow_right = "", -- chevron-right
    arrow_down  = "", -- chevron-down
    arrow_up    = "", -- chevron-up
    bullet      = "", -- filled circle
    empty       = "", -- empty circle
    check       = "", -- check
    cross       = "", -- times
    warning     = "", -- warning triangle
    info        = "", -- info-circle
    question    = "", -- question-circle
    edit        = "", -- pencil
    search      = "", -- search
    link        = "", -- link
    tag         = "", -- tag
    clock       = "", -- clock-o
    user        = "", -- user
    note        = "󰝗", -- sticky-note
    list        = "", -- list
    menu        = "", -- bars
    home        = "", -- home
    cog         = "", -- settings
    rocket      = "", -- rocket
    archive     = "󰀼", -- archive box
  },

  -- Priority indicators
  priority = {
    high   = "", -- arrow-up
    medium = "", -- minus
    low    = "", -- arrow-down
  },

  -- Checklist states
  checkbox = {
    checked   = "", -- check-square
    unchecked = "", -- square-o
    partial   = "", -- minus-square-o
  },

  -- File types
  file = {
    org        = "", -- file-text-o
    markdown   = "󰽛", -- markdown
    folder     = "", -- folder
    folder_open = "", -- folder-open
  },

  -- Progress/Status
  -- Progress/Status
  progress = {
    pending = "󰔛", -- hourglass-start
    active  = "", -- spinner
    done    = "", -- check-circle
    blocked = "", -- ban
    overdue = "", -- exclamation-circle (urgent/overdue)
    urgent  = "", -- warning triangle
    ontime  = "󰄬", -- check-all (on time)
    inactive = "󰏤", -- pause-circle-outline
  },
}
-- Helper: Get state glyph
function M.state_glyph(state)
  return M.glyphs.state[state] or M.glyphs.ui.bullet
end

-- Helper: Get container glyph
function M.container_glyph(name)
  local lower = (name or ""):lower()
  if lower:match("inbox") then
    return M.glyphs.container.inbox
  elseif lower:match("project") then
    return M.glyphs.container.projects
  elseif lower:match("area") then
    return M.glyphs.container.areas
  elseif lower:match("someday") then
    return M.glyphs.container.someday
  elseif lower:match("recurring") then
    return M.glyphs.container.recurring
  elseif lower:match("calendar") then
    return M.glyphs.container.calendar
  elseif lower:match("archive") then
    return M.glyphs.container.someday
  else
    return M.glyphs.file.org
  end
end

-- Helper: Format task for display with glyphs (colored for fzf-lua)
function M.format_task(item, opts)
  opts = opts or {}
  local colored = opts.colored ~= false  -- Default to colored
  
  local state_icon, container_icon
  if colored then
    state_icon = M.colored_state_glyph(item.state)
    container_icon = M.colored_container_glyph(item.filename or "")
  else
    state_icon = M.glyphs.state[item.state] or M.glyphs.ui.bullet
    container_icon = M.container_glyph(item.filename or "")
  end

  if opts.with_file then
    local short_file = (item.filename or ""):gsub("%.org$", "")
    local file_display = colored and M.colorize(short_file, "muted") or short_file
    return string.format("%s %s %s │ %s", state_icon, item.title or "", container_icon, file_display)
  else
    return string.format("%s %s", state_icon, item.title or "")
  end
end

-- Helper: Format header for fzf (colored)
function M.fzf_header(opts)
  local g = M.glyphs
  opts = opts or {}
  local parts = {}

  table.insert(parts, M.colorize("Enter", "muted") .. " " .. M.colorize(g.ui.arrow_right, "success") .. " Open")
  table.insert(parts, M.colorize("C-e", "muted") .. " " .. M.colorize(g.ui.edit, "info") .. " Edit")

  if opts.clarify then
    table.insert(parts, M.colorize("C-c", "muted") .. " " .. M.colorize(g.phase.clarify, "accent") .. " Clarify")
  end
  if opts.refile then
    table.insert(parts, M.colorize("C-r", "muted") .. " " .. M.colorize(g.phase.organize, "accent") .. " Refile")
  end
  if opts.archive then
    table.insert(parts, M.colorize("C-a", "muted") .. " " .. M.colorize(g.container.someday, "archive") .. " Archive")
  end
  if opts.delete then
    table.insert(parts, M.colorize("C-d", "muted") .. " " .. M.colorize(g.container.trash, "error") .. " Delete")
  end
  if opts.zettel then
    table.insert(parts, M.colorize("C-z", "muted") .. " " .. M.colorize(g.ui.note, "calendar") .. " Zettel")
  end
  if opts.back then
    table.insert(parts, M.colorize("C-b", "muted") .. " " .. M.colorize(g.ui.arrow_up, "warning") .. " Back")
  end

  return table.concat(parts, " │ ")
end

-- Helper: Create colored menu item for fzf
function M.menu_item(glyph, label, color)
  return M.colorize(glyph, color) .. " " .. label
end

-- ============================================================================
-- BASIC UTILITIES
-- ============================================================================

function M.xp(p)
  return vim.fn.expand(p or "")
end

function M.read_file(path)
  if not path then
    return {}
  end
  local expanded = M.xp(path)
  if vim.fn.filereadable(expanded) == 1 then
    return vim.fn.readfile(expanded)
  else
    return {}
  end
end

function M.have_fzf()
  return pcall(require, "fzf-lua")
end

function M.notify(msg, level)
  local levels = { INFO = vim.log.levels.INFO, WARN = vim.log.levels.WARN, ERROR = vim.log.levels.ERROR }
  vim.notify(msg, levels[level] or vim.log.levels.INFO)
end

-- ============================================================================
-- ORG PARSING WITH PROPER FILTERING
-- ============================================================================

function M.is_org_heading(line)
  return line and line:match("^%*+%s") ~= nil
end

function M.heading_level(line)
  if not line then
    return nil
  end
  local stars = line:match("^(%*+)%s")
  return stars and #stars or nil
end

function M.parse_org_heading(line)
  if not line then
    return nil, nil
  end
  local stars, rest = line:match("^(%*+)%s+(.*)")
  if not rest then
    return nil, nil
  end

  local state, title = rest:match("^([A-Z]+)%s+(.*)")
  if state and title then
    return state, title
  else
    return nil, rest
  end
end

function M.is_actionable_task(state, title, line)
  -- Filter out completed tasks
  if state and (state == "DONE" or state == "COMPLETED" or state == "CANCELLED" or state == "CLOSED") then
    return false
  end

  -- Filter out notes - these are headings without TODO keywords that look like notes
  if not state and title then
    local title_lower = title:lower()
    -- Skip if it looks like a note rather than a task
    if
      title_lower:match("^notes?:")
      or title_lower:match("^log:")
      or title_lower:match("^diary:")
      or title_lower:match("^journal:")
      or title_lower:match("^research:")
      or title_lower:match("^meeting:")
      or line:match("^%*+%s+Notes?%s")
    then
      return false
    end
  end

  -- Only include actionable states or PROJECT
  if state then
    return state == "TODO" or state == "NEXT" or state == "WAITING" or state == "SOMEDAY" or state == "PROJECT"
  end

  -- Include headings without state if they look like tasks (have clear task-like structure)
  return title and title ~= "" and not title:match("^%s*$")
end

-- ============================================================================
-- GTD HIERARCHY SORTING (System-wide consistent ordering)
-- ============================================================================
-- Order: 1. Inbox  2. Areas (alphabetical)  3. Projects (alphabetical)
-- Within each: NEXT → TODO → WAITING → SOMEDAY → other

-- Determine container type from path/filename
function M.get_container_type(path, filename)
  local lower_path = (path or ""):lower()
  local lower_name = (filename or ""):lower()
  
  -- Archive is lowest priority (shown last)
  if lower_name:match("archive") or lower_path:match("/archive") then
    return "archive", 6
  end
  
  -- Inbox is highest priority
  if lower_name:match("inbox") then
    return "inbox", 1
  end
  
  -- Areas directory
  if lower_path:match("/areas/") or lower_name:match("^area") then
    return "area", 2
  end
  
  -- Projects directory
  if lower_path:match("/projects/") or lower_name:match("^project") then
    return "project", 3
  end
  
  -- Someday/Maybe
  if lower_name:match("someday") or lower_name:match("maybe") then
    return "someday", 4
  end
  
  -- Reference/Resources
  if lower_name:match("reference") or lower_name:match("resource") then
    return "reference", 5
  end
  
  -- Default/other
  return "other", 5
end

-- State priority (lower = higher priority)
function M.get_state_priority(state)
  local priorities = {
    NEXT = 1,
    TODO = 2,
    PROJECT = 2,  -- Same as TODO
    WAITING = 3,
    SOMEDAY = 4,
    DONE = 9,
    CANCELLED = 9,
    ARCHIVED = 10,
    CLOSED = 9,
    COMPLETED = 9,
  }
  return priorities[state] or 5
end

-- Master GTD sort function - use this everywhere
function M.gtd_sort(items)
  table.sort(items, function(a, b)
    -- 1. Container hierarchy: Inbox → Areas → Projects → Someday → Other
    local _, a_container_pri = M.get_container_type(a.path, a.filename)
    local _, b_container_pri = M.get_container_type(b.path, b.filename)
    
    if a_container_pri ~= b_container_pri then
      return a_container_pri < b_container_pri
    end
    
    -- 2. Within same container: sort by filename (alphabetical)
    local a_file = (a.filename or ""):lower()
    local b_file = (b.filename or ""):lower()
    
    if a_file ~= b_file then
      return a_file < b_file
    end
    
    -- 3. Within same file: sort by state priority (NEXT first)
    local a_state_pri = M.get_state_priority(a.state)
    local b_state_pri = M.get_state_priority(b.state)
    
    if a_state_pri ~= b_state_pri then
      return a_state_pri < b_state_pri
    end
    
    -- 4. Finally: sort by title (alphabetical)
    return (a.title or ""):lower() < (b.title or ""):lower()
  end)
  
  return items
end

-- ============================================================================
-- ENHANCED SCANNING WITH PROPER SORTING
-- ============================================================================

function M.scan_gtd_files_robust(opts)
  opts = opts or {}
  local root = opts.root or vim.fn.expand("~/Documents/GTD")

  local files = vim.fn.globpath(root, "**/*.org", false, true)
  if type(files) == "string" then
    files = files ~= "" and { files } or {}
  end

  local items = {}

  for _, path in ipairs(files) do
    local filename = vim.fn.fnamemodify(path, ":t")

    -- Skip archived files
    if filename:lower():match("archive") or filename:lower():match("deleted") then
      goto continue
    end

    local lines = M.read_file(path)
    if #lines == 0 then
      goto continue
    end

    for i, line in ipairs(lines) do
      if M.is_org_heading(line) then
        local state, title = M.parse_org_heading(line)

        -- Apply actionable task filtering
        if not M.is_actionable_task(state, title, line) then
          goto continue_task
        end

        local level = M.heading_level(line) or 1
        local is_project = line:match("^%*+%s+PROJECT%s") ~= nil

        -- Find subtree end
        local h_end = i
        for j = i + 1, #lines do
          local next_level = M.heading_level(lines[j])
          if next_level and next_level <= level then
            break
          end
          h_end = j
        end

        -- Container type for sorting
        local container_type, container_priority = M.get_container_type(path, filename)
        
        -- State priority for sorting
        local state_priority = M.get_state_priority(state)

        -- Context glyph (using new glyph system)
        local context_icon = M.state_glyph(state)
        local container_icon = M.container_glyph(filename)

        local item = {
          path = path,
          lnum = i,
          h_start = i,
          h_end = h_end,
          line = line,
          state = state,
          title = title or "(No title)",
          filename = filename,
          level = level,
          is_project = is_project,
          context_icon = context_icon,
          container_icon = container_icon,
          container_type = container_type,
          container_priority = container_priority,
          state_priority = state_priority,
        }

        table.insert(items, item)

        ::continue_task::
      end
    end

    ::continue::
  end

  -- GTD HIERARCHY SORTING: Inbox → Areas → Projects, then by state, then title
  M.gtd_sort(items)

  return items
end

-- ============================================================================
-- FIXED FZF UTILITIES (no malformed bindings)
-- ============================================================================

--- Get a safe working directory for fzf-lua (handles deleted cwd case)
---@return string Valid directory path
local function get_safe_cwd()
  -- Try current cwd first
  local cwd = vim.uv.cwd()
  if cwd and vim.fn.isdirectory(cwd) == 1 then
    return cwd
  end
  -- Fallback to GTD root
  local gtd_root = vim.fn.expand("~/Documents/GTD")
  if vim.fn.isdirectory(gtd_root) == 1 then
    return gtd_root
  end
  -- Final fallback to home
  return vim.fn.expand("~")
end

--- Ensure we have a valid cwd before calling fzf-lua
--- CRITICAL: fzf-lua checks cwd BEFORE applying options, so we must fix it globally
function M.ensure_valid_cwd()
  local cwd = vim.uv.cwd()
  if not cwd or vim.fn.isdirectory(cwd) ~= 1 then
    local safe_cwd = get_safe_cwd()
    vim.fn.chdir(safe_cwd)
    return safe_cwd
  end
  return cwd
end

function M.create_fzf_config(title, prompt, header)
  return {
    prompt = prompt or "Select> ",
    cwd = get_safe_cwd(),  -- CRITICAL: Explicit safe cwd to avoid ENOENT errors
    winopts = {
      height = 0.90,       -- 90% of screen height
      width = 0.95,        -- 95% of screen width
      row = 0.05,          -- Slight offset from top
      title = title or " GTD ",
      title_pos = "center",
      preview = {
        hidden = "hidden", -- No preview by default, more room for list
      },
    },
    fzf_opts = {
      ["--ansi"] = true,  -- CRITICAL: Enable ANSI colors
      ["--no-info"] = true,
      ["--tiebreak"] = "index",
      ["--header"] = header or "Enter: Open • Ctrl-E: Edit & Return",
    },
  }
end

function M.edit_and_return(item, return_function, opts)
  if not item or not item.path or not item.lnum then
    M.notify("Invalid item for editing", "ERROR")
    return
  end

  -- Open file
  local ok = pcall(function()
    vim.cmd("edit " .. vim.fn.fnameescape(item.path))
    vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
  end)

  if not ok then
    M.notify("Failed to open file: " .. item.path, "ERROR")
    return
  end

  -- Set up return mechanism
  local bufnr = vim.api.nvim_get_current_buf()
  local group_name = "GTDReturn_" .. bufnr

  pcall(vim.api.nvim_del_augroup_by_name, group_name)

  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      vim.schedule(function()
        pcall(vim.api.nvim_del_augroup_by_name, group_name)
        vim.defer_fn(function()
          if type(return_function) == "function" then
            return_function(opts)
          end
        end, 100)
      end)
    end,
  })

  M.notify("Editing. Leave buffer to return to picker.", "INFO")
end

function M.create_standard_actions(display_items, meta_items, return_function, opts)
  return {
    ["default"] = function(sel)
      if not sel or not sel[1] then
        return
      end
      local idx = vim.fn.index(display_items, sel[1]) + 1
      local item = meta_items[idx]
      if not item then
        return
      end

      pcall(function()
        vim.cmd("edit " .. vim.fn.fnameescape(item.path))
        vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      end)
    end,

    ["ctrl-e"] = function(sel)
      if not sel or not sel[1] then
        return
      end
      local idx = vim.fn.index(display_items, sel[1]) + 1
      local item = meta_items[idx]
      if not item then
        return
      end

      M.edit_and_return(item, return_function, opts)
    end,

    ["ctrl-p"] = function(sel)
      if not sel or not sel[1] then
        return
      end
      local idx = vim.fn.index(display_items, sel[1]) + 1
      local item = meta_items[idx]
      if not item then
        return
      end

      pcall(function()
        vim.cmd("split " .. vim.fn.fnameescape(item.path))
        vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      end)
    end,
  }
end

-- ============================================================================
-- ORG-MODE COMPLIANCE HELPERS
-- ============================================================================
-- These functions ensure 100% org-mode compliant output across all GTD modules.
-- Reference: https://orgmode.org/manual/
--
-- COMPLIANT STRUCTURE:
-- * STATE Title :tags:
-- SCHEDULED: <2025-12-11 Thu>
-- DEADLINE: <2025-12-15 Mon>
-- :PROPERTIES:
-- :ID:        20251211123456
-- :TASK_ID:   20251211123456
-- :ZK_LINK:   [[zk:20251211123456]]
-- :CREATED:   [2025-12-11 Thu 14:30]
-- :END:
--
-- Body content here...
-- ============================================================================

--- Format a date as org-mode timestamp with weekday
--- @param date_str string Date in YYYY-MM-DD format
--- @param include_time boolean|nil Include time component
--- @return string Formatted org date like "<2025-12-11 Thu>" or "<2025-12-11 Thu 14:30>"
function M.format_org_date(date_str, include_time)
  if not date_str or date_str == "" then return nil end
  
  local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not year then return "<" .. date_str .. ">" end
  
  local time = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
  local weekday = os.date("%a", time)
  
  if include_time then
    local hour_min = os.date("%H:%M")
    return string.format("<%s %s %s>", date_str, weekday, hour_min)
  else
    return string.format("<%s %s>", date_str, weekday)
  end
end

--- Format an inactive org timestamp (for CREATED, CLOSED, etc.)
--- @param date_str string|nil Date in YYYY-MM-DD format (nil = now)
--- @param include_time boolean|nil Include time component (default true)
--- @return string Formatted inactive timestamp like "[2025-12-11 Thu 14:30]"
function M.format_org_inactive_timestamp(date_str, include_time)
  if include_time == nil then include_time = true end
  
  local time
  if date_str then
    local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if year then
      time = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
    else
      time = os.time()
    end
  else
    time = os.time()
  end
  
  local weekday = os.date("%a", time)
  local date_part = os.date("%Y-%m-%d", time)
  
  if include_time then
    local time_part = os.date("%H:%M", time)
    return string.format("[%s %s %s]", date_part, weekday, time_part)
  else
    return string.format("[%s %s]", date_part, weekday)
  end
end

--- Generate unique task ID
--- @return string ID in format YYYYMMDDHHMMSS
function M.generate_id()
  return os.date("!%Y%m%d%H%M%S")
end

--- Build a complete, org-mode compliant task entry
--- @param opts table Task options
--- @return table Array of lines forming the complete task
function M.build_org_task(opts)
  opts = opts or {}
  
  local id = opts.id or M.generate_id()
  local state = opts.state or "TODO"
  local title = opts.title or "New Task"
  local level = opts.level or 1
  local tags = opts.tags  -- string like "tag1:tag2" or nil
  local scheduled = opts.scheduled  -- YYYY-MM-DD or nil
  local deadline = opts.deadline    -- YYYY-MM-DD or nil
  local properties = opts.properties or {}  -- additional properties table
  local body = opts.body  -- string or table of lines
  local zk_link = opts.zk_link  -- ZK ID or full link
  local zk_note_path = opts.zk_note_path  -- file path for ZK_NOTE property
  local area = opts.area  -- area name
  
  local lines = {}
  
  -- 1. HEADING with state and optional tags
  local stars = string.rep("*", level)
  local tag_suffix = ""
  if tags and tags ~= "" then
    -- Ensure proper tag format :tag1:tag2:
    local clean_tags = tags:gsub("^:*", ""):gsub(":*$", "")
    if clean_tags ~= "" then
      tag_suffix = " :" .. clean_tags .. ":"
    end
  end
  table.insert(lines, string.format("%s %s %s%s", stars, state, title, tag_suffix))
  
  -- 2. PLANNING (SCHEDULED/DEADLINE) - MUST come before PROPERTIES
  if scheduled and scheduled ~= "" then
    local formatted = M.format_org_date(scheduled)
    if formatted then
      table.insert(lines, "SCHEDULED: " .. formatted)
    end
  end
  if deadline and deadline ~= "" then
    local formatted = M.format_org_date(deadline)
    if formatted then
      table.insert(lines, "DEADLINE: " .. formatted)
    end
  end
  
  -- 3. PROPERTIES drawer
  table.insert(lines, ":PROPERTIES:")
  
  -- Standard org-mode :ID: property
  table.insert(lines, string.format(":ID:        %s", id))
  
  -- GTD-specific :TASK_ID: (same value for compatibility)
  table.insert(lines, string.format(":TASK_ID:   %s", id))
  
  -- ZK link as property (NOT as standalone ID:: line)
  if zk_link and zk_link ~= "" then
    -- If it's just an ID, format as [[zk:ID]]
    if zk_link:match("^%d+$") or zk_link:match("^%d+[a-z]*$") then
      table.insert(lines, string.format(":ZK_LINK:   [[zk:%s]]", zk_link))
    else
      -- Already formatted
      table.insert(lines, string.format(":ZK_LINK:   %s", zk_link))
    end
  end
  
  -- ZK note file path
  if zk_note_path and zk_note_path ~= "" then
    local zk_filename = vim.fn.fnamemodify(zk_note_path, ":t")
    table.insert(lines, string.format(":ZK_NOTE:   [[file:%s][%s]]", zk_note_path, zk_filename))
  end
  
  -- Area property
  if area and area ~= "" then
    table.insert(lines, string.format(":AREA:      %s", area))
  end
  
  -- Created timestamp
  table.insert(lines, string.format(":CREATED:   %s", M.format_org_inactive_timestamp()))
  
  -- Additional custom properties
  for key, value in pairs(properties) do
    if value and value ~= "" then
      -- Ensure proper spacing for alignment
      local padded_key = key .. string.rep(" ", math.max(0, 8 - #key))
      table.insert(lines, string.format(":%s: %s", padded_key, value))
    end
  end
  
  table.insert(lines, ":END:")
  
  -- 4. BODY content (after PROPERTIES)
  if body then
    table.insert(lines, "")  -- Empty line before body
    if type(body) == "table" then
      for _, line in ipairs(body) do
        table.insert(lines, line)
      end
    else
      table.insert(lines, tostring(body))
    end
  end
  
  return lines
end

--- Build WAITING task with proper metadata
--- @param opts table Task options plus waiting_data
--- @return table Array of lines
function M.build_org_waiting_task(opts)
  opts = opts or {}
  local waiting_data = opts.waiting_data or {}
  
  -- Add WAITING-specific properties
  local properties = opts.properties or {}
  
  if waiting_data.waiting_for then
    properties.WAITING_FOR = waiting_data.waiting_for
  end
  if waiting_data.waiting_what then
    properties.WAITING_WHAT = waiting_data.waiting_what
  end
  if waiting_data.requested_date then
    properties.REQUESTED = waiting_data.requested_date
  end
  if waiting_data.follow_up_date then
    properties.FOLLOW_UP = waiting_data.follow_up_date
  end
  if waiting_data.context then
    properties.CONTEXT = waiting_data.context
  end
  if waiting_data.priority then
    properties.PRIORITY = waiting_data.priority
  end
  if waiting_data.notes and waiting_data.notes ~= "" then
    properties.WAITING_NOTES = waiting_data.notes
  end
  
  opts.properties = properties
  opts.state = "WAITING"
  
  -- Build body with WAITING summary
  local body_lines = {}
  if waiting_data.waiting_for then
    table.insert(body_lines, string.format("Waiting for: %s", waiting_data.waiting_for))
  end
  if waiting_data.waiting_what then
    table.insert(body_lines, string.format("Expecting: %s", waiting_data.waiting_what))
  end
  if waiting_data.requested_date and waiting_data.context then
    table.insert(body_lines, string.format("Requested: %s via %s", waiting_data.requested_date, waiting_data.context))
  end
  if waiting_data.notes and waiting_data.notes ~= "" then
    table.insert(body_lines, "")
    table.insert(body_lines, "Notes: " .. waiting_data.notes)
  end
  
  if #body_lines > 0 then
    opts.body = body_lines
  end
  
  return M.build_org_task(opts)
end

--- Build RECURRING task with proper metadata
--- @param opts table Task options plus recur_data
--- @return table Array of lines
function M.build_org_recurring_task(opts)
  opts = opts or {}
  local recur_data = opts.recur_data or {}
  
  -- Add RECURRING-specific properties
  local properties = opts.properties or {}
  
  if recur_data.frequency then
    properties.RECUR = recur_data.frequency
  end
  if recur_data.interval and recur_data.interval ~= 1 then
    properties.RECUR_INTERVAL = tostring(recur_data.interval)
  end
  if recur_data.recur_from then
    properties.RECUR_FROM = recur_data.recur_from
  end
  if recur_data.preferred_day then
    properties.RECUR_DAY = recur_data.preferred_day
  end
  properties.RECUR_CREATED = os.date("%Y-%m-%d")
  
  opts.properties = properties
  
  return M.build_org_task(opts)
end

--- Build PROJECT entry with proper metadata
--- @param opts table Project options
--- @return table Array of lines
function M.build_org_project(opts)
  opts = opts or {}
  
  local properties = opts.properties or {}
  
  -- Project-specific properties
  if opts.effort then
    properties.Effort = opts.effort
  end
  if opts.assigned then
    properties.ASSIGNED = opts.assigned
  end
  if opts.description then
    properties.DESCRIPTION = opts.description
  end
  
  opts.properties = properties
  opts.state = "PROJECT"
  opts.level = opts.level or 1
  
  -- Add progress cookie to title
  local title = opts.title or "New Project"
  if not title:match("%[%d+/%d+%]") and not title:match("%[%%]") then
    title = title .. " [/]"
  end
  opts.title = title
  
  return M.build_org_task(opts)
end

--- Find PROPERTIES drawer bounds in lines array
--- @param lines table Array of lines
--- @param start_line number Start searching from this line (1-indexed)
--- @param end_line number|nil Stop searching at this line
--- @return number|nil, number|nil props_start, props_end (1-indexed, inclusive)
function M.find_properties_drawer(lines, start_line, end_line)
  start_line = start_line or 1
  end_line = end_line or #lines
  
  local props_start, props_end = nil, nil
  
  for i = start_line, end_line do
    local line = lines[i] or ""
    if not props_start and line:match("^%s*:PROPERTIES:%s*$") then
      props_start = i
    elseif props_start and line:match("^%s*:END:%s*$") then
      props_end = i
      break
    end
  end
  
  return props_start, props_end
end

--- Get property value from PROPERTIES drawer
--- @param lines table Array of lines
--- @param key string Property key (case-insensitive)
--- @param start_line number|nil Start of search range
--- @param end_line number|nil End of search range
--- @return string|nil Property value or nil if not found
function M.get_property(lines, key, start_line, end_line)
  local props_start, props_end = M.find_properties_drawer(lines, start_line, end_line)
  if not props_start or not props_end then return nil end
  
  local key_upper = key:upper()
  for i = props_start + 1, props_end - 1 do
    local line = lines[i] or ""
    local k, v = line:match("^%s*:([^:]+):%s*(.*)%s*$")
    if k and k:upper() == key_upper then
      return v
    end
  end
  
  return nil
end

--- Set or update property in PROPERTIES drawer
--- Creates drawer if it doesn't exist
--- @param lines table Array of lines (modified in place)
--- @param key string Property key
--- @param value string Property value
--- @param heading_line number Line number of the heading (1-indexed)
--- @return table Modified lines array
function M.set_property(lines, key, value, heading_line)
  if not lines or not key or not heading_line then return lines end
  
  -- Find subtree end
  local level = M.heading_level(lines[heading_line])
  if not level then return lines end
  
  local subtree_end = heading_line
  for i = heading_line + 1, #lines do
    local line_level = M.heading_level(lines[i])
    if line_level and line_level <= level then
      break
    end
    subtree_end = i
  end
  
  -- Find existing PROPERTIES drawer
  local props_start, props_end = M.find_properties_drawer(lines, heading_line, subtree_end)
  
  if not props_start then
    -- No drawer exists - create one after heading (and after SCHEDULED/DEADLINE if present)
    local insert_after = heading_line
    
    -- Skip past SCHEDULED/DEADLINE lines
    for i = heading_line + 1, math.min(heading_line + 3, #lines) do
      local line = lines[i] or ""
      if line:match("^SCHEDULED:") or line:match("^DEADLINE:") then
        insert_after = i
      elseif line:match("^%s*$") or line:match("^%*") or line:match("^:") then
        break
      end
    end
    
    -- Insert new drawer
    table.insert(lines, insert_after + 1, ":PROPERTIES:")
    table.insert(lines, insert_after + 2, string.format(":%s: %s", key, value))
    table.insert(lines, insert_after + 3, ":END:")
    
    return lines
  end
  
  -- Drawer exists - update or add property
  local found = false
  local key_upper = key:upper()
  
  for i = props_start + 1, props_end - 1 do
    local line = lines[i] or ""
    local k = line:match("^%s*:([^:]+):")
    if k and k:upper() == key_upper then
      lines[i] = string.format(":%s: %s", key, value)
      found = true
      break
    end
  end
  
  if not found then
    -- Add new property before :END:
    table.insert(lines, props_end, string.format(":%s: %s", key, value))
  end
  
  return lines
end

--- Ensure PROPERTIES drawer exists and has required fields
--- @param lines table Array of lines (modified in place)
--- @param heading_line number Line of the heading
--- @param required_props table|nil Table of {key = value} for required properties
--- @return table, number, number Modified lines, props_start, props_end
function M.ensure_properties_drawer(lines, heading_line, required_props)
  required_props = required_props or {}
  
  -- First ensure drawer exists with ID
  local id = required_props.ID or required_props.TASK_ID or M.generate_id()
  lines = M.set_property(lines, "ID", id, heading_line)
  
  -- Find the drawer we just created/ensured
  local level = M.heading_level(lines[heading_line])
  local subtree_end = heading_line
  for i = heading_line + 1, #lines do
    local line_level = M.heading_level(lines[i])
    if line_level and line_level <= level then break end
    subtree_end = i
  end
  
  local props_start, props_end = M.find_properties_drawer(lines, heading_line, subtree_end)
  
  -- Add all required properties
  for key, value in pairs(required_props) do
    if key ~= "ID" then  -- Already added ID
      lines = M.set_property(lines, key, value, heading_line)
    end
  end
  
  -- Refresh drawer bounds
  props_start, props_end = M.find_properties_drawer(lines, heading_line, subtree_end + 10)
  
  return lines, props_start, props_end
end

--- Remove standalone ID:: lines (legacy format cleanup)
--- @param lines table Array of lines (modified in place)
--- @param start_line number|nil Start of range
--- @param end_line number|nil End of range  
--- @return table Modified lines, number of lines removed
function M.remove_legacy_id_lines(lines, start_line, end_line)
  start_line = start_line or 1
  end_line = end_line or #lines
  
  local removed = 0
  local i = end_line
  
  while i >= start_line do
    local line = lines[i] or ""
    if line:match("^ID::%s*%[%[zk:") then
      table.remove(lines, i)
      removed = removed + 1
    end
    i = i - 1
  end
  
  return lines, removed
end

--- Validate org-mode compliance of a task
--- @param lines table Array of lines
--- @param heading_line number Line of the heading
--- @return boolean, table is_valid, list of issues
function M.validate_org_task(lines, heading_line)
  local issues = {}
  
  if not lines or not heading_line or heading_line > #lines then
    return false, {"Invalid input"}
  end
  
  local heading = lines[heading_line]
  if not M.is_org_heading(heading) then
    return false, {"Line is not an org heading"}
  end
  
  -- Find subtree bounds
  local level = M.heading_level(heading)
  local subtree_end = heading_line
  for i = heading_line + 1, #lines do
    local line_level = M.heading_level(lines[i])
    if line_level and line_level <= level then break end
    subtree_end = i
  end
  
  -- Check for PROPERTIES drawer
  local props_start, props_end = M.find_properties_drawer(lines, heading_line, subtree_end)
  if not props_start then
    table.insert(issues, "Missing PROPERTIES drawer")
  else
    -- Check for required properties
    local has_id = M.get_property(lines, "ID", heading_line, subtree_end)
    local has_task_id = M.get_property(lines, "TASK_ID", heading_line, subtree_end)
    
    if not has_id and not has_task_id then
      table.insert(issues, "Missing :ID: or :TASK_ID: property")
    end
    
    -- Check for SCHEDULED/DEADLINE placement (should be before PROPERTIES)
    for i = props_start + 1, props_end - 1 do
      local line = lines[i] or ""
      if line:match("^SCHEDULED:") or line:match("^DEADLINE:") then
        table.insert(issues, "SCHEDULED/DEADLINE inside PROPERTIES drawer (should be before)")
      end
    end
  end
  
  -- Check for legacy ID:: lines
  for i = heading_line, subtree_end do
    local line = lines[i] or ""
    if line:match("^ID::%s*%[%[zk:") then
      table.insert(issues, string.format("Legacy ID:: line at line %d (should be :ZK_LINK: property)", i))
    end
  end
  
  -- Check SCHEDULED/DEADLINE format
  for i = heading_line + 1, math.min(heading_line + 5, subtree_end) do
    local line = lines[i] or ""
    if line:match("^SCHEDULED:") and not line:match("^SCHEDULED:%s*<[^>]+>") then
      table.insert(issues, "SCHEDULED has invalid format (should use angle brackets)")
    end
    if line:match("^DEADLINE:") and not line:match("^DEADLINE:%s*<[^>]+>") then
      table.insert(issues, "DEADLINE has invalid format (should use angle brackets)")
    end
  end
  
  return #issues == 0, issues
end

-- ============================================================================
-- SMART DATE PARSING
-- ============================================================================
-- Accepts flexible date input formats for faster entry:
--   "25"      → YYYY-MM-25 (current year and month, day 25)
--   "12-25"   → YYYY-12-25 (current year, month 12, day 25)
--   "+4d"     → today + 4 days
--   "+4m"     → today + 4 months
--   "+2w"     → today + 2 weeks
--   "2025-12-25" → passed through as-is (full date)
--   ""        → returns nil (skip/empty)
-- ============================================================================

--- Parse a flexible date input string into YYYY-MM-DD format
--- @param input string User input (e.g., "25", "12-25", "+4d", "+2w", "+3m", "2025-12-25")
--- @param base_date string|nil Optional base date for relative calculations (default: today)
--- @return string|nil Parsed date in YYYY-MM-DD format, or nil if empty/invalid
function M.parse_smart_date(input, base_date)
  -- Handle nil or empty
  if not input or input == "" then
    return nil
  end
  
  -- Trim whitespace
  input = input:gsub("^%s+", ""):gsub("%s+$", "")
  if input == "" then
    return nil
  end
  
  -- Get base date components (default to today)
  local base_time
  if base_date and base_date:match("^%d%d%d%d%-%d%d%-%d%d$") then
    local y, m, d = base_date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    base_time = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
  else
    base_time = os.time()
  end
  
  local base = os.date("*t", base_time)
  
  -- Pattern 1: Full date YYYY-MM-DD (pass through)
  if input:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return input
  end
  
  -- Pattern 2: Relative days "+Nd" or "+N" (days assumed if no suffix)
  local rel_days = input:match("^%+(%d+)d?$")
  if rel_days then
    local days = tonumber(rel_days)
    local new_time = base_time + (days * 24 * 60 * 60)
    return os.date("%Y-%m-%d", new_time)
  end
  
  -- Pattern 3: Relative weeks "+Nw"
  local rel_weeks = input:match("^%+(%d+)w$")
  if rel_weeks then
    local weeks = tonumber(rel_weeks)
    local new_time = base_time + (weeks * 7 * 24 * 60 * 60)
    return os.date("%Y-%m-%d", new_time)
  end
  
  -- Pattern 4: Relative months "+Nm"
  local rel_months = input:match("^%+(%d+)m$")
  if rel_months then
    local months = tonumber(rel_months)
    local new_month = base.month + months
    local new_year = base.year
    
    -- Handle month overflow
    while new_month > 12 do
      new_month = new_month - 12
      new_year = new_year + 1
    end
    
    -- Clamp day to valid range for target month
    local max_day = ({ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[new_month]
    -- Leap year check for February
    if new_month == 2 and ((new_year % 4 == 0 and new_year % 100 ~= 0) or (new_year % 400 == 0)) then
      max_day = 29
    end
    local new_day = math.min(base.day, max_day)
    
    return string.format("%04d-%02d-%02d", new_year, new_month, new_day)
  end
  
  -- Pattern 5: Month-day "MM-DD" (current year)
  local mm, dd = input:match("^(%d%d?)%-(%d%d?)$")
  if mm and dd then
    local month = tonumber(mm)
    local day = tonumber(dd)
    if month >= 1 and month <= 12 and day >= 1 and day <= 31 then
      return string.format("%04d-%02d-%02d", base.year, month, day)
    end
  end
  
  -- Pattern 6: Day only "D" or "DD" (current year and month)
  local day_only = input:match("^(%d%d?)$")
  if day_only then
    local day = tonumber(day_only)
    if day >= 1 and day <= 31 then
      return string.format("%04d-%02d-%02d", base.year, base.month, day)
    end
  end
  
  -- Invalid format - return nil
  return nil
end

--- Parse date with fallback to default
--- @param input string User input
--- @param default string Default date if input is empty
--- @param base_date string|nil Base for relative calculations
--- @return string Parsed date or default
function M.parse_smart_date_or_default(input, default, base_date)
  local parsed = M.parse_smart_date(input, base_date)
  return parsed or default
end

--- Validate if input could be a smart date (for UI hints)
--- @param input string User input
--- @return boolean True if input looks like a valid smart date format
function M.is_smart_date_format(input)
  if not input or input == "" then return true end  -- Empty is valid (optional)
  
  input = input:gsub("^%s+", ""):gsub("%s+$", "")
  
  -- Full date
  if input:match("^%d%d%d%d%-%d%d%-%d%d$") then return true end
  -- Relative days
  if input:match("^%+%d+d?$") then return true end
  -- Relative weeks
  if input:match("^%+%d+w$") then return true end
  -- Relative months
  if input:match("^%+%d+m$") then return true end
  -- Month-day
  if input:match("^%d%d?%-%d%d?$") then return true end
  -- Day only
  if input:match("^%d%d?$") then return true end
  
  return false
end

--- Generate help text for smart date formats
--- @return string Help text explaining accepted formats
function M.smart_date_help()
  return "Formats: 25 | 12-25 | +4d | +2w | +3m | 2025-12-25"
end

-- ============================================================================
-- ZK LINK HANDLING
-- ============================================================================

--- Extract ZK note path from a subtree
--- Looks for :ZK_NOTE: property with [[file:...]] format
--- Also handles :ZK_LINK: property with [[zk:ID]] format
--- @param item table Item with path, h_start, h_end fields
--- @return string|nil Path to ZK note file, or nil if not found
function M.extract_zk_path(item)
  if not item or not item.path then return nil end
  
  local lines = M.read_file(item.path)
  if not lines or #lines == 0 then return nil end
  
  local h_start = item.h_start or item.lnum or 1
  local h_end = item.h_end or #lines
  
  -- Look for ZK_NOTE property with file link: [[file:/path/to/note.md]]
  for i = h_start, math.min(h_end, #lines) do
    local line = lines[i] or ""
    
    -- Check :ZK_NOTE: property
    local zk_file = line:match(":ZK_NOTE:%s*%[%[file:([^%]]+)%]%]")
    if zk_file then
      return M.xp(zk_file)
    end
    
    -- Also check Notes: body link
    local notes_file = line:match("^%s*Notes:%s*%[%[file:([^%]]+)%]%]")
    if notes_file then
      return M.xp(notes_file)
    end
  end
  
  -- Look for ZK_LINK or ID:: with [[zk:ID]] format and try to resolve
  for i = h_start, math.min(h_end, #lines) do
    local line = lines[i] or ""
    
    -- Check :ZK_LINK: property or ID:: breadcrumb
    local zk_id = line:match(":ZK_LINK:%s*%[%[zk:([^%]]+)%]%]")
      or line:match("^ID::%s*%[%[zk:([^%]]+)%]%]")
    
    if zk_id then
      -- Try to resolve ZK ID to actual file path
      local resolved = M.resolve_zk_id(zk_id)
      if resolved then
        return resolved
      end
    end
  end
  
  return nil
end

--- Resolve a ZK ID to an actual file path
--- Searches common ZK note directories for matching files
--- @param zk_id string Zettelkasten ID (e.g., "20251211115618")
--- @return string|nil Path to found note file, or nil if not found
function M.resolve_zk_id(zk_id)
  if not zk_id or zk_id == "" then return nil end
  
  -- Common ZK note directories to search
  local search_dirs = {
    vim.fn.expand("~/Documents/Notes"),
    vim.fn.expand("~/Documents/Notes/Projects"),
    vim.fn.expand("~/Documents/Notes/Zettelkasten"),
    vim.fn.expand("~/Documents/Notes/Daily"),
  }
  
  -- Search for files starting with the ZK ID
  for _, dir in ipairs(search_dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      -- Look for ID-*.md pattern
      local pattern = dir .. "/" .. zk_id .. "*.md"
      local matches = vim.fn.glob(pattern, false, true)
      if matches and #matches > 0 then
        return matches[1]
      end
      
      -- Also search subdirectories one level deep
      local subdirs = vim.fn.glob(dir .. "/*", false, true)
      for _, subdir in ipairs(subdirs) do
        if vim.fn.isdirectory(subdir) == 1 then
          pattern = subdir .. "/" .. zk_id .. "*.md"
          matches = vim.fn.glob(pattern, false, true)
          if matches and #matches > 0 then
            return matches[1]
          end
        end
      end
    end
  end
  
  return nil
end

--- Open ZK note linked to an item
--- @param item table Item with path, h_start, h_end fields
--- @return boolean True if note was opened, false otherwise
function M.open_zk_link(item)
  local zk_path = M.extract_zk_path(item)
  
  if zk_path and zk_path ~= "" then
    if vim.fn.filereadable(zk_path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(zk_path))
      M.notify("Opened ZK note: " .. vim.fn.fnamemodify(zk_path, ":t"), "INFO")
      return true
    else
      M.notify("ZK note not found on disk: " .. zk_path, "WARN")
      return false
    end
  else
    M.notify("No ZK note linked to this item", "INFO")
    return false
  end
end

--- Check if a link is a ZK ID reference (not a file path)
--- @param link string Link content from [[...]]
--- @return boolean, string|nil True if ZK link, and the ID if so
function M.is_zk_link(link)
  if not link then return false, nil end
  
  -- Check for zk: scheme
  local zk_id = link:match("^zk:(%d+[a-z]?[a-z]?)$")
  if zk_id then
    return true, zk_id
  end
  
  return false, nil
end

return M