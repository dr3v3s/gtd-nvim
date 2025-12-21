# gtd-nvim

**GTD in Neovim** — A comprehensive Getting Things Done implementation using org-mode files.

[![Version](https://img.shields.io/badge/version-0.13.1-blue.svg)](VERSION)
[![Neovim](https://img.shields.io/badge/neovim-0.9+-green.svg)](https://neovim.io)

## Overview

gtd-nvim provides a complete GTD workflow inside Neovim with:

- **fzf-lua pickers** for tasks, projects, and areas
- **Chronos daemon integration** for real-time data
- **Capture wizards** for quick task entry
- **Apple Reminders sync** for mobile capture

## Requirements

- Neovim 0.9+
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [Chronos daemon](https://github.com/user/chronos) running

## Installation

### lazy.nvim

```lua
{
  dir = "~/projects/gtd-nvim",
  name = "chronos-gtd",
  lazy = false,
  dependencies = { "ibhagwan/fzf-lua" },
  config = function()
    require("gtd-nvim.gtd.chronos").setup({
      keymaps = "<leader>x",
    })
  end,
}
```

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
| `<leader>xpp` | `:ChronosProjects` | Active projects |
| `<leader>xpa` | `:ChronosAllProjects` | All projects |
| `<leader>xpn` | `:ChronosProject` | New project wizard |
| `<leader>xpc` | `:ChronosConvertProject` | Convert file to project |

### Areas (`<leader>xo`)

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>xoa` | `:ChronosAreas` | Areas of Responsibility |

### Capture (`<leader>xc`)

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>xcq` | `:ChronosQuick` | Quick capture |
| `<leader>xcc` | `:ChronosCapture` | Full capture wizard |
| `<leader>xcv` | `:ChronosClipboard` | Capture from clipboard |

### Other

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>x/` | `:ChronosSearch` | Full-text search |
| `<leader>xa` | `:ChronosArchive` | Archive browser |
| `<leader>xr` | `:ChronosRemindersSync` | Sync with Reminders |
| `<leader>xs` | `:ChronosStatus` | Daemon status |

## Picker Actions

### Task Picker

| Key | Action |
|-----|--------|
| `Enter` | Open file at task |
| `Ctrl-D` | Mark DONE |
| `Ctrl-X` | Delete task |
| `Ctrl-S` | Cycle state |
| `Ctrl-R` | Refile to project |
| `Ctrl-A` | Archive |

### Project Picker

| Key | Action |
|-----|--------|
| `Enter` | Open project file |
| `Ctrl-T` | Show project tasks |
| `Ctrl-O` | Toggle ONGOING |
| `Ctrl-H` | Toggle ON_HOLD |
| `Ctrl-A` | Archive project |

### Areas Picker

| Key | Action |
|-----|--------|
| `Enter` | Open `_AREA.md` |
| `Ctrl-P` | Projects in area |
| `Ctrl-T` | Tasks in area |
| `Ctrl-R` | Area review |
| `Ctrl-N` | Create new area |
| `Ctrl-A` | Archive area |

## Capture Wizards

### Quick Capture

Fastest path to capture a thought:

1. `<leader>xcq`
2. Type task title
3. Enter → Done (goes to Inbox)

### Full Capture

Complete task entry with all options:

1. `<leader>xcc`
2. Enter title
3. Select state (NEXT/TODO/WAITING/SOMEDAY)
4. Select destination:
   - Inbox
   - Project
   - Area
5. Enter dates (SCHEDULED/DEADLINE)
6. Add tags

### Project Creation

Guided project setup:

1. `<leader>xpn`
2. Enter project name
3. Select area (or standalone)
4. Enter outcome (optional)
5. Enter first action (optional)
6. Link ZK note (optional)
7. Choose type (Active/Ongoing)

## Configuration

```lua
require("gtd-nvim.gtd.chronos").setup({
  -- Keymap prefix (or false to disable)
  keymaps = "<leader>x",
  
  -- Chronos socket path
  socket_path = vim.fn.expand("~/.cache/chronos/chronos.sock"),
  
  -- Cache directory
  cache_dir = vim.fn.expand("~/.cache/chronos"),
})
```

## API Functions

The module exposes functions for custom integrations:

```lua
local chronos = require("gtd-nvim.gtd.chronos")

-- Check daemon status
if chronos.is_running() then
  -- Query data
  local metrics = chronos.metrics()
  local tasks = chronos.tasks({ state = "NEXT" })
  local projects = chronos.projects_info()
  local areas = chronos.areas()
  
  -- Search
  local results = chronos.search("keyword")
  
  -- Reminders
  local status = chronos.reminders_status()
  local result = chronos.reminders_sync()
end
```

## File Structure

```
lua/gtd-nvim/gtd/
└── chronos.lua      # Main module (v0.13.1)
```

## Related

- [Chronos daemon](https://github.com/user/chronos) - Backend daemon
- [GTD-SPEC](GTD-SPEC.md) - Org-mode format specification

## Version

Current: **0.13.1** (2025-12-21)

## License

MIT
