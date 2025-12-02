-- ~/.config/nvim/lua/gtd/projects.lua
-- GTD Projects (Org) – create, open, search, ZK integration (fzf-lua)
-- ENHANCED: Convert task to project feature
-- - Prompts for Title, Description, Defer (SCHEDULED), Due (DEADLINE)
-- - NEW: optional Area-of-Focus selection (uses gtd.areas + ~/Documents/GTD/Areas)
-- - NEW: Convert task at cursor to project with metadata preservation
-- - Seeds :PROPERTIES: with ID, Effort, ASSIGNED, ZK_NOTE (and optional :DESCRIPTION:)
-- - fzf-lua pickers for projects & ZK links (now across Areas)
-- - Open org [[file:...]] links under cursor
-- - Sync backlinks into the ZK note

local M = {}

-- ------------------------------------------------------------
-- Config
-- ------------------------------------------------------------
local cfg = {
  projects_dir     = "~/Documents/GTD/Projects",
  zk_project_root  = "~/Documents/Notes/Projects",
  default_effort   = "2:00",
  default_assigned = "",
  areas_root       = "~/Documents/GTD/Areas", -- new, used as fallback if gtd.areas is absent
}

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------
local function xp(p) return vim.fn.expand(p or "") end
local function ensure_dir(p) local e = xp(p); vim.fn.mkdir(e, "p"); return e end
local function file_exists(p) return vim.fn.filereadable(xp(p)) == 1 end
local function readfile(p) if not file_exists(p) then return {} end return vim.fn.readfile(xp(p)) end
local function writefile(p, L) ensure_dir(vim.fn.fnamemodify(xp(p), ":h")); vim.fn.writefile(L, xp(p)) end
local function have_fzf() return pcall(require, "fzf-lua") end

