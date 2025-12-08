-- ~/.config/nvim/lua/utils/zettelkasten/reading.lua
-- Book notes and reading management module

local M = {}

-- Get core zettelkasten module
local core = require("gtd-nvim.zettelkasten")

----------------------------------------------------------------------
-- Book Note Creation
----------------------------------------------------------------------
function M.new_book(title, author)
  local paths = core.get_paths()
  
  local function create_book_note(book_title, book_author)
    if not book_title or book_title == "" then
      core.notify("Book title required", vim.log.levels.WARN)
      return
    end
    
    local reading_dir = vim.fn.fnamemodify(vim.fs.joinpath(paths.notes_dir, "Reading"), ":p")
    vim.fn.mkdir(reading_dir, "p")
    
    local template_vars = {
      title = book_title,
      author = book_author or "Unknown",
      created = os.date(core.get_config().datetime_format),
      status = "To Read",
      rating = "⭐⭐⭐⭐⭐",
      tags = "#book #reading",
    }
    
    core.create_note_file({
      title = book_title,
      dir = reading_dir,
      template = "book",
      template_vars = template_vars,
      tags = "#book #reading",
      open = true,
    })
    
    core.notify("Created book note: " .. book_title)
  end
  
  if title and author then
    create_book_note(title, author)
  elseif title then
    vim.ui.input({ prompt = "Author: " }, function(input_author)
      create_book_note(title, input_author)
    end)
  else
    vim.ui.input({ prompt = "Book title: " }, function(input_title)
      if input_title and input_title ~= "" then
        vim.ui.input({ prompt = "Author: " }, function(input_author)
          create_book_note(input_title, input_author)
        end)
      end
    end)
  end
end

----------------------------------------------------------------------
-- List Reading Notes
----------------------------------------------------------------------
function M.list_books()
  local paths = core.get_paths()
  local reading_dir = vim.fs.joinpath(paths.notes_dir, "Reading")
  
  if vim.fn.isdirectory(reading_dir) == 0 then
    core.notify("No Reading directory found", vim.log.levels.WARN)
    return
  end
  
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    core.notify("fzf-lua required", vim.log.levels.ERROR)
    return
  end
  
  fzf.files({
    cwd = reading_dir,
    prompt = "Books ⟩ ",
    file_icons = false,
    fzf_opts = {
      ["--header"] = "[Enter] Open | [Ctrl-S] Update Status | [Ctrl-R] Add Rating",
    },
    actions = {
      ["default"] = fzf.actions.file_edit,
      ["ctrl-s"] = function(selected)
        if selected and selected[1] then
          M.update_reading_status(vim.fs.joinpath(reading_dir, selected[1]))
        end
      end,
      ["ctrl-r"] = function(selected)
        if selected and selected[1] then
          M.update_rating(vim.fs.joinpath(reading_dir, selected[1]))
        end
      end,
    },
  })
end

----------------------------------------------------------------------
-- Update Reading Status
----------------------------------------------------------------------
function M.update_reading_status(book_file)
  if vim.fn.filereadable(book_file) == 0 then
    core.notify("Book file not found", vim.log.levels.ERROR)
    return
  end
  
  local lines = vim.fn.readfile(book_file)
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
    core.notify("No status line found in book note", vim.log.levels.WARN)
    return
  end
  
  -- Status cycle: To Read → Reading → Finished → To Read
  local status_cycle = {
    ["To Read"] = "Reading",
    Reading = "Finished",
    Finished = "To Read",
  }
  
  local new_status = status_cycle[current_status] or "To Read"
  lines[status_line_idx] = "**Status:** " .. new_status
  
  -- Add finished date if completed
  if new_status == "Finished" then
    local finished_date = os.date("%Y-%m-%d")
    table.insert(lines, status_line_idx + 1, "**Finished:** " .. finished_date)
  end
  
  vim.fn.writefile(lines, book_file)
  core.notify(string.format("Reading status: %s → %s", current_status, new_status))
end

----------------------------------------------------------------------
-- Update Rating
----------------------------------------------------------------------
function M.update_rating(book_file)
  if vim.fn.filereadable(book_file) == 0 then
    core.notify("Book file not found", vim.log.levels.ERROR)
    return
  end
  
  vim.ui.input({ prompt = "Rating (1-5): " }, function(rating)
    if not rating or rating == "" then return end
    
    local rating_num = tonumber(rating)
    if not rating_num or rating_num < 1 or rating_num > 5 then
      core.notify("Rating must be 1-5", vim.log.levels.WARN)
      return
    end
    
    local stars = string.rep("⭐", rating_num) .. string.rep("☆", 5 - rating_num)
    
    local lines = vim.fn.readfile(book_file)
    for i, line in ipairs(lines) do
      if line:match("^%*%*Rating:%*%*") then
        lines[i] = "**Rating:** " .. stars
        vim.fn.writefile(lines, book_file)
        core.notify("Updated rating: " .. stars)
        return
      end
    end
    
    core.notify("No rating line found", vim.log.levels.WARN)
  end)
end

