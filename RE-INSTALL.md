# GTD-NVIM Re-Installation Guide

Quick reference for switching between **Chronos** (daemon-powered) and **Legacy** (standalone lua) modes.

## Current Status

```bash
gtd-mode          # or: ~/bin/gtd-mode
```

## Switching Modes

### To Chronos (daemon-powered, recommended)
```bash
gtd-mode chronos
# Restart nvim
```
- **Prefix:** `<leader>x`
- **Requires:** chronosd running (`~/Developer/chronos/bin/chronosd`)
- **Features:** Apple Reminders sync, daemon-powered search, real-time metrics

### To Legacy (standalone lua)
```bash
gtd-mode restore
# Restart nvim
```
- **Prefix:** `<leader>c`
- **Requires:** Nothing external
- **Features:** Full GTD workflow, ZK integration, all original features

## File Locations

| Component | Location |
|-----------|----------|
| Source code | `~/projects/gtd-nvim/` |
| Symlink | `~/.config/nvim/lua/gtd-nvim/gtd` → source |
| Toggle script | `~/bin/gtd-mode` |

### Nvim Plugin Specs

| File | Mode |
|------|------|
| `~/.config/nvim/lua/plugins/chronos.lua` | Chronos |
| `~/.config/nvim/lua/plugins/gtd-nvim.lua.disabled` | Legacy (disabled) |
| `~/.config/nvim/lua/mappings/gtd.lua.disabled` | Legacy mappings (disabled) |

## Keymap Reference

### Chronos Mode (`<leader>x`)

```
Tasks:
  <leader>xta    All tasks
  <leader>xtn    NEXT actions
  <leader>xtt    TODO tasks
  <leader>xtw    WAITING tasks
  <leader>xts    SOMEDAY tasks

Projects:
  <leader>xpp    List projects
  <leader>xpn    New project
  <leader>xpc    Convert to project

Capture:
  <leader>xcq    Quick capture
  <leader>xcc    Full capture wizard
  <leader>xcv    Capture from clipboard

Other:
  <leader>x/     Search tasks
  <leader>xa     Archive management
  <leader>xr     Reminders sync
  <leader>xs     Daemon status
```

### Legacy Mode (`<leader>c`)

```
Capture:
  <leader>cc     Capture to Inbox
  <leader>ci     Instant capture
  <leader>cv     Clipboard capture

Clarify/Lists:
  <leader>clt    Clarify current task
  <leader>cll    Clarify from list
  <leader>clm    Lists menu
  <leader>cln    Next actions
  <leader>clP    Projects
  <leader>cls    Someday/Maybe
  <leader>clw    Waiting for
  <leader>clx    Stuck projects

Refile/Projects:
  <leader>cr     Refile current task
  <leader>cR     Refile any task (fzf)
  <leader>cp     New project
  <leader>cP     Convert task to project

Manage:
  <leader>cmt    Manage tasks
  <leader>cmp    Manage projects
  <leader>ch     Health check
```

## Manual Switching

If `gtd-mode` isn't available:

```bash
# To Chronos
mv ~/.config/nvim/lua/plugins/gtd-nvim.lua{,.disabled}
mv ~/.config/nvim/lua/mappings/gtd.lua{,.disabled}
mv ~/.config/nvim/lua/plugins/chronos.lua{.disabled,}

# To Legacy
mv ~/.config/nvim/lua/plugins/chronos.lua{,.disabled}
mv ~/.config/nvim/lua/plugins/gtd-nvim.lua{.disabled,}
mv ~/.config/nvim/lua/mappings/gtd.lua{.disabled,}
```

## Troubleshooting

### Chronos daemon not running
```bash
# Start daemon
~/Developer/chronos/bin/chronosd &

# Check status in nvim
:ChronosStatus
```

### Module not found errors
```bash
# Verify symlink exists
ls -la ~/.config/nvim/lua/gtd-nvim/gtd

# Should point to:
# ~/projects/gtd-nvim/lua/gtd-nvim/gtd
```

### Clear nvim cache
```bash
rm -rf ~/.local/state/nvim/lazy/
# Restart nvim
```

## Dependencies

Both modes require:
- `ibhagwan/fzf-lua`
- Nerd Font (for glyphs)

Chronos additionally requires:
- Go daemon: `~/Developer/chronos/bin/chronosd`
- kairos-bridge: `~/Developer/kairos/bin/kairos-bridge`
