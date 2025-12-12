# GTD-Nvim

A comprehensive Getting Things Done (GTD) system for Neovim, built with Lua. Integrates with orgmode files, fzf-lua for fuzzy finding, which-key for keybindings, and zettelkasten note-taking.

## Overview

GTD-Nvim implements David Allen's GTD methodology with five core phases:

1. **Capture** - Quickly capture thoughts and tasks to your inbox
2. **Clarify** - Process inbox items, add context, dates, and priorities
3. **Organize** - Refile tasks to projects and areas
4. **Reflect** - Weekly review with guided cockpit interface
5. **Engage** - Work from actionable task lists

## Features

- 📥 **Quick Capture** - Capture tasks from anywhere with `<leader>cc`
- ✅ **Task Clarification** - Add status, priority, dates, and zettelkasten links
- 📁 **Smart Organization** - Refile tasks to projects with fzf-lua picker
- 📋 **GTD Lists** - Next Actions, Waiting For, Projects, Someday/Maybe
- 📅 **Calendar Integration** - Apple Calendar sync with Danish/English date support
- 🔔 **Reminders Sync** - Bidirectional Apple Reminders integration
- 📊 **Weekly Review** - Guided review cockpit with progress tracking
- 🔗 **Zettelkasten Links** - Connect tasks to knowledge notes
- 🏷️ **Task IDs** - Unique identifiers for task tracking
- 📈 **Status Line** - Mini status with task counts

## Requirements

