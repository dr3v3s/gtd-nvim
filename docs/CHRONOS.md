# gtd-nvim Chronos Integration

**Version:** 0.13.1  
**Updated:** 2025-12-21

Neovim plugin for GTD workflow powered by the Chronos daemon. Provides task management, project tracking, capture workflows, and Areas of Responsibility support.

## Installation

The plugin is loaded from `~/projects/gtd-nvim` and configured in your Neovim config:

```lua
-- ~/.config/nvim/lua/plugins/chronos.lua
return {
  dir = "~/projects/gtd-nvim",
  name = "chronos-gtd",
  lazy = false,
  dependencies = { "ibhagwan/fzf-lua" },
  config = function()
    local chronos = require("gtd-nvim.gtd.chronos")
    chronos.setup({
      keymaps = "<leader>x",
    })
  end,
}
```

## Requirements

- Neovim 0.9+
- fzf-lua plugin
- Chronos daemon running (`chronosd`)
- Nerd Font for icons

## Keybindings

All keybindings use the `<leader>x` prefix by default.

### Tasks (`<leader>xt`)

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>xta` | `:ChronosAll` | All active tasks |
| `<leader>xtn` | `:ChronosNext` | NEXT actions |
| `<leader>xtt` | `:ChronosTodo` | TODO tasks |
| `<leader>xtw` | `:ChronosWaiting` | WAITING tasks |
| `<leader>xts` | `:ChronosSomeday` | SOMEDAY tasks |

### Projects (`<leader>xp`)

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>xpp` | `:ChronosProjects` | Active projects (excludes ongoing/on-hold) |
| `<leader>xpa` | `:ChronosAllProjects` | All projects (grouped by status) |
| `<leader>xpn` | `:ChronosProject` | Create new project |
| `<leader>xpc` | `:ChronosConvertProject` | Convert file to project |

### Areas (`<leader>xo`)

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>xoa` | `:ChronosAreas` | Areas of Responsibility picker |

### Capture (`<leader>xc`)

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>xcq` | `:ChronosQuick` | Quick capture (brain dump) |
| `<leader>xcc` | `:ChronosCapture` | Full task capture with wizard |
| `<leader>xcv` | `:ChronosClipboard` | Capture from clipboard |

### Other

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>x/` | `:ChronosSearch` | Full-text search |
| `<leader>xa` | `:ChronosArchive` | Archive browser |
| `<leader>xr` | `:ChronosRemindersSync` | Trigger Reminders sync |
| `<leader>xs` | `:ChronosStatus` | Daemon status |

---

## Picker Actions

All pickers support common actions via keyboard shortcuts shown in the header.

### Task Picker Actions

| Key | Action |
|-----|--------|
| `Enter` | Open task in editor |
| `Ctrl-E` | Edit task in place |
| `Ctrl-D` | Mark DONE |
| `Ctrl-X` | Mark CANCELLED |
| `Ctrl-N` | Set to NEXT |
| `Ctrl-T` | Set to TODO |
| `Ctrl-A` | Archive task |
| `Ctrl-R` | Refile to different project |

### Project Picker Actions

| Key | Action |
|-----|--------|
| `Enter` | Open project file |
| `Ctrl-T` | Show project tasks |
| `Ctrl-O` | Toggle ONGOING status |
| `Ctrl-H` | Toggle ON_HOLD status |
| `Ctrl-A` | Archive project |

### All Projects Picker

Shows projects grouped by status:
- **Active** (󰷐) - Normal bounded projects
- **On Hold** (⏸) - Paused/deferred projects
- **Ongoing** (󰑖) - Continuous areas (not bounded)
- **Reminders** (󰅖) - Synced from Apple Reminders

### Areas Picker Actions

| Key | Action |
|-----|--------|
| `Enter` | Open `_AREA.md` definition |
| `Ctrl-P` | Show projects in area |
| `Ctrl-T` | Show all tasks in area |
| `Ctrl-R` | Area review dashboard |
| `Ctrl-N` | Create new area |
| `Ctrl-A` | Archive area |

---

## Capture Workflows

### Quick Capture (`<leader>xcq`)

Fast brain dump - just enter text and it goes to Inbox.org as a TODO.

### Full Capture (`<leader>xcc`)

Multi-step wizard:

1. **Title** - Task description
2. **State** - NEXT, TODO, WAITING, or SOMEDAY
3. **Destination** - Inbox, Project, or Area
4. **Schedule** - SCHEDULED and DEADLINE dates
5. **Tags** - Optional tags

**Smart Date Parsing:**
- `+1d` → tomorrow
- `+2w` → 2 weeks from now
- `+3m` → 3 months from now
- `mon` → next Monday
- `2025-12-25` → specific date

### Project Creation (`<leader>xpn`)

Creates a new project with proper structure:

1. **Name** - Project title
2. **Area** - Standalone or in an Area
3. **Outcome** - Desired outcome (optional)
4. **Next Action** - First task (optional)
5. **ZK Note** - Link to Zettelkasten note (optional)
6. **Type** - Active project or Ongoing area

---

## Project Properties

Projects can have special properties that affect display and filtering:

### ONGOING

Marks a project as an ongoing area (like "Home Maintenance") rather than a bounded project with a clear endpoint.

```org
* PROJECT Home Maintenance
:PROPERTIES:
:ONGOING:   t
:END:
```

- Excluded from active project picker (`<leader>xpp`)
- Shown in "Ongoing" section of all projects (`<leader>xpa`)
- Toggle with `Ctrl-O` in picker

### ON_HOLD

Marks a project as paused or deferred.

```org
* PROJECT Someday Project
:PROPERTIES:
:ON_HOLD:   t
:END:
```

- Excluded from active project picker
- Shown in "On Hold" section of all projects
- Toggle with `Ctrl-H` in picker

---

## Areas of Responsibility

GTD Horizon 2 - organizing life roles and responsibilities.

### Directory Structure

```
~/Documents/GTD/Areas/
├── 10-Personal/
│   ├── _AREA.md          # Area definition
│   ├── health.org        # Project
│   └── learning.org      # Project
├── 20-Household/
│   ├── _AREA.md
│   └── maintenance.org
└── ...
```

### Area Definition (`_AREA.md`)

```markdown
# Personal

