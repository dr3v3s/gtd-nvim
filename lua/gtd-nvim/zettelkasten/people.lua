-- ~/.config/nvim/lua/utils/zettelkasten/people.lua
-- Person/contact management module

local M = {}

-- Get core zettelkasten module
local core = require("utils.zettelkasten")

-- Forward declaration for directory regeneration
local regenerate_directory_silent

----------------------------------------------------------------------
-- Person Note Creation
----------------------------------------------------------------------
function M.new_person(name, relationship)
  local paths = core.get_paths()
  
  local function create_person_note(person_name, person_relationship, extra)
    if not person_name or person_name == "" then
      core.notify("Person name required", vim.log.levels.WARN)
      return
    end
    
    extra = extra or {}
    local people_dir = vim.fn.fnamemodify(vim.fs.joinpath(paths.notes_dir, "People"), ":p")
    vim.fn.mkdir(people_dir, "p")
    
    local template_vars = {
      title = person_name,
      relationship = person_relationship or "Contact",
      created = os.date(core.get_config().datetime_format),
      tags = "#person #people",
      email = extra.email or "",
      phone = extra.phone or "",
      company = extra.company or "",
      location = extra.location or "",
    }
    
    core.create_note_file({
      title = person_name,
      dir = people_dir,
      template = "person",
      template_vars = template_vars,
      tags = "#person #people",
      open = true,
    })
    
    core.notify("Created person note: " .. person_name)
    
    -- Auto-regenerate DIRECTORY.md in background
    vim.defer_fn(function()
      regenerate_directory_silent()
    end, 100)
  end
  
  -- Prompt chain for all fields
  local function prompt_extra_fields(person_name, person_relationship)
    vim.ui.input({ prompt = "Email (optional): " }, function(email)
      vim.ui.input({ prompt = "Phone (optional): " }, function(phone)
        vim.ui.input({ prompt = "Company (optional): " }, function(company)
          vim.ui.input({ prompt = "Location (optional): " }, function(location)
            create_person_note(person_name, person_relationship, {
              email = email or "",
              phone = phone or "",
              company = company or "",
              location = location or "",
            })
          end)
        end)
      end)
    end)
  end
  
  if name and relationship then
    prompt_extra_fields(name, relationship)
  elseif name then
    vim.ui.input({ prompt = "Relationship (colleague/friend/family): " }, function(input_rel)
      prompt_extra_fields(name, input_rel)
    end)
  else
    vim.ui.input({ prompt = "Person name: " }, function(input_name)
      if input_name and input_name ~= "" then
        vim.ui.input({ prompt = "Relationship: " }, function(input_rel)
          prompt_extra_fields(input_name, input_rel)
        end)
      end
    end)
  end
end

----------------------------------------------------------------------
-- List People
----------------------------------------------------------------------
function M.list_people()
  local paths = core.get_paths()
  local people_dir = vim.fs.joinpath(paths.notes_dir, "People")
  
  if vim.fn.isdirectory(people_dir) == 0 then
    core.notify("No People directory found", vim.log.levels.WARN)
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    core.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  fzf.files({
    cwd = people_dir,
    prompt = "People ⟩ ",
    file_icons = false,
    fzf_opts = {
      ["--header"] = "[Enter] Open | [Ctrl-A] Meeting | [Ctrl-I] Interaction | [Ctrl-D] Delete",
    },
    actions = {
      ["default"] = fzf.actions.file_edit,
      ["ctrl-a"] = function(selected)
        if selected and selected[1] then
          local person_file = vim.fs.joinpath(people_dir, selected[1])
          M.add_meeting(person_file)
        end
      end,
      ["ctrl-i"] = function(selected)
        if selected and selected[1] then
          local person_file = vim.fs.joinpath(people_dir, selected[1])
          M.add_interaction(person_file)
        end
      end,
      ["ctrl-d"] = function(selected)
        if selected and selected[1] then
          local person_file = vim.fs.joinpath(people_dir, selected[1])
          local person_name = selected[1]:gsub("%.md$", "")
          
          vim.ui.select({"No", "Yes, delete permanently"}, {
            prompt = "Delete " .. person_name .. "?",
          }, function(choice)
            if choice and choice:match("^Yes") then
              local ok_del, err = os.remove(person_file)
              if ok_del == nil then
                core.notify("Failed to delete: " .. (err or "unknown error"), vim.log.levels.ERROR)
              else
                core.notify("Deleted: " .. person_name)
                -- Regenerate directory and reopen picker
                vim.defer_fn(function()
                  regenerate_directory_silent()
                  M.list_people()
                end, 100)
              end
            end
          end)
        end
      end,
    },
  })
