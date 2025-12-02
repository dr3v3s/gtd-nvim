# Convert Task to Project - Feature Guide

## Overview

The **Convert Task to Project** feature allows you to promote any GTD task (TODO, SOMEDAY, NEXT, etc.) into a full project while preserving all metadata and context.

## Usage

### Via Command

```vim
:GtdConvertToProject
```

Place your cursor on any org-mode heading and run the command. The feature will:

1. ✅ Extract task metadata (title, dates, tags, body, ZK note)
2. ✅ Pre-fill project creation prompts with task data
3. ✅ Allow you to edit everything before finalizing
4. ✅ Create the project with proper org-mode structure
5. ✅ Prompt you to handle the original task

### Via Keymap (Recommended)

Add to your Neovim config:

```lua
-- In your keymap configuration
vim.keymap.set('n', '<leader>cp', ':GtdConvertToProject<CR>', 
  { desc = "Convert task to project" })

-- Or with WhichKey
{
  ["<leader>c"] = {
    name = "GTD",
    P = { "<cmd>GtdConvertToProject<cr>", "Convert to project" },
  }
}
```

### Via Task Pickers (Optional Integration)

You can also add this to your `lists.lua` or `manage.lua` pickers:

**In lists.lua task picker:**
```lua
["ctrl-p"] = function(item)  -- p = "promote to project"
  require("gtd.projects").create_from_task_at_cursor()
end
```

**In manage.lua task actions:**
```lua
-- Add to task_actions_menu options:
"Convert to Project"
```

## Workflow Example

### Before: Task in SOMEDAY
```org
* SOMEDAY Learn Rust programming
SCHEDULED: <2025-02-01>
:PROPERTIES:
:TASK_ID: 20250102120000
:END:

Want to build CLI tools and understand systems programming better.
```

### After: Full Project
```org
* PROJECT Learn Rust programming [0/0]
SCHEDULED: <2025-02-01>
:PROPERTIES:
:ID:          20250103150000
:Effort:      2:00
:ASSIGNED:    
:CONVERTED_FROM: 20250102120000
:ZK_NOTE:     [[file:~/Documents/Notes/Projects/20250103150000-learn-rust-programming.md][20250103150000-learn-rust-programming.md]]
:DESCRIPTION: Want to build CLI tools and understand systems programming better.
:END:

** NEXT Første skridt
```

## What Gets Preserved

| Metadata | Handling |
|----------|----------|
| **Title** | Pre-fills project name (editable) |
| **State** | Removed (projects start as "PROJECT") |
| **SCHEDULED** | Becomes project defer date (editable) |
| **DEADLINE** | Becomes project due date (editable) |
| **Tags** | Preserved on project heading |
| **Body content** | Becomes project description |
| **TASK_ID** | Stored in `:CONVERTED_FROM:` for audit trail |
| **ZK note** | Reused if exists, or new note created |
| **Area** | Auto-detected, with option to change |

## Original Task Handling

After creating the project, you'll be prompted with options:

1. **Archive task** - Moves to Archive.org with link to new project
2. **Delete task** - Permanently removes the task
3. **Mark DONE** - Marks task complete with project link in body
4. **Move as NEXT** - Makes it first NEXT action in new project
5. **Keep as-is** - Original task stays unchanged

## Area-Awareness

If your task is in an Area directory (e.g., `Areas/WORK/tasks.org`), the feature:

- ✅ Detects the Area automatically
- ✅ Offers to keep project in same Area
- ✅ Allows changing to different Area
- ✅ Falls back to Projects root if no Area

## Installation

### Step 1: Replace Files

```bash
# Backup originals
cp ~/.config/nvim/lua/gtd/projects.lua ~/.config/nvim/lua/gtd/projects.lua.backup
cp ~/.config/nvim/lua/gtd/init.lua ~/.config/nvim/lua/gtd/init.lua.backup

# Install enhanced versions
mv ~/.config/nvim/lua/gtd/projects_enhanced.lua ~/.config/nvim/lua/gtd/projects.lua
mv ~/.config/nvim/lua/gtd/init_enhanced.lua ~/.config/nvim/lua/gtd/init.lua
```

### Step 2: Restart Neovim

```vim
:qa
# Reopen Neovim
```

### Step 3: Test

```vim
# Open any org file with a task
:edit ~/Documents/GTD/Inbox.org

# Place cursor on a task heading
* TODO Test task conversion

# Run the command
:GtdConvertToProject
```

## Integration Points

The feature lives in `projects.lua` where it belongs, but can be called from:

- ✅ **Direct keymap** (recommended)
- ✅ **User command** `:GtdConvertToProject`
- ✅ **Task pickers** (lists.lua, manage.lua)
- ✅ **Clarify workflow** (post-actions menu)

## Benefits

### Why This Approach?

1. **Workflow consistency** - Reuses all existing project creation logic
2. **No data loss** - Everything from task is preserved
3. **User control** - You can edit all data before finalizing
4. **Audit trail** - `:CONVERTED_FROM:` property tracks conversion
5. **Flexible** - Works from anywhere you have a task

### GTD Philosophy

This feature aligns perfectly with GTD principles:

- **Natural Planning** - Task that "grew up" becomes project
- **No friction** - Convert directly where you're already working
- **Context preserved** - Areas, dates, notes all maintained
- **Clear outcome** - Explicit handling of original task

## Troubleshooting

### "No heading found at or above cursor"
- Make sure cursor is on or after an org heading (`* TODO ...`)
- The feature looks upward from cursor to find the heading

### "Failed to extract task metadata"
- File must be an org-mode file (`.org` extension)
- Heading must follow org-mode syntax (`* STATE Title`)

### Task not in expected Area
- Check that Areas are properly configured in `areas.lua`
- Manual Area selection is always available in the picker

## Advanced Usage

### Programmatic Conversion

```lua
-- Call from another module
local projects = require("gtd.projects")
projects.create_from_task_at_cursor()
```

### Custom Keymap with Leader

```lua
-- In your which-key config
{
  ["<leader>c"] = {
    name = "GTD",
    c = { "<cmd>GtdCapture<cr>", "Capture" },
    C = { "<cmd>GtdClarify<cr>", "Clarify" },
    p = { "<cmd>GtdProjectNew<cr>", "New project" },
    P = { "<cmd>GtdConvertToProject<cr>", "Convert to project" },  -- Capital P
  }
}
```

## Future Enhancements

Potential additions (feel free to suggest):

- [ ] Batch conversion (convert multiple tasks to projects)
- [ ] Template selection during conversion
- [ ] Auto-populate project with sub-tasks from original task
- [ ] Integration with review workflows
- [ ] Undo conversion feature

## Support

For issues or questions:
1. Check `:GtdHealth` to verify system integrity
2. Review the audit trail (`:CONVERTED_FROM:` property)
3. Check ZK note linking worked correctly
4. Verify Areas configuration if using Areas

---

**Happy converting!** 🚀

This feature transforms your GTD workflow by making task→project evolution seamless and metadata-preserving.
