# Zettelkasten System - Quick Reference

## Installation Complete! ✅

Your modular Zettelkasten system is now installed with:
- ✅ Core (search, backlinks, tags, index)
- ✅ Capture (quick notes, daily notes with GTD sync)
- ✅ Project (project management)
- ✅ Manage (mass file operations)
- ✅ Reading (book notes, quotes)
- ✅ People (person management, interactions)

## Setup in Your init.lua

Add this after line 27 (after `require('utils.gtd-audit').setup()`):

```lua
require("utils.zettelkasten").setup({
  gtd_integration = { enabled = true },
  keymaps = true,
})
```

## Default Keymaps (all start with `<leader>z`)

### Core Navigation
- `<leader>zn` - New note
- `<leader>zf` - Find notes (fuzzy)
- `<leader>zs` - Search content (grep)
- `<leader>zr` - Recent notes
- `<leader>zb` - Show backlinks

### Capture
- `<leader>zq` - Quick note
- `<leader>zd` - Daily note (with GTD sync - read only)
- `<leader>zM` - Meeting note

### Projects
- `<leader>zp` - New project
- `<leader>zP` - List projects
- `<leader>zD` - Project dashboard

### Management
- `<leader>zm` - Manage notes (multi-select!)
- `<leader>zt` - Bulk tag add
- `<leader>zT` - Bulk tag remove

### Reading (Books)
- `<leader>zb` - New book note
- `<leader>zB` - List books
- `<leader>zR` - Reading dashboard
- `<leader>zQ` - Capture quote (in book note)

### People
- `<leader>zo` - New person note
- `<leader>zO` - List people
- `<leader>zI` - Recent interactions (30 days)

## All Commands

### Core
`:ZettelNew [title]` - Create note
`:ZettelFind` - Find notes
`:ZettelSearch` - Search content
`:ZettelSearchAll` - Search notes + GTD
`:ZettelRecent` - Recent notes
`:ZettelBacklinks` - Show backlinks
`:ZettelTags` - Browse tags
`:ZettelStats` - Statistics
`:ZettelClearCache` - Clear cache

### Capture
`:ZettelQuick [title]` - Quick note
`:ZettelDaily` - Daily note (with GTD sync)
`:ZettelMeeting [title]` - Meeting note

### Projects
`:ZettelProject [title]` - New project
`:ZettelProjectList` - List projects
`:ZettelProjectDashboard` - Dashboard

### Management
`:ZettelManage` - Mass management
`:ZettelBulkTag` - Add tag to files
`:ZettelBulkUntag` - Remove tag

### Reading
`:ZettelBook [title]` - New book note
`:ZettelBookList` - List books
`:ZettelBookDashboard` - Reading dashboard
`:ZettelQuote` - Capture quote

### People
`:ZettelPerson [name]` - New person note
`:ZettelPeople` - List people
`:ZettelPeopleDirectory` - People directory
`:ZettelInteractions` - Recent interactions
`:ZettelBirthdays` - This month's birthdays

## Multi-Select in Management

When using `:ZettelManage` or `<leader>zm`:

**Selection:**
- `TAB` - Mark/unmark file
- `Shift-TAB` - Unmark
- `Alt-A` - Select all
- `Alt-D` - Deselect all

**Actions (on selected files):**
- `Enter` - Open
- `Ctrl-D` - Delete (careful!)
- `Ctrl-A` - Archive
- `Ctrl-R` - Move to directory
- `Ctrl-B` - Show backlinks
- `Ctrl-T` - Show tags
- `?` - Help

**Counter shows:** `5/687` (selected/total)

## File Structure

```
~/Documents/Notes/
├── index.md                    # Auto-generated index
├── Daily/                      # Daily notes
├── Quick/                      # Quick captures
├── Projects/                   # Project notes
│   ├── DASHBOARD.md           # Auto-generated
│   └── Archive/               # Archived projects
├── Reading/                    # Book notes
│   └── DASHBOARD.md           # Reading stats
├── People/                     # Person notes
│   └── DIRECTORY.md           # People directory
├── Templates/                  # Templates
│   ├── note.md
│   ├── daily.md
│   ├── quick.md
│   ├── project.md
│   ├── book.md
│   ├── person.md
│   └── meeting.md
└── Archive/                    # Archived notes
```