end

----------------------------------------------------------------------
-- Add Meeting to Person
----------------------------------------------------------------------
function M.add_meeting(person_file)
  if vim.fn.filereadable(person_file) == 0 then
    core.notify("Person file not found", vim.log.levels.ERROR)
    return
  end
  
  vim.ui.input({ prompt = "Meeting topic: " }, function(topic)
    if not topic or topic == "" then return end
    
    local timestamp = os.date("%Y-%m-%d %H:%M")
    local entry = string.format("- **%s** - %s", timestamp, topic)
    
    local lines = vim.fn.readfile(person_file)
    
    -- Find or create Meetings section
    local meetings_idx = nil
    for i, line in ipairs(lines) do
      if line:match("^## Meetings") then
        meetings_idx = i
        break
      end
    end
    
    if not meetings_idx then
      table.insert(lines, "")
      table.insert(lines, "## Meetings")
      table.insert(lines, "")
      meetings_idx = #lines
    end
    
    -- Insert meeting after Meetings header
    table.insert(lines, meetings_idx + 1, entry)
    
    vim.fn.writefile(lines, person_file)
    core.notify("Meeting added: " .. topic)
  end)
end

----------------------------------------------------------------------
-- Add Interaction to Person
----------------------------------------------------------------------
function M.add_interaction(person_file)
  if vim.fn.filereadable(person_file) == 0 then
    core.notify("Person file not found", vim.log.levels.ERROR)
    return
  end
  
  vim.ui.input({ prompt = "Interaction note: " }, function(note)
    if not note or note == "" then return end
    
    local timestamp = os.date("%Y-%m-%d")
    local entry = string.format("- **%s**: %s", timestamp, note)
    
    local lines = vim.fn.readfile(person_file)
    
    -- Find or create Interactions section
    local interactions_idx = nil
    for i, line in ipairs(lines) do
      if line:match("^## Interactions") then
        interactions_idx = i
        break
      end
    end
    
    if not interactions_idx then
      table.insert(lines, "")
      table.insert(lines, "## Interactions")
      table.insert(lines, "")
      interactions_idx = #lines
    end
    
    -- Insert interaction after Interactions header
    table.insert(lines, interactions_idx + 1, entry)
    
    vim.fn.writefile(lines, person_file)
    core.notify("Interaction logged")
  end)
end

----------------------------------------------------------------------
-- People Directory (by relationship)
----------------------------------------------------------------------

