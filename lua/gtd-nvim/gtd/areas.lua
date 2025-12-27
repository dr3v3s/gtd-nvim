-- ============================================================================
-- GTD-NVIM AREAS MODULE
-- ============================================================================
-- Areas of Responsibility management
-- - Browse areas and their files
-- - Create new areas (with suggested numbering)
-- - Rename areas (moves directory)
-- - Archive areas
--
-- Directory naming: NN-Name (e.g., 10-Personal, 20-Household)
-- Display shows full directory name for consistency
--
-- @module gtd-nvim.gtd.areas
-- @version 2.1.0
-- @updated 2025-12-24
-- @requires shared (>= 1.1.0)
-- ============================================================================

local M = {}

M._VERSION = "2.1.0"
M._UPDATED = "2025-12-24"

-- Load shared utilities
local shared = require("gtd-nvim.gtd.shared")
local g = shared.glyphs

-- ============================================================================
-- HELPERS
-- ============================================================================

local function xp(p) return vim.fn.expand(p) end

--- Get areas root directory
---@return string Path to Areas folder
function M.get_root()
  local gtd_home = shared.gtd_home()
  return gtd_home .. "/Areas"
end

--- Get archive root directory
---@return string Path to Archive/Areas folder
function M.get_archive_root()
  local gtd_home = shared.gtd_home()
  return gtd_home .. "/Archive/Areas"
end

--- Parse area directory name into components
---@param dirname string Directory name like "10-Personal"
---@return number|nil sort_num, string name
local function parse_area_dirname(dirname)
  local num, name = dirname:match("^(%d+)%-(.+)$")
  if num and name then
    return tonumber(num), name
  end
  -- No number prefix - sort at end
  return 999, dirname
end

--- Get next suggested number for new area
---@return number Next available number (rounded to next 10)
local function get_next_area_number()
  local areas = M.get_areas()
  local max_num = 0
  
  for _, area in ipairs(areas) do
    local num = parse_area_dirname(area.name)
    if num and num < 900 then  -- Ignore 999 (unprefixed)
      max_num = math.max(max_num, num)
    end
  end
  
  -- Round up to next 10
  return math.ceil((max_num + 1) / 10) * 10
end

-- ============================================================================
-- AREAS ACCESS (filesystem-based)
-- ============================================================================

--- Get all areas from filesystem
--- Returns full directory names for consistency
---@return table[] Array of area definitions
function M.get_areas()
  local config_areas = shared.get_areas() or {}
  local areas = {}
  
  local areas_root = M.get_root()
  
  -- Build lookup from config for metadata (icons, colors)
  local config_lookup = {}
  for _, area in ipairs(config_areas) do
    if area.name then
      config_lookup[area.name:lower()] = area
    end
    if area.dir then
      config_lookup[area.dir:lower()] = area
    end
  end
  
  -- Scan filesystem for actual areas
  if vim.fn.isdirectory(areas_root) == 1 then
    local dirs = vim.fn.glob(areas_root .. "/*", false, true)
    for _, dir in ipairs(dirs) do
      if vim.fn.isdirectory(dir) == 1 then
        local dirname = vim.fn.fnamemodify(dir, ":t")
        local sort_num, display_name = parse_area_dirname(dirname)
        local cfg = config_lookup[dirname:lower()] or config_lookup[display_name:lower()]
        
        table.insert(areas, {
          id = dirname:lower():gsub("[^%w]", "-"),
          name = dirname,  -- Full directory name for consistency
          display_name = display_name,  -- Parsed name without number
          sort_num = sort_num,
          icon = cfg and cfg.icon or g.container.areas or "󰕰",
          color = cfg and cfg.color or nil,
          dir = dir,
        })
      end
    end
    -- Sort by number prefix
    table.sort(areas, function(a, b) 
      if a.sort_num ~= b.sort_num then
        return a.sort_num < b.sort_num
      end
      return a.name < b.name
    end)
  end
  
  return areas
end

-- Legacy compatibility
setmetatable(M, {
  __index = function(_, key)
    if key == "areas" then
      return M.get_areas()
    end
    return nil
  end
})

--- Get area by name (matches full dirname)
---@param name string Area name (full dirname like "10-Personal")
---@return table|nil Area or nil
function M.get_area(name)
  if not name then return nil end
  for _, area in ipairs(M.get_areas()) do
    if area.name == name or area.display_name == name then
      return area
    end
  end
  return nil
end