----------------------------------------------------------------------
-- Reading Dashboard
----------------------------------------------------------------------
function M.dashboard()
  local paths = core.get_paths()
  local reading_dir = vim.fs.joinpath(paths.notes_dir, "Reading")
  
  if vim.fn.isdirectory(reading_dir) == 0 then
    core.notify("No Reading directory found", vim.log.levels.WARN)
    return
  end
  
  -- Scan all books and categorize by status
  local books = {
    ["To Read"] = {},
    Reading = {},
    Finished = {},
    Unknown = {},
  }
  
  local handle = vim.loop.fs_scandir(reading_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      if type == "file" and name:match("%.md$") then
        local file_path = vim.fs.joinpath(reading_dir, name)
        local lines = vim.fn.readfile(file_path)
        local status = "Unknown"
        local author = "Unknown"
        local rating = ""
        
        for _, line in ipairs(lines) do
          local s = line:match("^%*%*Status:%*%*%s*(.*)$")
          if s then status = s end
          
          local a = line:match("^%*%*Author:%*%*%s*(.*)$")
          if a then author = a end
          
          local r = line:match("^%*%*Rating:%*%*%s*(.*)$")
          if r then rating = " " .. r end
        end
        
        local book = {
          name = name:gsub("%.md$", ""),
          file = file_path,
          status = status,
          author = author,
          rating = rating,
        }
        
        if books[status] then
          table.insert(books[status], book)
        else
          table.insert(books.Unknown, book)
        end
      end
    end
  end
  
  -- Build dashboard content
  local dashboard = {
    "# Reading Dashboard",
    "",
    string.format("_Generated:_ %s", os.date("%Y-%m-%d %H:%M")),
    "",
  }
  
  for _, status in ipairs({"Reading", "To Read", "Finished", "Unknown"}) do
    local list = books[status]
    if #list > 0 then
      table.insert(dashboard, string.format("## %s (%d)", status, #list))
      table.insert(dashboard, "")
      for _, book in ipairs(list) do
        table.insert(dashboard, string.format("- [[%s]] - %s%s", book.name, book.author, book.rating))
      end
      table.insert(dashboard, "")
    end
  end
  
  -- Create or update dashboard file
  local dashboard_file = vim.fs.joinpath(reading_dir, "DASHBOARD.md")
  vim.fn.writefile(dashboard, dashboard_file)
  vim.cmd("edit " .. vim.fn.fnameescape(dashboard_file))
  core.notify("Reading dashboard updated")
end

----------------------------------------------------------------------
-- Quote Capture from Book
----------------------------------------------------------------------
function M.capture_quote()
  local current_file = vim.fn.expand("%:p")
  local reading_dir = vim.fs.joinpath(core.get_paths().notes_dir, "Reading")
  
  -- Check if we're in a book note
  if not current_file:match("^" .. vim.pesc(reading_dir)) then
    core.notify("Not in a book note", vim.log.levels.WARN)
    return
  end
  
  vim.ui.input({ prompt = "Quote: " }, function(quote)
    if not quote or quote == "" then return end
    
    vim.ui.input({ prompt = "Page (optional): " }, function(page)
      local book_name = vim.fn.fnamemodify(current_file, ":t:r")
      local entry = string.format("> %s\n\n— [[%s]]", quote, book_name)
      
      if page and page ~= "" then
        entry = string.format("> %s\n\n— [[%s]], p.%s", quote, book_name, page)
      end
      
      -- Append to current buffer
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      
      -- Find or create Quotes section
      local quotes_idx = nil
      for i, line in ipairs(lines) do
        if line:match("^## Quotes") then
          quotes_idx = i
          break
        end
      end
      
      if not quotes_idx then
        table.insert(lines, "")
        table.insert(lines, "## Quotes")
        table.insert(lines, "")
        quotes_idx = #lines
      end
      
      -- Insert quote after Quotes header
      table.insert(lines, quotes_idx + 1, "")
      table.insert(lines, quotes_idx + 2, entry)
      table.insert(lines, quotes_idx + 3, "")
      
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      core.notify("Quote captured")
    end)
  end)
end

----------------------------------------------------------------------
-- Setup Commands
----------------------------------------------------------------------
function M.setup_commands()
  vim.api.nvim_create_user_command("ZettelBook", function(c)
    M.new_book(c.args ~= "" and c.args or nil)
  end, { nargs = "?" })
  
  vim.api.nvim_create_user_command("ZettelBookList", M.list_books, {})
  vim.api.nvim_create_user_command("ZettelBookDashboard", M.dashboard, {})
  vim.api.nvim_create_user_command("ZettelQuote", M.capture_quote, {})
end

----------------------------------------------------------------------
-- Setup Keymaps
----------------------------------------------------------------------
function M.setup_keymaps()
  vim.keymap.set("n", "<leader>zb", M.new_book, { desc = "New book note" })
  vim.keymap.set("n", "<leader>zB", M.list_books, { desc = "List books" })
  vim.keymap.set("n", "<leader>zR", M.dashboard, { desc = "Reading dashboard" })
  vim.keymap.set("n", "<leader>zQ", M.capture_quote, { desc = "Capture quote" })
end

return M
