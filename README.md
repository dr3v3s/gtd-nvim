# GTD-Nvim 📝✨

A complete **Getting Things Done (GTD)** system for Neovim, integrated with Zettelkasten for knowledge management. Built entirely in Lua for terminal-based productivity.

## Features

### 🎯 GTD System
- **Capture** - Quick inbox capture with WAITING FOR support
- **Clarify** - Process inbox items with smart categorization  
- **Organize** - Refile tasks to projects and areas
- **Lists** - View Next Actions, Waiting For, Someday/Maybe, Stuck Projects
- **Projects** - Track multi-step outcomes with Areas of Focus
- **Audit** - Validate org-mode compliance across your GTD system

### 🗂️ Zettelkasten Integration
- Create and link notes (daily, project, people, reading)
- Full-text search across your knowledge base
- Seamless integration with GTD for capturing ideas
- Markdown-based note management

### ⚡ Built for Speed
- Terminal-based interface with fzf-lua
- Keyboard-driven workflow
- Fast fuzzy finding
- Strict org-mode compliance

## 📚 Documentation

- **[WORKFLOW.md](WORKFLOW.md)** - Complete guide to using GTD-Nvim
- **[DEPENDENCIES.md](DEPENDENCIES.md)** - Dependencies and installation
- **[example-mappings.lua](example-mappings.lua)** - Ready-to-use keymap configuration

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "dr3v3s/gtd-nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "ibhagwan/fzf-lua",
  },
  config = function()
    require("gtd-nvim").setup({
      gtd_root = vim.fn.expand("~/Documents/GTD"),
      zk_root = vim.fn.expand("~/Documents/Notes"),
    })
  end,
}
```

## Configuration

```lua
require("gtd-nvim").setup({
  -- GTD directories
  gtd_root = vim.fn.expand("~/Documents/GTD"),
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  areas_dir = "Areas",
  archive_file = "Archive.org",
  
  -- Zettelkasten directories
  zk_root = vim.fn.expand("~/Documents/Notes"),
  
  -- Behavior
  auto_save = true,
  quiet_capture = true,
})
```

## Keymaps

All GTD keymaps use `<leader>c` prefix. Copy `example-mappings.lua` to your config or use:

```lua
-- In your init.lua or keymaps file
require("path.to.example-mappings").setup()
```

### Quick Reference

| Keymap | Description |
|--------|-------------|
| `<leader>cc` | Capture → Inbox |
| `<leader>clt` | Clarify current task |
| `<leader>cll` | Clarify from list (fzf picker) |
| `<leader>clm` | Lists menu |
| `<leader>cln` | Next Actions |
| `<leader>clP` | Projects list |
| `<leader>clw` | Waiting For |
| `<leader>cls` | Someday/Maybe |
| `<leader>clx` | Stuck Projects |
| `<leader>cr` | Refile current task |
| `<leader>cR` | Refile any task (fzf) |
| `<leader>cp` | New project |
| `<leader>cmt` | Manage tasks |
| `<leader>cmp` | Manage projects |
| `<leader>ch` | Health check |

### Zettelkasten

| Keymap | Description |
|--------|-------------|
| `<leader>zn` | New note |
| `<leader>zf` | Find notes |
| `<leader>zs` | Search notes |
| `<leader>zd` | Daily note |
| `<leader>zp` | Project note |

## Commands

### GTD Commands
- `:GtdCapture` - Capture to inbox
- `:GtdClarify` - Clarify current item
- `:GtdRefile` - Refile to project
- `:GtdProjectNew` - Create new project
- `:GtdNextActions` - Show next actions
- `:GtdProjects` - Show projects
- `:GtdWaiting` - Show waiting for
- `:GtdSomedayMaybe` - Show someday/maybe
- `:GtdStuckProjects` - Show stuck projects
- `:GtdMenu` - Show lists menu
- `:GtdManageTasks` - Task manager
- `:GtdManageProjects` - Project manager
- `:GtdAudit` - Audit current file
- `:GtdAuditAll` - Audit all GTD files
- `:GtdHealth` - Health check

### Zettelkasten Commands
- `:ZkNew` - New note
- `:ZkFind` - Find notes
- `:ZkSearch` - Search notes  
- `:ZkRecent` - Recent notes
- `:ZkDaily` - Daily note
- `:ZkProject` - Project note
- `:ZkPerson` - Person note
- `:ZkBook` - Book note

## File Structure

```
~/Documents/GTD/
├── Inbox.org           # Captured items
├── Archive.org         # Archived tasks
├── Projects/           # Project files
│   └── project-name.org
└── Areas/              # Areas of Focus
    ├── 10-Personal/
    ├── 80-Work/
    └── ...

~/Documents/Notes/
├── daily/              # Daily notes
├── Projects/           # Project notes
├── People/             # People notes
└── ...
```

## Requirements

### Essential
- **Neovim >= 0.9.0**
- **[fzf-lua](https://github.com/ibhagwan/fzf-lua)** - Fuzzy finder
- **[plenary.nvim](https://github.com/nvim-lua/plenary.nvim)** - Utility functions

### Recommended
- [which-key.nvim](https://github.com/folke/which-key.nvim) - Keybinding hints
- `fzf`, `ripgrep`, `fd` - System tools for search

## Health Check

Run `:checkhealth gtd-nvim` to verify your setup.

## License

MIT License - See LICENSE file for details.

## Credits

Created by [@dr3v3s](https://github.com/dr3v3s)

Built for terminal-based productivity with:
- Getting Things Done by David Allen
- Zettelkasten method by Niklas Luhmann
- The power of plain text, org-mode, and Neovim
