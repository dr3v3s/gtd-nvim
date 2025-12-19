# GTD-NVIM Project Handover Document

> **Purpose**: This document enables any new Claude session to immediately understand and continue development on gtd-nvim without losing context.
> **Last Updated**: 2025-12-18
> **Version**: 1.0.0-alpha

---

## Project Overview

**gtd-nvim** is a comprehensive GTD (Getting Things Done) system for Neovim, built entirely in Lua with org-mode file formats. It integrates GTD methodology with Zettelkasten note-taking principles.

### Goals
- "The greatest terminal-based GTD system ever invented"
- Public GitHub release planned
- Full GTD workflow: Capture → Clarify → Organize → Review → Engage
- Strict org-mode compliance
- Fast, keyboard-driven fzf-lua interface

---

## Directory Structure

```
~/.config/nvim/lua/gtd/           # Personal configuration (active development)
~/projects/gtd-nvim/              # Plugin version for GitHub
~/Documents/GTD/                  # GTD data files
~/Documents/Notes/                # Zettelkasten notes
~/.cache/kairos/                  # Kairos daemon cache
```

### Key Files in ~/.config/nvim/lua/gtd/

| File | Version | Purpose |
|------|---------|---------|
| `shared.lua` | 1.0.0 | Core utilities, glyphs, colors, org parsing |
| `init.lua` | 1.0.0-alpha | Main entry point, setup, commands |
| `capture.lua` | 0.9.0 | Quick capture to Inbox with WAITING support |
| `clarify.lua` | 0.9.0 | GTD clarification workflow |
| `organize.lua` | 1.0.0 | Refile, task organization |
| `manage.lua` | 1.0.0 | Task/project management pickers |
| `lists.lua` | 1.0.0 | GTD lists (Next Actions, Projects, Waiting, etc.) |
| `projects.lua` | 0.8.0 | Project CRUD, ZK integration |
| `areas.lua` | 0.8.0 | Areas of Focus support |
| `review.lua` | 1.2.0 | Weekly Review cockpit (12 steps, 3 phases) |
| `status.lua` | 0.8.0 | Status change functionality |
| `fzf.lua` | 1.0.0 | Centralized fzf-lua utilities |
| `ui.lua` | 0.8.0 | UI helpers, notifications |
| `editor.lua` | 0.8.0 | Task editor |
| `calendar.lua` | 0.8.0 | Calendar integration |
| `icalbuddy.lua` | 0.8.0 | iCalBuddy wrapper |
| `reminders.lua` | 0.8.0 | Apple Reminders integration |

### Supporting Utilities

```
~/.config/nvim/lua/utils/gtd-audit/   # Org-mode audit tools
  ├── init.lua                        # Main entry
  ├── parser.lua                      # Org parsing
  ├── validators.lua                  # Validation rules
  ├── reports.lua                     # Report generation
  ├── insights.lua                    # Analytics
  └── migrate.lua                     # Migration tools

~/.config/nvim/lua/gtd/utils/
  └── task_id.lua                     # TASK_ID generation, validation
```

---

## Architecture Principles

### 1. Org-Mode Compliance (Non-Negotiable)
```org
* TODO Task title                           :tag1:tag2:
SCHEDULED: <2024-12-18>
DEADLINE: <2024-12-25>
:PROPERTIES:
:ID:        20241218143052
:TASK_ID:   20241218143052
:ZK_LINK:   [[file:~/Documents/Notes/Projects/20241218143052-title.md][title.md]]
:END:
ID:: [[zk:20241218143052]]
```

### 2. ID System
- Format: `YYYYMMDDHHMMSS` (14 digits) + optional suffix (`a`, `b`, `aa`, etc.)
- Same ID in `:ID:`, `:TASK_ID:`, and `ID:: [[zk:...]]` breadcrumb
- Collision avoidance with suffix increment

### 3. State Keywords
```lua
STATES = { "TODO", "NEXT", "WAITING", "SOMEDAY", "DONE", "PROJECT", "CANCELLED" }
```

