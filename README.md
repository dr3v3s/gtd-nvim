# gtd-nvim

**Getting Things Done for Neovim** — Comprehensive GTD workflow powered by Chronos daemon.

[![Version](https://img.shields.io/badge/version-0.13.1-blue.svg)](lua/gtd-nvim/gtd/chronos.lua)
[![Neovim](https://img.shields.io/badge/neovim-0.9+-green.svg)](https://neovim.io)

## Overview

gtd-nvim provides a complete GTD implementation for Neovim using org-mode files. It integrates with the Chronos daemon for:

- Real-time task data and metrics
- Full-text search with FTS5
- Apple Reminders bidirectional sync
- Areas of Responsibility (Horizon 2)

## Requirements

- Neovim 0.9+
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [Chronos daemon](https://github.com/dr3v3s/chronos) running
- Nerd Font for icons

## Installation

```lua
-- lazy.nvim
return {
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

All commands use `<leader>x` prefix.

### Tasks

| Key | Description |
|-----|-------------|
| `<leader>xta` | All active tasks |
| `<leader>xtn` | NEXT actions |
| `<leader>xtt` | TODO tasks |
| `<leader>xtw` | WAITING tasks |
| `<leader>xts` | SOMEDAY tasks |

### Projects

| Key | Description |
|-----|-------------|
| `<leader>xpp` | Active projects |
| `<leader>xpa` | All projects (grouped by status) |
| `<leader>xpn` | Create new project |
| `<leader>xpc` | Convert file to project |

### Areas

| Key | Description |
|-----|-------------|
| `<leader>xoa` | Areas of Responsibility |

### Capture

| Key | Description |
|-----|-------------|
| `<leader>xcq` | Quick capture |
| `<leader>xcc` | Full capture wizard |
| `<leader>xcv` | Capture from clipboard |

### Other

| Key | Description |
|-----|-------------|
| `<leader>x/` | Search tasks |
| `<leader>xa` | Archive browser |
| `<leader>xr` | Reminders sync |
| `<leader>xs` | Daemon status |

## Picker Actions

### Task Picker

| Key | Action |
|-----|--------|
| `Enter` | Open task |
| `Ctrl-D` | Mark DONE |
| `Ctrl-X` | Mark CANCELLED |
| `Ctrl-N` | Set to NEXT |
| `Ctrl-A` | Archive |
| `Ctrl-R` | Refile |

### Project Picker

| Key | Action |
|-----|--------|
| `Enter` | Open project |
| `Ctrl-T` | Show tasks |
| `Ctrl-O` | Toggle ONGOING |
| `Ctrl-H` | Toggle ON_HOLD |
| `Ctrl-A` | Archive |

### Areas Picker

| Key | Action |
|-----|--------|
| `Enter` | Open definition |
| `Ctrl-P` | Show projects |
| `Ctrl-T` | Show tasks |
| `Ctrl-R` | Review dashboard |
| `Ctrl-N` | Create area |
| `Ctrl-A` | Archive area |

## Documentation

See [docs/CHRONOS.md](docs/CHRONOS.md) for complete documentation including:

- All keybindings and commands
- Capture workflows
- Project properties (ONGOING, ON_HOLD)
- Areas of Responsibility
- API functions
- Troubleshooting

## Commands

| Command | Description |
|---------|-------------|
| `:ChronosStatus` | Daemon status |
| `:ChronosAll` | All tasks |
| `:ChronosNext` | NEXT actions |
| `:ChronosTodo` | TODO tasks |
| `:ChronosWaiting` | WAITING tasks |
| `:ChronosSomeday` | SOMEDAY tasks |
| `:ChronosSearch {query}` | Search tasks |
| `:ChronosProjects` | Active projects |
| `:ChronosAllProjects` | All projects |
| `:ChronosProject` | New project wizard |
| `:ChronosAreas` | Areas picker |
| `:ChronosArchive` | Archive browser |
| `:ChronosQuick {text}` | Quick capture |
| `:ChronosCapture` | Full capture |
| `:ChronosRemindersSync` | Sync reminders |

## Icons

| Icon | Meaning |
|------|---------|
| 󰁔 | NEXT |
| 󰄲 | TODO |
| 󰈸 | WAITING |
| 󰋚 | SOMEDAY |
| 󰷐 | PROJECT |
| ⏸ | ON_HOLD |
| 󰑖 | ONGOING |
| 󰠱 | Area |
| 󰄳 | DONE |

## Version History

- **0.13.1** — Area management (create/archive), task capture to areas
- **0.13.0** — Areas picker, Horizon 2 support
- **0.12.3** — Picker refresh timing fixes
- **0.12.2** — ON_HOLD property, project status sections
- **0.12.0** — ONGOING property, project pickers from daemon
- **0.11.0** — Project creation wizard enhancements
- **0.10.0** — Full capture workflow, smart dates

## Related

- [Chronos](https://github.com/dr3v3s/chronos) — GTD daemon
- [GTD-SPEC](https://github.com/dr3v3s/chronos/blob/main/docs/GTD-SPEC.md) — Org-mode format

## License

MIT
