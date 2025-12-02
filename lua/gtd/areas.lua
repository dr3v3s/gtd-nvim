-- ~/.config/nvim/lua/gtd/areas.lua
-- Minimal debug version: provides pick_area() for gtd.capture

local M = {}

-- Hard-coded AoF list for now; we can wire areas.txt later
M.areas = {
  { name = "10-Personal", dir = vim.fn.expand("~/Documents/GTD/10-Personal") },
  { name = "11-Ditte",    dir = vim.fn.expand("~/Documents/GTD/11-Ditte") },
  { name = "20-Household",dir = vim.fn.expand("~/Documents/GTD/20-Household") },
  { name = "30-Children", dir = vim.fn.expand("~/Documents/GTD/30-Children") },
  { name = "40-Friends",  dir = vim.fn.expand("~/Documents/GTD/40-Friends") },
  { name = "50-GTD",      dir = vim.fn.expand("~/Documents/GTD/50-GTD") },
  { name = "80-DDS",      dir = vim.fn.expand("~/Documents/GTD/80-DDS") },
  { name = "90-WORK",     dir = vim.fn.expand("~/Documents/GTD/90-WORK") },
}

-- Simple helper to log
local function dbg(msg)
  vim.notify("[gtd.areas] " .. msg, vim.log.levels.INFO)
end

-- Interactive picker
-- cb(false)  -> user cancelled
-- cb(nil)    -> "All areas" / no filter
-- cb(table)  -> selected area { name, dir }
function M.pick_area(cb)
  if not cb then return end

  dbg("pick_area() called")

  local items = { "All areas (no filter)" }
  for _, a in ipairs(M.areas) do
    table.insert(items, a.name)
  end

  vim.ui.select(items, { prompt = "Area of Focus (optional)" }, function(choice)
    if not choice then
      dbg("user cancelled AoF selection")
      cb(false)
      return
    end

    if choice == "All areas (no filter)" then
      dbg("AoF: all areas / no filter")
      cb(nil)
      return
    end

    for _, a in ipairs(M.areas) do
      if a.name == choice then
        dbg("AoF selected: " .. a.name)
        cb(a)
        return
      end
    end

    dbg("AoF: unknown choice, treating as no filter")
    cb(nil)
  end)
end

return M