### 4. GTD Hierarchy (Sorting Priority)
1. Inbox (highest priority)
2. Areas of Focus
3. Projects
4. Someday/Maybe
5. Reference
6. Archive (lowest)

### 5. Cross-Module Patterns
- All modules use `shared.lua` for utilities
- `fzf.lua` provides centralized picker configuration
- `vim.schedule()` required for chained fzf calls
- ANSI colors for fzf, highlight groups for buffers

---

## Areas of Focus Configuration

```lua
-- ~/.config/nvim/lua/gtd/areas.lua
M.base_dir = vim.fn.expand("~/Documents/GTD/Areas")
M.areas = {
  { name = "10-Personal",  dir = M.base_dir .. "/10-Personal" },
  { name = "11-Ditte",     dir = M.base_dir .. "/11-Ditte" },
  { name = "20-Household", dir = M.base_dir .. "/20-Household" },
  { name = "30-Children",  dir = M.base_dir .. "/30-Children" },
  { name = "40-Friends",   dir = M.base_dir .. "/40-Friends" },
  { name = "50-GTD",       dir = M.base_dir .. "/50-GTD" },
  { name = "80-DDS",       dir = M.base_dir .. "/80-DDS" },
  { name = "90-WORK",      dir = M.base_dir .. "/90-WORK" },
}
```

---

## Kairos Daemon Integration

### What is Kairos?
A background daemon providing real-time GTD metrics via Unix socket and JSON cache files.

### Socket Path
```
~/.cache/kairos/kairos.sock
```

### Cache Files
| File | Purpose |
|------|---------|
| `gtd.json` | GTD metrics (counts by state) |
| `tasks.json` | All tasks with metadata |
| `next.json` | NEXT actions |
| `waiting.json` | WAITING items |
| `overdue.json` | Overdue tasks |
| `calendar.json` | Calendar events |
| `reminders.json` | Apple Reminders |
| `mail.json` | Mail counts |

### gtd.json Structure
```json
{
  "total": 54,
  "next": 13,
  "todo": 11,
  "waiting": 0,
  "someday": 5,
  "projects": 22,
  "done": 3,
  "overdue": 5,
  "recurring": 4,
  "inbox": 3,
  "updated_at": 1766081776
}
```

### Integration Status: NOT STARTED
**Task**: Create `~/.config/nvim/lua/gtd/kairos.lua` module to:
1. Query Unix socket for real-time metrics
2. Replace slow file scanning with daemon queries
3. Provide fallback to file scanning if daemon unavailable
4. Update status bar, lists, review with Kairos data

---

## PENDING TASK: Kairos Integration

### Implementation Plan

1. **Create `kairos.lua` module**
   ```lua
   -- lua/gtd/kairos.lua
   local M = {}
   M.socket_path = vim.fn.expand("~/.cache/kairos/kairos.sock")
   M.cache_dir = vim.fn.expand("~/.cache/kairos")
   
   function M.is_available() ... end
   function M.query(request) ... end  -- Unix socket query
   function M.get_metrics() ... end   -- Read gtd.json
   function M.get_tasks() ... end     -- Read tasks.json
   function M.get_next() ... end      -- Read next.json
   ```

2. **Update modules to use Kairos**
   - `lists.lua`: Use Kairos for task lists instead of file scan
   - `manage.lua`: Use Kairos for project/task counts
   - `review.lua`: Pull metrics from Kairos for weekly review
   - `shared.lua`: Add Kairos helpers

3. **Fallback Pattern**
   ```lua
   local function get_tasks()
     local kairos = safe_require("gtd.kairos")
     if kairos and kairos.is_available() then
       return kairos.get_tasks()
     end
     -- Fallback to file scanning
     return scan_gtd_files()
   end
   ```

---

## Key Design Decisions

### vim.schedule() for Chained Pickers
```lua
-- WRONG: Second picker fails
fzf.fzf_exec(items1, { actions = {
  default = function()
    fzf.fzf_exec(items2, ...)  -- Fails!
  end
}})

-- CORRECT: Schedule second picker
fzf.fzf_exec(items1, { actions = {
  default = function()
    vim.schedule(function()
      fzf.fzf_exec(items2, ...)  -- Works!
    end)
  end
}})
```