- Neovim 0.9+
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [nvim-orgmode](https://github.com/nvim-orgmode/orgmode)
- [which-key.nvim](https://github.com/folke/which-key.nvim) (recommended)
- macOS (for Calendar/Reminders integration)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-username/gtd-nvim",
  dependencies = {
    "ibhagwan/fzf-lua",
    "nvim-orgmode/orgmode",
  },
  config = function()
    require("gtd-nvim.gtd").setup({
      gtd_root = "~/Documents/GTD",
      zk_root = "~/Documents/Notes",
      inbox_file = "Inbox.org",
      projects_dir = "Projects",
    })
  end,
}
```

## Directory Structure

```
~/Documents/GTD/
├── Inbox.org           # Capture inbox
├── Archive.org         # Completed/cancelled tasks
├── Areas/              # Areas of responsibility
│   ├── Health.org
│   ├── Finance.org
│   └── ...
├── Projects/           # Active projects
│   ├── 10-ProjectName.org
│   ├── 20-AnotherProject.org
│   └── ...
└── Reviews/            # Weekly review notes
    ├── 2025-W49.md
    └── ...
```

## Commands

| Command | Description |
|---------|-------------|
| `:GtdCapture` | Quick capture to inbox |
| `:GtdClarify` | Clarify task at cursor |
| `:GtdRefile` | Refile task to project |
| `:GtdProjectNew` | Create new project |
| `:GtdConvertToProject` | Convert task to project |
| `:GtdLists` | Open GTD lists menu |
| `:GtdReview` | Start weekly review |
| `:GtdReviewIndex` | Browse past reviews |
| `:GtdEdit` | Open task editor |
| `:GtdStatus` | Show GTD statistics |
| `:GtdHealth` | Check system health |
| `:GtdVersion` | Show version info |

## Keybindings

All keybindings are under `<leader>c` (GTD prefix):

### Capture & Clarify
| Key | Action |
|-----|--------|
| `<leader>cc` | Quick capture |
| `<leader>cx` | Clarify at cursor |
| `<leader>cX` | Clarify and promote |
| `<leader>ce` | Task editor |

### Organize
| Key | Action |
|-----|--------|
| `<leader>cr` | Refile to project |
| `<leader>cp` | New project |
| `<leader>cP` | Convert to project |

### Lists
| Key | Action |
|-----|--------|
| `<leader>cl` | Lists menu |
| `<leader>cn` | Next actions |
| `<leader>cw` | Waiting for |
| `<leader>cs` | Someday/maybe |
| `<leader>cj` | Projects |

### Review
| Key | Action |
|-----|--------|
| `<leader>cR` | Weekly review |
| `<leader>cI` | Review index |

### Integrations
| Key | Action |
|-----|--------|
| `<leader>cC` | Calendar menu |
| `<leader>cM` | Reminders menu |

## Modules

### capture.lua
Quick capture interface for adding tasks to inbox. Supports templates and automatic task ID generation.

### clarify.lua
Task clarification wizard. Add/modify:
- Status (TODO, NEXT, WAITING, SOMEDAY, DONE, CANCELLED)
- Priority ([#A], [#B], [#C])
- Scheduled/Deadline dates
- Zettelkasten note links
- WAITING FOR metadata (who, what, when, follow-up)

### organize.lua
Refile tasks between files. Preserves task IDs and zettelkasten links during moves.

### projects.lua
Project management:
- Create new projects with templates
- Convert tasks to projects
- Link tasks to existing projects

### lists.lua
GTD list views with fzf-lua:
- **Next Actions** - NEXT and TODO tasks
- **Waiting For** - Tasks waiting on others
- **Projects** - Active projects
- **Stuck Projects** - Projects without next actions
- **Someday/Maybe** - Future possibilities

### review.lua (v1.0.0)
Weekly review cockpit with three phases:

**GET CLEAR**
- Collect loose papers and materials
- Process inbox to zero
- Empty your head

**GET CURRENT**
- Review action lists
- Review past/upcoming calendar
- Review waiting for items
- Review projects
- Review stuck projects
- Review checklists

**GET CREATIVE**
- Review someday/maybe
- Brainstorm new ideas

Features:
- Progress tracking with checkmarks
- Review history index
- Note-taking during review
- Ctrl-B return navigation

### editor.lua
Full task editor interface for detailed task modification.

### calendar.lua
Apple Calendar integration:
- View upcoming events
- Pull events as tasks
- Danish/English date format support

### reminders.lua
Apple Reminders integration:
- Sync tasks to/from Reminders
- Priority mapping
- Due date handling

### status.lua
Status line integration showing:
- Total tasks (T)
- Projects (P)
- Today's tasks (TD)
- Next actions (N)
- Waiting items (W)
- Overdue (O)

### shared.lua
Shared utilities:
- Glyph/icon definitions
- Color schemes
- Common helper functions
- Configuration

## Task States

| State | Glyph | Description |
|-------|-------|-------------|
| `TODO` | ○ | Task to be done |
| `NEXT` | ◉ | Next physical action |
| `WAITING` | ⏳ | Waiting on someone/something |
| `SOMEDAY` | 💭 | Future possibility |
| `DONE` | ✓ | Completed |
| `CANCELLED` | ✗ | Cancelled |

## Task ID Format

Tasks are assigned unique IDs in the format:
```
[[zk:YYYYMMDDHHmmss]]
```

Example: `[[zk:202512101430]]`

These IDs enable:
- Linking tasks to zettelkasten notes
- Tracking tasks across refiles
- Duplicate detection

## Weekly Review Workflow

1. Start with `:GtdReview` or `<leader>cR`
2. Navigate steps with `j/k`
3. Press `Enter` to execute step action
4. Press `Space` to mark step complete
5. Use `Ctrl-B` to return from task editing
6. Progress auto-saves between sessions

## Configuration

```lua
require("gtd-nvim.gtd").setup({
  -- Paths
  gtd_root = "~/Documents/GTD",
  zk_root = "~/Documents/Notes",
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  
  -- Review settings
  review = {
    left_panel_width = 45,
    review_dir = "Reviews",
  },
  
  -- Glyphs (optional customization)
  glyphs = {
    states = {
      TODO = "○",
      NEXT = "◉",
      DONE = "✓",
    },
  },
})
```

## Health Check

Run `:GtdHealth` to verify:
- All modules loaded correctly
- GTD directory structure exists
- Required dependencies available

## Version History

- **1.0.0** (2024-12-10) - First stable release
  - Weekly review cockpit
  - Task editor
  - Full GTD workflow

## License

MIT

## Credits

Inspired by David Allen's Getting Things Done methodology and built for the Neovim ecosystem.
