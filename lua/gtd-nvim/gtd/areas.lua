-- ~/.config/nvim/lua/gtd/areas.lua
-- Areas of Focus for GTD, with fzf-lua picker (fallback to vim.ui.select)

local M = {}

-- Base directory for Areas-of-Focus on disk
M.base_dir = vim.fn.expand("~/Documents/GTD/Areas")

-- Hard-coded AoF list for now; each dir lives under M.base_dir
M.areas = {
  { name = "10-Personal", dir = M.base_dir .. "/10-Personal" },
  { name = "11-Ditte",    dir = M.base_dir .. "/11-Ditte" },
  { name = "20-Household",dir = M.base_dir .. "/20-Household" },
  { name = "30-Children", dir = M.base_dir .. "/30-Children" },
  { name = "40-Friends",  dir = M.base_dir .. "/40-Friends" },
  { name = "50-GTD",      dir = M.base_dir .. "/50-GTD" },
  { name = "80-DDS",      dir = M.base_dir .. "/80-DDS" },
  { name = "90-WORK",     dir = M.base_dir .. "/90-WORK" },
}

--- pick_area(cb)
---   cb(false)  -> user cancelled
---   cb(nil)    -> "all areas" / no filter
---   cb(table)  -> selected { name, dir }
function M.pick_area(cb)
  if not cb then return end

  local items = { "All areas (no filter)" }
  for _, a in ipairs(M.areas) do
    table.insert(items, a.name)
  end

  local ok, fzf = pcall(require, "fzf-lua")
  if ok and fzf then
    -- fzf-based picker
    fzf.fzf_exec(items, {
      prompt = "Area of Focus> ",
      actions = {
        ["default"] = function(sel)
          local line = sel and sel[1]
          if not line then
            cb(false)
            return
          end

          if line == "All areas (no filter)" then
            cb(nil)
            return
          end

          for _, a in ipairs(M.areas) do
            if a.name == line then
              cb(a)
              return
            end
          end

          -- Unknown choice -> treat as no filter
          cb(nil)
        end,
        ["esc"] = function() cb(false) end,
        ["ctrl-c"] = function() cb(false) end,
      },
      fzf_opts = { ["--no-info"] = true },
      winopts = { height = 0.35, width = 0.60, row = 0.10 },
    })
  else
    -- Simple fallback
    vim.ui.select(items, { prompt = "Area of Focus (optional)" }, function(choice)
      if not choice then
        cb(false)
        return
      end

      if choice == "All areas (no filter)" then
        cb(nil)
        return
      end

      for _, a in ipairs(M.areas) do
        if a.name == choice then
          cb(a)
          return
        end
      end

      cb(nil)
    end)
  end
end

return M