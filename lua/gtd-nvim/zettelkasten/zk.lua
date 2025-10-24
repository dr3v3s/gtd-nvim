-- ~/.config/nvim/lua/mappings/zk.lua
-- Register Zettelkasten actions + a small cheat-sheet for fzf-lua keys

local M = {}

function M.setup()
  local ok, zk = pcall(require, "utils.zettelkasten")
  if not ok then return end

  -- Normal keymaps
  local map = function(lhs, rhs, desc)
    if type(rhs) == "function" then
      vim.keymap.set("n", lhs, rhs, { silent = true, noremap = true, desc = desc })
    end
  end

  map("<leader>zN", zk.new_note,     "ZK: New note")
  map("<leader>zQ", zk.quick_note,   "ZK: Quick note")
  map("<leader>zD", zk.daily_note,   "ZK: Daily note")
  map("<leader>zF", zk.find_notes,   "ZK: Find files")
  map("<leader>zS", zk.search_notes, "ZK: Search")
  map("<leader>zR", zk.recent_notes, "ZK: Recent")
  map("<leader>zM", zk.manage_notes, "ZK: Manage (TAB multi; C-d del; C-a arch; C-m move)")
  map("<leader>zI", zk.rebuild_index,"ZK: Rebuild index")

  -- Quick help popup for fzf keys
  vim.keymap.set("n", "<leader>z?", function()
    local hints = (zk.whichkey_hints and zk.whichkey_hints.manage) or {}
    local lines = { "ZK Manage (fzf-lua) keys:", "" }
    for k, v in pairs(hints) do
      table.insert(lines, string.format(" %-7s %s", k, v))
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local w = 56
    local h = #lines + 2
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = w,
      height = h,
      row = math.floor((vim.o.lines - h) / 2),
      col = math.floor((vim.o.columns - w) / 2),
      style = "minimal",
      border = "rounded",
      title = " ZK Keys ",
      title_pos = "center",
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
    vim.keymap.set("n", "<esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
  end, { silent = true, noremap = true, desc = "ZK: show fzf keys" })

  -- which-key labels (optional)
  pcall(function()
    local wk = require("which-key")
    wk.add({
      { "<leader>z",  group = "Zettelkasten" },
      { "<leader>zN", desc = "New note" },
      { "<leader>zQ", desc = "Quick note" },
      { "<leader>zD", desc = "Daily note" },
      { "<leader>zF", desc = "Find files" },
      { "<leader>zS", desc = "Search" },
      { "<leader>zR", desc = "Recent" },
      { "<leader>zM", desc = "Manage (TAB/C-d/C-a/C-m)" },
      { "<leader>zI", desc = "Rebuild index" },
      { "<leader>z?", desc = "ZK keys (help)" },
    })
  end)
end

return M