## Workflows

### Morning Routine
1. `<leader>zd` - Open daily note
2. Review synced GTD tasks (up to 600!)
3. Use your GTD module for task management

### Project Management
1. `<leader>zp` - Create project
2. Work on project...
3. `<leader>zD` - Review project dashboard
4. In project file: `Ctrl-T` to toggle status

### Reading Workflow
1. `<leader>zb` - Create book note
2. While reading: `<leader>zQ` - Capture quotes
3. `Ctrl-S` in book list - Update status
4. `<leader>zR` - View reading dashboard

### People Management
1. `<leader>zo` - Create person note
2. After meeting: `Ctrl-M` - Add meeting log
3. `Ctrl-I` - Log interaction
4. `<leader>zI` - Review recent interactions
5. `:ZettelBirthdays` - Check this month

### Mass Cleanup
1. `<leader>zm` - Open manager
2. `TAB` on files to mark (counter shows selection)
3. `Ctrl-A` - Archive batch
4. Or `Ctrl-R` - Move batch

### Weekly Review
```
:ZettelStats              # See overview
:ZettelProjectDashboard   # Review projects
:ZettelBookDashboard      # Review reading
:ZettelInteractions       # Review connections
```

## Index Maintenance

The `index.md` file is **automatically maintained**!

Updated when:
- Notes created (any module)
- Notes deleted/archived/moved
- Cache cleared
- Projects created
- Books added
- People added

Shows:
- Total notes count
- All tags with counts
- Directory breakdown
- Links to all notes

## GTD Integration (Read-Only)

The system reads GTD tasks for display in daily notes:
- Daily notes show up to 600 tasks
- Tasks are sorted by priority
- Direct links to org files
- **Use your GTD module for task management**

GTD task reading is provided by `get_gtd_tasks()` internal API.

## Tips & Tricks

1. **TAB is your friend** - Use it liberally in management
2. **Alt-A then Shift-TAB** - Select all, then deselect what you want
3. **Daily notes auto-sync GTD** - Up to 600 tasks (read-only)!
4. **Use tags liberally** - They auto-index
5. **Dashboards auto-generate** - Just open them
6. **Templates are customizable** - Edit in Templates/
7. **Keymaps are optional** - Set `keymaps = false` in setup

## Module Independence

Use modules separately:

```lua
local capture = require("utils.zettelkasten.capture")
capture.daily_note()

local project = require("utils.zettelkasten.project")
project.dashboard()

local reading = require("utils.zettelkasten.reading")
reading.list_books()

local people = require("utils.zettelkasten.people")
people.recent_interactions(60)  -- 60 days
```

## Customization Examples

### Custom Capture Workflow
```lua
vim.keymap.set("n", "<leader>zi", function()
  vim.ui.input({ prompt = "Idea: " }, function(text)
    if text and text ~= "" then
      require("utils.zettelkasten").quick_note("Idea: " .. text)
    end
  end)
end, { desc = "Capture idea" })
```

### Weekly Project Review
```lua
vim.keymap.set("n", "<leader>zw", function()
  require("utils.zettelkasten").project_dashboard()
end, { desc = "Weekly review" })
```

### Auto-Birthday Check
```lua
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(function()
      require("utils.zettelkasten.people").birthdays()
    end, 1000)
  end,
})
```

## Support

- Check templates: `~/Documents/Notes/Templates/`
- Check README: `~/.config/nvim/lua/utils/zettelkasten/README.md`
- Debug GTD: `:lua require("utils.zettelkasten").debug_gtd_tasks()`

## What's Next?

1. Add to init.lua (see SETUP_ZETTELKASTEN.lua)
2. Restart Neovim
3. Run `:ZettelStats` to verify
4. Press `<leader>zd` to create your first daily note!
5. Enjoy your zen workflow! 🧘

---

**Philosophy:** Unix-style modular system. Each module does one thing well. GTD task management is handled by your existing GTD module - zettelkasten only reads tasks for display.
