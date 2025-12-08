-- Fixed shared utilities with proper sorting, filtering, and fzf config

local M = {}

-- ============================================================================
-- GLYPH SYSTEM (Nerd Font icons for consistent UI)
-- ============================================================================
-- Uses Nerd Fonts: https://www.nerdfonts.com/cheat-sheet
-- Requires a Nerd Font patched terminal font

M.glyphs = {
  -- GTD States (task status)
  state = {
    NEXT     = "",  -- nf-fa-bolt (lightning/action)
    TODO     = "",  -- nf-fa-circle_o (open circle)
    WAITING  = "",  -- nf-fa-clock_o (clock/waiting)
    SOMEDAY  = "",  -- nf-fa-star_o (star/dream)
    DONE     = "",  -- nf-fa-check (checkmark)
    PROJECT  = "",  -- nf-oct-project (project)
    CANCELLED = "",  -- nf-fa-times (x mark)
  },
  
  -- GTD Workflow phases
  phase = {
    capture  = "",  -- nf-fa-plus_circle (add/capture)
    clarify  = "",  -- nf-fa-filter (filter/clarify)
    organize = "",  -- nf-fa-sitemap (organize)
    reflect  = "",  -- nf-fa-eye (review/reflect)
    engage   = "",  -- nf-fa-play (do/engage)
  },
  
  -- GTD Containers/Locations
  container = {
    inbox     = "",  -- nf-fa-inbox (inbox tray)
    projects  = "",  -- nf-fa-folder_open (folder)
    areas     = "",  -- nf-fa-th_large (grid/areas)
    someday   = "",  -- nf-fa-archive (archive/someday)
    reference = "",  -- nf-fa-book (reference)
    trash     = "",  -- nf-fa-trash (trash)
    calendar  = "",  -- nf-fa-calendar (calendar)
    recurring = "",  -- nf-fa-refresh (recurring/repeat)
  },
  
  -- Review phases
  review = {
    clear    = "",  -- nf-fa-eraser (clear/clean)
    current  = "",  -- nf-fa-refresh (current/sync)
    creative = "",  -- nf-fa-lightbulb_o (creative/idea)
    complete = "",  -- nf-fa-check_circle (complete)
  },
  
  -- UI Elements
  ui = {
    arrow_right = "",  -- nf-fa-chevron_right
    arrow_down  = "",  -- nf-fa-chevron_down
    arrow_up    = "",  -- nf-fa-chevron_up
    bullet      = "",  -- nf-fa-circle (filled)
    empty       = "",  -- nf-fa-circle_o (empty)
    check       = "",  -- nf-fa-check
    cross       = "",  -- nf-fa-times
    warning     = "",  -- nf-fa-exclamation_triangle
    info        = "",  -- nf-fa-info_circle
    question    = "",  -- nf-fa-question_circle
    edit        = "",  -- nf-fa-pencil
    search      = "",  -- nf-fa-search
    link        = "",  -- nf-fa-link
    tag         = "",  -- nf-fa-tag
    clock       = "",  -- nf-fa-clock_o
    user        = "",  -- nf-fa-user
    note        = "",  -- nf-fa-sticky_note_o
    list        = "",  -- nf-fa-list
    menu        = "",  -- nf-fa-bars
    home        = "",  -- nf-fa-home
    cog         = "",  -- nf-fa-cog (settings)
    rocket      = "",  -- nf-fa-rocket (brainstorm)
  },
  
  -- Priority indicators
  priority = {
    high   = "",  -- nf-fa-arrow_up
    medium = "",  -- nf-fa-minus
    low    = "",  -- nf-fa-arrow_down
  },
  
  -- Checklist states
  checkbox = {
    checked   = "",  -- nf-fa-check_square
    unchecked = "",  -- nf-fa-square_o
    partial   = "",  -- nf-fa-minus_square_o
  },
  
  -- File types
  file = {
    org      = "",  -- nf-fa-file_text_o
    markdown = "",  -- nf-dev-markdown
    folder   = "",  -- nf-fa-folder
    folder_open = "",  -- nf-fa-folder_open
  },
  
  -- Progress/Status
  progress = {
    pending  = "",  -- nf-fa-hourglass_start
    active   = "",  -- nf-fa-spinner
    done     = "",  -- nf-fa-check_circle
    blocked  = "",  -- nf-fa-ban
  },
}

-- Helper: Get state glyph
function M.state_glyph(state)
  return M.glyphs.state[state] or M.glyphs.ui.bullet
end

-- Helper: Get container glyph
function M.container_glyph(name)
  local lower = (name or ""):lower()
  if lower:match("inbox") then return M.glyphs.container.inbox
  elseif lower:match("project") then return M.glyphs.container.projects
  elseif lower:match("area") then return M.glyphs.container.areas
  elseif lower:match("someday") then return M.glyphs.container.someday
  elseif lower:match("recurring") then return M.glyphs.container.recurring
  elseif lower:match("calendar") then return M.glyphs.container.calendar
  elseif lower:match("archive") then return M.glyphs.container.someday
  else return M.glyphs.file.org
  end
end

-- Helper: Format task for display with glyphs
function M.format_task(item, opts)
  opts = opts or {}
  local g = M.glyphs
  
  local state_icon = g.state[item.state] or g.ui.bullet
  local container_icon = M.container_glyph(item.filename or "")
  
  if opts.with_file then
    local short_file = (item.filename or ""):gsub("%.org$", "")
    return string.format("%s %s %s │ %s", state_icon, item.title or "", container_icon, short_file)
  else
    return string.format("%s %s", state_icon, item.title or "")
  end
