# gtd-nvim

A complete **Getting Things Done (GTD)** system for Neovim, integrated with Zettelkasten for knowledge management.

Built with Lua, org-mode files, and fzf-lua for a fast, keyboard-driven workflow.

## Features

- **Capture** – Quick inbox capture with optional ZK notes
- **Clarify** – Process tasks with status, dates, tags, WAITING FOR metadata
- **Organize** – Refile tasks to projects and areas
- **Reflect** – GTD lists (Next Actions, Projects, Waiting, Someday, Stuck)
- **Engage** – Task management with archive/delete operations
- **Areas of Focus** – Organize projects by life area
- **WAITING FOR** – Track delegated items with full metadata
- **Zettelkasten** – Integrated note-taking system
- **Health Checks** – Built-in diagnostics (`:checkhealth gtd-nvim`)

## Requirements

- Neovim >= 0.9.0
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (for pickers)
- [nvim-orgmode](https://github.com/nvim-orgmode/orgmode) (optional, for org syntax)
- [which-key.nvim](https://github.com/folke/which-key.nvim) (optional, for keymap hints)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "dr3v3s/gtd-nvim",
  dependencies = {
    "ibhagwan/fzf-lua",
    "nvim-orgmode/orgmode",  -- optional
    "folke/which-key.nvim",  -- optional
  },
  config = function()
    require("gtd-nvim").setup({
      -- GTD directories
      gtd_root = vim.fn.expand("~/Documents/GTD"),
      inbox_file = "Inbox.org",
      projects_dir = "Projects",
      areas_dir = "Areas",
      
      -- Zettelkasten
      zk_root = vim.fn.expand("~/Documents/Notes"),
      zk_projects = "Projects",
      
      -- Keymaps (default: enabled with <leader>c prefix)
      keymaps = {
        enabled = true,
        prefix = "<leader>c",
      },
    })
  end,
}
```

### Using local path (for development)

```lua
{
  dir = "~/projects/gtd-nvim",
  config = function()
    require("gtd-nvim").setup()
  end,
}
```

## Keymaps

All keymaps use the configurable prefix (default: `<leader>c`).

| Key | Action |
|-----|--------|
| **Capture** ||
| `<leader>cc` | Capture → Inbox |
| **Status** ||
| `<leader>cs` | Change task status |
| **Clarify / Lists** ||
| `<leader>clt` | Clarify current task |
| `<leader>cll` | Clarify from list (fzf) |
| `<leader>clp` | Link task → project |
| `<leader>clm` | Lists menu |
| `<leader>cln` | Next Actions |
| `<leader>clP` | Projects |
| `<leader>cls` | Someday/Maybe |
| `<leader>clw` | Waiting For |
| `<leader>clx` | Stuck Projects |
| `<leader>cla` | Search All |
| **Refile / Projects** ||
| `<leader>cr` | Refile current task |
| `<leader>cR` | Refile any task (fzf) |
| `<leader>cp` | New project |
| `<leader>cP` | Convert task → project |
| **Manage** ||
| `<leader>cmt` | Manage tasks |
| `<leader>cmp` | Manage projects |
| `<leader>cmh` | Help menu |
| **Health** ||
| `<leader>ch` | Health check |

### Customizing Keymaps

```lua
require("gtd-nvim").setup({
  keymaps = {
    enabled = true,
    prefix = "<leader>g",  -- Change prefix
    keys = {
      capture = "c",        -- <leader>gc
      clarify_task = "t",   -- <leader>gt
      lists_next = "n",     -- <leader>gn
      -- Set to false to disable specific keys
      manage_help = false,
    },
  },
})
```

### Disable All Keymaps

```lua
require("gtd-nvim").setup({
  keymaps = false,  -- Use commands instead
})
```

## Commands

All features are also available as commands:

| Command | Description |
|---------|-------------|
| `:GtdCapture` | Capture to inbox |
| `:GtdClarify` | Clarify at cursor |
| `:GtdRefile` | Refile to project |
| `:GtdProjectNew` | Create new project |
| `:GtdNextActions` | Show next actions |
| `:GtdProjects` | Show projects |
| `:GtdWaiting` | Show waiting items |
| `:GtdSomedayMaybe` | Show someday/maybe |
| `:GtdStuckProjects` | Show stuck projects |
| `:GtdMenu` | Lists menu |
| `:GtdManageTasks` | Task manager |
| `:GtdManageProjects` | Project manager |
| `:GtdHealth` | Health check |


## Directory Structure

The plugin expects this directory structure:

```
~/Documents/GTD/           # gtd_root
├── Inbox.org              # Captured items land here
├── Archive.org            # Archived items
├── Projects/              # Project files
│   ├── project-name.org
│   └── ...
└── Areas/                 # Areas of focus
    ├── Work/
    │   ├── Inbox.org
    │   └── projects...
    ├── Personal/
    └── ...

~/Documents/Notes/         # zk_root
├── Projects/              # Project notes
├── People/                # People notes
├── Reading/               # Book/article notes
└── ...
```

## API

Access modules directly for custom integrations:

```lua
local gtd = require("gtd-nvim")

-- Direct module access
gtd.gtd.capture({})
gtd.gtd.clarify({ promote_if_needed = true })

-- Submodules
local lists = require("gtd-nvim.gtd.lists")
lists.next_actions()

local manage = require("gtd-nvim.gtd.manage")
manage.manage_tasks()

-- Zettelkasten
local zk = require("gtd-nvim.zettelkasten")
zk.new_note()
```

## Configuration Options

```lua
require("gtd-nvim").setup({
  -- GTD directories
  gtd_root = "~/Documents/GTD",
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  areas_dir = "Areas",
  archive_file = "Archive.org",
  
  -- Zettelkasten directories
  zk_root = "~/Documents/Notes",
  zk_projects = "Projects",
  
  -- UI settings
  border = "rounded",
  
  -- Behavior
  auto_save = true,
  quiet_capture = true,  -- Minimal notifications
  
  -- Keymaps
  keymaps = {
    enabled = true,
    prefix = "<leader>c",
    keys = { ... },  -- See mappings.lua for all options
  },
})
```

## Health Check

Run `:GtdHealth` or `:checkhealth gtd-nvim` to verify your setup.

## License

MIT

## Credits

- Inspired by David Allen's [Getting Things Done](https://gettingthingsdone.com/) methodology
- Built for the Neovim community