My individual life, health, growth, and personal goals.

## Responsibilities

- Maintain physical and mental health
- Continue learning and personal development
- Pursue meaningful hobbies and interests
- Financial security and planning

## Standards to Maintain

- Exercise regularly
- Read and learn daily
- Annual health checkup
- Monthly budget review

## Review Questions

- [ ] Am I taking care of my health?
- [ ] Am I growing as a person?
- [ ] Am I neglecting any personal interests?
- [ ] Is my financial situation on track?
```

### Area Numbering Convention

| Range | Category |
|-------|----------|
| 10-19 | Personal/Individual |
| 20-29 | Home/Household |
| 30-39 | Family |
| 40-49 | Social/Friends |
| 50-59 | Systems/Tools |
| 60-79 | (Available) |
| 80-89 | Organizations/Clubs |
| 90-99 | Work/Professional |

### Creating an Area

1. Open areas picker: `<leader>xoa`
2. Press `Ctrl-N`
3. Enter area number (e.g., `60`)
4. Enter area name (e.g., `Health`)
5. Edit the generated `_AREA.md` template

### Archiving an Area

1. Open areas picker: `<leader>xoa`
2. Select area, press `Ctrl-A`
3. Confirm archival

Area moves to: `Archive/Areas/{area_id}_{timestamp}/`

Multiple archives of the same area are preserved with different timestamps.

---

## Icons Reference

| Icon | Meaning |
|------|---------|
| 󰁔 | NEXT action |
| 󰄲 | TODO task |
| 󰈸 | WAITING task |
| 󰋚 | SOMEDAY task |
| 󰷐 | PROJECT (active) |
| ⏸ | ON_HOLD project |
| 󰑖 | ONGOING project |
| 󰅖 | Reminders project |
| 󰄳 | DONE |
| 󰜺 | CANCELLED |
| 󰠱 | Area |
| 󰆍 | Inbox |

---

## API Functions

The module exposes functions for programmatic access:

```lua
local chronos = require("gtd-nvim.gtd.chronos")

-- Check daemon status
chronos.is_running()

-- Get metrics
local metrics = chronos.metrics()

-- Query tasks
local tasks = chronos.tasks({ state = "NEXT", limit = 10 })

-- Search
local results = chronos.search("keyword")

-- Get projects
local projects = chronos.projects_info()

-- Get areas
local areas = chronos.areas()
local area = chronos.area_info("10-Personal")

-- Trigger sync
local result = chronos.reminders_sync()
```

---

## Troubleshooting

### Daemon not running

```
Chronos daemon not running
```

Start the daemon:
```bash
~/Developer/chronos/bin/chronosd &
```

### Socket connection failed

Check socket exists:
```bash
ls -la ~/.cache/chronos/chronos.sock
```

### Tasks not updating

Force refresh:
```lua
:lua require("gtd-nvim.gtd.chronos").query("gtd", "refresh", nil)
```

Or restart daemon.

### TCC Permissions (macOS)

If Reminders sync fails, ensure the terminal app has Calendar/Reminders permissions in System Settings → Privacy & Security.
