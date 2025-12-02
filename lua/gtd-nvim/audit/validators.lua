-- ~/.config/nvim/lua/utils/gtd-audit/validators.lua
-- Validation rules for org-mode GTD files

local M = {}

-- Validate parsed org data
function M.validate(data, config)
  local issues = {}
  
  for _, heading in ipairs(data.headings) do
    -- Add heading-specific issues from parser
    for _, issue in ipairs(heading.issues or {}) do
      table.insert(issues, vim.tbl_extend("force", issue, {
        heading_line = heading.line,
        heading_title = heading.title,
      }))
    end
    
    -- Check for duplicate SCHEDULED entries
    if #heading.scheduled_lines > 1 then
      table.insert(issues, {
        type = "error",
        line = heading.scheduled_lines[2],
        heading_line = heading.line,
        heading_title = heading.title,
        message = string.format("Duplicate SCHEDULED (found at lines: %s)", 
          table.concat(heading.scheduled_lines, ", ")),
        fixable = true,
      })
    end
    
    -- Check for duplicate DEADLINE entries
    if #heading.deadline_lines > 1 then
      table.insert(issues, {
        type = "error",
        line = heading.deadline_lines[2],
        heading_line = heading.line,
        heading_title = heading.title,
        message = string.format("Duplicate DEADLINE (found at lines: %s)", 
          table.concat(heading.deadline_lines, ", ")),
        fixable = true,
      })
    end
    
    -- Check for multiple PROPERTIES drawers
    if #heading.properties_drawers > 1 then
      table.insert(issues, {
        type = "error",
        line = heading.properties_drawers[2],
        heading_line = heading.line,
        heading_title = heading.title,
        message = string.format("Multiple PROPERTIES drawers (found at lines: %s)", 
          table.concat(heading.properties_drawers, ", ")),
        fixable = true,
      })
    end
    
    -- Validate TODO keywords
    if heading.todo_keyword then
      local valid_keywords = vim.tbl_extend("force", 
        config.active_keywords, 
        config.done_keywords,
        {"PROJECT", "RECURRING"}  -- Special GTD keywords
      )
      
      if not vim.tbl_contains(valid_keywords, heading.todo_keyword) then
        table.insert(issues, {
          type = "warning",
          line = heading.line,
          heading_line = heading.line,
          heading_title = heading.title,
          message = string.format("Unknown TODO keyword: %s (valid: %s)", 
            heading.todo_keyword, 
            table.concat(valid_keywords, ", ")),
          fixable = false,
        })
      end
    end
    
    -- GTD-specific validations
    if config.gtd_mode then
      M.validate_gtd_rules(heading, issues, config)
    end
    
    -- Strict org-mode validations
    if config.strict_mode then
      M.validate_strict_orgmode(heading, issues, config)
    end
  end
  
  return issues
end

-- GTD-specific validation rules
function M.validate_gtd_rules(heading, issues, config)
  local kw = heading.todo_keyword
  
  -- PROJECT items should have subtasks or [0/0] progress
  if kw == "PROJECT" then
    if not heading.title:match("%[%d+/%d+%]") then
      table.insert(issues, {
        type = "warning",
        line = heading.line,
        heading_line = heading.line,
        heading_title = heading.title,
        message = "PROJECT missing progress tracker [n/m]",
        fixable = false,
      })
    end
    
    -- Check for required properties
    local req_props = config.required_properties.PROJECT or {}
    for _, prop in ipairs(req_props) do
      if not heading.properties[prop] then
        table.insert(issues, {
          type = "warning",
          line = heading.line,
          heading_line = heading.line,
          heading_title = heading.title,
          message = string.format("PROJECT missing required property: %s", prop),
          fixable = false,
        })
      end
    end
  end
  
  -- NEXT items should have SCHEDULED or DEADLINE
  if kw == "NEXT" then
    if not heading.scheduled and not heading.deadline then
      table.insert(issues, {
        type = "info",
        line = heading.line,
        heading_line = heading.line,
        heading_title = heading.title,
        message = "NEXT item without SCHEDULED or DEADLINE",
        fixable = false,
      })
    end
  end
  
  -- WAIT items should have some follow-up context
  if kw == "WAIT" then
    if not heading.scheduled and not heading.properties.WAITING_FOR then
      table.insert(issues, {
        type = "info",
        line = heading.line,
        heading_line = heading.line,
        heading_title = heading.title,
        message = "WAIT item should have SCHEDULED (follow-up date) or :WAITING_FOR: property",
        fixable = false,
      })
    end
  end
  
  -- RECURRING tasks should have repeater in schedule
  if kw == "RECURRING" or heading.title:match("%[Recurring%]") or heading.title:match("%[.*weekly.*%]") then
    if heading.scheduled and not heading.scheduled:match("[+%.]+%d+[dwmy]") then
      table.insert(issues, {
        type = "warning",
        line = heading.line,
        heading_line = heading.line,
        heading_title = heading.title,
        message = "RECURRING item missing repeater pattern (++Xd, .+Xw, etc)",
        fixable = false,
      })
    end
  end
end

-- Strict org-mode syntax validation
function M.validate_strict_orgmode(heading, issues, config)
  -- Check for SCHEDULED/DEADLINE in properties when they should be outside
  -- (org-mode spec: scheduling goes AFTER the heading, BEFORE properties drawer)
  if heading.properties.SCHEDULED then
    table.insert(issues, {
      type = "error",
      line = heading.properties.SCHEDULED.line,
      heading_line = heading.line,
      heading_title = heading.title,
      message = "SCHEDULED should not be inside PROPERTIES drawer (move above it)",
      fixable = true,
    })
  end
  
  if heading.properties.DEADLINE then
    table.insert(issues, {
      type = "error",
      line = heading.properties.DEADLINE.line,
      heading_line = heading.line,
      heading_title = heading.title,
      message = "DEADLINE should not be inside PROPERTIES drawer (move above it)",
      fixable = true,
    })
  end
  
  -- Validate property drawer format
  if #heading.properties_drawers > 0 then
    -- Properties should come after heading and scheduling
    -- (This is validated by checking if SCHEDULED appears after PROPERTIES in file)
  end
  
  -- Check for proper tag format
  for _, tag in ipairs(heading.tags) do
    if tag:match("%s") then
      table.insert(issues, {
        type = "error",
        line = heading.line,
        heading_line = heading.line,
        heading_title = heading.title,
        message = string.format("Tag contains whitespace: '%s' (tags must be single words)", tag),
        fixable = false,
      })
    end
    
    if tag:match("[^%w_@]") then
      table.insert(issues, {
        type = "warning",
        line = heading.line,
        heading_line = heading.line,
        heading_title = heading.title,
        message = string.format("Tag contains special characters: '%s' (should be alphanumeric, _, or @)", tag),
        fixable = false,
      })
    end
  end
end

return M
