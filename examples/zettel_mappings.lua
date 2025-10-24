-- ~/.config/nvim/lua/mappings/zettel.lua
-- Enhanced Zettelkasten keymaps with GTD integration and new features

local M = {}

local function wrap(fnname)
  return function()
    local ok, mod = pcall(require, "utils.zettelkasten")
    if not ok then
      vim.notify("require('utils.zettelkasten') failed:\n" .. tostring(mod),
        vim.log.levels.ERROR, { title = "Zettel key" })
      return
    end
    if type(mod) ~= "table" then
      vim.notify("utils.zettelkasten loaded but returned " .. type(mod) ..
        " (did you forget `return M` at the bottom?)",
        vim.log.levels.ERROR, { title = "Zettel key" })
      return
    end
    local fn = mod[fnname]
    if type(fn) ~= "function" then
      vim.notify("utils.zettelkasten." .. fnname .. " is not a function",
        vim.log.levels.ERROR, { title = "Zettel key" })
      return
    end
    return fn()
  end
end

function M.setup()
  local map = function(lhs, name, desc)
    vim.keymap.set("n", lhs, wrap(name), { silent = true, noremap = true, desc = desc })
  end

  -- Core zettelkasten functions (preserved)
  map("<leader>zn", "new_note",     "Zettel: New note")
  map("<leader>zq", "quick_note",   "Zettel: Quick note")
  map("<leader>zd", "daily_note",   "Zettel: Daily note")
  map("<leader>zo", "find_notes",   "Zettel: Open notes")
  map("<leader>zf", "search_notes", "Zettel: Search notes")
  map("<leader>zr", "recent_notes", "Zettel: Recent notes")
  map("<leader>zm", "manage_notes", "Zettel: Manage (fzf)")
  
  -- Enhanced features
  map("<leader>zb", "show_backlinks",           "Zettel: Backlinks")
  map("<leader>zt", "browse_tags",              "Zettel: Browse tags")
  map("<leader>zg", "browse_gtd_tasks",         "Zettel: GTD tasks")
  map("<leader>za", "search_all",               "Zettel: Search all (Notes+GTD)")
  map("<leader>zp", "new_project",              "Zettel: New project")
  map("<leader>zi", "show_stats",               "Zettel: Statistics")
  map("<leader>zc", "clear_all_cache",          "Zettel: Clear cache")
  map("<leader>zu", "update_backlinks_in_buffer", "Zettel: Update backlinks")

  -- which-key integration
  pcall(function()
    local wk = require("which-key")
    wk.add({
      -- Group definition
      { "<leader>z",  group = "Zettelkasten" },
      
      -- Core functions
      { "<leader>zn", desc  = "New note" },
      { "<leader>zq", desc  = "Quick note" },
      { "<leader>zd", desc  = "Daily note" },
      { "<leader>zo", desc  = "Open notes" },
      { "<leader>zf", desc  = "Search notes" },
      { "<leader>zr", desc  = "Recent notes" },
      { "<leader>zm", desc  = "Manage notes (fzf)" },
      
      -- Enhanced features
      { "<leader>zb", desc  = "Show backlinks" },
      { "<leader>zt", desc  = "Browse tags" },
      { "<leader>zg", desc  = "Browse GTD tasks" },
      { "<leader>za", desc  = "Search all (Notes+GTD)" },
      { "<leader>zp", desc  = "New project" },
      { "<leader>zi", desc  = "Statistics & info" },
      { "<leader>zc", desc  = "Clear cache" },
      { "<leader>zu", desc  = "Update backlinks" },
    })
  end)
end

return M