# GTD Apple Integrations Guide

Complete guide for Apple Reminders and Calendar integration with your GTD system.

## 🚀 Quick Start

### 1. Grant Permissions

**First Time Setup:**
1. Open **System Settings** → **Privacy & Security** → **Automation**
2. Find your terminal app (iTerm, Terminal, Alacritty, etc.)
3. Enable both:
   - ✅ **Reminders**
   - ✅ **Calendar**

### 2. Test Access

```vim
:GtdRemindersTest   " Test Reminders access
:GtdCalendarTest    " Test Calendar access
```

### 3. First Sync

```vim
:GtdSyncAll         " Sync both Reminders & Calendar
```

---

## 🍎 Apple Reminders Integration

### Commands

#### Import & Export
```vim
:GtdImportReminders       " Import reminders → Inbox.org
:GtdExportTasks           " Export tasks → Reminders app
:GtdSyncReminders         " Bidirectional sync
```

#### Sync & Maintenance
```vim
:GtdSyncCompletion        " Mark reminders complete when task is DONE
:GtdCleanInboxDuplicates  " Remove duplicate imports
```

#### Configuration
```vim
:GtdRemindersConfig       " Interactive configuration menu
```

### How It Works

**Import (Reminders → GTD):**
- Fetches incomplete reminders from Apple Reminders
- Creates tasks in `Inbox.org` with:
  - `:APPLE_ID:` property (links back to reminder)
  - `:APPLE_LIST:` property (source list name)
  - `SCHEDULED` date from reminder date
  - `DEADLINE` date from due date
  - Priority mapped to GTD states (High → NEXT, Medium → TODO, Low → SOMEDAY)
  - Tags based on list name

**Export (GTD → Reminders):**
- Scans org files for tasks with states: TODO, NEXT, WAITING
- Creates/updates reminders in Reminders app
- Adds `:APPLE_ID:` property to track the link
- Maps SCHEDULED → reminder date, DEADLINE → due date
- Sets priority: NEXT tasks get high priority (9)

**Sync Completion:**
- When you mark a task DONE in GTD
- Automatically marks the linked reminder as complete
- Requires `:APPLE_ID:` property to identify the reminder

### Configuration Options

Edit in your GTD setup or via `:GtdRemindersConfig`:

```lua
require("gtd").setup({
  -- In your init.lua or similar
})

require("gtd.reminders").setup({
  -- Import settings
  mark_imported = false,              -- Mark reminders complete after import
  skip_completed = true,               -- Skip completed reminders
  import_lists = {},                   -- Empty = all lists, or {"Personal", "Work"}
  excluded_lists = {"Completed"},     -- Lists to skip
  
  -- Export settings
  export_list = "GTD",                 -- Target list name
  export_states = {"TODO", "NEXT", "WAITING"},  -- States to export
  sync_completion = true,              -- Auto-mark reminders complete
  
  -- Priority mapping
  map_high_priority = "NEXT",          -- Priority 9 → NEXT
  map_medium_priority = "TODO",        -- Priority 5-8 → TODO
  map_low_priority = "SOMEDAY",        -- Priority 1-4 → SOMEDAY
  
  -- Advanced
  auto_sync_on_save = false,           -- Auto-export on .org file save
})
```

### Example Task with Reminders Link

```org
* TODO Buy groceries  :PERSONAL:
SCHEDULED: <2025-10-27>
DEADLINE: <2025-10-28>
:PROPERTIES:
:ID:        20251025123456
:TASK_ID:   20251025123456
:APPLE_ID:  x-apple-reminder://AF3B2C1D-5E6F-4A8B-9C0D-1E2F3A4B5C6D
:APPLE_LIST: Personal
:PRIORITY:  5
:END:
ID:: [[zk:20251025123456]]

Need milk, eggs, bread

#+IMPORTED: 2025-10-25 12:34 from Apple Reminders (Personal)
```

---

## 📅 Apple Calendar Integration

### Commands

#### Import & Export
```vim
:GtdImportEvents          " Import events → Inbox.org
:GtdExportToCalendar      " Export tasks with dates → Calendar
:GtdSyncCalendar          " Bidirectional sync
```