### ANSI Colors in fzf Matching
Display strings with ANSI codes can break selection matching. Use separate display vs comparison arrays:
```lua
local display_items = {}  -- With colors
local meta_items = {}     -- Clean data
```

### Backward Compatibility
Never remove functionality. New features must gracefully degrade if dependencies unavailable.

---

## Testing Checklist

Before any change, verify:
- [ ] `:GtdCapture` works (Inbox capture)
- [ ] `:GtdClarify` works (at cursor)
- [ ] `:GtdClarifyPick` works (fzf picker)
- [ ] `:GtdRefile` works (to project)
- [ ] `:GtdProjectNew` works
- [ ] `:GtdManageTasks` works
- [ ] `:GtdManageProjects` works
- [ ] `:GtdNextActions` works
- [ ] `:GtdProjects` works
- [ ] `:GtdWaiting` works
- [ ] `:GtdReview` works (weekly review)
- [ ] Areas filtering works in all pickers
- [ ] Org-mode output is valid
- [ ] TASK_IDs are properly generated

---

## Sync Between Development and Plugin

```bash
# Personal config → Plugin
~/projects/gtd-nvim/sync-to-plugin.sh

# Or manual rsync
rsync -av --exclude='*.bak' --exclude='*~' \
  ~/.config/nvim/lua/gtd/ \
  ~/projects/gtd-nvim/lua/gtd-nvim/gtd/
```

---

## Audit Tools

### Run GTD Audit
```vim
:lua require('utils.gtd-audit').full_audit()
:lua require('utils.gtd-audit').validate_all()
:lua require('utils.gtd-audit').find_invalid_todos()
:lua require('utils.gtd-audit').find_malformed_properties()
```

### Common Issues Found
1. Invalid TODO keywords (typos, old formats)
2. Missing angle brackets in SCHEDULED/DEADLINE
3. Malformed PROPERTIES drawers
4. Legacy `ID::` breadcrumb formats
5. Duplicate TASK_IDs

---

## Commands Reference

| Command | Description |
|---------|-------------|
| `:GtdCapture` | Quick capture to Inbox |
| `:GtdClarify` | Clarify task at cursor |
| `:GtdClarifyPick` | Pick task and clarify |
| `:GtdRefile` | Refile task to project |
| `:GtdProjectNew` | Create new project |
| `:GtdConvertToProject` | Convert task to project |
| `:GtdLinkToProject` | Link task to project |
| `:GtdManage` | Management menu |
| `:GtdManageTasks` | Manage all tasks |
| `:GtdManageProjects` | Manage all projects |
| `:GtdNextActions` | List NEXT actions |
| `:GtdProjects` | List all projects |
| `:GtdWaiting` | List WAITING items |
| `:GtdSomedayMaybe` | List SOMEDAY items |
| `:GtdReview` | Weekly review cockpit |
| `:GtdHealth` | System health check |
| `:GtdVersion` | Show version info |
| `:GtdFindDuplicates` | Find duplicate IDs |

---

## Environment

- **OS**: macOS
- **Shell**: zsh
- **Editor**: Neovim
- **Package Manager**: Homebrew
- **Key Dependencies**: fzf-lua, orgmode.nvim (optional)

---

## Contact Points

- **GTD Data**: `~/Documents/GTD/`
- **Notes**: `~/Documents/Notes/`
- **Plugin Dev**: `~/projects/gtd-nvim/`
- **Personal Config**: `~/.config/nvim/lua/gtd/`
- **Kairos Cache**: `~/.cache/kairos/`

---

## How to Resume Work

1. Read this document first
2. Check `:GtdHealth` for system status
3. Review any TODO.md in the project
4. Use gtd-audit to verify data integrity
5. Test core commands before making changes
6. Never remove existing functionality
7. Ensure org-mode compliance in all outputs
8. Update this document with new decisions

---

*This document should be provided to any new Claude project working on gtd-nvim.*
