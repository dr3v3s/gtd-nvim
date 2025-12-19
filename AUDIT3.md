# GTD-NVIM Audit 3: GtdAgenda Redesign & Cleanup

**Date:** 2025-12-19
**Focus:** GtdAgenda comprehensive redesign, duplicate command removal, Catppuccin styling
**Session commits:** 12 commits (4a635b8 → 28ee31a)

---

## Executive Summary

This session focused on creating a **comprehensive GTD Agenda view** that provides an immediate overview of what needs attention. The agenda now shows:

- **MUST DO TODAY**: Calendar events + SCHEDULED + DEADLINE items
- **OVERDUE**: Past deadline items with days count
- **COULD DO TODAY**: NEXT actions, stuck projects, Someday inspiration

Additionally, we completed **Phase 1** from AUDIT2.md (duplicate command removal) and added **Catppuccin Mocha** color styling.

---

## ✅ COMPLETED CHANGES

### 1. Duplicate Command Removal (Phase 1 Complete)

| Removed | Kept | Reduction |
|---------|------|-----------|
| `GtdLists` (init.lua) | `GtdLists` (lists.lua) | -1 |
| `GtdProjects` (init.lua) | `GtdProjects` (lists.lua) | -1 |
| `GtdWaiting` (init.lua) | `GtdWaiting` (lists.lua) | -1 |
| `GtdWeeklyReview` (init.lua) | `GtdReview` | -1 |
| `GtdReviewResume` (init.lua) | `GtdReviewResume` (review.lua) | -1 |
| `GtdReviewHistory` (init.lua) | `GtdReviewHistory` (review.lua) | -1 |
| `GtdTaskEditor` (editor.lua) | `GtdEdit` | -1 |
| `GtdListsMenu` (lists.lua) | `GtdLists` | -1 |
| `GtdNextActions` (lists.lua) | `GtdNext` | -1 |
| `GtdReviewIndex` (review.lua) | `GtdReviewHistory` | -1 |

**Result:** 58 → 54 unique commands, 0 duplicates

### 2. Init.lua Agenda/FreeSlots Delegation

Removed ~100 lines of duplicate code from init.lua:

```lua
-- Before: Full implementation in init.lua (95 lines)
function M.agenda(date)
  -- kairos.build_agenda_async ...
  -- vim.api.nvim_create_buf ...
  -- vim.api.nvim_open_win ...
end

-- After: Simple delegation (10 lines)
function M.agenda(date)
  if not lists then
    vim.notify("gtd.lists not loaded", vim.log.levels.ERROR)
    return
  end
  return lists.agenda(date)
end
```

### 3. Comprehensive Agenda Redesign

**New structure:**
```
┌─────────────────────────────────────────┐
│ 󰃰 MUST DO TODAY (green header)          │
│    Calendar events for today           │
│   󰃭 Tasks SCHEDULED = today (teal)      │
│   󰀨 Tasks DEADLINE = today (peach)      │
│                                         │
│ 󰀦 OVERDUE (red header)                  │
│   󰀨 Past deadline items (Xd) (red)      │
│   Limited to 10 items                  │
│                                         │
│ 󰋚 COULD DO TODAY (lavender header)      │
│   NEXT actions available: (yellow)     │
│   Stuck projects: (maroon)             │
│   Someday/Maybe inspiration: (muted)   │
└─────────────────────────────────────────┘
```

**Features:**
- Async data collection (calendar + tasks in parallel)
- Archive filtering (excludes Archive/, ArchiveDeleted/, (archived))
- Deduplication (tasks both scheduled AND due shown once)
- Stuck project detection (PROJECTs without NEXT actions)
- Random Someday inspiration (3 shuffled items)
- Catppuccin Mocha ANSI colors throughout

### 4. Catppuccin Mocha Color Palette

| Element | Color | Hex |
|---------|-------|-----|
| MUST DO header | Green | `#a6e3a1` |
| OVERDUE header | Red | `#f38ba8` |
| COULD DO header | Lavender | `#b4befe` |
| NEXT tasks | Yellow | `#f9e2af` |
| TODO tasks | Blue | `#89b4fa` |
| WAITING tasks | Peach | `#fab387` |
| SOMEDAY tasks | Overlay | `#7f849c` |
| Calendar time | Sapphire | `#74c7ec` |
| Scheduled tasks | Teal | `#94e2d5` |
| Stuck projects | Maroon | `#eba0ac` |
| Project names | Overlay1 | `#7f849c` |
| Overdue days | Red | `#f38ba8` |

### 5. Agenda Actions

| Key | Action |
|-----|--------|
| **Enter** | Open task/show event details |
| **Ctrl-E** | Edit task & return to agenda |
| **Ctrl-B** | Back to GtdLists menu |

### 6. Cache Refresh

Added `kairos.refresh("gtd")` at start of agenda to ensure fresh data after edits.

---

## 🐛 BUGS FIXED

### kairos.lua
| Line | Issue | Fix |
|------|-------|-----|
| 704 | `ipairs` on userdata | Type check: `type(agenda.events) == "table"` |
| 633 | `calculate_free_slots` ipairs | Type check: `type(events) == "table"` |

