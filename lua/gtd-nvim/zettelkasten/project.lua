-- ~/.config/nvim/lua/utils/zettelkasten/project.lua
-- Project management module

local M = {}

-- Get core zettelkasten module
local core = require("gtd-nvim.zettelkasten")

----------------------------------------------------------------------
-- Project Creation
----------------------------------------------------------------------
function M.new_project(title)
  local paths = core.get_paths()
  
  local function create_project(project_title)
    if not project_title or project_title == "" then
      core.notify("Project title required", vim.log.levels.WARN)
      return
    end
    
    local projects_dir = vim.fn.fnamemodify(vim.fs.joinpath(paths.notes_dir, "Projects"), ":p")
    vim.fn.mkdir(projects_dir, "p")
    
    local template_vars = {
      title = project_title,
      created = os.date(core.get_config().datetime_format),
      status = "Active",
      tags = "#project",
    }
    
    core.create_note_file({
      title = project_title,
      dir = projects_dir,
      template = "project",
      template_vars = template_vars,
      tags = "#project",
      open = true,
    })
    
    core.notify("Created project: " .. project_title)
  end
  
  if title then
    create_project(title)
  else
    vim.ui.input({ prompt = "Project title: " }, create_project)
  end
end

----------------------------------------------------------------------
-- List Projects
----------------------------------------------------------------------
function M.list_projects()
  local paths = core.get_paths()
  local projects_dir = vim.fs.joinpath(paths.notes_dir, "Projects")
  
  if vim.fn.isdirectory(projects_dir) == 0 then
    core.notify("No Projects directory found", vim.log.levels.WARN)
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    core.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  fzf.files({
    cwd = projects_dir,
    prompt = "Projects ⟩ ",
    file_icons = false,
    fzf_opts = {
      ["--header"] = "[Enter] Open | [Ctrl-T] Toggle Status | [Ctrl-A] Archive",
    },
    actions = {
      ["default"] = fzf.actions.file_edit,
      ["ctrl-t"] = function(selected)
        if selected and selected[1] then
          M.toggle_project_status(vim.fs.joinpath(projects_dir, selected[1]))
        end
      end,
      ["ctrl-a"] = function(selected)
        if selected and selected[1] then
          M.archive_project(vim.fs.joinpath(projects_dir, selected[1]))
        end
      end,
    },
  })
end

----------------------------------------------------------------------
-- Toggle Project Status
----------------------------------------------------------------------
function M.toggle_project_status(project_file)
  if vim.fn.filereadable(project_file) == 0 then
    core.notify("Project file not found", vim.log.levels.ERROR)
    return
  end
  
  local lines = vim.fn.readfile(project_file)
  local status_line_idx = nil
  local current_status = nil
  
  for i, line in ipairs(lines) do
    local status = line:match("^%*%*Status:%*%*%s*(.*)$")
    if status then
      status_line_idx = i
      current_status = status
      break
    end
  end
  
  if not status_line_idx then
    core.notify("No status line found in project", vim.log.levels.WARN)
    return
  end
  
  -- Toggle status: Active <-> On Hold <-> Completed <-> Active
  local status_cycle = {
    Active = "On Hold",
    ["On Hold"] = "Completed",
    Completed = "Active",
  }
  
  local new_status = status_cycle[current_status] or "Active"
  lines[status_line_idx] = "**Status:** " .. new_status
  
  vim.fn.writefile(lines, project_file)
  core.notify(string.format("Project status: %s → %s", current_status, new_status))
end

----------------------------------------------------------------------
-- Archive Project
----------------------------------------------------------------------
function M.archive_project(project_file)
  local paths = core.get_paths()
  local projects_dir = vim.fs.joinpath(paths.notes_dir, "Projects")
  local archive_dir = vim.fs.joinpath(projects_dir, "Archive")
  
  vim.fn.mkdir(archive_dir, "p")
  
  local filename = vim.fn.fnamemodify(project_file, ":t")
  local dest = vim.fs.joinpath(archive_dir, filename)
  
  local ok = pcall(vim.fn.rename, project_file, dest)
  if ok then
    core.notify("Archived project: " .. filename)
    core.clear_cache()
    core.write_index()
  else
    core.notify("Failed to archive project", vim.log.levels.ERROR)
  end
end

----------------------------------------------------------------------
-- Project Dashboard
----------------------------------------------------------------------
function M.dashboard()
  local paths = core.get_paths()
  local projects_dir = vim.fs.joinpath(paths.notes_dir, "Projects")
  
  if vim.fn.isdirectory(projects_dir) == 0 then
    core.notify("No Projects directory found", vim.log.levels.WARN)
    return
  end
  
  -- Scan all projects and categorize by status
  local projects = {
    Active = {},
    ["On Hold"] = {},
    Completed = {},
    Unknown = {},
  }
  
  local handle = vim.loop.fs_scandir(projects_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      if type == "file" and name:match("%.md$") then
        local file_path = vim.fs.joinpath(projects_dir, name)
        local lines = vim.fn.readfile(file_path)
        local status = "Unknown"
        
        for _, line in ipairs(lines) do
          local s = line:match("^%*%*Status:%*%*%s*(.*)$")
          if s then
            status = s
            break
          end
        end
        
        local project = {
          name = name:gsub("%.md$", ""),
          file = file_path,
          status = status,
        }
        
        if projects[status] then
          table.insert(projects[status], project)
        else
          table.insert(projects.Unknown, project)
        end
      end
    end
  end
  
  -- Build dashboard content
  local dashboard = {
    "# Project Dashboard",
    "",
    string.format("_Generated:_ %s", os.date("%Y-%m-%d %H:%M")),
    "",
  }
  
  for _, status in ipairs({"Active", "On Hold", "Completed", "Unknown"}) do
    local list = projects[status]
    if #list > 0 then
      table.insert(dashboard, string.format("## %s (%d)", status, #list))
      table.insert(dashboard, "")
      for _, proj in ipairs(list) do
        table.insert(dashboard, string.format("- [[%s]]", proj.name))
      end
      table.insert(dashboard, "")
    end
  end
  
  -- Create or update dashboard file
  local dashboard_file = vim.fs.joinpath(projects_dir, "DASHBOARD.md")
  vim.fn.writefile(dashboard, dashboard_file)
  vim.cmd("edit " .. vim.fn.fnameescape(dashboard_file))
  core.notify("Project dashboard updated")
end

----------------------------------------------------------------------
-- Setup Commands
----------------------------------------------------------------------
function M.setup_commands()
  vim.api.nvim_create_user_command("ZettelProject", function(c)
    M.new_project(c.args ~= "" and c.args or nil)
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command("ZettelProjectList", M.list_projects, {})
  vim.api.nvim_create_user_command("ZettelProjectDashboard", M.dashboard, {})
end

----------------------------------------------------------------------
-- Setup Keymaps
----------------------------------------------------------------------
function M.setup_keymaps()
  vim.keymap.set("n", "<leader>zp", M.new_project, { desc = "New project" })
  vim.keymap.set("n", "<leader>zP", M.list_projects, { desc = "List projects" })
  vim.keymap.set("n", "<leader>zD", M.dashboard, { desc = "Project dashboard" })
end

return M
