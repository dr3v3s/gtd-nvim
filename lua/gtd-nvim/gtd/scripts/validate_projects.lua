-- ============================================================================
-- GTD PROJECT VALIDATION SCRIPT
-- ============================================================================
-- Scans all .org files under GTD directory for nested PROJECT headings.
-- A PROJECT must ALWAYS be at level 1 (* PROJECT) in its own file.
--
-- @module gtd-nvim.gtd.scripts.validate_projects
-- @version 1.0.0
-- @updated 2025-12-27
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-27"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local function get_gtd_home()
  local shared_ok, shared = pcall(require, "gtd-nvim.gtd.shared")
  if shared_ok and shared.gtd_home then
    return shared.gtd_home()
  end
  return vim.fn.expand("~/Documents/GTD")
end

-- ============================================================================
-- SCANNING
-- ============================================================================

--- Scan a single file for nested PROJECT headings
---@param filepath string Path to .org file
---@return table|nil violations Array of { line, level, title } or nil if no violations
local function scan_file(filepath)
  local lines = vim.fn.readfile(filepath)
  if not lines then return nil end
  
  local violations = {}
  
  for i, line in ipairs(lines) do
    -- Match ** PROJECT, *** PROJECT, etc. (level 2+)
    local stars, title = line:match("^(%*%*+) PROJECT (.+)")
    if stars then
      local level = #stars
      -- Clean title (remove progress indicators and tags)
      title = title:gsub("%s*%[%d+/%d+%]%s*$", "")
      title = title:gsub("%s*:.-:%s*$", "")
      title = vim.trim(title)
      
      table.insert(violations, {
        line = i,
        level = level,
        title = title,
        raw = line,
      })
    end
  end
  
  return #violations > 0 and violations or nil
end

--- Scan all .org files in GTD directory
---@param gtd_dir string|nil GTD directory (defaults to ~/Documents/GTD)
---@return table results { file_path = { violations... }, ... }
function M.scan_all(gtd_dir)
  gtd_dir = gtd_dir or get_gtd_home()
  
  -- Find all .org files
  local files = vim.fn.glob(gtd_dir .. "/**/*.org", false, true)
  
  local results = {}
  local total_violations = 0
  
  for _, filepath in ipairs(files) do
    local violations = scan_file(filepath)
    if violations then
      results[filepath] = violations
      total_violations = total_violations + #violations
    end
  end
  
  return results, total_violations
end

--- Print scan results
---@param results table Scan results from scan_all()
---@param total number Total violation count
function M.print_results(results, total)
  if total == 0 then
    vim.notify("✅ No nested PROJECT headings found. All projects are correctly at level 1.", vim.log.levels.INFO)
    return
  end
  
  local lines = {
    "⚠️  NESTED PROJECT VIOLATIONS FOUND",
    "=====================================",
    "",
    "A PROJECT must be at level 1 (* PROJECT) in its own .org file.",
    "The following files have nested projects that should be extracted:",
    "",
  }
  
  for filepath, violations in pairs(results) do
    local rel_path = filepath:gsub(get_gtd_home() .. "/", "")
    table.insert(lines, "📁 " .. rel_path)
    
    for _, v in ipairs(violations) do
      local level_str = string.rep("*", v.level)
      table.insert(lines, string.format("   Line %d: %s PROJECT %s", v.line, level_str, v.title))
    end
    table.insert(lines, "")
  end
  
  table.insert(lines, string.format("Total: %d nested project(s) in %d file(s)", total, vim.tbl_count(results)))
  table.insert(lines, "")
  table.insert(lines, "Run :GtdMigrateProjects to extract these to separate files.")
  
  -- Show in a floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  
  local width = 80
  local height = math.min(#lines + 2, 30)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " GTD Project Validation ",
    title_pos = "center",
  })
  
  -- Close on q or Esc
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
end

--- Run validation and show results
function M.validate()
  local results, total = M.scan_all()
  M.print_results(results, total)
  return results, total
end

-- ============================================================================
-- COMMANDS
-- ============================================================================

function M.setup_commands()
  vim.api.nvim_create_user_command("GtdValidateProjects", function()
    M.validate()
  end, { desc = "Validate GTD projects are at level 1" })
end

return M
