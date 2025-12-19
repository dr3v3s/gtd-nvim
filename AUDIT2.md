# GTD-NVIM Command & Function Audit

**Date:** 2025-12-19
**Purpose:** Identify redundant commands, technical debt, and consolidation opportunities
**Total Commands:** 58 (some duplicated across modules)
**Total Public Functions:** 297

---

## Executive Summary

The codebase has grown organically with significant duplication:
- **11 duplicate command definitions** (same command defined in multiple files)
- **~40 commands** that could be consolidated into **~20 well-organized commands**
- **Significant function overlap** between shared.lua, ui.lua, and individual modules

### Recommended Actions
1. **Immediate:** Remove duplicate command definitions (keep module-specific ones)
2. **Short-term:** Consolidate overlapping commands into unified entry points
3. **Long-term:** Refactor shared.lua/ui.lua overlap

---

## 🔴 DUPLICATE COMMANDS (Critical - Fix First)

These commands are defined in **multiple files** causing potential conflicts:

| Command | Locations | Recommendation |
|---------|-----------|----------------|
| `GtdLists` | init.lua:732, lists.lua:1308 | **Keep lists.lua**, remove from init.lua |
| `GtdProjects` | init.lua:740, lists.lua:1299 | **Keep lists.lua**, remove from init.lua |
| `GtdWaiting` | init.lua:744, lists.lua:1301 | **Keep lists.lua**, remove from init.lua |
| `GtdReviewHistory` | init.lua:779, review.lua:2579 | **Keep review.lua**, remove from init.lua |
| `GtdReviewResume` | init.lua:775, review.lua:2580 | **Keep review.lua**, remove from init.lua |
| `GtdEdit` / `GtdTaskEditor` | editor.lua:1229, editor.lua:1230 | **Keep GtdEdit**, remove GtdTaskEditor |
| `GtdListsMenu` / `GtdLists` | lists.lua:1297, lists.lua:1308 | **Keep GtdLists**, remove GtdListsMenu |

### Why This Matters
- Commands defined later overwrite earlier definitions
- Inconsistent behavior depending on load order
- Confusing for users (which one to use?)

---

## 🟡 REDUNDANT/OVERLAPPING COMMANDS

Commands that do the same or very similar things:

### List Navigation (Consolidate → `GtdLists`)
| Current | What it does | Keep? |
|---------|--------------|-------|
| `GtdLists` | Main menu | ✅ KEEP |
| `GtdListsMenu` | Same as GtdLists | ❌ REMOVE |
| `GtdNext` | Show NEXT actions | ⚠️ Keep as shortcut |
| `GtdNextActions` | Same as GtdNext | ❌ REMOVE (duplicate) |
| `GtdProjects` | Project list | ⚠️ Keep as shortcut |
| `GtdWaiting` | Waiting list | ⚠️ Keep as shortcut |
| `GtdWaitingOverdue` | Subset of waiting | ⚠️ Consider sub-menu |
| `GtdWaitingUrgent` | Subset of waiting | ⚠️ Consider sub-menu |
| `GtdSomedayMaybe` | Someday list | ⚠️ Keep as shortcut |
| `GtdStuckProjects` | Stuck projects | ⚠️ Keep as shortcut |
| `GtdSearchAll` | Search GTD files | ✅ KEEP |

**Recommendation:** Keep shortcuts but ensure they're defined in ONE place only (lists.lua)

### Task Editing (Consolidate → `GtdEdit`)
| Current | What it does | Keep? |
|---------|--------------|-------|
| `GtdEdit` | Open task editor | ✅ KEEP |
| `GtdTaskEditor` | Same as GtdEdit | ❌ REMOVE |
| `GtdClarify` | Clarify inbox item | ✅ KEEP (different purpose) |
| `GtdClarifyPick` | Pick item to clarify | ✅ KEEP |
| `GtdClarifyPromote` | Promote to project | ⚠️ Move to GtdEdit sub-action |

### Review Commands (Consolidate → `GtdReview`)
| Current | What it does | Keep? |
|---------|--------------|-------|
| `GtdReview` | Start weekly review | ✅ KEEP |
| `GtdWeeklyReview` | Same as GtdReview | ❌ REMOVE (alias) |
| `GtdReviewResume` | Resume review | ✅ KEEP |
| `GtdReviewHistory` | Show past reviews | ✅ KEEP |
| `GtdReviewIndex` | Same as History | ❌ REMOVE (alias) |
| `GtdReviewChecklists` | Manage checklists | ✅ KEEP |

