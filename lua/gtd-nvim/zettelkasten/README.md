# Zettelkasten Modular System

A complete note-taking, GTD integration, and knowledge management system for Neovim.

## Architecture

```
~/.config/nvim/lua/utils/
├── zettelkasten.lua           # Core module (index, search, backlinks, tags)
└── zettelkasten/
    ├── init.lua               # Module loader (use this!)
    ├── capture.lua            # Quick capture, daily notes, GTD capture
    ├── project.lua            # Project management & dashboard
    └── manage.lua             # Mass file operations
```

## Setup

### In your `init.lua` or `lazy.nvim`:

```lua
-- Option 1: Simple setup (loads all modules)
require("utils.zettelkasten").setup()

-- Option 2: Custom config
require("utils.zettelkasten").setup({
  notes_dir = "~/Documents/Notes",
  gtd_dir = "~/Documents/GTD",
  gtd_integration = {
    enabled = true,
  },
  keymaps = true,  -- Set to false to disable default keymaps
})
```

## Commands

### Core Commands (from `zettelkasten.lua`)
- `:ZettelNew [title]` - Create new note
- `:ZettelFind` - Fuzzy find notes
- `:ZettelSearch` - Live grep search
- `:ZettelSearchAll` - Search notes + GTD
- `:ZettelRecent` - Recent notes
- `:ZettelBacklinks` - Show backlinks for current file
- `:ZettelTags` - Browse by tags
- `:ZettelGTD` - Browse GTD tasks
- `:ZettelStats` - Show statistics
- `:ZettelClearCache` - Clear cache

### Capture Commands (from `capture.lua`)
- `:ZettelQuick [title]` - Quick note capture
- `:ZettelDaily` - Open/create today's daily note (with GTD sync)
- `:ZettelCapture [text]` - Capture to GTD inbox
- `:ZettelMeeting [title]` - Create meeting note

### Project Commands (from `project.lua`)
- `:ZettelProject [title]` - Create new project
- `:ZettelProjectList` - List all projects
- `:ZettelProjectDashboard` - Generate project dashboard

### Management Commands (from `manage.lua`)
- `:ZettelManage` - Mass file management with multi-select
- `:ZettelBulkTag` - Add tag to multiple files
- `:ZettelBulkUntag` - Remove tag from multiple files

## Default Keymaps

### Core
- `<leader>zn` - New note
- `<leader>zf` - Find notes
- `<leader>zs` - Search content
- `<leader>zr` - Recent notes
- `<leader>zb` - Show backlinks
- `<leader>zg` - Browse GTD tasks

### Capture
- `<leader>zq` - Quick note
- `<leader>zd` - Daily note
- `<leader>zc` - GTD capture
- `<leader>zM` - Meeting note

### Projects
- `<leader>zp` - New project
- `<leader>zP` - List projects
- `<leader>zD` - Project dashboard

### Management
- `<leader>zm` - Manage notes (multi-select)
- `<leader>zt` - Bulk tag add
- `<leader>zT` - Bulk tag remove

## Multi-Select in Management

When you open `:ZettelManage` (or `<leader>zm`):

1. **TAB** - Mark/unmark files
2. **Shift-TAB** - Unmark file
3. **Alt-A** - Select all
4. **Alt-D** - Deselect all
5. **Ctrl-D** - Delete selected files
6. **Ctrl-A** - Archive selected files
7. **Ctrl-R** - Move selected files
8. **?** - Show help

The selection counter shows in the top right (e.g., `5/687`).

## Index Maintenance

The index file (`~/Documents/Notes/index.md`) is **automatically maintained** by all modules:

- Updated when notes are created
- Updated when notes are deleted/archived/moved
- Updated by cache invalidation
- Shows total notes, tags, and directory breakdown

## Module Integration

All modules integrate through the core API:

```lua
local core = require("utils.zettelkasten")

-- Available API functions:
core.get_config()                 -- Get current config
core.notify(msg, level, opts)     -- Send notification
core.clear_cache(key)             -- Clear cache
core.get_gtd_tasks()              -- Get GTD tasks
core.get_all_tags()               -- Get all tags
core.get_all_notes()              -- Get all notes
core.write_index()                -- Rebuild index
core.sel_to_paths_fzf(selected)   -- Convert fzf selection to paths
```

## Templates

Templates are stored in `~/Documents/Notes/Templates/`:

- `note.md` - Standard note template
- `daily.md` - Daily note template (with `{{gtd_tasks}}` variable)
- `quick.md` - Quick note template
- `project.md` - Project template
- `meeting.md` - Meeting note template

Template variables:
- `{{title}}` - Note title
- `{{created}}` - Creation datetime
- `{{date}}` - Creation date
- `{{id}}` - Unique ID
- `{{tags}}` - Tags
- `{{gtd_tasks}}` - GTD tasks (daily notes only)

## GTD Integration

When enabled, the system:
- Syncs tasks from `~/Documents/GTD` (org-mode files)
- Shows tasks in daily notes
- Allows task capture to `inbox.org`
- Supports up to 600 tasks
- Sorts by priority: NEXT → TODO → WAITING → PROJECT → SOMEDAY → DONE

## Cache System

5-minute TTL on:
- File discovery
- GTD tasks
- Backlinks
- Tags

Clear manually with `:ZettelClearCache` or programmatically with `core.clear_cache()`.

## File Organization

```
~/Documents/Notes/
├── index.md                 # Auto-generated index
├── Daily/                   # Daily notes
├── Quick/                   # Quick captures
├── Projects/                # Project notes
│   ├── DASHBOARD.md        # Auto-generated dashboard
│   └── Archive/            # Archived projects
├── Templates/               # Note templates
└── Archive/                 # Archived notes
```

## Examples

### Create Custom Capture Workflow

```lua
local capture = require("utils.zettelkasten.capture")

vim.keymap.set("n", "<leader>zi", function()
  vim.ui.input({ prompt = "Idea: " }, function(text)
    if text and text ~= "" then
      capture.quick_note("Idea: " .. text)
    end
  end)
end, { desc = "Capture idea" })
```

### Custom Project Workflow

```lua
local project = require("utils.zettelkasten.project")

vim.keymap.set("n", "<leader>zw", function()
  project.dashboard()  -- Open dashboard
end, { desc = "Weekly project review" })
```

### Custom Bulk Operations

```lua
local manage = require("utils.zettelkasten.manage")

-- Archive all notes older than 1 year
function archive_old_notes()
  local paths = require("utils.zettelkasten").get_all_notes()
  local old_notes = {}
  
  for _, note in ipairs(paths) do
    local mtime = vim.loop.fs_stat(note.path).mtime.sec
    local age_days = (os.time() - mtime) / 86400
    
    if age_days > 365 then
      table.insert(old_notes, note.path)
    end
  end
  
  if #old_notes > 0 then
    manage.archive_notes(old_notes)
  end
end
```

## Philosophy

This modular system follows Unix philosophy:
- **Core** - Do one thing well (index, search, backlinks)
- **Capture** - Fast note entry points
- **Project** - Project lifecycle management
- **Manage** - Bulk file operations

Each module is independent but integrates through the core API.

## License

MIT
