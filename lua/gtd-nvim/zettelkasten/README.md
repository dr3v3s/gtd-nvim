# 󰎞 Zettelkasten for Neovim

**Version:** 1.0.0  
**Updated:** 2025-12-11

A comprehensive Zettelkasten note-taking system for Neovim with GTD integration, backlinks, tags, and people management.

## ✨ Features

- **Note Management** — Create, find, search, and organize markdown notes
- **GTD Integration** — Sync tasks from org-mode GTD files into daily notes
- **Backlinks** — Automatic detection and display of note references
- **Tag System** — Extract and browse tags across all notes
- **People/CRM** — Track contacts, meetings, and interactions
- **Daily Notes** — Templated daily notes with GTD task sync
- **Quick Capture** — Fast note capture with timestamps
- **File Operations** — Archive, delete, move notes with fzf-lua
- **Caching** — 5-minute cache for fast repeated operations

## 📦 Requirements

- Neovim 0.9+
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (primary picker)
- [fd](https://github.com/sharkdp/fd) (file finding)
- [ripgrep](https://github.com/BurntSushi/ripgrep) (content search)
- [Nerd Font](https://www.nerdfonts.com/) (for glyphs)

Optional:
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (fallback picker)

## 📁 Directory Structure

```
~/Documents/
├── Notes/                    # Main notes directory
│   ├── Daily/               # Daily notes (YYYY-MM-DD.md)
│   ├── Quick/               # Quick capture notes
│   ├── Projects/            # Project notes
│   ├── People/              # Contact/person notes
│   ├── Templates/           # Note templates
│   ├── Archive/             # Archived notes
│   └── index.md             # Auto-generated index
└── GTD/                      # GTD org-mode files (for integration)
```

## 🚀 Installation

Add to your Neovim configuration:

```lua
-- lazy.nvim
{
  "your-username/gtd-nvim",
  config = function()
    require("gtd-nvim.zettelkasten").setup()
  end,
}
```

## ⚙️ Configuration

```lua
require("gtd-nvim.zettelkasten").setup({
  -- Directories
  notes_dir       = vim.fn.expand("~/Documents/Notes"),
  daily_dir       = vim.fn.expand("~/Documents/Notes/Daily"),
  quick_dir       = vim.fn.expand("~/Documents/Notes/Quick"),
  templates_dir   = vim.fn.expand("~/Documents/Notes/Templates"),
  archive_dir     = vim.fn.expand("~/Documents/Notes/Archive"),
  gtd_dir         = vim.fn.expand("~/Documents/GTD"),
  
  -- File settings
  file_ext        = ".md",
  id_format       = "%Y%m%d%H%M",      -- Note ID format
  date_format     = "%Y-%m-%d",
  datetime_format = "%Y-%m-%d %H:%M:%S",
  slug_lowercase  = false,              -- Keep case in filenames
  
  -- Features
  cache = {
    enabled = true,
    ttl = 300,                          -- 5 minutes
  },
  backlinks = {
    enabled = true,
    show_in_buffer = true,              -- Auto-update backlinks section
  },
  gtd_integration = {
    enabled = true,
    sync_tags = true,
    create_note_refs = true,
  },
  notifications = {
    enabled = true,
    timeout = 2000,
  },
  
  -- Keymaps (optional)
  -- false = disable keymaps
  -- true/nil = default keymaps
  -- { ... } = custom configuration
  keymaps = {
    prefix = "<leader>z",  -- Change prefix
    -- Override specific keys (set to "" to disable)
    -- new_note = "n",
    -- daily_note = "d",
  },
})
```

## ⌨️ Keymaps

All keymaps use the `<leader>z` prefix by default.

### Notes Creation

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>zn` | `:ZettelNew` | 󰎞 New note |
| `<leader>zd` | `:ZettelDaily` |  Daily note |
| `<leader>zq` | `:ZettelQuick` | 󱓧 Quick note |
| `<leader>zp` | `:ZettelProject` |  New project |
| `<leader>zM` | `:ZettelMeeting` | 󰤙 New meeting |

### People

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>zo` | `:ZettelPerson` |  New person |
| `<leader>zO` | `:ZettelPeople` |  List people |
| `<leader>zI` | `:ZettelInteractions` |  Recent interactions |

### Search & Navigation

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>zf` | `:ZettelFind` |  Find notes (files) |
| `<leader>zs` | `:ZettelSearch` |  Search content |
| `<leader>za` | `:ZettelSearchAll` |  Search all (Notes+GTD) |
| `<leader>zr` | `:ZettelRecent` |  Recent notes |
| `<leader>zt` | `:ZettelTags` |  Browse tags |
| `<leader>zb` | `:ZettelBacklinks` | 󰌹 Show backlinks |
| `<leader>zg` | `:ZettelGTD` |  GTD tasks |

### Management

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>zm` | `:ZettelManage` | 󰧑 Manage notes |
| `<leader>zc` | `:ZettelClearCache` | 󰑐 Clear cache |
| `<leader>zi` | `:ZettelStats` | 󰄪 Statistics |
| `<leader>zu` | `:ZettelUpdateBacklinks` | 󰌹 Update backlinks |

### Legacy (if modules available)

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>zB` | `:ZettelBooks` |  List books |
| `<leader>zR` | `:ZettelReadingDash` |  Reading dashboard |
| `<leader>zP` | `:ZettelProjects` |  List projects |
| `<leader>zD` | `:ZettelProjectDash` |  Project dashboard |

### Custom Keymaps

```lua
require("gtd-nvim.zettelkasten").setup({
  keymaps = {
    prefix = "<leader>n",     -- Use <leader>n instead of <leader>z
    new_note = "n",           -- <leader>nn for new note
    daily_note = "d",         -- <leader>nd for daily
    find_notes = "f",         -- <leader>nf for find
    search_all = "",          -- Disable search all keymap
  },
})
```

Or setup keymaps manually:

```lua
require("gtd-nvim.zettelkasten").setup({ keymaps = false })

-- Then set your own
local zk = require("gtd-nvim.zettelkasten")
vim.keymap.set("n", "<leader>nn", zk.new_note, { desc = "New note" })
vim.keymap.set("n", "<leader>nd", zk.daily_note, { desc = "Daily note" })
```

## 📋 Commands

### Note Creation

| Command | Description |
|---------|-------------|
| `:ZettelNew [title]` | Create a new note |
| `:ZettelDaily` | Open/create today's daily note with GTD sync |
| `:ZettelQuick [title]` | Quick capture note with timestamp |
| `:ZettelProject [title]` | Create a project note |
| `:ZettelReading [title]` | Create a reading/book note |
| `:ZettelMeeting [title]` | Create a meeting note |

### Search & Navigation

| Command | Description |
|---------|-------------|
| `:ZettelFind` | Find notes by filename (fzf-lua) |
| `:ZettelSearch` | Search note contents (ripgrep) |
| `:ZettelSearchAll` | Search across Notes + GTD directories |
| `:ZettelRecent` | Browse recently opened notes |
| `:ZettelTags` | Browse all tags, then files by tag |
| `:ZettelBacklinks` | Show backlinks for current note |

### GTD Integration

| Command | Description |
|---------|-------------|
| `:ZettelGTD` | Browse GTD tasks from org files |

**GTD Picker Keys:**
- `Enter` — Open org file at task line
- `Ctrl-z` — Create Zettel note for task

### File Management

| Command | Description |
|---------|-------------|
| `:ZettelManage` | File manager with multi-select |

**Manage Picker Keys:**
- `Tab` — Toggle selection
- `Enter` — Open file
- `Ctrl-d` — Delete selected
- `Ctrl-a` — Archive selected
- `Ctrl-r` — Move selected to directory
- `?` — Show help

### People/CRM

| Command | Description |
|---------|-------------|
| `:ZettelPerson [name]` | Create a person/contact note |
| `:ZettelPeople` | Browse and manage people |
| `:ZettelPeopleDirectory` | Generate directory by relationship |
| `:ZettelInteractions` | Show recent interactions (30 days) |
| `:ZettelBirthdays` | Show upcoming birthdays |

**People Picker Keys:**
- `Enter` — Open person file
- `Ctrl-n` — Create new person
- `Ctrl-m` — Add meeting to person
- `Ctrl-i` — Add interaction to person

### Utilities

| Command | Description |
|---------|-------------|
| `:ZettelStats` | Show statistics (notes, tags, tasks) |
| `:ZettelIndex` | Rebuild notes index |
| `:ZettelClearCache` | Clear internal cache |
| `:ZettelUpdateBacklinks` | Update backlinks in current buffer |

## 🎨 Glyphs

The module uses Nerd Font glyphs throughout:

| Glyph | Meaning |
|-------|---------|
| 󰎞 | Zettel note |
|  | Daily note |
| 󱓧 | Quick note |
|  | Project |
|  | Reading/book |
|  | Person |
| 󰤙 | Meeting |
|  | Search |
|  | Link |
| 󰌹 | Backlink |
|  | Tag |
| 󰧑 | Brain/manage |

## 📝 Note Templates

### Standard Note
```markdown
# {{title}}

**Created:** {{created}}
**ID:** {{id}}
**Tags:** {{tags}}

## Notes

## Related

## Backlinks
```

### Daily Note
```markdown
# 󰃭 {{date}}

## Tasks
- [ ] 

## Notes

## GTD Sync
{{gtd_tasks}}

## Reflections
```

### Person Note
```markdown
# {{name}}

**Created:** {{created}}
**Relationship:** {{relationship}}
**Tags:** #person

## Contact
- **Email:** 
- **Phone:** 
- **Company:** 
- **Location:** 

## Notes

## Meetings

## Interactions
```

## 🔗 Backlinks

Backlinks are automatically detected when notes reference each other using:
- Wiki-style: `[[note-name]]`
- Markdown: `[text](note-name.md)`
- Relative paths: `[text](../folder/note.md)`

Use `:ZettelBacklinks` to see all notes linking to the current file.

## 🏷️ Tags

Tags are extracted from note content:
- Markdown style: `#tag`
- Org style: `:tag:`

Browse all tags with `:ZettelTags`, then select a tag to see all files using it.

## 📊 GTD Integration

When GTD integration is enabled, the module:

1. Scans `~/Documents/GTD/` for org-mode files
2. Extracts TODO, NEXT, WAITING tasks
3. Syncs active tasks into daily notes
4. Allows browsing tasks with `:ZettelGTD`

Task states recognized:
- `TODO` — Standard todo
- `NEXT` — Next action
- `WAITING` — Waiting for someone/something
- `DONE` — Completed
- `PROJ` — Project
- `SOMEDAY` — Someday/maybe

## 🗂️ Module Architecture

```
zettelkasten/
├── init.lua          # Entry point, command registration
├── core.lua          # Config, cache, utilities, paths
├── notes.lua         # Note creation, templates, index
├── search.lua        # Find, search, browse, tags
├── gtd.lua           # GTD task extraction, browsing
├── file_manage.lua   # Delete, archive, move operations
├── people.lua        # Person/contact management
├── capture.lua       # Quick capture (legacy)
├── project.lua       # Project notes (legacy)
├── reading.lua       # Reading notes (legacy)
└── manage.lua        # File management (legacy)
```

### Core Dependencies

```
init.lua
    ├── core.lua ←── All modules depend on this
    ├── notes.lua
    ├── search.lua
    ├── gtd.lua
    ├── file_manage.lua
    └── people.lua (legacy, self-contained)
```

## 🔧 API

### Lua API

```lua
local zk = require("gtd-nvim.zettelkasten")

-- Get paths
local paths = zk.get_paths()
-- paths.notes_dir, paths.gtd_dir, etc.

-- Get statistics
local stats = zk.get_stats()
-- stats.notes_count, stats.tags_count, stats.gtd_tasks_count

-- Clear cache
zk.clear_all_cache()

-- Create note programmatically
zk.create_note_file({
  title = "My Note",
  dir = paths.notes_dir,
  template = "note",
  tags = "#example",
  open = true,
})
```

## 🐛 Troubleshooting

### "fzf-lua required"
Install fzf-lua: `{ "ibhagwan/fzf-lua" }`

### Junk files appearing (.DS_Store, etc.)
The module filters these automatically. If you see them, run `:ZettelClearCache`

### GTD tasks not syncing
- Check `gtd_dir` points to your org files
- Ensure files have `.org` extension
- Tasks must start with `* TODO`, `* NEXT`, etc.

### Backlinks not updating
Run `:ZettelUpdateBacklinks` or save the file (auto-updates on save)

## 📄 License

MIT License — See LICENSE file

## 🙏 Credits

Part of the [gtd-nvim](https://github.com/your-username/gtd-nvim) project.

Built with:
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [Nerd Fonts](https://www.nerdfonts.com/)
