# GTD-NVIM Roadmap & Comparison

## Feature Comparison: GTD-NVIM vs Commercial Tools

### Legend
- ✅ Full support
- ⚠️ Partial/workaround
- ❌ Not available

### Capture

| Feature | GTD-NVIM | OmniFocus | Todoist | Things 3 |
|---------|----------|-----------|---------|----------|
| Quick capture | ✅ `capi`, `<leader>ci` | ✅ Quick Entry | ✅ Quick Add | ✅ Quick Entry |
| Clipboard capture | ✅ `capv`, `<leader>cv` | ✅ | ⚠️ Paste only | ⚠️ Paste only |
| Global hotkey capture | ✅ `Alt+Shift+C` | ✅ | ✅ | ✅ |
| Natural language dates | ✅ Smart dates | ✅ | ✅ Best-in-class | ✅ |
| Email to inbox | ❌ | ✅ | ✅ | ❌ |
| Browser extension | ❌ | ✅ | ✅ | ❌ |
| Shell capture | ✅ `capture.sh` | ❌ | ❌ | ❌ |

### Organization

| Feature | GTD-NVIM | OmniFocus | Todoist | Things 3 |
|---------|----------|-----------|---------|----------|
| Full GTD States | ✅ TODO/NEXT/WAITING/SOMEDAY/DONE/PROJECT | ✅ | ⚠️ Basic | ⚠️ Basic |
| Projects | ✅ | ✅ | ✅ | ✅ |
| Areas of Focus | ✅ | ✅ Folders | ⚠️ Labels | ✅ |
| Tags/Labels | ✅ org tags | ✅ | ✅ | ✅ |
| Contexts | ✅ via @tags | ✅ Native | ⚠️ Labels | ⚠️ Tags |
| WAITING FOR | ✅ Rich metadata (who/what/when) | ✅ | ❌ | ❌ |
| SOMEDAY/Maybe | ✅ | ✅ | ⚠️ Manual | ✅ |
| Sequential projects | ❌ | ✅ | ❌ | ❌ |
| Parallel projects | ✅ Default | ✅ | ✅ | ✅ |

### Dates & Scheduling

| Feature | GTD-NVIM | OmniFocus | Todoist | Things 3 |
|---------|----------|-----------|---------|----------|
| Due dates | ✅ DEADLINE | ✅ | ✅ | ✅ |
| Defer/Start dates | ✅ SCHEDULED | ✅ | ❌ | ✅ |
| Recurring tasks | ✅ org repeaters | ✅ | ✅ | ✅ |
| Calendar view | ⚠️ icalBuddy integration | ✅ Forecast | ✅ | ✅ |

### Review & Lists

| Feature | GTD-NVIM | OmniFocus | Todoist | Things 3 |
|---------|----------|-----------|---------|----------|
| Inbox processing | ✅ Clarify workflow | ✅ | ✅ | ✅ |
| Next Actions list | ✅ | ✅ | ⚠️ Manual | ⚠️ Today |
| Waiting For list | ✅ | ✅ | ❌ | ❌ |
| Projects list | ✅ | ✅ | ✅ | ✅ |
| Someday list | ✅ | ✅ | ⚠️ Manual | ✅ |
| Custom perspectives | ⚠️ FZF + scripts | ✅ Powerful | ✅ Filters | ❌ |
| **Weekly Review** | ✅ **3-phase guided cockpit** | ⚠️ Basic | ❌ | ❌ |
| Review history | ✅ | ❌ | ❌ | ❌ |
| Review notes | ✅ ZK integration | ❌ | ❌ | ❌ |
| Stuck projects | ✅ | ✅ | ❌ | ❌ |
| Custom checklists | ✅ | ✅ | ❌ | ❌ |

### Integration

| Feature | GTD-NVIM | OmniFocus | Todoist | Things 3 |
|---------|----------|-----------|---------|----------|
| Menu bar widget | ✅ SketchyBar | ❌ | ❌ | ❌ |
| Terminal prompt | ✅ Starship | ❌ | ❌ | ❌ |
| Editor integration | ✅ Neovim native | ❌ | ❌ | ❌ |
| Click-to-open tasks | ✅ | ✅ | ✅ | ✅ |
| Zettelkasten link | ✅ ZK_LINK | ❌ | ⚠️ Comments | ⚠️ Notes |
| API/Scripting | ✅ Full Lua + Shell | ⚠️ AppleScript | ⚠️ API | ⚠️ Shortcuts |

### Platform & Data

| Feature | GTD-NVIM | OmniFocus | Todoist | Things 3 |
|---------|----------|-----------|---------|----------|
| macOS | ✅ | ✅ | ✅ | ✅ |
| iOS/iPadOS | ❌ | ✅ | ✅ | ✅ |
| Web | ❌ | ✅ | ✅ | ❌ |
| Linux/Windows | ✅ Portable | ❌ | ✅ | ❌ |
| Plain text storage | ✅ org-mode | ❌ | ❌ | ❌ |
| Version control | ✅ Git native | ❌ | ❌ | ❌ |
| Own your data | ✅ | ⚠️ Local DB | ❌ Cloud | ⚠️ Local DB |
| Offline-first | ✅ | ✅ | ⚠️ | ✅ |
| Cost | ✅ Free | $100 | $48/yr | $50 |