#### Configuration
```vim
:GtdCalendarConfig        " Interactive configuration menu
```

### How It Works

**Import (Calendar → GTD):**
- Fetches upcoming events (default: 90 days ahead)
- Creates tasks in `Inbox.org` with:
  - `:EVENT_ID:` property (links to calendar event)
  - `:CALENDAR:` property (source calendar name)
  - `:LOCATION:` property (if event has location)
  - All-day events → `DEADLINE`
  - Timed events → `SCHEDULED`
  - Tags based on calendar name

**Export (GTD → Calendar):**
- Scans for tasks with SCHEDULED or DEADLINE dates
- States: TODO, NEXT, WAITING
- Creates/updates calendar events:
  - SCHEDULED dates → timed events (9 AM default)
  - DEADLINE dates → all-day events
  - Default duration: 60 minutes
  - Adds `:EVENT_ID:` property to track link

### Configuration Options

```lua
require("gtd.calendar").setup({
  -- Calendar settings
  default_calendar = "GTD",            -- Target calendar name
  event_duration = 60,                 -- Minutes
  import_calendars = {},               -- Empty = all, or {"Personal", "Work"}
  excluded_calendars = {"Birthdays", "Holidays"},
  
  -- Event creation
  create_from_scheduled = true,        -- Create events from SCHEDULED
  create_from_deadline = true,         -- Create events from DEADLINE
  deadline_as_allday = true,          -- DEADLINE → all-day event
  scheduled_as_timed = true,          -- SCHEDULED → timed event
  
  -- Sync settings
  sync_on_date_change = true,          -- Update when dates change
  import_future_only = true,           -- Only future events
  days_ahead = 90,                     -- Import window
  
  -- States to sync
  sync_states = {"TODO", "NEXT", "WAITING"},
  
  -- Advanced
  auto_sync_on_save = false,           -- Auto-export on save
})
```

### Example Task with Calendar Link

```org
* TODO Team meeting preparation  :WORK:
SCHEDULED: <2025-10-27 14:00>
:PROPERTIES:
:ID:        20251025143000
:TASK_ID:   20251025143000
:EVENT_ID:  D8F7E6C5-B4A3-9281-7069-584736251ABC
:CALENDAR:  Work
:LOCATION:  Conference Room A
:END:
ID:: [[zk:20251025143000]]

Location: Conference Room A

Prepare slides and agenda

#+IMPORTED: 2025-10-25 14:30 from Calendar (Work)
```

---

## 🔄 Workflow Examples

### Morning Review

```vim
" 1. Import everything from Apple ecosystem
:GtdSyncAll

" 2. Review inbox
:edit ~/Documents/GTD/Inbox.org

" 3. Clarify imported items
:GtdClarify

" 4. Process inbox
:GtdRefile
```

### Planning a Project

```vim
" 1. Create project with date
:GtdProjectNew

" 2. Add SCHEDULED date for start
" Add DEADLINE date for completion

" 3. Export to both systems
:GtdExportTasks          " Creates reminder
:GtdExportToCalendar     " Creates calendar event
```

### End of Day

```vim
" 1. Mark completed tasks DONE
* DONE Task title

" 2. Sync completion status
:GtdSyncCompletion       " Marks reminders complete

" 3. Review tomorrow's calendar
:GtdImportEvents
```

### Weekly Review

```vim
" 1. Full bidirectional sync
:GtdSyncAll

" 2. Clean up duplicates
:GtdCleanInboxDuplicates

" 3. Review next actions
:GtdNextActions

" 4. Review projects
:GtdProjects
```

---

## 🎯 Best Practices

### Date Management

**SCHEDULED vs DEADLINE:**
- `SCHEDULED` = When you want to START working
  - Creates timed calendar event (default 9 AM)
  - Sets reminder date in Reminders
  - Shows in day's agenda

- `DEADLINE` = When it must be DONE
  - Creates all-day calendar event
  - Sets due date in Reminders
  - Appears in deadline warnings

**Example:**
```org
* TODO Write quarterly report
SCHEDULED: <2025-10-27>    " Start Monday
DEADLINE: <2025-11-03>     " Due next Monday
```

