# Zettelkasten Modular System v2.0

A complete note-taking, GTD integration, and knowledge management system for Neovim.

## Architecture

```
~/.config/nvim/lua/utils/
├── zettelkasten.lua           # Entry point (loads core)
└── zettelkasten/
    ├── init.lua               # Full system loader
    ├── core.lua               # Core: notes, search, tags, backlinks, cache
    ├── capture.lua            # GTD-integrated capture (daily, meeting, tasks)
    ├── manage.lua             # Mass file operations
    ├── project.lua            # Project management
    ├── people.lua             # Contact/person notes
    └── reading.lua            # Book notes
```

## Key Features

### 1. GTD Task Sync (capture.lua)

Daily notes automatically pull tasks from `~/Documents/GTD/*.org`:

- ⚡ **NEXT** - Highest priority actions
- 📋 **TODO** - Standard tasks  
- ⏳ **WAITING** - Blocked/waiting tasks

Each task links back to its source org file:
```markdown
- [ ] ⚡ **NEXT** Review proposal [[file:~/Documents/GTD/Projects.org][Projects]]
```

### 2. Meeting Action Extraction

1. Create meeting note with `:ZettelMeeting`
2. Add action items under `## Action Items`
3. On save, unchecked items are extracted to GTD Inbox
4. Items marked with `[GTD]` suffix after extraction

### 3. Proper ZK_LINK Handling

**Fixed:** ZK_LINK is ONLY added when a note actually exists.

```
Capture → "Create note?" → No  → Task added WITHOUT :ZK_LINK:
                         → Yes → Note created → Task added WITH :ZK_LINK:
```

## Setup

```lua
-- In init.lua or lazy config
require("utils.zettelkasten.init").setup({
  keymaps = true,  -- Enable default keymaps
})
```

## Keymaps

### Core (`<leader>z...`)
| Key | Function | Description |
|-----|----------|-------------|
| `zn` | `new_note` | Create new note |
| `zo` | `find_notes` | Open/find notes |
| `zf` | `search_notes` | Search content |
| `zr` | `recent_notes` | Recent notes |
| `zt` | `browse_tags` | Browse by tags |
| `zb` | `show_backlinks` | Show backlinks |
| `za` | `search_all` | Search notes + GTD |
| `zi` | `show_stats` | Statistics |

### Capture (GTD Integrated)
| Key | Function | Description |
|-----|----------|-------------|
| `zd` | `daily_note` | Daily note with GTD sync |
| `zq` | `quick_note` | Quick capture |
| `zM` | `meeting_note` | Meeting note |
| `zc` | `capture_to_gtd` | Capture → GTD Inbox |
| `zG` | `note_to_gtd_task` | Convert note → GTD task |
| `zg` | `browse_gtd_tasks` | Browse GTD tasks |
| `zX` | `extract_actions_now` | Extract meeting actions |
| `zR` | `refresh_daily_gtd` | Refresh GTD in daily |

### Management
| Key | Function | Description |
|-----|----------|-------------|
| `zm` | `manage_notes` | Mass file management |
| `zp` | `new_project` | New project |
| `zP` | `list_projects` | List projects |

## Commands

```vim
" Core
:ZettelNew [title]      " New note
:ZettelFind             " Find notes
:ZettelSearch           " Search content
:ZettelTags             " Browse tags
:ZettelBacklinks        " Show backlinks
:ZettelStats            " Statistics

" Capture (GTD)
:ZettelDaily            " Daily note with GTD
:ZettelQuick [title]    " Quick note
:ZettelMeeting [title]  " Meeting note
:ZettelCapture [text]   " Capture to GTD
:ZettelToGtd            " Current note → GTD
:ZettelGTD              " Browse GTD tasks
:ZettelExtractActions   " Extract meeting actions
:ZettelRefreshGtd       " Refresh GTD tasks

" Management
:ZettelManage           " File manager
:ZettelBulkTag          " Add tag to files
:ZettelBulkUntag        " Remove tag
```

## File Structure

```
~/Documents/Notes/
├── INDEX.md            # Auto-generated index
├── Daily/              # Daily notes (YYYY-MM-DD.md)
├── Quick/              # Quick captures
├── Projects/           # Project notes
├── People/             # Person notes
├── Reading/            # Book notes
├── Templates/          # Note templates
└── Archive/            # Archived notes

~/Documents/GTD/
├── Inbox.org           # Capture inbox
├── Projects.org        # Active projects
└── Someday.org         # Someday/maybe
```

## Cache System

5-minute TTL cache for:
- File discovery
- GTD tasks
- Tags
- Backlinks

Clear with `:ZettelClearCache` or `core.clear_cache()`

## Template Variables

| Variable | Description |
|----------|-------------|
| `{{title}}` | Note title |
| `{{created}}` | Creation datetime |
| `{{date}}` | Creation date |
| `{{id}}` | Unique ID (YYYYMMDDHHMM) |
| `{{tags}}` | Tags |
| `{{gtd_tasks}}` | GTD task list (daily notes) |

## License

MIT
