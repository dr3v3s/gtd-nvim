# GTD-Neovim System Specification v1.0

**Status:** Normative  
**Date:** 2025-12-19  
**Maintainer:** Michael  
**Scope:** All gtd-nvim modules + zettelkasten integration

This specification defines the canonical structure for GTD org-mode files and Zettelkasten markdown notes. **ALL modules MUST follow these rules.**

---

## Table of Contents

1. [Module Inventory](#1-module-inventory)
2. [Configuration System](#2-configuration-system)
3. [Directory Structure](#3-directory-structure)
4. [GTD File Types & Heading Levels](#4-gtd-file-types--heading-levels)
5. [Org-Mode Syntax Rules](#5-org-mode-syntax-rules)
6. [Zettelkasten Markdown Rules](#6-zettelkasten-markdown-rules)
7. [Linking Between Systems](#7-linking-between-systems)
8. [Identifiers](#8-identifiers)
9. [Canonical Parsing Functions](#9-canonical-parsing-functions)
10. [Module Compliance Checklist](#10-module-compliance-checklist)

---

## 1. Module Inventory

### 1.1 Core GTD Modules (`gtd-nvim/gtd/`)

| Module | Lines | Purpose | Must Follow Spec Sections |
|--------|-------|---------|---------------------------|
| `shared.lua` | 1970 | Shared utilities, parsing, fzf | 3, 4, 8 |
| `capture.lua` | 1705 | Task capture to org | 3, 4, 7 |
| `clarify.lua` | 1304 | Process/clarify tasks | 3, 4 |
| `organize.lua` | 943 | Move/refile tasks | 3, 4 |
| `projects.lua` | 1341 | Project management, ZK links | 3, 4, 6 |
| `lists.lua` | 1820 | Task lists, agenda | 3, 4 |
| `manage.lua` | 1415 | Bulk operations | 3, 4 |
| `review.lua` | 2586 | Weekly review | 3, 4 |
| `editor.lua` | 1256 | Task editor UI | 3, 4 |
| `areas.lua` | 332 | Areas of focus | 3 |
| `kairos.lua` | 892 | Kairos daemon integration | 3 |
| `reminders.lua` | 899 | Apple Reminders | - |
| `ui.lua` | 328 | UI helpers | - |
| `status.lua` | 240 | Status line | 3 |
| `init.lua` | 690 | Module loader | - |

### 1.2 GTD Utils (`gtd-nvim/gtd/utils/`)

| Module | Lines | Purpose | Must Follow Spec Sections |
|--------|-------|---------|---------------------------|
| `refile.lua` | 463 | Refile operations | 3, 4 |
| `task_id.lua` | 497 | TASK_ID generation | 7 |
| `org_dates.lua` | 329 | Date parsing | 4 |
| `sorting.lua` | 506 | Task sorting | 3, 4 |

### 1.3 Audit System (`gtd-nvim/audit/`)

| Module | Lines | Purpose | Must Follow Spec Sections |
|--------|-------|---------|---------------------------|
| `validators.lua` | 310 | Validation rules | 3, 4 (ENFORCES) |
| `parser.lua` | 210 | Org parsing | 4 (ENFORCES) |
| `reports.lua` | 193 | Report generation | - |
| `insights.lua` | 250 | Feature suggestions | - |
| `migrate.lua` | 453 | Migration tools | 3, 4 |
| `init.lua` | 153 | Audit loader | - |

### 1.4 Link System (`gtd-nvim/utils/`)

| Module | Lines | Purpose | Must Follow Spec Sections |
|--------|-------|---------|---------------------------|
| `link_insert.lua` | 725 | Insert links | 4, 5, 6 |
| `link_open.lua` | 864 | Open/resolve links | 4, 5, 6 |

### 1.5 Zettelkasten System (`~/.config/nvim/lua/utils/zettelkasten/`)

| Module | Lines | Purpose | Must Follow Spec Sections |
|--------|-------|---------|---------------------------|
| `core.lua` | 1114 | Core ZK functions | 5, 6, 7 |
| `capture.lua` | 823 | Note capture, GTD sync | 5, 6 |
| `people.lua` | 543 | Contact management | 5 |
| `manage.lua` | 378 | Note management | 5 |
| `reading.lua` | 349 | Book notes | 5 |
| `project.lua` | 257 | Project notes | 5, 6 |
| `init.lua` | 169 | ZK loader | - |

**Total: ~24,500 lines of code across 28 modules**

---

## 2. Configuration System

### 2.1 User Configuration

All user-specific settings are centralized in `~/.config/gtd-nvim/config.lua`:

```lua
return {
  -- Paths
  gtd_home = "~/Documents/GTD",
  notes_home = "~/Documents/Notes",
  
  -- User Identity
  user = {
    name = "Your Name",
    email = "you@example.com",
    timezone = "Europe/Copenhagen",
  },
  
  -- Areas of Focus
  areas = {
    { id = "work", name = "Work", icon = "󰊕", dir = "Work" },
    { id = "family", name = "Family", icon = "󰋑", dir = "Family" },
  },
  
  -- Contexts
  contexts = {
    { tag = "@computer", name = "Computer", icon = "󰌢" },
    { tag = "@phone", name = "Phone", icon = "󰏲" },
  },
  
  -- People (for WAITING)
  people = {
    { id = "boss", name = "Boss Name", email = "boss@work.com" },
  },
  
  -- Integrations
  integrations = {
    kairos = { enabled = true, socket = "~/.cache/kairos/kairos.sock" },
  },
}
```

### 2.2 Configuration Loading

Modules access configuration via `shared.lua`:

```lua
local shared = require("gtd-nvim.gtd.shared")

-- Path accessors
local gtd_root = shared.gtd_home()      -- "~/Documents/GTD" expanded
local notes_root = shared.notes_home()  -- "~/Documents/Notes" expanded
local inbox = shared.gtd_path("inbox")  -- Full path to Inbox.org

-- Data accessors
local areas = shared.get_areas()        -- User's areas of focus
local contexts = shared.get_contexts()  -- User's @contexts
local people = shared.get_people()      -- User's people list
```

### 2.3 Config Module API

| Function | Returns | Description |
|----------|---------|-------------|
| `config.get()` | table | Full configuration |
| `config.gtd_home()` | string | Expanded GTD path |
| `config.notes_home()` | string | Expanded Notes path |
| `config.gtd_path(key)` | string | GTD subdirectory path |
| `config.notes_path(key)` | string | Notes subdirectory path |
| `config.areas()` | table[] | Areas of focus |
| `config.contexts()` | table[] | GTD contexts |
| `config.people()` | table[] | People for WAITING |
| `config.effort_options()` | table[] | Time estimate options |
| `config.reload()` | table | Force reload config |

---

## 3. Directory Structure

### 3.1 GTD Directory (`~/Documents/GTD/`)

```
GTD/
├── Inbox.org                 # Unprocessed captures
├── Recurring.org             # Recurring tasks  
├── Tickler.org               # Future/scheduled (optional)
├── Projects/                 # Active project files
│   └── {project-slug}.org
├── Areas/                    # Areas of responsibility
│   └── {area-name}/
│       └── {project}.org
└── Archive/                  # Completed (EXCLUDED from counts)
    └── *.org
```

### 3.2 Notes Directory (`~/Documents/Notes/`)

```
Notes/
├── Daily/                    # Daily notes (YYYYMMDD-*.md)
├── Quick/                    # Quick captures
├── Projects/                 # Project notes (linked to GTD)
│   └── {id}-{slug}.md
├── People/                   # Contact notes
│   └── {id}-{name}.md
├── Reading/                  # Book notes
│   └── {id}-{title}.md
├── Templates/                # Note templates
│   ├── note.md
│   ├── book.md
│   ├── meeting.md
│   └── person.md
└── Archive/                  # Archived notes
```

---

## 4. GTD File Types & Heading Levels

### 4.1 The Golden Rule

> **Heading level is determined by file type, NOT by the action.**

| File Type | Detection | Action Heading Level |
|-----------|-----------|---------------------|
| Standalone (Inbox, Recurring, Tickler) | No `* PROJECT` heading | `*` (level 1) |
| Project file | Has `* PROJECT` at line 1-10 | `**` (level 2) |

### 4.2 Standalone Files

**Files:** `Inbox.org`, `Recurring.org`, `Tickler.org`, and any `.org` without `* PROJECT`

```org
* TODO Task title                              :tag1:tag2:
SCHEDULED: <2025-12-20 Fri>
:PROPERTIES:
:TASK_ID: 20251219143022
:END:

* NEXT Another task
DEADLINE: <2025-12-25 Wed>
```

### 4.3 Project Files

**Files:** Any `.org` with `* PROJECT` heading in first 10 lines

```org
* PROJECT Project Name [2/5]                   :tag1:tag2:
SCHEDULED: <2025-12-15 Mon>
DEADLINE: <2025-12-31 Wed>
:PROPERTIES:
:ID: 20251219143022
:TASK_ID: 20251219143022
:Effort: 2:00
:ASSIGNED: 
:ZK_NOTE: [[file:~/Documents/Notes/Projects/20251219-project-name.md][Project Note]]
:DESCRIPTION: Optional description
:END:

Project overview text.

** TODO First action
:PROPERTIES:
:TASK_ID: 20251219143100
:END:

** NEXT Second action                          :context:
SCHEDULED: <2025-12-20 Fri>
:PROPERTIES:
:TASK_ID: 20251219143200
:END:

*** Notes under action
Sub-notes at level 3.

** DONE Completed action
CLOSED: [2025-12-18 Thu 10:00]
```

### 4.4 Moving Between File Types

When moving tasks between files, heading levels MUST be adjusted:

| From | To | Transformation |
|------|-----|----------------|
| Inbox (`*`) | Project | `* TODO` → `** TODO` |
| Project (`**`) | Inbox | `** TODO` → `* TODO` |
| Project (`**`) | Project | `** TODO` → `** TODO` |
| Inbox (`*`) | Inbox | `* TODO` → `* TODO` |

**Implementation:** All refile/move operations must call `is_project_file()` on BOTH source and destination.

---

## 5. Org-Mode Syntax Rules

### 5.1 TODO Keywords

| Keyword | Type | Description | Icon |
|---------|------|-------------|------|
| `TODO` | Active | Standard task | 󰄲 |
| `NEXT` | Active | Next action (ready) | 󰁔 |
| `WAITING` | Active | Blocked/delegated | 󰈸 |
| `SOMEDAY` | Active | Maybe/future | 󰋚 |
| `PROJECT` | Container | Project heading | 󰷐 |
| `DONE` | Complete | Finished | 󰄳 |
| `CANCELLED` | Complete | Cancelled | 󰜺 |

### 5.2 Heading Format

```
STARS SPACE KEYWORD SPACE TITLE [PROGRESS] TAGS
```

**Examples:**
```org
* TODO Buy milk                                :errands:
** NEXT Call dentist [2/3]                     :health:phone:
* PROJECT Home Renovation [0/5]                :home:
```

### 5.3 Scheduling (MUST be AFTER heading, BEFORE properties)

```org
* TODO Task title
SCHEDULED: <2025-12-20 Fri>
DEADLINE: <2025-12-25 Wed +1w>
:PROPERTIES:
...
:END:
```

**Repeaters:**
- `+1d` - Daily
- `+1w` - Weekly  
- `+1m` - Monthly
- `.+1w` - From completion date
- `++1w` - Shift to future

### 5.4 Properties Drawer

**Location:** Immediately after SCHEDULED/DEADLINE (or after heading if none)

```org
:PROPERTIES:
:TASK_ID: 20251219143022
:ID: 20251219143022
:Effort: 2:00
:ASSIGNED: person
:CREATED: [2025-12-19 Fri]
:WAITING_FOR: person
:WAITING_SINCE: [2025-12-15 Mon]
:WAITING_CONTEXT: email
:ZK_NOTE: [[file:path][title]]
:DESCRIPTION: Short description
:END:
```

**Required Properties by Type:**

| Heading Type | Required | Optional |
|--------------|----------|----------|
| All tasks | `TASK_ID` | `Effort`, `ASSIGNED` |
| `PROJECT` | `TASK_ID`, `ID` | `ZK_NOTE`, `DESCRIPTION` |
| `WAITING` | `TASK_ID` | `WAITING_FOR`, `WAITING_SINCE`, `WAITING_CONTEXT` |
| `RECURRING` | `TASK_ID` | - |

### 5.5 Tags

**Format:** `:tag1:tag2:tag3:` at end of heading line

**Valid characters:** `a-z`, `A-Z`, `0-9`, `_`, `@`

**Special tags:**
- `@context` - GTD contexts (e.g., `@phone`, `@computer`, `@errands`)
- `@person` - Person-related (e.g., `@boss`, `@spouse`)

### 5.6 Progress Tracker

**Format:** `[done/total]` in heading

```org
* PROJECT Home Renovation [2/5]
```

**Rule:** `done` = count of `DONE`/`CANCELLED` children, `total` = all children

---

## 6. Zettelkasten Markdown Rules

### 6.1 Filename Format

```
{ID}-{slug}.md
```

**Examples:**
- `20251219143022-meeting-with-client.md`
- `20251219-daily.md` (daily notes)

### 6.2 Frontmatter (YAML)

```yaml
---
title: Note Title
created: 2025-12-19 14:30:22
id: 20251219143022
tags: [tag1, tag2]
type: note|project|person|book|meeting|daily
status: active|archived|completed
---
```

### 6.3 Template Structure

**Standard Note:**
```markdown
# {{title}}

**Created:** {{datetime}}
**Tags:** {{tags}}

## Content

## Related
```

**Person Note:**
```markdown
# {{title}}

**Relationship:** {{relationship}}
**Email:** {{email}}
**Phone:** {{phone}}
**Company:** {{company}}
**Tags:** {{tags}}

## Context

## Meetings

## Interactions

## Notes

## Related Projects
```

**Book Note:**
```markdown
# {{title}}

**Author:** {{author}}
**Status:** {{status}}
**Rating:** {{rating}}
**Tags:** {{tags}}

## Summary

## Key Takeaways

## Quotes

## Notes
```

---

## 7. Linking Between Systems

### 7.1 GTD → Zettelkasten (in org files)

```org
:ZK_NOTE: [[file:~/Documents/Notes/Projects/20251219-project.md][Project Note]]
```

### 7.2 Zettelkasten → GTD (in markdown)

```markdown
[[file:~/Documents/GTD/Projects/my-project.org][My Project]]
```

### 7.3 Wiki Links (markdown to markdown)

```markdown
[[note-title]]                    # By title
[[20251219143022]]                # By ID
[[note-title|Display Text]]       # With alias
```

### 7.4 Internal Org Links

```org
[[file:../Projects/other.org][Other Project]]
[[file:path.org::*Heading][Jump to Heading]]
[[id:20251219143022][By ID]]
```

### 7.5 Link Resolution Priority

1. Exact path match
2. ID match (TASK_ID, ID, or filename ID)
3. Title/slug match
4. Fuzzy basename match

---

## 8. Identifiers

### 8.1 TASK_ID

**Format:** `YYYYMMDDHHmmss` (14 digits)

**Example:** `20251219143022`

**Usage:** Unique identifier for every task/heading

**Generation:**
```lua
local function gen_task_id()
  return os.date("%Y%m%d%H%M%S")
end
```

### 8.2 ID (for projects)

Same format as TASK_ID, used in PROJECT headings for linking.

### 8.3 Note ID (Zettelkasten)

**Format:** `YYYYMMDDHHmm` (12 digits) or `YYYYMMDD` (8 digits for daily)

---

## 9. Canonical Parsing Functions

All modules MUST use these shared functions from `shared.lua`:

### 9.1 File Type Detection

```lua
-- Returns true if file has * PROJECT heading in first 10 lines
function M.is_project_file(filepath)
  local lines = M.read_file(filepath)
  if not lines or #lines == 0 then return false end
  for i = 1, math.min(10, #lines) do
    if lines[i]:match("^%* PROJECT%s") then
      return true
    end
  end
  return false
end
```

### 9.2 Heading Parsing

```lua
function M.parse_org_heading(line)
  if not line then return nil end
  local stars, rest = line:match("^(%*+)%s+(.*)")
  if not stars then return nil end
  
  local level = #stars
  local keyword, title = rest:match("^([A-Z]+)%s+(.*)")
  local tags = {}
  
  if title then
    local title_clean, tag_str = title:match("^(.-)%s+(:.+:)%s*$")
    if tag_str then
      title = title_clean
      for tag in tag_str:gmatch(":([^:]+)") do
        table.insert(tags, tag)
      end
    end
  else
    keyword = nil
    title = rest
  end
  
  return {
    level = level,
    keyword = keyword,
    title = title,
    tags = tags,
    raw = line,
  }
end
```

### 9.3 Heading Level Adjustment

```lua
function M.adjust_heading_level(line, source_is_project, dest_is_project)
  if not line:match("^%*+%s") then return line end
  
  if not source_is_project and dest_is_project then
    -- Add star: * → **
    return "*" .. line
  elseif source_is_project and not dest_is_project then
    -- Remove star: ** → *
    return line:gsub("^%*%*", "*")
  end
  return line
end
```

### 9.4 Property Extraction

```lua
function M.get_property(lines, h_start, h_end, key)
  local in_props = false
  for i = h_start, h_end do
    local line = lines[i]
    if line:match("^%s*:PROPERTIES:%s*$") then
      in_props = true
    elseif line:match("^%s*:END:%s*$") then
      break
    elseif in_props then
      local k, v = line:match("^%s*:([^:]+):%s*(.*)%s*$")
      if k and k:upper() == key:upper() then
        return v
      end
    end
  end
  return nil
end
```

---

## 10. Module Compliance Checklist

Before modifying any module, verify:

### 10.1 Heading Level Rules

- [ ] Uses `is_project_file()` to detect file type
- [ ] Creates headings at correct level based on destination
- [ ] Adjusts heading levels when moving between files

### 10.2 Property Handling

- [ ] Uses canonical `get_property()` / `upsert_property()`
- [ ] Generates TASK_ID for new tasks
- [ ] Places SCHEDULED/DEADLINE before PROPERTIES

### 10.3 Link Format

- [ ] Uses correct link format for file type (org vs md)
- [ ] ZK_NOTE links use `[[file:path][title]]` format
- [ ] Wiki links use `[[target]]` or `[[target|alias]]`

### 10.4 Date Format

- [ ] Dates use `<YYYY-MM-DD Day>` format
- [ ] Timestamps use `[YYYY-MM-DD Day HH:MM]` format
- [ ] Repeaters follow `+Nd/w/m/y` pattern

### 10.5 Tag Format

- [ ] Tags at end of heading line
- [ ] Format: `:tag1:tag2:`
- [ ] Only alphanumeric, `_`, `@` characters

---

## Appendix A: Migration Guide

When updating modules to comply with this spec:

1. **Audit current behavior** using `:GtdAudit` and `:GtdAuditAll`
2. **Update parsing** to use `shared.lua` functions
3. **Test refile operations** between all file type combinations
4. **Verify link resolution** works bidirectionally
5. **Run full audit** to confirm compliance

---

## Appendix B: Configuration System

### B.1 User Configuration Location

```
~/.config/gtd-nvim/config.lua
```

### B.2 Configuration Structure

```lua
return {
  -- Paths
  gtd_home = "~/Documents/GTD",
  notes_home = "~/Documents/Notes",
  
  -- User identity
  user = { name = "...", email = "...", timezone = "..." },
  
  -- Areas of focus
  areas = {
    { id = "work", name = "Work", icon = "󰊕", dir = "Work" },
    -- ...
  },
  
  -- GTD contexts
  contexts = {
    { tag = "@computer", name = "Computer", icon = "󰌢" },
    -- ...
  },
  
  -- People (for WAITING)
  people = {
    { id = "boss", name = "Boss Name", email = "..." },
    -- ...
  },
  
  -- UI preferences
  ui = { icons = "nerd", date_format = "%Y-%m-%d" },
  
  -- Integrations
  integrations = {
    kairos = { enabled = true, socket = "~/.cache/kairos/kairos.sock" },
    calendar = { enabled = true, provider = "apple" },
  },
}
```

### B.3 Accessing Configuration

All modules MUST use the config module instead of hardcoded paths:

```lua
local config = require("gtd-nvim.config")

-- Paths
local gtd = config.gtd_home()      -- ~/Documents/GTD (expanded)
local notes = config.notes_home()  -- ~/Documents/Notes (expanded)
local inbox = config.gtd_path("inbox")  -- ~/Documents/GTD/Inbox.org

-- Data
local areas = config.areas()       -- Array of area definitions
local contexts = config.contexts() -- Array of context definitions
local people = config.people()     -- Array of people definitions

-- Glyphs
local icon = config.state_glyph("NEXT")  -- 󰁔
local color = config.color("next")       -- #a6e3a1
```

### B.4 Generating User Config

```vim
:lua require("gtd-nvim.config").generate_user_config()
:lua require("gtd-nvim.config").edit()
```

---

## Appendix C: Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1 | 2025-12-19 | Added configuration system (Appendix B) |
| 1.0 | 2025-12-19 | Initial specification |