--- Get area by ID
---@param id string Area ID
---@return table|nil Area or nil
function M.get_area_by_id(id)
  if not id then return nil end
  for _, area in ipairs(M.get_areas()) do
    if area.id == id then
      return area
    end
  end
  return nil
end

--- Get area containing a file path
---@param path string File path
---@return table|nil Area or nil
function M.get_area_for_path(path)
  if not path then return nil end
  local expanded = xp(path)
  
  for _, area in ipairs(M.get_areas()) do
    local area_dir = xp(area.dir)
    if expanded:find(area_dir, 1, true) then
      return area
    end
  end
  return nil
end

--- Get list of area names
---@return string[] List of names (full dirnames)
function M.list_names()
  local names = {}
  for _, area in ipairs(M.get_areas()) do
    table.insert(names, area.name)
  end
  return names
end

-- ============================================================================
-- AREA OPERATIONS
-- ============================================================================

--- Create a new area
---@param dirname string Full directory name (e.g., "60-Hobbies")
---@param opts table|nil { create_inbox = true }
---@return boolean success
function M.create(dirname, opts)
  opts = opts or { create_inbox = true }
  
  if not dirname or dirname == "" then
    shared.notify("Area name required", "WARN")
    return false
  end
  
  local areas_root = M.get_root()
  local area_path = areas_root .. "/" .. dirname
  
  -- Check if exists
  if vim.fn.isdirectory(area_path) == 1 then
    shared.notify("Area already exists: " .. dirname, "WARN")
    return false
  end
  
  -- Create directory
  local ok = vim.fn.mkdir(area_path, "p")
  if ok ~= 1 then
    shared.notify("Failed to create area directory", "ERROR")
    return false
  end
  
  -- Create Inbox.org if requested
  if opts.create_inbox then
    local inbox_path = area_path .. "/Inbox.org"
    local _, display_name = parse_area_dirname(dirname)
    local inbox_content = string.format(
      "#+TITLE: %s Inbox\n#+FILETAGS: :%s:\n\n",
      display_name, display_name:lower():gsub("[^%w]", "-")
    )
    
    local f = io.open(inbox_path, "w")
    if f then
      f:write(inbox_content)
      f:close()
    end
  end
  
  shared.notify("󰕰 Created area: " .. dirname, "INFO")
  return true
end

--- Rename an area (moves directory)
---@param old_dirname string Current directory name
---@param new_dirname string New directory name
---@return boolean success
function M.rename(old_dirname, new_dirname)
  if not old_dirname or not new_dirname or new_dirname == "" then
    shared.notify("Both old and new names required", "WARN")
    return false
  end
  
  if old_dirname == new_dirname then
    return true  -- No change needed
  end
  
  local areas_root = M.get_root()
  local old_path = areas_root .. "/" .. old_dirname
  local new_path = areas_root .. "/" .. new_dirname
  
  -- Check source exists
  if vim.fn.isdirectory(old_path) ~= 1 then
    shared.notify("Area not found: " .. old_dirname, "WARN")
    return false
  end
  
  -- Check destination doesn't exist
  if vim.fn.isdirectory(new_path) == 1 then
    shared.notify("Area already exists: " .. new_dirname, "WARN")
    return false
  end
  
  -- Close any buffers in the old area (to avoid issues)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local bufname = vim.api.nvim_buf_get_name(buf)
    if bufname:find(old_path, 1, true) then
      if vim.api.nvim_buf_is_loaded(buf) then
        -- Save if modified
        if vim.bo[buf].modified then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("write")
          end)
        end
        -- Unload buffer
        vim.api.nvim_buf_delete(buf, { force = false })
      end
    end
  end
  
  -- Rename (move) directory
  local ok = vim.fn.rename(old_path, new_path)
  if ok ~= 0 then
    shared.notify("Failed to rename area", "ERROR")
    return false
  end
  
  shared.notify("󰕰 Renamed: " .. old_dirname .. " → " .. new_dirname, "INFO")
  return true
end

