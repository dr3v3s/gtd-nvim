# GTD-Nvim 📝✨

A complete **Getting Things Done (GTD)** system for Neovim, integrated with Zettelkasten for knowledge management. Built entirely in Lua for terminal-based productivity.

## Features

### 🎯 GTD System
- **Capture** - Quick inbox capture from anywhere in Neovim
- **Clarify** - Process inbox items with smart categorization
- **Organize** - Manage tasks, projects, and contexts
- **Manage** - View and work with your lists (Next Actions, Waiting For, Someday/Maybe)
- **Projects** - Track multi-step outcomes
- **Reminders** - Never miss a deadline

### 🗂️ Zettelkasten Integration
- Create and link notes
- Full-text search across your knowledge base
- Seamless integration with GTD for capturing ideas
- Markdown-based note management

### ⚡ Built for Speed
- Terminal-based interface
- Keyboard-driven workflow
- Fast fuzzy finding with fzf/telescope
- No external dependencies beyond Neovim

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "dr3v3s/gtd-nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim", -- or "ibhagwan/fzf-lua"
  },
  config = function()
    require("gtd-nvim").setup({
      -- GTD configuration
      gtd_dir = vim.fn.expand("~/.gtd/"),
      
      -- Zettelkasten configuration
      zk_dir = vim.fn.expand("~/Documents/Notes/"),
      
      -- Optional: auto-save
      auto_save = true,
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "dr3v3s/gtd-nvim",
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("gtd-nvim").setup({
      gtd_dir = vim.fn.expand("~/.gtd/"),
      zk_dir = vim.fn.expand("~/Documents/Notes/"),
    })
  end
}
```

## Configuration

### Default Configuration

```lua
{
  -- GTD directories
  gtd_dir = vim.fn.expand("~/.config/kanso/"),
  
  -- Zettelkasten directories  
  zk_dir = vim.fn.expand("~/Documents/Notes/"),
  
  -- Auto-save settings
  auto_save = true,
  
  -- UI settings
  border = "rounded",
}
```

## Usage

### GTD Workflow

#### 1. Capture
Quickly capture thoughts, tasks, and ideas from anywhere:

```lua
-- Add to your keymaps
vim.keymap.set("n", "<leader>gc", function()
  require("gtd-nvim.gtd.capture").capture()
end, { desc = "GTD Capture" })
```

#### 2. Clarify
Process your inbox and decide what each item means:

```lua
vim.keymap.set("n", "<leader>gp", function()
  require("gtd-nvim.gtd.clarify").process_inbox()
end, { desc = "GTD Process Inbox" })
```

#### 3. Organize
Manage your tasks and projects:

```lua
vim.keymap.set("n", "<leader>go", function()
  require("gtd-nvim.gtd.organize").organize()
end, { desc = "GTD Organize" })
```

#### 4. Lists
View your action lists:

```lua
-- Next Actions
vim.keymap.set("n", "<leader>gn", function()
  require("gtd-nvim.gtd.lists").show_next_actions()
end, { desc = "GTD Next Actions" })

-- Waiting For
vim.keymap.set("n", "<leader>gw", function()
  require("gtd-nvim.gtd.lists").show_waiting_for()
end, { desc = "GTD Waiting For" })

-- Projects
vim.keymap.set("n", "<leader>gP", function()
  require("gtd-nvim.gtd.projects").show_projects()
end, { desc = "GTD Projects" })
```

### Zettelkasten

#### Create a New Note

```lua
vim.keymap.set("n", "<leader>zn", function()
  require("gtd-nvim.zettelkasten").new_note()
end, { desc = "New Zettel" })
```

#### Search Notes

```lua
vim.keymap.set("n", "<leader>zf", function()
  require("gtd-nvim.zettelkasten").find_notes()
end, { desc = "Find Zettel" })
```


### Example Keymap Configuration

Here's a complete example keymap setup:

```lua
-- GTD Keymaps
local gtd = require("gtd-nvim.gtd")

-- Capture
vim.keymap.set("n", "<leader>gc", gtd.capture.capture, { desc = "GTD: Capture" })

-- Process/Clarify
vim.keymap.set("n", "<leader>gp", gtd.clarify.process_inbox, { desc = "GTD: Process Inbox" })

-- Organize
vim.keymap.set("n", "<leader>go", gtd.organize.organize, { desc = "GTD: Organize" })

-- Lists
vim.keymap.set("n", "<leader>gn", gtd.lists.show_next_actions, { desc = "GTD: Next Actions" })
vim.keymap.set("n", "<leader>gw", gtd.lists.show_waiting_for, { desc = "GTD: Waiting For" })
vim.keymap.set("n", "<leader>gs", gtd.lists.show_someday_maybe, { desc = "GTD: Someday/Maybe" })

-- Projects
vim.keymap.set("n", "<leader>gP", gtd.projects.show_projects, { desc = "GTD: Projects" })

-- Zettelkasten
local zk = require("gtd-nvim.zettelkasten")

vim.keymap.set("n", "<leader>zn", zk.new_note, { desc = "Zettel: New Note" })
vim.keymap.set("n", "<leader>zf", zk.find_notes, { desc = "Zettel: Find Note" })
vim.keymap.set("n", "<leader>zl", zk.insert_link, { desc = "Zettel: Insert Link" })
vim.keymap.set("n", "<leader>zb", zk.backlinks, { desc = "Zettel: Backlinks" })
```

## File Structure

GTD-Nvim stores data in plain text files for maximum portability:

```
~/.gtd/
├── inbox.org           # Captured items
├── next_actions.org    # Actionable tasks
├── projects.org        # Multi-step outcomes
├── waiting_for.org     # Delegated items
├── someday_maybe.org   # Future possibilities
├── contexts.txt        # @contexts list
└── tags.txt           # #tags list
```

Zettelkasten notes are stored as markdown files:

```
~/Documents/Notes/
├── 202410241200-example-note.md
├── 202410241230-another-note.md
└── ...
```

## GTD Methodology

This plugin implements David Allen's GTD methodology:

1. **Capture** - Collect everything that has your attention
2. **Clarify** - Process what each item means and what to do about it
3. **Organize** - Put everything in the right place
4. **Reflect** - Review your system regularly
5. **Engage** - Do the work

### GTD Lists

- **Next Actions** - Single-step tasks you can do now
- **Projects** - Multi-step outcomes requiring more than one action
- **Waiting For** - Items delegated to others
- **Someday/Maybe** - Things you might want to do in the future
- **Reference** - Information to store and retrieve later

## Requirements

- Neovim >= 0.9.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) OR [fzf-lua](https://github.com/ibhagwan/fzf-lua)

## Philosophy

This plugin is built on these principles:

- **Plain text** - All data stored in readable text files
- **Keyboard-driven** - Fast, efficient workflow without touching the mouse
- **Terminal-native** - Built for developers who live in the terminal
- **Minimal dependencies** - Uses only what's necessary
- **Lua-based** - Fast, integrated, extensible

## Credits

Created by [@dr3v3s](https://github.com/dr3v3s)

Built for terminal-based productivity enthusiasts who believe in:
- Getting Things Done by David Allen
- Zettelkasten method by Niklas Luhmann
- The power of plain text and Neovim

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.

## Support

If you find this plugin useful, please ⭐️ star the repository!

For issues, feature requests, or questions, please open an issue on GitHub.


### Link Management

The plugin includes powerful link utilities for managing connections between notes:

#### Insert Links

```lua
vim.keymap.set("n", "<leader>li", function()
  require("gtd-nvim.utils.link_insert").insert_link()
end, { desc = "Insert Link" })
```

Supports:
- File links (with fuzzy finding)
- URLs
- Email (mailto) links
- Tags
- Date stamps

Works with both **Markdown** and **Org-mode** formats!

#### Open Links

```lua
vim.keymap.set("n", "gx", function()
  require("gtd-nvim.utils.link_open").open_link()
end, { desc = "Open Link" })
```

Opens:
- URLs in your browser
- File links in Neovim
- Mailto links in your email client
- Supports macOS and Linux