### Avoiding Duplicates

**On Import:**
- Uses `:APPLE_ID:` and `:EVENT_ID:` to detect duplicates
- Run `:GtdCleanInboxDuplicates` if needed
- Import filters by list/calendar name

**On Export:**
- Only creates new reminders/events if no ID exists
- Updates existing if ID is present
- Won't create duplicate events

### Tag Strategy

**Tags from Import:**
- Reminder lists → `:PERSONAL:`, `:WORK:`, etc.
- Calendar names → `:WORK:`, `:FAMILY:`, etc.
- Use these tags to filter and organize

**Export Filtering:**
```lua
-- Only export work tasks
export_states = {"NEXT"},  -- Only urgent tasks
import_lists = {"Work"},   -- Only work reminders
```

### State Management

**Priority Mapping:**
- Reminders High Priority (9) → `NEXT` state
- Reminders Medium Priority (5-8) → `TODO` state
- Reminders Low Priority (1-4) → `SOMEDAY` state

**Export States:**
- `TODO` - Regular tasks
- `NEXT` - High priority (gets priority 9 in Reminders)
- `WAITING` - On hold tasks
- `SOMEDAY` - Not exported by default
- `DONE` - Triggers completion sync

---

## 🛠️ Troubleshooting

### Permission Issues

**Error:** "Failed to execute osascript"

**Solution:**
1. System Settings → Privacy & Security → Automation
2. Enable Reminders and Calendar for your terminal
3. Restart terminal
4. Run `:GtdRemindersTest` and `:GtdCalendarTest`

### Date Parsing Issues

**Error:** Dates not showing correctly

**Solution:**
- System supports both Danish and English date formats
- Checks multiple formats: "20. juni 2025", "June 20, 2025", "2025-06-20"
- Dates stored in org as `<YYYY-MM-DD>` or `<YYYY-MM-DD HH:MM>`

### Sync Not Working

**Issue:** Changes not syncing

**Solution:**
```vim
" 1. Check configuration
:GtdRemindersConfig
:GtdCalendarConfig

" 2. Test access
:GtdRemindersTest
:GtdCalendarTest

" 3. Manual sync
:GtdSyncAll

" 4. Check for errors
:messages
```

### Missing Properties

**Issue:** Tasks missing `:APPLE_ID:` or `:EVENT_ID:`

**Solution:**
- These are added automatically on first export
- Re-run export command to add missing IDs
- Check that properties drawer exists in task

---

## 📊 Integration Status

Check integration status anytime:

```vim
:GtdIntegrations         " Show all integration info and commands
:GtdHealth              " Check GTD system health
```

---

## 🔧 Advanced Usage

### Auto-sync on Save

Enable automatic sync when saving org files:

```lua
require("gtd.reminders").setup({
  auto_sync_on_save = true,  -- Export tasks on every .org save
})

require("gtd.calendar").setup({
  auto_sync_on_save = true,  -- Export to calendar on save
})
```

**Warning:** This triggers on every save - may be too aggressive for large systems.

### Custom Import Filters

Import only specific lists/calendars:

```lua
require("gtd.reminders").setup({
  import_lists = {"Work", "Personal"},     -- Only these lists
  excluded_lists = {"Shopping", "Archive"}, -- Skip these
})

require("gtd.calendar").setup({
  import_calendars = {"Work", "Personal"},
  excluded_calendars = {"Birthdays", "Holidays", "Subscribed"},
})
```

### Selective Export

Export only specific task states:

```lua
require("gtd.reminders").setup({
  export_states = {"NEXT"},  -- Only export NEXT actions
})

require("gtd.calendar").setup({
  sync_states = {"NEXT", "WAITING"},  -- Only urgent and waiting
})
```

---

## 📝 Property Reference

### Reminders Properties

```org
:PROPERTIES:
:APPLE_ID:   x-apple-reminder://UUID    " Link to reminder (required for sync)
:APPLE_LIST: Personal                   " Source list name
:PRIORITY:   5                          " Reminder priority (0-9)
:END:
```