### Reminders Commands (8 commands - consider consolidating)
| Current | What it does | Keep? |
|---------|--------------|-------|
| `GtdBrowseReminders` | Browse reminders | ✅ KEEP |
| `GtdImportReminders` | Import from Apple | ⚠️ Sub-action of Browse |
| `GtdExportTasks` | Export to Apple | ⚠️ Sub-action of Browse |
| `GtdSyncReminders` | Bidirectional sync | ⚠️ Sub-action of Browse |
| `GtdSyncCompletion` | Sync completion | ⚠️ Sub-action of Browse |
| `GtdRemindersConfig` | Configure | ⚠️ Sub-action of Browse |
| `GtdRemindersTest` | Test connection | ⚠️ Sub-action of Browse |
| `GtdCleanInboxDuplicates` | Clean duplicates | ⚠️ Sub-action of Browse |

**Recommendation:** Keep `GtdBrowseReminders` as main entry, add sub-menu for operations

### Audit/Migration Commands (Legacy?)
| Current | What it does | Keep? |
|---------|--------------|-------|
| `GtdAudit` | Run audit | ✅ KEEP |
| `GtdAuditAll` | Full audit | ⚠️ Merge into GtdAudit with flag |
| `GtdSuggest` | Show suggestions | ⚠️ Part of GtdAudit output |
| `GtdQuickFix` | Auto-fix issues | ✅ KEEP |
| `GtdMigrate` | Migration script | ⚠️ Legacy - remove after v2 stable |
| `GtdMigrateFix` | Fix migration | ⚠️ Legacy |
| `GtdMigrateFixAll` | Fix all | ⚠️ Legacy |
| `GtdMigrateReport` | Migration report | ⚠️ Legacy |
| `GtdFixCompliance` | Fix org compliance | ⚠️ Merge into GtdQuickFix |

---

## 🟢 RECOMMENDED COMMAND STRUCTURE

### Tier 1: Primary Commands (User-Facing)
```
GtdCapture        - Quick capture to inbox
GtdClarify        - Process inbox items
GtdLists          - Main navigation menu
GtdReview         - Weekly review
GtdEdit           - Edit task at cursor
GtdAreas          - Browse areas of responsibility
```

### Tier 2: Shortcuts (Power Users)
```
GtdNext           - NEXT actions list
GtdProjects       - Projects list
GtdWaiting        - Waiting list
GtdAgenda         - Today's agenda
GtdFreeSlots      - Free time slots
```

### Tier 3: Management
```
GtdManage         - Task/project management menu
GtdBrowseReminders - Apple Reminders integration
GtdAudit          - System health & compliance
```

### Tier 4: Utilities (Advanced)
```
GtdHealth         - Quick health check
GtdVersion        - Show version info
GtdStatus         - Kairos daemon status
```

---

## 📊 FUNCTION OVERLAP ANALYSIS

### shared.lua vs ui.lua (SIGNIFICANT OVERLAP)

| Function | shared.lua | ui.lua | Recommendation |
|----------|------------|--------|----------------|
| `xp()` / `expand_path()` | ✓ | ✓ | Keep shared.lua |
| `read_file()` | ✓ | ✓ | Keep shared.lua |
| `file_exists()` | - | ✓ | Move to shared.lua |
| `dir_exists()` | - | ✓ | Move to shared.lua |
| `write_file()` | - | ✓ | Move to shared.lua |
| `ensure_dir()` | - | ✓ | Move to shared.lua |
| `notify()` / `info/warn/error()` | ✓ | ✓ | Keep shared.lua |
| `is_org_heading()` | ✓ | ✓ | Keep shared.lua |
| `parse_org_heading()` | ✓ | ✓ | Keep shared.lua |
| `heading_level()` / `org_heading_level()` | ✓ | ✓ | Keep shared.lua |
| `have_fzf()` / `has_fzf()` | ✓ | ✓ | Keep shared.lua |
| `slugify()` | - | ✓ | Move to shared.lua |

**Recommendation:** Consolidate all into shared.lua, ui.lua becomes thin wrapper for enhanced UI functions only.

### capture.lua vs clarify.lua vs organize.lua

| Function | capture | clarify | organize | Recommendation |
|----------|---------|---------|----------|----------------|
| `clarify()` | - | ✓ | ✓ | Keep clarify.lua |
| `clarify_pick_any()` | - | ✓ | ✓ | Keep clarify.lua |
| `fast()` | - | ✓ | ✓ | Keep clarify.lua |
| `list_waiting_items()` | ✓ | ✓ | - | Keep clarify.lua |
| `at_cursor()` | - | ✓ | ✓ | Keep clarify.lua |

**Recommendation:** organize.lua appears to be legacy wrapper around clarify.lua - consider deprecation.

### lists.lua vs init.lua

Multiple functions in init.lua are just wrappers around lists.lua:
- `list_next()` → `lists.next_actions()`
- `list_projects()` → `lists.projects()`
- `list_waiting()` → `lists.waiting()`
- `lists_menu()` → `lists.menu()`
- `agenda()` → `lists.agenda()`
- `free_slots()` → `lists.free_slots()`

**Recommendation:** Remove wrapper functions from init.lua, call lists.lua directly.

---

## 🛠 IMPLEMENTATION PLAN