-- Internal helper: regenerate directory file, optionally open it
local function do_regenerate_directory(open_after)
  local paths = core.get_paths()
  local people_dir = vim.fs.joinpath(paths.notes_dir, "People")
  
  if vim.fn.isdirectory(people_dir) == 0 then
    return nil
  end
  
  -- Scan all people and categorize by relationship
  local people = {
    Colleague = {},
    Friend = {},
    Family = {},
    Contact = {},
    Other = {},
  }
  
  local handle = vim.loop.fs_scandir(people_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      if type == "file" and name:match("%.md$") and name ~= "DIRECTORY.md" then
        local file_path = vim.fs.joinpath(people_dir, name)
        local lines = vim.fn.readfile(file_path)
        local relationship = "Other"
        local email = ""
        local company = ""
        local display_name = name:gsub("%.md$", "")  -- fallback
        
        for _, line in ipairs(lines) do
          -- Extract title from # heading
          local title = line:match("^#%s+(.+)$")
          if title and display_name == name:gsub("%.md$", "") then
            display_name = title
          end
          
          -- Handle both "**Relationship:** value" and "- **Relationship:** value" formats
          local r = line:match("^%-?%s*%*%*Relationship:?%*%*%s*(.*)$")
          if r and r ~= "" then relationship = r end
          
          local e = line:match("^%-?%s*%*%*Email:?%*%*%s*(.*)$")
          if e and e ~= "" then email = " ✉ " .. e end
          
          local c = line:match("^%-?%s*%*%*Company:?%*%*%s*(.*)$")
          if c and c ~= "" then company = " @ " .. c end
        end
        
        local person = {
          name = display_name,
          filename = name:gsub("%.md$", ""),  -- for wiki-link
          file = file_path,
          relationship = relationship,
          email = email,
          company = company,
        }
        
        if people[relationship] then
          table.insert(people[relationship], person)
        else
          table.insert(people.Other, person)
        end
      end
    end
  end
  
  -- Build directory content
  local directory = {
    "# People Directory",
    "",
    string.format("_Generated:_ %s", os.date("%Y-%m-%d %H:%M")),
    "",
  }
  
  for _, rel in ipairs({"Family", "Friend", "Colleague", "Contact", "Other"}) do
    local list = people[rel]
    if #list > 0 then
      -- Sort alphabetically by display name
      table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
      
      table.insert(directory, string.format("## %s (%d)", rel, #list))
      table.insert(directory, "")
      for _, person in ipairs(list) do
        -- Wiki-link with alias: [[filename|Display Name]]
        table.insert(directory, string.format("- [[%s|%s]]%s%s", person.filename, person.name, person.company, person.email))
      end
      table.insert(directory, "")
    end
  end
  
  -- Create or update directory file
  local directory_file = vim.fs.joinpath(people_dir, "DIRECTORY.md")
  vim.fn.writefile(directory, directory_file)
  
  if open_after then
    vim.cmd("edit " .. vim.fn.fnameescape(directory_file))
    core.notify("People directory updated")
  end
  
  return directory_file
end

-- Assign to forward declaration for use in new_person()
regenerate_directory_silent = function()
  do_regenerate_directory(false)
end

-- Public: regenerate and open directory
function M.directory()
  local paths = core.get_paths()
  local people_dir = vim.fs.joinpath(paths.notes_dir, "People")
  
  if vim.fn.isdirectory(people_dir) == 0 then
    core.notify("No People directory found", vim.log.levels.WARN)
    return
  end
  
  do_regenerate_directory(true)
end

----------------------------------------------------------------------
-- Recent Interactions
----------------------------------------------------------------------
function M.recent_interactions(days)
  days = days or 30
  local paths = core.get_paths()
  local people_dir = vim.fs.joinpath(paths.notes_dir, "People")
  
  if vim.fn.isdirectory(people_dir) == 0 then
    core.notify("No People directory found", vim.log.levels.WARN)
    return
  end
  
  local interactions = {}
  local cutoff_time = os.time() - (days * 86400)
  
  local handle = vim.loop.fs_scandir(people_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      if type == "file" and name:match("%.md$") then
        local file_path = vim.fs.joinpath(people_dir, name)
        local stat = vim.loop.fs_stat(file_path)
        
        if stat and stat.mtime.sec >= cutoff_time then
          local person_name = name:gsub("%.md$", "")
          local last_modified = os.date("%Y-%m-%d", stat.mtime.sec)
          
          table.insert(interactions, {
            person = person_name,
            file = file_path,
            date = last_modified,
            timestamp = stat.mtime.sec,
          })
        end
      end
    end
  end
  
  -- Sort by most recent
  table.sort(interactions, function(a, b)
    return a.timestamp > b.timestamp
  end)
  
  -- Build report
  local report = {
    string.format("# Recent Interactions (%d days)", days),
    "",
    string.format("_Generated:_ %s", os.date("%Y-%m-%d %H:%M")),
    "",
  }
  
  if #interactions > 0 then
    for _, interaction in ipairs(interactions) do
      table.insert(report, string.format("- **%s** - [[%s]]", interaction.date, interaction.person))
    end
  else
    table.insert(report, "_No recent interactions_")
  end
  
  -- Display in floating window
  local cols, rows = vim.o.columns, vim.o.lines
  local w, h = math.max(50, math.floor(cols * 0.5)), math.min(#report + 4, math.floor(rows * 0.8))
  local row, col = math.floor((rows - h) / 2), math.floor((cols - w) / 2)
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, report)
  vim.bo[buf].filetype = "markdown"
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = w, height = h,
    style = "minimal", border = "rounded", title = " Recent Interactions ", title_pos = "center",
  })
  
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

----------------------------------------------------------------------
-- Birthday Tracker (reads from person files)
----------------------------------------------------------------------
function M.birthdays()
  local paths = core.get_paths()
  local people_dir = vim.fs.joinpath(paths.notes_dir, "People")
  
  if vim.fn.isdirectory(people_dir) == 0 then
    core.notify("No People directory found", vim.log.levels.WARN)
    return
  end
  
  local birthdays = {}
  local today = os.date("*t")
  local current_month = today.month
  
  local handle = vim.loop.fs_scandir(people_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      if type == "file" and name:match("%.md$") then
        local file_path = vim.fs.joinpath(people_dir, name)
        local lines = vim.fn.readfile(file_path)
        
        for _, line in ipairs(lines) do
          local birthday = line:match("^%*%*Birthday:%*%*%s*(.*)$")
          if birthday then
            -- Parse date (assumes YYYY-MM-DD or MM-DD format)
            local month, day = birthday:match("(%d+)%-(%d+)$")
            if month and day then
              month = tonumber(month)
              day = tonumber(day)
              
              if month == current_month then
                table.insert(birthdays, {
                  person = name:gsub("%.md$", ""),
                  day = day,
                  date = string.format("%02d-%02d", month, day),
                })
              end
            end
          end
        end
      end
    end
  end
  
  -- Sort by day
  table.sort(birthdays, function(a, b)
    return a.day < b.day
  end)
  
  if #birthdays > 0 then
    local month_name = os.date("%B", os.time({ year = 2025, month = current_month, day = 1 }))
    core.notify(string.format("Birthdays in %s: %d", month_name, #birthdays))
    
    for _, bday in ipairs(birthdays) do
      print(string.format("  %s - %s", bday.date, bday.person))
    end
  else
    core.notify("No birthdays this month")
  end
end

----------------------------------------------------------------------
-- Setup Commands
----------------------------------------------------------------------
function M.setup_commands()
  vim.api.nvim_create_user_command("ZettelPerson", function(c)
    M.new_person(c.args ~= "" and c.args or nil)
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command("ZettelPeople", M.list_people, {})
  vim.api.nvim_create_user_command("ZettelPeopleDirectory", M.directory, {})
  vim.api.nvim_create_user_command("ZettelInteractions", function()
    M.recent_interactions(30)
  end, {})
  vim.api.nvim_create_user_command("ZettelBirthdays", M.birthdays, {})
end

----------------------------------------------------------------------
-- Setup Keymaps
----------------------------------------------------------------------
function M.setup_keymaps()
  vim.keymap.set("n", "<leader>zo", M.new_person, { desc = "New person note" })
  vim.keymap.set("n", "<leader>zO", M.list_people, { desc = "List people" })
  vim.keymap.set("n", "<leader>zI", function() M.recent_interactions(30) end, { desc = "Recent interactions" })
end

return M