### Calendar Properties

```org
:PROPERTIES:
:EVENT_ID:   UUID                       " Link to calendar event (required for sync)
:CALENDAR:   Work                       " Source calendar name
:LOCATION:   Conference Room A          " Event location
:END:
```

### Combined Example

```org
* TODO Project kickoff meeting  :WORK:
SCHEDULED: <2025-10-27 10:00>
DEADLINE: <2025-10-27>
:PROPERTIES:
:ID:        20251025100000
:TASK_ID:   20251025100000
:APPLE_ID:  x-apple-reminder://UUID1
:EVENT_ID:  UUID2
:CALENDAR:  Work
:LOCATION:  Main Office
:APPLE_LIST: Work
:PRIORITY:  9
:END:
ID:: [[zk:20251025100000]]

Reminder in Apple Reminders (Work list)
Event in Apple Calendar (Work calendar)
High priority (NEXT state)
```

---

## 🎓 Tips & Tricks

### Quick Capture Flow

```vim
" From anywhere in macOS:
" 1. Use Reminders.app to quickly add task
" 2. In Neovim: :GtdImportReminders
" 3. Process in GTD system
" 4. Clarify and organize
```

### Calendar Integration

```vim
" Block time for deep work:
* NEXT Write documentation  :WORK:
SCHEDULED: <2025-10-27 14:00>
DEADLINE: <2025-10-27 17:00>

" This creates a 3-hour calendar block
```

### Mobile Workflow

1. **Capture** → Use Apple Reminders on iPhone
2. **Sync** → Run `:GtdImportReminders` on Mac
3. **Process** → Clarify in GTD system
4. **Reflect** → Calendar shows your schedule
5. **Engage** → Work from Next Actions list

---

## 🚦 Command Quick Reference

### Essential Commands
```vim
:GtdSyncAll              " Sync everything
:GtdIntegrations         " Show status & all commands
:GtdHealth              " System health check
```

### Reminders
```vim
:GtdImportReminders      " Import from Reminders
:GtdExportTasks          " Export to Reminders
:GtdSyncReminders        " Bidirectional sync
:GtdSyncCompletion       " Sync DONE → complete
:GtdRemindersConfig      " Configure
:GtdRemindersTest        " Test access
```

### Calendar
```vim
:GtdImportEvents         " Import from Calendar
:GtdExportToCalendar     " Export to Calendar
:GtdSyncCalendar         " Bidirectional sync
:GtdCalendarConfig       " Configure
:GtdCalendarTest         " Test access
```

---

## 📚 Additional Resources

### GTD Core Commands
```vim
:GtdCapture              " Quick capture to inbox
:GtdClarify              " Clarify current task
:GtdClarifyPick          " Pick task to clarify
:GtdRefile               " Refile to project
:GtdProjectNew           " Create new project
:GtdManageTasks          " Manage tasks (archive/delete)
:GtdManageProjects       " Manage projects
```

### Workflow Integration

The integrations work seamlessly with your existing GTD workflow:
1. **Capture** (Reminders/Calendar) → **Import** → GTD Inbox
2. **Clarify** → Add properties and dates
3. **Organize** → Refile to projects
4. **Export** → Sync back to Reminders/Calendar
5. **Engage** → Work from synced system
6. **Review** → Clean up and plan ahead

---

## 💡 Philosophy

These integrations follow GTD principles:

1. **Ubiquitous Capture**: Use Apple Reminders anywhere to capture quickly
2. **Clarify**: Import to GTD system for proper clarification
3. **Organize**: Keep everything in sync across systems
4. **Reflect**: Calendar shows your time commitments
5. **Engage**: Work from a unified, trusted system

The Apple integrations extend your GTD system without disrupting it - they're tools that enhance your workflow, not replace it.

---

## 🤝 Support

Having issues? Check these first:

1. `:GtdIntegrations` - Check status
2. `:GtdHealth` - System health
3. `:GtdRemindersTest` / `:GtdCalendarTest` - Test access
4. `:messages` - Check for errors
5. System Settings → Privacy & Security → Automation - Permissions

Happy GTD! 🚀