local function slugify(title)
  title = tostring(title or "")
  local s = title:gsub("[/%\\%:%*%?%\"%<%>%|]", "-")
  s = s:gsub("%s+", "-")
  s = s:gsub("^%-+", ""):gsub("%-+$", "")
  return (#s > 0) and s or ("project-" .. os.date("%Y%m%d%H%M%S"))
end

local function gen_id() return os.date("%Y%m%d%H%M%S") end

-- Small prompt helpers
local function input_nonempty(opts, cb)
  vim.ui.input(opts, function(s)
    if not s or s == "" then return end
    cb(s)
  end)
end

local function maybe_input(opts, cb)
  vim.ui.input(opts, function(s) cb(s or "") end)
end

local function valid_yyyy_mm_dd(s)
  if s == "" then return true end
  return s:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

local function safe_require(mod)
  local ok, m = pcall(require, mod)
  if ok then return m end
  return nil
end

-- ------------------------------------------------------------
-- Areas integration
-- ------------------------------------------------------------

-- Prefer gtd.areas if available, otherwise scan filesystem.
-- Returns a list of { label = "...", dir = "/full/path" }
local function get_area_dirs()
  local results = {}

  -- 1) From gtd.areas, if present
  local areas_mod = safe_require("gtd.areas")
  if areas_mod then
    local list = nil
    if type(areas_mod.get_areas) == "function" then
      list = areas_mod.get_areas()
    elseif type(areas_mod.areas) == "table" then
      list = areas_mod.areas
    end

    if type(list) == "table" then
      for _, a in ipairs(list) do
        if type(a) == "table" then
          local dir = a.dir or a.path
          if dir then
            local full = xp(dir)
            if vim.fn.isdirectory(full) == 1 then
              local label = a.label or a.name or vim.fn.fnamemodify(full, ":t")
              table.insert(results, { label = label, dir = full })
            end
          end
        end
      end
    end
  end

  -- 2) Fallback: scan cfg.areas_root/* as Area dirs
  local root = xp(cfg.areas_root)
  if vim.fn.isdirectory(root) == 1 then
    local dirs = vim.fn.glob(root .. "/*", false, true)
    for _, d in ipairs(dirs) do
      if vim.fn.isdirectory(d) == 1 then
        local label = vim.fn.fnamemodify(d, ":t")
        table.insert(results, { label = label, dir = d })
      end
    end
  end

  -- Deduplicate on dir
  local seen, out = {}, {}
  for _, a in ipairs(results) do
    if not seen[a.dir] then
      seen[a.dir] = true
      table.insert(out, a)
    end
  end

  return out
end

-- All project directories: legacy Projects dir + all Areas dirs
local function get_all_project_dirs()
  local dirs = {}
  local projects_root = xp(cfg.projects_dir)
  if vim.fn.isdirectory(projects_root) == 1 then
    table.insert(dirs, projects_root)
  end

  for _, a in ipairs(get_area_dirs()) do
    table.insert(dirs, a.dir)
  end

  -- Dedup
  local seen, out = {}, {}
  for _, d in ipairs(dirs) do
    if vim.fn.isdirectory(d) == 1 and not seen[d] then
      seen[d] = true
      table.insert(out, d)
    end
  end
  return out
end

-- Helper to list all project .org files across all dirs
local function get_all_project_files()
  local files = {}
  for _, d in ipairs(get_all_project_dirs()) do
    local globbed = vim.fn.glob(d .. "/*.org", false, true)
    for _, f in ipairs(globbed) do
      table.insert(files, f)
    end
  end
  return files
end

-- Area picker for project creation (optional; default is Projects root)
local function pick_area_dir(cb)
  local dirs = {}
  local labels = {}

  local projects_root = xp(cfg.projects_dir)
  table.insert(labels, "No Area (Projects root)")
  table.insert(dirs, projects_root)

  for _, a in ipairs(get_area_dirs()) do
    table.insert(labels, ("Area: %s"):format(a.label))
    table.insert(dirs, a.dir)
  end

  if #labels == 1 then
    -- No Areas defined; just use Projects root
    cb(dirs[1])
    return
  end

  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if fzf_ok then
    fzf.fzf_exec(labels, {
      prompt = "Area of Focus> ",
      fzf_opts = { ["--no-info"] = true },
      winopts = { height = 0.40, width = 0.60, row = 0.25 },
      actions = {
        ["default"] = function(sel)
          local line = sel and sel[1]
          if not line then
            cb(dirs[1])
            return
          end
          local idx = vim.fn.index(labels, line) + 1
          cb(dirs[idx] or dirs[1])
        end,
      },
    })
  else
    vim.ui.select(labels, { prompt = "Area of Focus (optional)" }, function(choice)
      if not choice then
        cb(dirs[1])
        return
      end
      local idx = vim.fn.index(labels, choice) + 1
      cb(dirs[idx] or dirs[1])
    end)
  end
end

-- ------------------------------------------------------------
-- ZK notes
-- ------------------------------------------------------------
local function zk_note_for_project(title, id)
  ensure_dir(cfg.zk_project_root)
  local fname = id .. "-" .. slugify(title) .. ".md"
  local path = xp(cfg.zk_project_root .. "/" .. fname)
  if not file_exists(path) then
    writefile(path, {
      "# " .. title,
      "",
      "**Dato:** " .. os.date("%Y-%m-%d %H:%M:%S"),
      "**ID:** " .. id,
      "",
      "## Beskrivelse",
      "",
      "## Indhold",
      "",
      "## Backlinks",
      "",
    })
  end
  return path
end

-- ------------------------------------------------------------
-- Org helpers
-- ------------------------------------------------------------
local function org_find_first_heading(lines)
  for i, ln in ipairs(lines) do
    if ln:match("^%*+%s") then return i end
  end
  return nil
end

local function org_subtree_range(lines, head_idx)
  local head = lines[head_idx]; if not head then return nil end
  local stars = head:match("^(%*+)%s"); if not stars then return nil end
  local lvl = #stars
  local i = head_idx + 1
  while i <= #lines do
    local s = lines[i]:match("^(%*+)%s")
    if s and #s <= lvl then break end
    i = i + 1
  end
  return head_idx, i - 1
end

local function find_properties_drawer(lines, start_idx, end_idx)
  start_idx = start_idx or 1
  end_idx = end_idx or #lines
  local s_i, e_i = nil, nil
  for i = start_idx, end_idx do
    if not s_i and lines[i]:match("^%s*:PROPERTIES:%s*$") then
      s_i = i
    elseif s_i and lines[i]:match("^%s*:END:%s*$") then
      e_i = i
      break
    end
  end
  return s_i, e_i
end

local function ensure_properties_drawer(lines, insert_at)
  local s_i, e_i = find_properties_drawer(lines)
  if s_i and e_i then return s_i, e_i end
  insert_at = insert_at or 2
  table.insert(lines, insert_at, ":PROPERTIES:")
  table.insert(lines, insert_at + 1, ":END:")
  return insert_at, insert_at + 1
end

local function upsert_property(lines, key, value)
  local head_idx = org_find_first_heading(lines) or 1
  local _, sub_e = org_subtree_range(lines, head_idx)
  local s_i, e_i = find_properties_drawer(lines, head_idx, sub_e or #lines)
  if not s_i then
    s_i, e_i = ensure_properties_drawer(lines, head_idx + 1)
  end
  local found = false
  for i = s_i + 1, e_i - 1 do
    local k = lines[i]:match("^%s*:(%w+):")
    if k and k:upper() == key:upper() then
      lines[i] = (":%s: %s"):format(key, value)
      found = true
      break
    end
  end
  if not found then
    table.insert(lines, e_i, (":%s: %s"):format(key, value))
  end
  return lines
end

local function get_property(lines, key)
  local s_i, e_i = find_properties_drawer(lines)
  if not s_i then return nil end
  for i = s_i + 1, e_i - 1 do
    local k, v = lines[i]:match("^%s*:(%w+):%s*(.*)%s*$")
    if k and k:upper() == key:upper() then return v end
  end
  return nil
end

-- ------------------------------------------------------------
-- NEW: Task Metadata Extraction
-- ------------------------------------------------------------

-- Extract metadata from task at cursor position
local function extract_task_metadata_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  
  -- Find heading at or above cursor
  local h_start, h_end = nil, nil
  for i = cursor_line, 1, -1 do
    if lines[i] and lines[i]:match("^%*+%s") then
      h_start = i
      local stars = lines[i]:match("^(%*+)%s")
      local lvl = stars and #stars or 1
      
      -- Find end of subtree
      for j = i + 1, #lines do
        local s = lines[j] and lines[j]:match("^(%*+)%s")
        if s and #s <= lvl then break end
        h_end = j
      end
      h_end = h_end or i
      break
    end
  end
  
  if not h_start then
    return nil, "No heading found at or above cursor"
  end
  
  local heading_line = lines[h_start]
  
  -- Parse heading: state and title
  local stars, rest = heading_line:match("^(%*+)%s+(.*)")
  local state, title = nil, rest or ""
  if rest then
    local s, t = rest:match("^([A-Z]+)%s+(.*)")
    if s and t then
      state = s
      title = t
    end
  end
  
  -- Extract tags from heading
  local tags = {}
  local tag_block = heading_line:match("%s+:([%w_:%-]+):%s*$")
  if tag_block then
    for t in tag_block:gmatch("([^:]+)") do
      table.insert(tags, t)
    end
    -- Remove tags from title
    title = title:gsub("%s+:[%w_:%-]+:%s*$", "")
  end
  
  -- Find dates in subtree (SCHEDULED/DEADLINE)
  local scheduled, deadline = nil, nil
  for i = h_start, h_end do
    local line = lines[i] or ""
    local sch = line:match("SCHEDULED:%s*<([^>]+)>")
    local ddl = line:match("DEADLINE:%s*<([^>]+)>")
    if sch and not scheduled then scheduled = sch end
    if ddl and not deadline then deadline = ddl end
  end
  
  -- Extract properties
  local props_start, props_end = find_properties_drawer(lines, h_start, h_end)
  local task_id, zk_note = nil, nil
  if props_start and props_end then
    for i = props_start + 1, props_end - 1 do
      local line = lines[i] or ""
      local key, val = line:match("^%s*:(%w+):%s*(.*)%s*$")
      if key then
        if key:upper() == "TASK_ID" or key:upper() == "ID" then
          task_id = task_id or val
        elseif key:upper() == "ZK_NOTE" then
          -- Extract path from [[file:...]]
          zk_note = val:match("%[%[file:(.-)%]%]") or val:match("^file:(.+)")
        end
      end
    end
  end
  
  -- Extract body content (after properties, before next heading)
  local body_lines = {}
  local in_body = false
  for i = h_start + 1, h_end do
    local line = lines[i] or ""
    
    -- Skip properties drawer
    if line:match("^%s*:PROPERTIES:%s*$") then
      in_body = false
    elseif line:match("^%s*:END:%s*$") then
      in_body = true
      goto continue
    end
    
    -- Skip date lines
    if line:match("^%s*SCHEDULED:") or line:match("^%s*DEADLINE:") then
      goto continue
    end
    
    -- Skip ZK breadcrumb
    if line:match("^ID::%s*%[%[zk:") then
      goto continue
    end
    
    if in_body and line ~= "" then
      table.insert(body_lines, line)
    end
    
    ::continue::
  end
  
  local description = table.concat(body_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
  
  -- Detect Area from file path
  local area = nil
  local areas = get_area_dirs()
  for _, a in ipairs(areas) do
    if file_path:find(a.dir, 1, true) then
      area = a
      break
    end
  end
  
  return {
    title = title,
    state = state,
    scheduled = scheduled,
    deadline = deadline,
    tags = tags,
    description = description,
    task_id = task_id,
    zk_note = zk_note and xp(zk_note) or nil,
    area = area,
    file_path = file_path,
    h_start = h_start,
    h_end = h_end,
  }
end

-- ------------------------------------------------------------
-- NEW: Original Task Handler
-- ------------------------------------------------------------

local function handle_original_task(task_data, new_project_path)
  local options = {
    "Archive task (move to Archive.org with link)",
    "Delete task permanently",
    "Mark task DONE with link to project",
    "Move as first NEXT action in project",
    "Keep task as-is"
  }
  
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if fzf_ok then
    fzf.fzf_exec(options, {
      prompt = "Original task> ",
      fzf_opts = { ["--no-info"] = true },
      winopts = { height = 0.40, width = 0.70, row = 0.25 },
      actions = {
        ["default"] = function(sel)
          local choice = sel and sel[1]
          if not choice then return end
          
          local lines = readfile(task_data.file_path)
          local new_lines = {}
          
          if choice:match("^Archive") then
            -- Move to Archive.org with link
            local archive_path = xp("~/Documents/GTD/Archive.org")
            local task_lines = {}
            for i = task_data.h_start, task_data.h_end do
              table.insert(task_lines, lines[i])
            end
            
            -- Add conversion note to archived task
            table.insert(task_lines, "")
            table.insert(task_lines, string.format("Converted to project: [[file:%s][%s]]", 
              new_project_path, vim.fn.fnamemodify(new_project_path, ":t:r")))
            table.insert(task_lines, "Archived: " .. os.date("%Y-%m-%d %H:%M:%S"))
            
            -- Append to Archive.org
            vim.fn.writefile({""}, archive_path, "a")
            vim.fn.writefile(task_lines, archive_path, "a")
            
            -- Remove from original file
            for i = 1, task_data.h_start - 1 do
              table.insert(new_lines, lines[i])
            end
            for i = task_data.h_end + 1, #lines do
              table.insert(new_lines, lines[i])
            end
            
            writefile(task_data.file_path, new_lines)
            vim.notify("✅ Task archived to Archive.org", vim.log.levels.INFO)
            
          elseif choice:match("^Delete") then
            -- Delete permanently
            for i = 1, task_data.h_start - 1 do
              table.insert(new_lines, lines[i])
            end
            for i = task_data.h_end + 1, #lines do
              table.insert(new_lines, lines[i])
            end
            
            writefile(task_data.file_path, new_lines)
            vim.notify("🗑️ Task deleted", vim.log.levels.INFO)
            
          elseif choice:match("^Mark") then
            -- Mark DONE with link
            lines[task_data.h_start] = lines[task_data.h_start]:gsub("^(%*+)%s+%u+%s+", "%1 DONE ")
            
            -- Add link to project in body
            local insert_pos = task_data.h_end
            table.insert(lines, insert_pos, "")
            table.insert(lines, insert_pos + 1, string.format("Converted to project: [[file:%s][%s]]",
              new_project_path, vim.fn.fnamemodify(new_project_path, ":t:r")))
            
            writefile(task_data.file_path, lines)
            vim.notify("✅ Task marked DONE with project link", vim.log.levels.INFO)
            
          elseif choice:match("^Move") then
            -- Move as first NEXT action in project
            local proj_lines = readfile(new_project_path)
            local first_heading_idx = org_find_first_heading(proj_lines)
            
            if first_heading_idx then
              -- Insert after project heading
              local insert_pos = first_heading_idx + 1
              
              -- Find where to insert (after SCHEDULED/DEADLINE and properties)
              while insert_pos <= #proj_lines do
                local line = proj_lines[insert_pos] or ""
                if not line:match("^%s*SCHEDULED:") and 
                   not line:match("^%s*DEADLINE:") and
                   not line:match("^%s*:PROPERTIES:") and
                   not line:match("^%s*:") and
                   not line:match("^%s*$") then
                  break
                end
                insert_pos = insert_pos + 1
              end
              
              -- Create NEXT action from task
              table.insert(proj_lines, insert_pos, "")
              table.insert(proj_lines, insert_pos + 1, "** NEXT " .. task_data.title)
              if task_data.description and task_data.description ~= "" then
                table.insert(proj_lines, insert_pos + 2, task_data.description)
              end
              
              writefile(new_project_path, proj_lines)
            end
            
            -- Remove from original file
            for i = 1, task_data.h_start - 1 do
              table.insert(new_lines, lines[i])
            end
            for i = task_data.h_end + 1, #lines do
              table.insert(new_lines, lines[i])
            end
            
            writefile(task_data.file_path, new_lines)
            vim.notify("✅ Task moved as first NEXT action in project", vim.log.levels.INFO)
            
          else
            -- Keep as-is
            vim.notify("Task kept unchanged", vim.log.levels.INFO)
          end
        end,
      },
    })
  else
    vim.ui.select(options, { prompt = "Handle original task" }, function(choice)
      -- Same logic as above but without fzf wrapper
      vim.notify("Task handling: " .. (choice or "cancelled"), vim.log.levels.INFO)
    end)
  end
end

-- ------------------------------------------------------------
-- Project template & creation (existing code)
-- ------------------------------------------------------------
local function project_template(opts)
  local title     = opts.title
  local id        = opts.id
  local zk_path   = opts.zk_path
  local desc      = opts.description
  local scheduled = opts.scheduled  -- YYYY-MM-DD or ""
  local deadline  = opts.deadline   -- YYYY-MM-DD or ""

  local lines = {}
  table.insert(lines, "* PROJECT " .. title .. " [0/0]")

  if scheduled ~= "" then table.insert(lines, "SCHEDULED: <" .. scheduled .. ">") end
  if deadline  ~= "" then table.insert(lines, "DEADLINE:  <" .. deadline  .. ">") end

  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":ID:        " .. id)
  table.insert(lines, ":Effort:    " .. cfg.default_effort)
  table.insert(lines, ":ASSIGNED:  " .. cfg.default_assigned)
  if opts.converted_from then
    table.insert(lines, ":CONVERTED_FROM: " .. opts.converted_from)
  end
  if zk_path and zk_path ~= "" then
    table.insert(lines, ":ZK_NOTE:   [[file:" .. zk_path .. "][" .. vim.fn.fnamemodify(zk_path, ":t") .. "]]")
  end
  if desc and desc ~= "" then
    table.insert(lines, ":DESCRIPTION: " .. desc)
  end
  table.insert(lines, ":END:")
  table.insert(lines, "")
  table.insert(lines, "** NEXT Første skridt")
  return lines
end

local function open_and_seed(file, lines)
  if not file_exists(file) then
    ensure_dir(vim.fn.fnamemodify(file, ":h"))
    writefile(file, lines or { "" })
  end
  vim.cmd("edit " .. file)
end

-- Public: create a new project (prompts for everything)
function M.create()
  input_nonempty({ prompt = "Project name: " }, function(title)
    local id = gen_id()

    -- Ask description (optional)
    maybe_input({ prompt = "Description (optional): " }, function(desc)
      -- Defer / Due with defaults (empty = skip)
      local today = os.date("%Y-%m-%d")
      local plus7 = os.date("%Y-%m-%d", os.time() + 7 * 24 * 3600)

      local scheduled = ""
      local deadline  = ""

      local function finalize(area_dir)
        area_dir = area_dir or xp(cfg.projects_dir)
        ensure_dir(area_dir)
        local slug   = slugify(title)
        local file   = xp(area_dir .. "/" .. slug .. ".org")
        local zkpath = zk_note_for_project(title, id) -- always create & link
        local lines  = project_template({
          title       = title,
          id          = id,
          zk_path     = zkpath,
          description = desc,
          scheduled   = scheduled,
          deadline    = deadline,
        })
        open_and_seed(file, lines)
        vim.notify("📂 Created project: " .. title, vim.log.levels.INFO)
      end

      local function after_dates()
        -- Area-of-focus picker (optional)
        pick_area_dir(function(area_dir)
          finalize(area_dir)
        end)
      end

      -- Defer (SCHEDULED)
      maybe_input({ prompt = ("Defer (YYYY-MM-DD) [Enter=skip, e.g. %s]"):format(today) }, function(d1)
        if d1 ~= "" and not valid_yyyy_mm_dd(d1) then
          vim.notify("Invalid date, expected YYYY-MM-DD (defer skipped).", vim.log.levels.WARN)
          d1 = ""
        end
        scheduled = d1

        -- Due (DEADLINE)
        maybe_input({ prompt = ("Due   (YYYY-MM-DD) [Enter=skip, e.g. %s]"):format(plus7) }, function(d2)
          if d2 ~= "" and not valid_yyyy_mm_dd(d2) then
            vim.notify("Invalid date, expected YYYY-MM-DD (due skipped).", vim.log.levels.WARN)
            d2 = ""
          end
          deadline = d2
          after_dates()
        end)
      end)
    end)
  end)
end

-- ------------------------------------------------------------
-- NEW: Convert Task to Project (Main Feature with Enhanced UI)
-- ------------------------------------------------------------

function M.create_from_task_at_cursor()
  -- Load enhanced UI helpers
  local ui = safe_require("gtd.projects_enhanced_ui")
  if not ui then
    vim.notify("❌ Enhanced UI module not found", vim.log.levels.ERROR)
    return
  end
  
  -- Extract task metadata
  local task_data, err = extract_task_metadata_at_cursor()
  if not task_data then
    vim.notify("❌ " .. (err or "Failed to extract task metadata"), vim.log.levels.ERROR)
    return
  end
  
  -- Show extraction summary with fzf preview
  ui.show_extraction_summary(task_data, function()
    local id = gen_id()
    local total_steps = 5
    
    -- Step 1/5: Project Title
    ui.enhanced_input(1, total_steps, {
      icon = "🏷️",
      prompt = "Project Name",
      hint = "This becomes the main PROJECT heading",
      default = task_data.title,
    }, function(title)
      
      -- Step 2/5: Description
      ui.enhanced_input(2, total_steps, {
        icon = "📝",
        prompt = "Description",
        hint = "Stored in :DESCRIPTION: property (optional)",
        default = task_data.description or "",
        allow_empty = true,
      }, function(desc)
        
        local scheduled = task_data.scheduled or ""
        local deadline = task_data.deadline or ""
        
        local function finalize(area_dir)
          area_dir = area_dir or (task_data.area and task_data.area.dir) or xp(cfg.projects_dir)
          ensure_dir(area_dir)
          
          local slug = slugify(title)
          local file = xp(area_dir .. "/" .. slug .. ".org")
          
          -- Handle ZK note: reuse or create
          local zkpath = nil
          if task_data.zk_note and file_exists(task_data.zk_note) then
            zkpath = task_data.zk_note
            vim.notify("♻️  Reusing existing ZK note", vim.log.levels.INFO)
          else
            zkpath = zk_note_for_project(title, id)
            vim.notify("📝 Created new ZK note", vim.log.levels.INFO)
          end
          
          local lines = project_template({
            title = title,
            id = id,
            zk_path = zkpath,
            description = desc,
            scheduled = scheduled,
            deadline = deadline,
            converted_from = task_data.task_id,
          })
          
          open_and_seed(file, lines)
          
          -- Beautiful success notification
          ui.show_success(file, id, zkpath)
          
          -- Handle original task
          vim.defer_fn(function()
            handle_original_task(task_data, file)
          end, 800)
        end
        
        local function after_dates()
          -- Step 5/5: Area selection
          ui.enhanced_area_picker(task_data, total_steps, function(choice)
            if choice == "keep" then
              finalize(task_data.area.dir)
            elseif choice == "choose" then
              pick_area_dir(finalize)
            elseif choice == "root" then
              finalize(xp(cfg.projects_dir))
            else
              pick_area_dir(finalize)
            end
          end)
        end
        
        -- Step 3/5: Defer date
        ui.enhanced_input(3, total_steps, {
          icon = "📅",
          prompt = "Defer Date (SCHEDULED)",
          hint = "When to start (YYYY-MM-DD, or press Enter to skip)",
          example = os.date("%Y-%m-%d"),
          default = scheduled,
          allow_empty = true,
        }, function(d1)
          if d1 ~= "" and not valid_yyyy_mm_dd(d1) then
            vim.notify("⚠️  Invalid date format, skipping", vim.log.levels.WARN)
            d1 = ""
          end
          scheduled = d1
          
          -- Step 4/5: Due date
          ui.enhanced_input(4, total_steps, {
            icon = "🎯",
            prompt = "Due Date (DEADLINE)",
            hint = "When to finish (YYYY-MM-DD, or press Enter to skip)",
            example = os.date("%Y-%m-%d", os.time() + 7 * 24 * 3600),
            default = deadline,
            allow_empty = true,
          }, function(d2)
            if d2 ~= "" and not valid_yyyy_mm_dd(d2) then
              vim.notify("⚠️  Invalid date format, skipping", vim.log.levels.WARN)
              d2 = ""
            end
            deadline = d2
            after_dates()
          end)
        end)
      end)
    end)
  end)
end

-- ------------------------------------------------------------
-- Browsing/search (fzf-lua navigation across Areas)
-- ------------------------------------------------------------
function M.open_project_dir()
  -- If Areas exist, open Areas root; otherwise legacy projects dir
  local areas_root = xp(cfg.areas_root)
  local root
  if vim.fn.isdirectory(areas_root) == 1 then
    root = areas_root
  else
    root = xp(cfg.projects_dir)
  end
  vim.cmd("edit " .. root)
end

function M.find_files()
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
    return
  end

  local files = get_all_project_files()
  if #files == 0 then
    vim.notify("No project files found.", vim.log.levels.INFO)
    return
  end

  local display = {}
  for _, f in ipairs(files) do
    table.insert(display, vim.fn.fnamemodify(f, ":~:."))
  end

  fzf.fzf_exec(display, {
    prompt = "Projects> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    winopts = { height = 0.55, width = 0.80, row = 0.15 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local path = files[idx]
        if path then
          vim.cmd("edit " .. vim.fn.fnameescape(path))
        end
      end,
    },
  })
end

function M.search()
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
    return
  end

  -- Search within GTD root, but constrain ripgrep to project .org files
  local projects_root = xp(cfg.projects_dir)
  local gtd_root = vim.fn.fnamemodify(projects_root, ":h") -- usually ~/Documents/GTD

  fzf.live_grep({
    cwd = gtd_root,
    prompt = "Projects> ",
    -- Keep rg options explicit so we don't clobber user config
    rg_opts = table.concat({
      "--column",
      "--line-number",
      "--no-heading",
      "--color=always",
      "--smart-case",
      "--glob", "Projects/*.org",
      "--glob", "Areas/*/*.org",
    }, " "),
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
  })