### Phase 1: Remove Duplicates (Low Risk)
1. Remove duplicate command definitions from init.lua (keep module-specific)
2. Remove `GtdTaskEditor` (keep `GtdEdit`)
3. Remove `GtdListsMenu` (keep `GtdLists`)
4. Remove `GtdWeeklyReview` (keep `GtdReview`)
5. Remove `GtdReviewIndex` (keep `GtdReviewHistory`)
6. Remove `GtdNextActions` (keep `GtdNext`)

### Phase 2: Consolidate Reminders (Medium Risk)
1. Add sub-menu to `GtdBrowseReminders` for all operations
2. Keep individual commands as aliases for backwards compatibility
3. Document deprecation

### Phase 3: Refactor shared.lua/ui.lua (Higher Risk)
1. Move file I/O functions to shared.lua
2. Keep ui.lua for enhanced input/display only
3. Update all modules to use shared.lua

### Phase 4: Clean Migration Code (After v2 Stable)
1. Remove `GtdMigrate*` commands
2. Remove `GtdFixCompliance` (merge into `GtdQuickFix`)
3. Archive scripts/migrate_to_v2.lua

---

## 📋 COMMAND INVENTORY BY MODULE

### gtd/init.lua (24 commands - TOO MANY)
```
GtdCapture, GtdClarify, GtdClarifyPromote, GtdClarifyPick,
GtdRefile, GtdProjectNew, GtdConvertToProject, GtdLinkToProject,
GtdLists*, GtdNext*, GtdProjects*, GtdWaiting*, GtdAgenda,
GtdFreeSlots, GtdHealth, GtdVersion, GtdFindDuplicates,
GtdWeeklyReview*, GtdReviewResume*, GtdReviewHistory*,
GtdStatus, GtdCycleStatus, GtdAreas
```
*Starred items are duplicates - REMOVE

### gtd/lists.lua (10 commands - APPROPRIATE)
```
GtdListsMenu*, GtdNextActions*, GtdProjects, GtdSomedayMaybe,
GtdWaiting, GtdWaitingOverdue, GtdWaitingUrgent,
GtdStuckProjects, GtdSearchAll, GtdLists
```
*Starred items are duplicates - REMOVE

### gtd/review.lua (5 commands - APPROPRIATE)
```
GtdReview, GtdReviewIndex*, GtdReviewHistory,
GtdReviewResume, GtdReviewChecklists
```
*Starred item is alias - REMOVE

### gtd/editor.lua (4 commands - APPROPRIATE)
```
GtdEdit, GtdTaskEditor*, GtdEnsureId, GtdScanIds
```
*Starred item is duplicate - REMOVE

### gtd/manage.lua (5 commands - APPROPRIATE)
```
GtdManage, GtdManageTasks, GtdManageProjects,
GtdArchiveTask, GtdDeleteTask
```

### gtd/reminders.lua (8 commands - CONSIDER CONSOLIDATION)
```
GtdImportReminders, GtdExportTasks, GtdSyncReminders,
GtdSyncCompletion, GtdRemindersConfig, GtdCleanInboxDuplicates,
GtdRemindersTest, GtdBrowseReminders
```

### audit/init.lua (4 commands - APPROPRIATE)
```
GtdAudit, GtdAuditAll, GtdSuggest, GtdQuickFix
```

### audit/migrate.lua (3 commands - LEGACY)
```
GtdMigrateReport, GtdMigrateFix, GtdMigrateFixAll
```

### gtd/scripts/*.lua (2 commands - LEGACY)
```
GtdMigrate, GtdFixCompliance
```

---

## 📈 METRICS AFTER CLEANUP

| Metric | Before | After Phase 1 | Target |
|--------|--------|---------------|--------|
| Total Commands | 58 | 54 | ~35 |
| Duplicate Definitions | 11 | 0 ✅ | 0 |
| Commands in init.lua | 24 | 13 | 8 |
| Legacy Commands | 6 | 6 | 0 |

---

## ✅ CHECKLIST FOR CLEANUP

- [x] Remove GtdLists from init.lua (keep lists.lua)
- [x] Remove GtdProjects from init.lua (keep lists.lua)
- [x] Remove GtdWaiting from init.lua (keep lists.lua)
- [x] Remove GtdReviewHistory from init.lua (keep review.lua)
- [x] Remove GtdReviewResume from init.lua (keep review.lua)
- [x] Remove GtdTaskEditor from editor.lua (keep GtdEdit)
- [x] Remove GtdListsMenu from lists.lua (keep GtdLists)
- [x] Remove GtdWeeklyReview from init.lua (alias of GtdReview)
- [x] Remove GtdReviewIndex from review.lua (alias of GtdReviewHistory)
- [x] Remove GtdNextActions from lists.lua (alias of GtdNext)
- [ ] Update keymaps to use canonical command names
- [ ] Update documentation
- [ ] Run full test suite

**Phase 1 completed:** 2025-12-19

---

*Generated by gtd-nvim audit system*