---

## Unique Strengths 💪

1. **Terminal-native** - No context switching for developers
2. **SketchyBar + Starship** - Always-visible GTD metrics
3. **Plain text + Git** - Version history, portable, future-proof  
4. **Zettelkasten integration** - Tasks linked to knowledge base
5. **Full scriptability** - Shell + Lua automation
6. **Best-in-class WAITING FOR** - Rich metadata (who/what/when/follow-up)
7. **Superior Weekly Review** - 3-phase guided cockpit with notes
8. **Zero cost, no subscription**

---

## TODO: Planned Improvements

### High Priority

- [ ] **Priority levels** - Add `[#A]`/`[#B]`/`[#C]` support to capture UI
  - Update `capture.lua` with priority picker
  - Update `capture.sh` with `-P` flag
  - Display priority in lists

- [ ] **Effort estimates** - Add `:EFFORT:` property
  - Quick time tagging (5min, 15min, 30min, 1h, 2h)
  - Filter by effort for "quick wins"

- [ ] **Sequential projects** - Next action auto-progression
  - Mark project as sequential
  - Only show first incomplete task as NEXT
  - Auto-promote when task completes

### Medium Priority

- [ ] **Calendar integration improvements**
  - Two-way sync with Apple Calendar
  - Show scheduled tasks in calendar view
  - Deadline reminders via `terminal-notifier`

- [ ] **Project templates**
  - Predefined project structures
  - Auto-create tasks from template
  - Custom template directory

- [ ] **Email capture**
  - Neomutt integration
  - Mail rule → inbox file
  - Preserve email link in task

- [ ] **Visual selection capture** (nvim)
  - Capture highlighted text as task title
  - Auto-link to source file:line

### Low Priority (Nice to Have)

- [ ] **Mobile access**
  - Document Orgzly (Android) setup
  - Document beorg (iOS) setup
  - Syncthing configuration guide

- [ ] **Web dashboard**
  - Static HTML export
  - GitHub Pages deployment
  - Read-only view of lists

- [ ] **Natural language improvements**
  - "tomorrow at 3pm" parsing
  - "next monday" in capture
  - Relative date display ("in 3 days")

- [ ] **Notifications/Reminders**
  - `launchd` scheduled checks
  - `terminal-notifier` for overdue
  - Morning briefing script

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GTD-NVIM System                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CAPTURE                     ORGANIZE                           │
│  ├─ capture.lua             ├─ clarify.lua                     │
│  ├─ capture.sh              ├─ organize.lua                    │
│  └─ capture_global.sh       └─ projects.lua                    │
│                                                                 │
│  REVIEW                      LISTS                              │
│  ├─ review.lua (2500+ LOC)  ├─ lists.lua                       │
│  └─ Weekly Review Cockpit   ├─ fzf.lua                         │
│                             └─ status.lua                       │
│                                                                 │
│  DISPLAY                     DATA                               │
│  ├─ gtd_sketchybar.sh       ├─ ~/Documents/GTD/                │
│  ├─ gtd_starship.sh         │   ├─ Inbox.org                   │
│  ├─ gtd_metrics.sh          │   ├─ Projects/                   │
│  └─ Aerospace hotkeys       │   ├─ Areas/                      │
│                             │   └─ Archive/                     │
│                                                                 │
│  INTEGRATION                                                    │
│  ├─ Zettelkasten (ZK_LINK)                                     │
│  ├─ SketchyBar (menu bar)                                      │
│  ├─ Starship (prompt)                                          │
│  └─ Aerospace (global hotkeys)                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Global Hotkeys (Aerospace)

| Hotkey | Action | Implementation |
|--------|--------|----------------|
| `Alt+Shift+Space` | **GTD Global Menu** (full access) | `GTDMenu.app` |
| `Alt+Shift+C` | Quick capture | `GTDCapture.app` |
| `Alt+Shift+V` | Capture from clipboard | `GTDClipboard.app` |
| `Alt+Shift+I` | Open Inbox in Ghostty/nvim | Aerospace inline |

**Note:** The `.app` bundles are compiled AppleScript applications that properly receive window focus when triggered from background hotkeys. Source files are in `applescript/`.

## Shell Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `cap` | `capture.sh` | Normal capture |
| `capi` | `capture.sh -i` | Instant capture |
| `capv` | `capture.sh -c` | Clipboard capture |
| `gtd` | GTD browser | FZF task browser |
| `gtdm` | `gtd_global.sh` | GTD global menu (macOS dialogs) |
| `inbox` | `nvim ~/Documents/GTD/Inbox.org` | Open inbox |

## Neovim Keymaps (default prefix: `<leader>c`)

| Key | Function |
|-----|----------|
| `c` | Capture to inbox |
| `i` | Instant capture |
| `v` | Clipboard capture |
| `s` | Change task status |
| `lt` | Clarify current task |
| `ll` | Clarify from list |
| `lm` | Lists menu |
| `ln` | Next actions |
| `lw` | Waiting for |
| `ls` | Someday/maybe |
| `r` | Refile task |
| `p` | New project |
| `h` | Health check |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT - See [LICENSE](LICENSE)