### status.lua
| Line | Issue | Fix |
|------|-------|-----|
| 89 | `fzf_utils` undefined | Replaced with `shared.notify()`, inline options |

### lists.lua
| Issue | Fix |
|-------|-----|
| Agenda fallback to menu | Removed `vim.schedule(function() M.menu() end)` |
| ANSI codes break fzf selection | Added `strip_ansi()` helper + `find_item_index()` |
| Archived items in OVERDUE | Added `is_excluded()` filter function |

### init.lua
| Issue | Fix |
|-------|-----|
| Require path `gtd-nvim.gtd.X` not found | Created symlink `~/.config/nvim/lua/gtd-nvim/gtd/` |

---

## 📁 FILES MODIFIED

| File | Lines Changed | Summary |
|------|---------------|---------|
| `lists.lua` | +400 / -50 | Complete agenda redesign with colors |
| `init.lua` | -95 | Removed duplicate agenda/free_slots |
| `kairos.lua` | +10 | Type safety for JSON responses |
| `status.lua` | +5 / -10 | Removed fzf_utils dependency |

---

## 🔍 KNOWN ISSUES (To Investigate)

### Fresh Nvim Session → Empty Agenda

**Symptom:** First `:GtdAgenda` in fresh session shows "No agenda items"

**Debug output added:**
```
Agenda empty. Tasks received: X, Kairos: true/false, Next: X, Someday: X, Overdue: X
```

**Possible causes:**
1. Kairos daemon not fully initialized
2. Async callbacks racing
3. vim.wait(50ms) not sufficient after refresh

**Mitigations added:**
- Fallback to `shared.scan_gtd_files_robust()` if Kairos returns empty
- 50ms wait after refresh trigger

---

## 📋 REMAINING WORK (From AUDIT2)

### Phase 2: Consolidate Reminders (Not Started)
- [ ] Add sub-menu to `GtdBrowseReminders`
- [ ] Move 7 reminders commands into sub-menu
- [ ] Keep individual commands as deprecated aliases

### Phase 3: Refactor shared.lua/ui.lua (Not Started)
- [ ] Move file I/O to shared.lua
- [ ] Deduplicate 12+ overlapping functions
- [ ] ui.lua becomes thin wrapper

### Phase 4: Clean Migration Code (Not Started)
- [ ] Remove `GtdMigrate*` commands (6 commands)
- [ ] Remove `GtdFixCompliance`
- [ ] Archive migration scripts

---

## 📊 METRICS

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Commands | 58 | 54 | -4 |
| Duplicates | 11 | 0 | -11 ✅ |
| init.lua commands | 24 | 13 | -11 |
| init.lua lines | ~780 | ~690 | -90 |
| Agenda features | 3 | 12 | +9 |

---

## 🔗 COMMIT HISTORY

```
28ee31a debug: Add diagnostic output when agenda is empty
0b3e695 feat: Force Kairos GTD refresh before agenda display
cd52c51 fix: Filter out archived and completed tasks from agenda
86f530f fix: Add debug notifications and improve ANSI stripping
a4ee81a fix: Agenda item selection and remove menu fallback
872eba4 fix: Agenda no longer falls back to menu when Kairos unavailable
ee4ec8f style: Add Catppuccin Mocha colors to GtdAgenda
ac5d19e fix: Free slots ipairs error + add Ctrl-E edit-and-return
8c0ab6d fix: Agenda task categorization and display
e774438 feat: Complete GTD Agenda redesign with sections
4a635b8 refactor: Remove duplicate agenda/free_slots from init.lua
f33da6a fix: Phase 1 duplicate command removal complete
```

---

## 🎯 NEXT SESSION PRIORITIES

1. **Debug fresh session empty agenda** - Investigate async timing
2. **Phase 2: Reminders consolidation** - Reduce 8 → 1 command with sub-menu
3. **Improve archive detection** - May need to filter at Kairos level
4. **Add GtdAgenda date picker** - Allow viewing other days

---

## 📝 NOTES

### Symlink Structure
```
~/.config/nvim/lua/gtd/           → ~/projects/gtd-nvim/lua/gtd-nvim/gtd/
~/.config/nvim/lua/gtd-nvim/gtd/  → ~/projects/gtd-nvim/lua/gtd-nvim/gtd/
```

Both paths now resolve correctly for `require("gtd.X")` and `require("gtd-nvim.gtd.X")`.

### Archive Filtering Logic
```lua
local function is_excluded(t)
  -- DONE/CANCELLED/CLOSED states
  if t.state == "DONE" or t.state == "CANCELLED" or t.state == "CLOSED" then
    return true
  end
  -- Title contains "(archived)"
  if t.title and t.title:match("%(archived%)") then
    return true
  end
  -- Project is exactly "archive"
  if t.project and t.project:lower() == "archive" then
    return true
  end
  -- File in Archive or ArchiveDeleted directory
  if t.file then
    local file_lower = t.file:lower()
    if file_lower:match("/archive/") or file_lower:match("/archivedeleted/") 
       or file_lower:match("/archive%.org$") then
      return true
    end
  end
  return false
end
```
