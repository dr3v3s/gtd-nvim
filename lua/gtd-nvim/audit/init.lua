-- ~/.config/nvim/lua/utils/gtd-audit/init.lua
-- Strict org-mode auditor for GTD system
-- Validates syntax, checks consistency, suggests features

local M = {}

-- Lazy-load submodules
local parser = nil
local validators = nil
local insights = nil
local reports = nil

-- Configuration
M.config = {
  gtd_root = vim.fn.expand("~/Documents/GTD"),
  todo_keywords = { "INBOX", "TODO", "NEXT", "WAIT", "SOMEDAY", "DONE", "CANCELLED" },
  active_keywords = { "INBOX", "TODO", "NEXT", "WAIT", "SOMEDAY" },
  done_keywords = { "DONE", "CANCELLED" },
  
  -- Required properties for different heading types
  required_properties = {
    PROJECT = { "ID", "TASK_ID" },
    RECURRING = { "TASK_ID" },
  },
  
  -- Valid tags (set to nil to allow any)
  valid_tags = nil,  -- Will learn from your files
  
  -- Strictness levels
  strict_mode = true,  -- Enforce strict org-mode syntax
  gtd_mode = true,     -- Enforce GTD-specific rules
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Main audit function
function M.audit(file_path)
  parser = parser or require("gtd-nvim.audit.parser")
  validators = validators or require("gtd-nvim.audit.validators")
  reports = reports or require("gtd-nvim.audit.reports")
  
  local path = file_path or vim.fn.expand("%:p")
  
  if not vim.endswith(path, ".org") then
    vim.notify("Not an org file: " .. path, vim.log.levels.WARN)
    return
  end
  
  -- Parse the file
  local parse_result = parser.parse_file(path)
  if not parse_result.success then
    vim.notify("Parse failed: " .. parse_result.error, vim.log.levels.ERROR)
    return
  end
  
  -- Run validators
  local issues = validators.validate(parse_result.data, M.config)
  
  -- Show report
  reports.show(path, issues, parse_result.stats)
end

-- Audit entire GTD directory
function M.audit_all()
  parser = parser or require("gtd-nvim.audit.parser")
  validators = validators or require("gtd-nvim.audit.validators")
  reports = reports or require("gtd-nvim.audit.reports")
  
  local gtd_files = vim.fn.globpath(M.config.gtd_root, "**/*.org", false, true)
  
  -- Exclude backup files
  gtd_files = vim.tbl_filter(function(f)
    return not f:match("%.bak$")
  end, gtd_files)
  
  local all_issues = {}
  local all_stats = {}
  
  for _, file in ipairs(gtd_files) do
    local parse_result = parser.parse_file(file)
    if parse_result.success then
      local issues = validators.validate(parse_result.data, M.config)
      if #issues > 0 then
        all_issues[file] = issues
      end
      all_stats[file] = parse_result.stats
    end
  end
  
  reports.show_all(all_issues, all_stats)
end

-- Show org-mode feature insights for current file
function M.suggest_features()
  insights = insights or require("gtd-nvim.audit.insights")
  parser = parser or require("gtd-nvim.audit.parser")
  
  local path = vim.fn.expand("%:p")
  local parse_result = parser.parse_file(path)
  
  if parse_result.success then
    insights.show(parse_result.data, M.config)
  end
end

-- Quick fix for common issues
function M.quick_fix()
  local path = vim.fn.expand("%:p")
  parser = parser or require("gtd-nvim.audit.parser")
  validators = validators or require("gtd-nvim.audit.validators")
  
  local parse_result = parser.parse_file(path)
  if not parse_result.success then
    vim.notify("Cannot quick-fix: parse failed", vim.log.levels.ERROR)
    return
  end
  
  local issues = validators.validate(parse_result.data, M.config)
  
  -- Filter fixable issues
  local fixable = vim.tbl_filter(function(issue)
    return issue.fixable
  end, issues)
  
  if #fixable == 0 then
    vim.notify("No auto-fixable issues found", vim.log.levels.INFO)
    return
  end
  
  -- TODO: Implement fixes
  vim.notify(string.format("Found %d fixable issues (fix implementation pending)", #fixable), vim.log.levels.INFO)
end

-- User commands
vim.api.nvim_create_user_command("GtdAudit", function()
  M.audit()
end, { desc = "Audit current org file" })

vim.api.nvim_create_user_command("GtdAuditAll", function()
  M.audit_all()
end, { desc = "Audit all GTD org files" })

vim.api.nvim_create_user_command("GtdSuggest", function()
  M.suggest_features()
end, { desc = "Suggest org-mode features" })

vim.api.nvim_create_user_command("GtdQuickFix", function()
  M.quick_fix()
end, { desc = "Quick fix common issues" })

return M