end

-- ------------------------------------------------------------
-- Ensure metadata on current project file
-- ------------------------------------------------------------
function M.ensure_metadata_current()
  local path = xp("%:p")
  if not path:match("%.org$") then
    vim.notify("Not an org file.", vim.log.levels.WARN); return
  end
  local lines = readfile(path)
  if #lines == 0 then
    vim.notify("Empty file?", vim.log.levels.WARN); return
  end

  -- Determine project title from first heading
  local head_idx = org_find_first_heading(lines) or 1
  local head = lines[head_idx] or ""
  local title = head:gsub("^%*+%s+PROJECT%s+", "")
  if title == head then title = head:gsub("^%*+%s+", "") end
  if title == "" then title = vim.fn.fnamemodify(path, ":t:r") end

  local has_desc = get_property(lines, "DESCRIPTION") ~= nil
  local has_zk   = get_property(lines, "ZK_NOTE") ~= nil

  if has_desc or has_zk then
    vim.notify("Project metadata OK (DESCRIPTION or ZK_NOTE present).", vim.log.levels.INFO)
    return
  end

  -- Neither present → create ZK and link it
  local id = get_property(lines, "ID") or gen_id()
  local zkpath = zk_note_for_project(title, id)
  upsert_property(lines, "ID", id)
  upsert_property(lines, "ZK_NOTE",
    ("[[file:%s][%s]]"):format(zkpath, vim.fn.fnamemodify(zkpath, ":t")))
  writefile(path, lines)
  vim.notify("Added ZK_NOTE to project (no DESCRIPTION found).", vim.log.levels.INFO)
