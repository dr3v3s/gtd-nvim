-- Example lualine configuration with Chronos GTD integration
-- Add to your lualine.nvim setup

require('lualine').setup({
  sections = {
    -- ... other sections ...
    
    lualine_x = {
      -- Sync status icon: 󰅟 (synced), 󰅞 (partial), 󰅜 (offline)
      {
        require('gtd-nvim.gtd.chronos').lualine_sync,
        color = function()
          local status = require('gtd-nvim.gtd.chronos').sync_status()
          if not status.daemon_ok then return { fg = '#f38ba8' } end  -- red
          if status.reminders_ok then return { fg = '#a6e3a1' } end   -- green
          return { fg = '#f9e2af' }                                   -- yellow
        end
      },
      
      -- GTD task counts: 󰁔 5 󰈸 2 󰇮 3
      {
        require('gtd-nvim.gtd.chronos').lualine_gtd,
        cond = function()
          return require('gtd-nvim.gtd.chronos').is_connected()
        end
      },
    },
  },
})

-- Alternative: Direct statusline integration (for non-lualine setups)
-- vim.opt.statusline = "%{%v:lua.require('gtd-nvim.gtd.chronos').statusline()%}"

-- Keymap to show detailed status
vim.keymap.set('n', '<leader>cs', function()
  require('gtd-nvim.gtd.chronos').show_status()
end, { desc = 'Chronos: Show sync status' })

-- Available functions:
-- require('gtd-nvim.gtd.chronos').sync_status()     -- Get cached status table
-- require('gtd-nvim.gtd.chronos').sync_statusline() -- Get icon + tooltip
-- require('gtd-nvim.gtd.chronos').is_connected()    -- Quick daemon check
-- require('gtd-nvim.gtd.chronos').daemon_version()  -- Get daemon version
-- require('gtd-nvim.gtd.chronos').detailed_status() -- Full status info
-- require('gtd-nvim.gtd.chronos').show_status()     -- Floating window