--- Archive an area (move to Archive/Areas/)
---@param dirname string Area directory name to archive
---@return boolean success
function M.archive(dirname)
  if not dirname then
    shared.notify("Area name required", "WARN")
    return false
  end
  
  local areas_root = M.get_root()
  local archive_root = M.get_archive_root()
  local source_path = areas_root .. "/" .. dirname
  local archive_path = archive_root .. "/" .. dirname
  
  -- Check source exists
  if vim.fn.isdirectory(source_path) ~= 1 then
    shared.notify("Area not found: " .. dirname, "WARN")
    return false
  end
  
  -- Ensure archive directory exists
  if vim.fn.isdirectory(archive_root) ~= 1 then
    vim.fn.mkdir(archive_root, "p")
  end
  
  -- Handle collision - add timestamp
  if vim.fn.isdirectory(archive_path) == 1 then
    archive_path = archive_path .. "_" .. os.date("%Y%m%d")
  end
  
  -- Close any buffers in the area
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local bufname = vim.api.nvim_buf_get_name(buf)
    if bufname:find(source_path, 1, true) then
      if vim.api.nvim_buf_is_loaded(buf) then
        if vim.bo[buf].modified then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("write")
          end)
        end
        vim.api.nvim_buf_delete(buf, { force = false })
      end
    end
  end
  
  -- Move to archive
  local ok = vim.fn.rename(source_path, archive_path)
  if ok ~= 0 then
    shared.notify("Failed to archive area", "ERROR")
    return false
  end
  
  shared.notify("󰀼 Archived: " .. dirname, "INFO")
  return true
end

-- ============================================================================
-- PICKERS
-- ============================================================================

--- Pick an area with fzf-lua
---@param callback function Called with selected area
---@param opts table|nil { prompt, title }
function M.pick(callback, opts)
  opts = opts or {}
  local areas = M.get_areas()
  
  if #areas == 0 then
    shared.notify("No areas found", "WARN")
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    shared.notify("fzf-lua not available", "WARN")
    return
  end
  
  local display = {}
  local lookup = {}
  
  for _, area in ipairs(areas) do
    local icon = area.icon or g.container.areas or "󰕰"
    local label = string.format("%s %s", icon, area.name)
    table.insert(display, label)
    lookup[label] = area
  end
  
  fzf.fzf_exec(display, {
    prompt = opts.prompt or "Area ❯ ",
    winopts = {
      height = 0.40,
      width = 0.50,
      title = opts.title or " " .. (g.container.areas or "󰕰") .. " Select Area ",
      title_pos = "center",
    },
    fzf_opts = { ["--no-info"] = true },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local area = lookup[sel[1]]
        if callback and area then
          callback(area)
        end
      end,
    },
  })
end

-- ============================================================================
-- MANAGE AREAS (main interface)
-- ============================================================================

--- Main area management interface
function M.manage()
  local areas = M.get_areas()
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    shared.notify("fzf-lua not available", "WARN")
    return
  end
  
  local display = {}
  local lookup = {}
  
  for _, area in ipairs(areas) do
    if area.name and area.dir then
      local icon = area.icon or g.container.areas or "󰕰"
      local dir = xp(area.dir)
      local file_count = 0
      
      if vim.fn.isdirectory(dir) == 1 then
        local files = vim.fn.glob(dir .. "/*.org", false, true)
        file_count = #files
      end
      
      -- Show full directory name for consistency
      local label = string.format("%s %s (%d files)", icon, area.name, file_count)
      table.insert(display, label)
      lookup[label] = area
    end
  end
  
  -- Add "create new" option at top
  local next_num = get_next_area_number()
  local create_label = string.format("  󰐕 Create new area (suggested: %d-...)", next_num)
  table.insert(display, 1, "━━━ Actions ━━━")
  table.insert(display, 2, create_label)
  
  local header = "Enter=browse │ C-a=add │ C-n=new project │ C-e=rename │ C-x=archive │ C-d=delete"
  
  fzf.fzf_exec(display, {
    prompt = "Areas ❯ ",
    winopts = {
      height = 0.60,
      width = 0.80,
      title = " " .. (g.container.areas or "󰕰") .. " Manage Areas ",
      title_pos = "center",
    },
    fzf_opts = {
      ["--no-info"] = true,
      ["--header"] = header,
      ["--header-first"] = true,
    },
    actions = {
      -- Browse files in area
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        
        -- Handle "Create new area" action
        if sel[1]:match("Create new area") then
          vim.schedule(function() M._prompt_create_area() end)
          return
        end
        
        -- Skip headers
        if sel[1]:match("^━━━") then return end
        
        local area = lookup[sel[1]]
        if area and area.dir then
          local dir = xp(area.dir)
          if vim.fn.isdirectory(dir) == 1 then
            -- Open files picker with back navigation using fzf_actions.nested()
            vim.schedule(function()
              local fzf_actions = require("gtd-nvim.capture.ui.fzf_actions")
              fzf.files(fzf_actions.nested(M.manage, { 
                cwd = dir,
                winopts = {
                  title = " " .. (area.icon or "󰕰") .. " " .. area.name .. " ",
                  title_pos = "center",
                },
                fzf_opts = {
                  ["--header"] = "Enter=open",
                },
              }))
            end)
          else
            shared.notify("Directory not found: " .. (dir or "nil"), "WARN")
          end
        end
      end,
      
      -- Create new area
      ["ctrl-a"] = function(_)
        vim.schedule(function() M._prompt_create_area() end)
      end,
      
      -- New project in area
      ["ctrl-n"] = function(sel)
        if not sel or not sel[1] or sel[1]:match("^━━━") or sel[1]:match("Create new") then 
          return 
        end
        
        local area = lookup[sel[1]]
        if area and area.dir then
          vim.schedule(function()
            local projects = require("gtd-nvim.gtd.projects")
            if projects and projects.create then
              projects.create({ area = area })
            end
          end)
        end
      end,
      
      -- Rename area
      ["ctrl-e"] = function(sel)
        if not sel or not sel[1] or sel[1]:match("^━━━") or sel[1]:match("Create new") then 
          return 
        end
        
        local area = lookup[sel[1]]
        if area then
          vim.schedule(function() M._prompt_rename_area(area) end)
        end
      end,
      
      -- Archive area (ctrl-x)
      ["ctrl-x"] = function(sel)
        if not sel or not sel[1] or sel[1]:match("^━━━") or sel[1]:match("Create new") then 
          return 
        end
        
        local area = lookup[sel[1]]
        if area then
          vim.schedule(function() M._prompt_archive_area(area) end)
        end
      end,
      
      -- Delete/Archive area (ctrl-d) - same as ctrl-x for safety
      ["ctrl-d"] = function(sel)
        if not sel or not sel[1] or sel[1]:match("^━━━") or sel[1]:match("Create new") then 
          return 
        end
        
        local area = lookup[sel[1]]
        if area then
          vim.schedule(function() M._prompt_archive_area(area) end)
        end
      end,
    },
  })