end

-- ------------------------------------------------------------
-- ZK links browser & backlink sync (fzf-lua navigation)
-- ------------------------------------------------------------
local function collect_zk_links_from_file(path)
  local res = {}
  local lines = readfile(path)
  local current_heading = nil
  for i = 1, #lines do
    local ln = lines[i]
    local h = ln:match("^%*+%s+(.*)")
    if h and h ~= "" then current_heading = h end

    local prop_link = ln:match(":ZK_NOTE:%s*%[%[file:(.-)%]%]")
    if prop_link and prop_link ~= "" then
      table.insert(res, { project = path, lnum = i, heading = current_heading or "(no heading)", zk_path = prop_link })
    end

    local body_link = ln:match("^%s*Notes:%s*%[%[file:(.-)%]%]")
    if body_link and body_link ~= "" then
      table.insert(res, { project = path, lnum = i, heading = current_heading or "(no heading)", zk_path = body_link })
    end
  end
  return res
end

local function gather_all_zk_links()
  local out = {}
  local files = get_all_project_files()
  for _, f in ipairs(files) do
    local list = collect_zk_links_from_file(f)
    for _, item in ipairs(list) do
      table.insert(out, item)
    end
  end
  return out
end

function M.list_zk_links()
  if not have_fzf() then
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
    return
  end
  
  local items = gather_all_zk_links()
  if #items == 0 then
    vim.notify("No ZK links found in project files.", vim.log.levels.INFO)
    return
  end

  local display = {}
  for _, it in ipairs(items) do
    local pfile = vim.fn.fnamemodify(it.project, ":t")
    local zfile = vim.fn.fnamemodify(it.zk_path, ":t")
    table.insert(display, pfile .. " │ " .. it.heading .. " │ " .. zfile)
  end

  local fzf = require("fzf-lua")
  fzf.fzf_exec(display, {
    prompt = "ZK Links> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    winopts = { height = 0.55, width = 0.80, row = 0.15 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local it = items[idx]
        if it and it.zk_path then vim.cmd("edit " .. xp(it.zk_path)) end
      end,
      ["ctrl-e"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local it = items[idx]
        if it then
          vim.cmd("edit " .. it.project)
          pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, 0 })
        end
      end,
      ["ctrl-s"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local it = items[idx]
        if it and it.zk_path then vim.cmd("split " .. xp(it.zk_path)) end
      end,
    },
  })
