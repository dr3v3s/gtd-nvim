-- ============================================================================
-- STEP: ZK_NOTE
-- ============================================================================
-- Create and link a Zettelkasten note for the task/project.
--
-- @module gtd-nvim.capture.steps.zk_note
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

M.name = "zk_note"
M.applies_to = { "task", "project" }

-- ============================================================================
-- CONFIG
-- ============================================================================

M.defaults = {
  -- Auto-create note without asking?
  auto_create = false,
  
  -- Template to use
  template = "note",  -- or "project", "task"
  
  -- Notes directory
  notes_dir = "~/Documents/Notes/Projects",
  
  -- Prompt
  prompt = "Create linked note?",
}

-- ============================================================================
-- SHOULD RUN
-- ============================================================================

function M.should_run(obj, opts)
  opts = opts or {}
  -- Skip if already has a note
  if obj.zk_note then
    return false
  end
  return opts.skip_zk ~= true
end

-- ============================================================================
-- RUN
-- ============================================================================

function M.run(obj, opts, next_step)
  opts = vim.tbl_extend("force", M.defaults, opts or {})
  
  -- Auto-create for projects
  if opts.auto_create or obj.type == "project" then
    M._create_note(obj, opts, next_step)
    return
  end
  
  -- Ask user
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  
  if fzf_ok then
    fzf.fzf_exec({
      "󰎞 Create linked note",
      "󰜺 Skip (no note)",
    }, {
      prompt = opts.prompt .. " ❯ ",
      winopts = { height = 0.18, width = 0.4 },
      actions = {
        ["default"] = function(sel)
          if sel and sel[1] and sel[1]:match("Create") then
            vim.schedule(function()
              M._create_note(obj, opts, next_step)
            end)
          else
            vim.schedule(function() next_step(obj) end)
          end
        end,
      },
    })
  else
    -- Fallback: just skip
    next_step(obj)
  end
end

--- Create the ZK note
function M._create_note(obj, opts, next_step)
  -- Try to use existing ZK system
  local zk_ok, zk = pcall(require, "utils.zettelkasten.core")
  
  if zk_ok and zk.create_note_file then
    -- Use existing ZK system
    local paths_ok, paths = pcall(require, "gtd.paths")
    local notes_dir = opts.notes_dir
    
    if paths_ok and paths.notes_dir then
      notes_dir = paths.notes_dir .. "/Projects"
    end
    
    local note_result = zk.create_note_file({
      title = obj.title,
      dir = vim.fn.expand(notes_dir),
      template = opts.template,
      id = obj.id,
      open = false,  -- Don't open, just create
    })
    
    if note_result then
      obj.zk_note = note_result
      vim.notify("󰎞 Note created: " .. vim.fn.fnamemodify(note_result, ":t"), vim.log.levels.INFO)
    end
  else
    -- Fallback: create simple markdown note
    local notes_dir = vim.fn.expand(opts.notes_dir)
    vim.fn.mkdir(notes_dir, "p")
    
    local id = obj.id or os.date("%Y%m%d%H%M%S")
    local slug = obj.title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
    local filename = id .. "-" .. slug .. ".md"
    local filepath = notes_dir .. "/" .. filename
    
    -- Create note content
    local lines = {
      "# " .. obj.title,
      "",
      "Created: " .. os.date("%Y-%m-%d %H:%M"),
      "",
      "## Outcome",
      "",
      obj.outcome or "_What does success look like?_",
      "",
      "## Notes",
      "",
      "",
      "## References",
      "",
      "- [[GTD:" .. id .. "]]",
    }
    
    local ok = vim.fn.writefile(lines, filepath)
    if ok == 0 then
      obj.zk_note = filepath
      vim.notify("󰎞 Note created: " .. filename, vim.log.levels.INFO)
    end
  end
  
  next_step(obj)
end

return M