end

--- Prompt to create new area
function M._prompt_create_area()
  local next_num = get_next_area_number()
  local default_prefix = string.format("%d-", next_num)
  
  vim.ui.input({ 
    prompt = "󰐕 New area directory name: ",
    default = default_prefix,
  }, function(dirname)
    if not dirname or dirname == "" or dirname == default_prefix then return end
    
    -- Validate format (warn if no number prefix but allow it)
    if not dirname:match("^%d+%-") then
      vim.ui.select({ "Yes - Create anyway", "No - Let me fix the name" }, {
        prompt = "Name doesn't follow 'NN-Name' pattern. Continue?",
      }, function(choice)
        if choice and choice:match("^Yes") then
          M._finish_create_area(dirname)
        else
          vim.schedule(function() M._prompt_create_area() end)
        end
      end)
    else
      M._finish_create_area(dirname)
    end
  end)
end

--- Finish area creation (ask about Inbox)
---@param dirname string Directory name
function M._finish_create_area(dirname)
  vim.ui.select({ "Yes - Create Inbox.org", "No - Empty folder" }, {
    prompt = "Create Inbox.org in area?",
  }, function(choice)
    local create_inbox = choice and choice:match("^Yes")
    
    if M.create(dirname, { create_inbox = create_inbox }) then
      vim.schedule(function() M.manage() end)
    end
  end)
end

--- Prompt to rename area
---@param area table Area to rename
function M._prompt_rename_area(area)
  vim.ui.input({ 
    prompt = "󰏫 Rename directory to: ",
    default = area.name,
  }, function(new_dirname)
    if not new_dirname or new_dirname == "" then return end
    
    if M.rename(area.name, new_dirname) then
      vim.schedule(function() M.manage() end)
    end
  end)
end

--- Prompt to archive area (with confirmation)
---@param area table Area to archive
function M._prompt_archive_area(area)
  local dir = xp(area.dir)
  local files = vim.fn.glob(dir .. "/*.org", false, true)
  local file_count = #files
  
  local msg = string.format("Archive '%s' (%d files)?", area.name, file_count)
  
  vim.ui.select({ "Yes - Archive it", "No - Cancel" }, {
    prompt = msg,
  }, function(choice)
    if choice and choice:match("^Yes") then
      if M.archive(area.name) then
        vim.schedule(function() M.manage() end)
      end
    end
  end)
end

-- ============================================================================
-- BROWSE (backwards compatibility)
-- ============================================================================

--- Browse areas (alias for manage)
function M.browse()
  M.manage()
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(opts)
  if opts and opts.areas then
    shared.notify("areas.setup() is deprecated. Areas are scanned from filesystem.", "WARN")
  end
end

return M