end

-- Find ZK path for subtree at/above current cursor (in org)
local function zk_path_under_cursor(bufnr, lnum)
  bufnr = bufnr or 0
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Climb up to nearest heading
  local start = lnum
  while start > 1 do
    if lines[start]:match("^%*+%s+") then break end
    start = start - 1
  end

  -- Scan downward within this subtree for either :ZK_NOTE: or Notes: line
  local level = lines[start]:match("^(%*+)")
  local subtree_prefix = level and string.rep("%*", #level) or "%*"
  local i = start
  while i <= #lines do
    local ln = lines[i]
    if i > start and ln:match("^" .. subtree_prefix .. "%s") then break end
    local prop = ln:match(":ZK_NOTE:%s*%[%[file:(.-)%]%]")
    if prop and prop ~= "" then return prop, start end
    local body = ln:match("^%s*Notes:%s*%[%[file:(.-)%]%]")
    if body and body ~= "" then return body, start end
    i = i + 1
  end
  return nil, start
end

function M.open_zk_from_cursor()
  local path = xp("%:p")
  if not path:match("%.org$") then
    vim.notify("Not an org file.", vim.log.levels.WARN); return
  end
  local zk, _ = zk_path_under_cursor(0, nil)
  if zk then
    vim.cmd("edit " .. xp(zk))
  else
    vim.notify("No ZK link found in this subtree.", vim.log.levels.INFO)
  end
end

-- Backlink support
local function ensure_backlinks_section(lines)
  for i, ln in ipairs(lines) do
    if ln:match("^##%s*Backlinks") then return i end
  end
  table.insert(lines, "")
  table.insert(lines, "## Backlinks")
  table.insert(lines, "")
  return #lines
end

local function append_backlink(zk_path, project_path, heading)
  local lines = readfile(zk_path)
  local idx = ensure_backlinks_section(lines)
  local disp_proj = vim.fn.fnamemodify(project_path, ":t")
  local disp_head = heading or "(task)"
  local link = string.format("- [[file:%s::*%s][%s → %s]]", project_path, disp_head, disp_proj, disp_head)
  table.insert(lines, link)
  writefile(zk_path, lines)
end

function M.sync_backlink_under_cursor()
  local project_path = xp("%:p")
  if not project_path:match("%.org$") then
    vim.notify("Not an org project file.", vim.log.levels.WARN); return
  end

  local zk, head_start = zk_path_under_cursor(0, nil)
  if not zk then
    vim.notify("No ZK link found in this subtree.", vim.log.levels.INFO); return
  end

  local heading = "(task)"
  local ln = vim.api.nvim_buf_get_lines(0, head_start - 1, head_start, false)[1]
  local h = ln and ln:match("^%*+%s+(.*)") or nil
  if h and h ~= "" then heading = h end

  append_backlink(xp(zk), project_path, heading)
  vim.notify("🔗 Backlink appended to ZK note.", vim.log.levels.INFO)
end

-- ------------------------------------------------------------
-- Org [[file:...]] link opener
-- ------------------------------------------------------------
local function parse_org_file_link_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local _, _, inner = line:find("%[%[(.-)%]%]")
  if not inner then return nil end
  local target = inner:match("^file:([^%]]+)%]") or inner:match("^file:(.+)$")
  if not target or target == "" then return nil end
  return xp(target)
end

function M.open_link_under_cursor()
  local path = parse_org_file_link_at_cursor()
  if path then vim.cmd("edit " .. vim.fn.fnameescape(path))
  else vim.notify("No org [[file:...]] link on this line.", vim.log.levels.INFO) end
end

function M.split_link_under_cursor()
  local path = parse_org_file_link_at_cursor()
  if path then vim.cmd("split " .. vim.fn.fnameescape(path))
  else vim.notify("No org [[file:...]] link on this line.", vim.log.levels.INFO) end
end

function M.tab_link_under_cursor()
  local path = parse_org_file_link_at_cursor()
  if path then vim.cmd("tabedit " .. vim.fn.fnameescape(path))
  else vim.notify("No org [[file:...]] link on this line.", vim.log.levels.INFO) end
end

-- ------------------------------------------------------------
-- Setup
-- ------------------------------------------------------------
function M.setup(opts)
  cfg = vim.tbl_deep_extend("force", cfg, opts or {})
  ensure_dir(cfg.projects_dir)
  ensure_dir(cfg.zk_project_root)
  -- areas_root is only used if it exists, so no mkdir here
end

return M
