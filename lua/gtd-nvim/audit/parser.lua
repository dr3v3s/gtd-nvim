-- ~/.config/nvim/lua/utils/gtd-audit/parser.lua
-- Strict org-mode parser for GTD files

local M = {}

-- Parse a single org file
function M.parse_file(filepath)
  local lines = vim.fn.readfile(filepath)
  
  local result = {
    success = true,
    error = nil,
    data = {
      filepath = filepath,
      title = nil,
      headings = {},
      properties = {},  -- File-level properties
    },
    stats = {
      total_headings = 0,
      todo_count = 0,
      done_count = 0,
      projects = 0,
      errors = 0,
      warnings = 0,
    },
  }
  
  local current_heading = nil
  local in_properties = false
  local properties_start_line = nil
  
  for lnum, line in ipairs(lines) do
    -- File-level metadata
    if line:match("^#%+TITLE:%s*(.+)") then
      result.data.title = line:match("^#%+TITLE:%s*(.+)")
    end
    
    -- Heading detection
    local stars, todo_kw, title = line:match("^(%*+)%s+([A-Z]+)%s+(.+)")
    if stars then
      -- Close previous heading
      if current_heading and in_properties then
        table.insert(current_heading.issues, {
          type = "error",
          line = lnum,
          message = "Unclosed PROPERTIES drawer",
        })
        in_properties = false
      end
      
      -- Create new heading
      current_heading = {
        level = #stars,
        line = lnum,
        todo_keyword = todo_kw,
        title = title,
        raw = line,
        tags = {},
        properties = {},
        scheduled = nil,
        deadline = nil,
        scheduled_lines = {},  -- Track all SCHEDULED occurrences
        deadline_lines = {},   -- Track all DEADLINE occurrences
        properties_drawers = {},  -- Track PROPERTIES drawer occurrences
        issues = {},
      }
      
      -- Extract tags from title
      local title_no_tags, tags_str = title:match("^(.-)%s+(:.+:)%s*$")
      if tags_str then
        current_heading.title = title_no_tags
        for tag in tags_str:gmatch(":([^:]+)") do
          table.insert(current_heading.tags, tag)
        end
      end
      
      table.insert(result.data.headings, current_heading)
      result.stats.total_headings = result.stats.total_headings + 1
      
      -- Count todos
      if todo_kw == "DONE" or todo_kw == "CANCELLED" then
        result.stats.done_count = result.stats.done_count + 1
      else
        result.stats.todo_count = result.stats.todo_count + 1
      end
      
      if todo_kw == "PROJECT" then
        result.stats.projects = result.stats.projects + 1
      end
    elseif line:match("^%*+%s+(.+)") and not stars then
      -- Heading without TODO keyword
      local level_stars, heading_title = line:match("^(%*+)%s+(.+)")
      if level_stars then
        if current_heading and in_properties then
          table.insert(current_heading.issues, {
            type = "error",
            line = lnum,
            message = "Unclosed PROPERTIES drawer",
          })
          in_properties = false
        end
        
        current_heading = {
          level = #level_stars,
          line = lnum,
          todo_keyword = nil,
          title = heading_title,
          raw = line,
          tags = {},
          properties = {},
          scheduled = nil,
          deadline = nil,
          scheduled_lines = {},
          deadline_lines = {},
          properties_drawers = {},
          issues = {},
        }
        
        -- Extract tags
        local title_no_tags, tags_str = heading_title:match("^(.-)%s+(:.+:)%s*$")
        if tags_str then
          current_heading.title = title_no_tags
          for tag in tags_str:gmatch(":([^:]+)") do
            table.insert(current_heading.tags, tag)
          end
        end
        
        table.insert(result.data.headings, current_heading)
        result.stats.total_headings = result.stats.total_headings + 1
      end
    end
    
    if current_heading then
      -- PROPERTIES drawer
      if line:match("^%s*:PROPERTIES:%s*$") then
        if in_properties then
          table.insert(current_heading.issues, {
            type = "error",
            line = lnum,
            message = "Nested PROPERTIES drawer detected",
          })
        end
        in_properties = true
        properties_start_line = lnum
        table.insert(current_heading.properties_drawers, lnum)
      elseif line:match("^%s*:END:%s*$") and in_properties then
        in_properties = false
        properties_start_line = nil
      elseif in_properties then
        -- Property inside drawer
        local key, value = line:match("^%s*:([^:]+):%s*(.*)$")
        if key then
          if current_heading.properties[key] then
            table.insert(current_heading.issues, {
              type = "error",
              line = lnum,
              message = string.format("Duplicate property: %s", key),
            })
          end
          current_heading.properties[key] = {
            value = value,
            line = lnum,
          }
        end
      else
        -- Not in properties drawer - check for scheduling outside
        local sched_date = line:match("^SCHEDULED:%s*(<.+>)")
        if sched_date then
          table.insert(current_heading.scheduled_lines, lnum)
          if not current_heading.scheduled then
            current_heading.scheduled = sched_date
          end
        end
        
        local dead_date = line:match("^DEADLINE:%s*(<.+>)")
        if dead_date then
          table.insert(current_heading.deadline_lines, lnum)
          if not current_heading.deadline then
            current_heading.deadline = dead_date
          end
        end
        
        -- Check for malformed ID links outside properties
        if line:match("^ID::%s*%[%[zk:") then
          table.insert(current_heading.issues, {
            type = "error",
            line = lnum,
            message = "ID link outside PROPERTIES drawer (should be inside :ID: property)",
          })
        end
      end
    end
  end
  
  -- Close any open properties at EOF
  if in_properties and current_heading then
    table.insert(current_heading.issues, {
      type = "error",
      line = #lines,
      message = "Unclosed PROPERTIES drawer at EOF",
    })
  end
  
  return result
end

return M
