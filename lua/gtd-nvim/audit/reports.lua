-- ~/.config/nvim/lua/utils/gtd-audit/reports.lua
-- Display audit results

local M = {}

-- Show audit results for a single file
function M.show(filepath, issues, stats)
  local filename = vim.fn.fnamemodify(filepath, ":t")
  
  if #issues == 0 then
    vim.notify(string.format("✓ %s: No issues found", filename), vim.log.levels.INFO)
    M.show_stats(stats)
    return
  end
  
  -- Sort issues by severity
  local errors = vim.tbl_filter(function(i) return i.type == "error" end, issues)
  local warnings = vim.tbl_filter(function(i) return i.type == "warning" end, issues)
  local infos = vim.tbl_filter(function(i) return i.type == "info" end, issues)
  
  -- Create quickfix list
  local qf_items = {}
  for _, issue in ipairs(issues) do
    table.insert(qf_items, {
      filename = filepath,
      lnum = issue.line,
      col = 1,
      text = issue.message,
      type = issue.type == "error" and "E" or (issue.type == "warning" and "W" or "I"),
    })
  end
  
  vim.fn.setqflist(qf_items, 'r')
  
  -- Open quickfix window
  vim.cmd("copen")
  
  -- Summary notification
  local summary = {
    string.format("GTD Audit: %s", filename),
    string.format("Errors: %d, Warnings: %d, Info: %d", #errors, #warnings, #infos),
  }
  
  vim.notify(table.concat(summary, "\n"), vim.log.levels.WARN)
  M.show_stats(stats)
end

-- Show audit results for all files
function M.show_all(all_issues, all_stats)
  local total_errors = 0
  local total_warnings = 0
  local total_info = 0
  local files_with_issues = 0
  
  local qf_items = {}
  
  for filepath, issues in pairs(all_issues) do
    files_with_issues = files_with_issues + 1
    for _, issue in ipairs(issues) do
      if issue.type == "error" then total_errors = total_errors + 1 end
      if issue.type == "warning" then total_warnings = total_warnings + 1 end
      if issue.type == "info" then total_info = total_info + 1 end
      
      table.insert(qf_items, {
        filename = filepath,
        lnum = issue.line,
        col = 1,
        text = issue.message,
        type = issue.type == "error" and "E" or (issue.type == "warning" and "W" or "I"),
      })
    end
  end
  
  if #qf_items == 0 then
    vim.notify("✓ All GTD files validated successfully!", vim.log.levels.INFO)
    return
  end
  
  vim.fn.setqflist(qf_items, 'r')
  vim.cmd("copen")
  
  local summary = {
    string.format("GTD Audit Complete: %d files with issues", files_with_issues),
    string.format("Errors: %d, Warnings: %d, Info: %d", total_errors, total_warnings, total_info),
  }
  
  vim.notify(table.concat(summary, "\n"), vim.log.levels.WARN)
  
  -- Aggregate stats
  local total_stats = {
    total_headings = 0,
    todo_count = 0,
    done_count = 0,
    projects = 0,
  }
  
  for _, stats in pairs(all_stats) do
    total_stats.total_headings = total_stats.total_headings + stats.total_headings
    total_stats.todo_count = total_stats.todo_count + stats.todo_count
    total_stats.done_count = total_stats.done_count + stats.done_count
    total_stats.projects = total_stats.projects + stats.projects
  end
  
  M.show_stats(total_stats)
end

-- Show statistics
function M.show_stats(stats)
  local lines = {
    "═══ GTD Statistics ═══",
    string.format("Total headings: %d", stats.total_headings),
    string.format("Active tasks: %d", stats.todo_count),
    string.format("Completed: %d", stats.done_count),
    string.format("Projects: %d", stats.projects),
  }
  
  if stats.todo_count > 0 then
    local completion_rate = math.floor((stats.done_count / (stats.todo_count + stats.done_count)) * 100)
    table.insert(lines, string.format("Completion rate: %d%%", completion_rate))
  end
  
  print(table.concat(lines, "\n"))
end

-- Create a formatted report buffer (for future use)
function M.create_report_buffer(filepath, issues, stats)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  local lines = {
    "# GTD Audit Report",
    "",
    string.format("**File:** %s", filepath),
    string.format("**Date:** %s", os.date("%Y-%m-%d %H:%M")),
    "",
    "## Statistics",
    "",
  }
  
  -- Add stats
  table.insert(lines, string.format("- Total headings: %d", stats.total_headings))
  table.insert(lines, string.format("- Active tasks: %d", stats.todo_count))
  table.insert(lines, string.format("- Completed: %d", stats.done_count))
  table.insert(lines, string.format("- Projects: %d", stats.projects))
  table.insert(lines, "")
  
  if #issues > 0 then
    table.insert(lines, "## Issues Found")
    table.insert(lines, "")
    
    local errors = vim.tbl_filter(function(i) return i.type == "error" end, issues)
    local warnings = vim.tbl_filter(function(i) return i.type == "warning" end, issues)
    local infos = vim.tbl_filter(function(i) return i.type == "info" end, issues)
    
    if #errors > 0 then
      table.insert(lines, "### ❌ Errors")
      table.insert(lines, "")
      for _, issue in ipairs(errors) do
        table.insert(lines, string.format("- Line %d: %s", issue.line, issue.message))
      end
      table.insert(lines, "")
    end
    
    if #warnings > 0 then
      table.insert(lines, "### ⚠️  Warnings")
      table.insert(lines, "")
      for _, issue in ipairs(warnings) do
        table.insert(lines, string.format("- Line %d: %s", issue.line, issue.message))
      end
      table.insert(lines, "")
    end
    
    if #infos > 0 then
      table.insert(lines, "### ℹ️  Info")
      table.insert(lines, "")
      for _, issue in ipairs(infos) do
        table.insert(lines, string.format("- Line %d: %s", issue.line, issue.message))
      end
      table.insert(lines, "")
    end
  else
    table.insert(lines, "✅ **No issues found!**")
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  return buf
end

return M