end

-- Helper: Format header for fzf
function M.fzf_header(opts)
  local g = M.glyphs
  opts = opts or {}
  local parts = {}
  
  table.insert(parts, "Enter:" .. g.ui.arrow_right .. "Open")
  table.insert(parts, "C-e:" .. g.ui.edit .. "Edit")
  
  if opts.clarify then
    table.insert(parts, "C-c:" .. g.phase.clarify .. "Clarify")
  end
  if opts.zettel then
    table.insert(parts, "C-z:" .. g.ui.note .. "Zettel")
  end
  if opts.back then
    table.insert(parts, "C-b:" .. g.ui.arrow_up .. "Back")
  end
  
  return table.concat(parts, " │ ")
end

-- ============================================================================
-- BASIC UTILITIES
-- ============================================================================

function M.xp(p) return vim.fn.expand(p or "") end

function M.read_file(path)
  if not path then return {} end
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
  if not line then return nil end
  local stars = line:match("^(%*+)%s")
  return stars and #stars or nil
end

function M.parse_org_heading(line)
  if not line then return nil, nil end
  local stars, rest = line:match("^(%*+)%s+(.*)")
  if not rest then return nil, nil end
  
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
    if title_lower:match("^notes?:") or 
       title_lower:match("^log:") or 
       title_lower:match("^diary:") or
       title_lower:match("^journal:") or
       title_lower:match("^research:") or
       title_lower:match("^meeting:") or
       line:match("^%*+%s+Notes?%s") then
      return false
    end
  end
  
  -- Only include actionable states or PROJECT
  if state then
    return state == "TODO" or state == "NEXT" or state == "WAITING" or 
           state == "SOMEDAY" or state == "PROJECT"
  end
  
  -- Include headings without state if they look like tasks (have clear task-like structure)
  return title and title ~= "" and not title:match("^%s*$")
end

-- ============================================================================
-- ENHANCED SCANNING WITH PROPER SORTING
-- ============================================================================

function M.scan_gtd_files_robust(opts)
  opts = opts or {}
  local root = opts.root or vim.fn.expand("~/Documents/GTD")
  
  local files = vim.fn.globpath(root, "**/*.org", false, true)
  if type(files) == "string" then
    files = files ~= "" and {files} or {}
  end
  
  local items = {}
  
  for _, path in ipairs(files) do
    local filename = vim.fn.fnamemodify(path, ":t")
    
    -- Skip archived files
    if filename:lower():match("archive") or filename:lower():match("deleted") then
      goto continue
    end
    
    local lines = M.read_file(path)
    if #lines == 0 then goto continue end
    
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
          if next_level and next_level <= level then break end
          h_end = j
        end
        
        -- Priority-based sorting (lower number = higher priority)
        local priority = 9
        if state == "NEXT" then priority = 1
        elseif state == "TODO" then priority = 2
        elseif state == "WAITING" then priority = 3
        elseif state == "SOMEDAY" then priority = 4
        elseif is_project then priority = 2
        elseif filename:lower():match("inbox") then priority = 1
        end
        
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
          priority = priority,
        }
        
        table.insert(items, item)
        
        ::continue_task::
      end
    end
    
    ::continue::
  end
  
  -- PROPER SORTING: Priority first, then filename, then title
  table.sort(items, function(a, b)
    if a.priority ~= b.priority then 
      return a.priority < b.priority 
    end
    if a.filename ~= b.filename then 
      return a.filename < b.filename 
    end
    return a.title < b.title
  end)
  
  return items
end

-- ============================================================================
-- FIXED FZF UTILITIES (no malformed bindings)
-- ============================================================================

function M.create_fzf_config(title, prompt, header)
  return {
    prompt = prompt or "Select> ",
    winopts = {
      height = 0.80,
      width = 0.90,
      title = title or " GTD ",
      title_pos = "center",
    },
    fzf_opts = {
      ["--no-info"] = true,
      ["--tiebreak"] = "index",
      ["--header"] = header or "Enter: Open • Ctrl-E: Edit & Return",
      -- Removed malformed bindings that were causing fzf errors
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
  vim.api.nvim_create_autocmd({"BufLeave", "WinLeave"}, {
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
      if not sel or not sel[1] then return end
      local idx = vim.fn.index(display_items, sel[1]) + 1
      local item = meta_items[idx]
      if not item then return end
      
      pcall(function()
        vim.cmd("edit " .. vim.fn.fnameescape(item.path))
        vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      end)
    end,
    
    ["ctrl-e"] = function(sel)
      if not sel or not sel[1] then return end
      local idx = vim.fn.index(display_items, sel[1]) + 1
      local item = meta_items[idx]
      if not item then return end
      
      M.edit_and_return(item, return_function, opts)
    end,
    
    ["ctrl-p"] = function(sel)
      if not sel or not sel[1] then return end
      local idx = vim.fn.index(display_items, sel[1]) + 1
      local item = meta_items[idx]
      if not item then return end
      
      pcall(function()
        vim.cmd("split " .. vim.fn.fnameescape(item.path))
        vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
      end)
    end,
  }
end

return M