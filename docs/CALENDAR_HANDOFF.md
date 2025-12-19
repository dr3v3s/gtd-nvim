# GTD Calendar Integration - Project Handoff

## Context

I'm building deep calendar integration for my GTD system (gtd-nvim). The system uses:
- **org-mode files** in `~/Documents/GTD/`
- **Neovim + Lua** for the core GTD system
- **iCalBuddy** for fast calendar access (read-only)
- **AppleScript** for calendar writes (create/update/delete events)
- **Shell scripts** for SketchyBar, Starship prompt, and CLI tools

## Current State

### Files Created/Modified

**Lua Modules (gtd-nvim):**
- `/Users/plague/projects/gtd-nvim/lua/gtd-nvim/gtd/icalbuddy.lua` — NEW: iCalBuddy integration module
- `/Users/plague/projects/gtd-nvim/lua/gtd-nvim/gtd/calendar.lua` — EXISTING: AppleScript-based calendar sync (bidirectional)
- `/Users/plague/projects/gtd-nvim/lua/gtd-nvim/gtd/shared.lua` — Glyphs and theme definitions (source of truth)

**Shell Scripts:**
- `/Users/plague/bin/gtd_calendar.sh` — NEW: Calendar CLI tool (today, week, agenda, free slots)
- `/Users/plague/bin/gtd_theme.sh` — NEW: Shell glyphs/colors mirroring shared.lua

### What's Working

1. **iCalBuddy access** — Full Disk Access granted, events fetch correctly
2. **Shell commands:**
   - `gtd_calendar.sh today` — Today's events via iCalBuddy
   - `gtd_calendar.sh week` — Next 7 days with date separators
   - `gtd_calendar.sh free` — Free time slots during work hours (09:00-18:00)
   - `gtd_calendar.sh agenda` — Combined calendar events + GTD scheduled/deadline tasks
3. **Theme integration** — Nerd Font glyphs from gtd_theme.sh (mirrors shared.lua)
4. **AppleScript fallback** — Works when iCalBuddy permissions fail

### What Needs Work

1. **Lua icalbuddy.lua module** — Not yet wired into main gtd-nvim init
2. **Agenda command** — Calendar events not showing (only GTD tasks appear)
3. **Event parsing** — iCalBuddy output format varies, needs robust parsing
4. **Bidirectional sync** — calendar.lua exists but needs testing/refinement
5. **Free slot scheduling** — Auto-suggest times for new tasks

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GTD Calendar System                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  READ Operations (iCalBuddy - fast)                         │
│  ├─ icalbuddy.lua (Lua module)                              │
│  └─ gtd_calendar.sh (Shell CLI)                             │
│                                                              │
│  WRITE Operations (AppleScript)                             │
│  └─ calendar.lua (existing, bidirectional sync)             │
│                                                              │
│  Theme/Glyphs                                               │
│  ├─ shared.lua (source of truth)                            │
│  └─ gtd_theme.sh (shell mirror)                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## My Calendars

**Actual event calendars (include these):**
- Calendar, Cirkuskalender, Bestyrelse, Special Forces, Juniorer, Ledere

**Exclude (Reminders/lists):**
- Fødselsdage, Siri-forslag, Mærkedagskalender, Gruble Listen, Indkøb, Indkøbsliste, Indkøb Spejder, Pakkeliste, Ønskeliste, Noras ønskeliste, Sømandens Ønskeliste, Juleliste 🎄, Opskrifter, Filmliste, Snerlevej, LoveShop A/S, INBOX, Sømandsopgaver, GTDeling, Sebastian and Michael, Sommerlejr, Specialforces

## Key Technical Details

### iCalBuddy Commands
```bash
# Basic events
icalBuddy -df '%Y-%m-%d' -tf '%H:%M' -nrd eventsToday
icalBuddy -df '%Y-%m-%d' -tf '%H:%M' -nrd -sd eventsToday+7
icalBuddy -df '%Y-%m-%d' -tf '%H:%M' -nrd "eventsFrom:2025-12-13 to:2025-12-13"

# Exclude calendars
icalBuddy -ec "Fødselsdage,Siri-forslag" eventsToday

# Parseable output
icalBuddy -nc -nrd -df '%Y-%m-%d' -tf '%H:%M' -po "title,datetime,location,calendar,uid" -ps "|§|" -b "" eventsToday
```

### Glyphs (from shared.lua)
```lua
state = {
  NEXT = "󱥦", TODO = "", WAITING = "", SOMEDAY = "󰋊", DONE = "󰸟"
}
container = {
  inbox = "", calendar = "", recurring = "󰑖"
}
ui = {
  clock = "", check = "", warning = "", location = ""
}
progress = {
  overdue = ""
}
```

### GTD Date Patterns in org files
```
SCHEDULED: <2025-12-13 Sat 14:00>
DEADLINE: <2025-12-13>
```

## Immediate TODO

1. **Fix agenda calendar events** — The iCalBuddy call in cmd_agenda isn't returning events
2. **Wire up icalbuddy.lua** — Add to gtd-nvim setup, create commands
3. **Add `:GtdAgenda` command** — Floating window with combined view
4. **Test free slot integration** — Suggest times when scheduling tasks

## Environment

- macOS (Apple Silicon)
- Ghostty terminal
- Neovim with gtd-nvim plugin
- iCalBuddy 1.10.1 at `/opt/homebrew/bin/icalBuddy`
- TokyoNight theme colors

## Preferences

- Use Nerd Font glyphs, not emojis
- Follow patterns in shared.lua for consistency
- Keep shell scripts POSIX-compatible where possible
- Use awk for complex text processing
- Test changes incrementally
