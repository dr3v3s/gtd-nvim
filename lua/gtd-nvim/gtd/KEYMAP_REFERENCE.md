# GTD Convert Task to Project - Quick Reference

## 🎯 New Keymap

Your new keymap has been integrated into your existing `<leader>c` GTD workflow:

```
<leader>cp  = New project (from scratch)
<leader>cP  = Convert task → project (promote existing task)
```

**Mnemonic:** 
- lowercase `p` = project (create new)
- uppercase `P` = Project (Promote task to project)

## 🚀 Usage

### Step 1: Position Cursor
Place your cursor on any org-mode task heading:

```org
* TODO Learn Rust programming
SCHEDULED: <2025-02-01>
:PROPERTIES:
:TASK_ID: 20250102120000
:END:

Want to build CLI tools and understand systems programming.
```

### Step 2: Press Keymap
```
<leader>cP
```

Or use the command:
```vim
:GtdConvertToProject
```

### Step 3: Follow Prompts
The workflow will:

1. **Pre-fill project name** with task title (editable)
2. **Pre-fill description** with task body (editable)
3. **Pre-fill dates** from task SCHEDULED/DEADLINE (editable)
4. **Ask for Area** (auto-detects if task is in Area, allows change)
5. **Create project** with full org-mode structure + ZK note
6. **Prompt for original task** handling

### Step 4: Handle Original Task
Choose what to do with the original task:

- **Archive** → Moves to Archive.org with link to new project
- **Delete** → Permanently removes task
- **Mark DONE** → Marks complete with project link
- **Move as NEXT** → Becomes first action in new project
- **Keep as-is** → No changes to original

## 🗺️ Complete GTD Keymap Structure

```
<leader>c     → GTD (root)
  ├─ cc       → Capture → Inbox
  ├─ cs       → Change task status
  │
  ├─ cl*      → Clarify / Lists
  │   ├─ clt  → Clarify current task
  │   ├─ cll  → Clarify from list (fzf)
  │   ├─ clp  → Link task → project note
  │   ├─ clm  → Lists → Menu
  │   ├─ cln  → Lists → Next Actions
  │   ├─ clP  → Lists → Projects
  │   ├─ cls  → Lists → Someday/Maybe
  │   ├─ clw  → Lists → Waiting For
  │   ├─ clx  → Lists → Stuck Projects
  │   └─ cla  → Lists → Search All
  │
  ├─ cr       → Refile current task
  ├─ cR       → Refile any task (fzf)
  │
  ├─ cp       → New project (org + ZK)      ← CREATE NEW
  ├─ cP       → Convert task → project      ← NEW! PROMOTE EXISTING
  │
  ├─ cm*      → Manage
  │   ├─ cmt  → Manage → Tasks
  │   ├─ cmp  → Manage → Projects
  │   └─ cmh  → Manage → Help
  │
  └─ ch       → Health check
```

## 🎨 Example Workflows

### Workflow 1: SOMEDAY → Project
```org
# You're reviewing Someday list
* SOMEDAY Learn functional programming

# Press <leader>cP
# → Becomes full project with structure
# → Original task archived with link
```

### Workflow 2: TODO → Project (realizes it's bigger)
```org
# Working on TODO list
* TODO Organize home office

# Realize this needs multiple steps
# Press <leader>cP
# → Converts to project
# → Add as first NEXT action in project
```

### Workflow 3: Inbox → Project (skip TODO step)
```org
# Processing inbox
* Redesign company website

# Too big for single task
# Press <leader>cP instead of clarifying
# → Goes straight to project
```

## 🔍 WhichKey Integration

When you press `<leader>c`, WhichKey will show:

```
GTD
  p → New project (org + ZK)
  P → Convert task → project        ← NEW!
```

The uppercase `P` makes it visually distinct from lowercase `p`.

## ✅ Verification

Test the installation:

1. **Open any org file:**
   ```vim
   :edit ~/Documents/GTD/Inbox.org
   ```

2. **Create test task:**
   ```org
   * TODO Test conversion feature
   This is a test task for conversion.
   ```

3. **Convert it:**
   ```
   <leader>cP
   ```

4. **Should see:**
   - Task metadata extracted
   - Prompts pre-filled with task data
   - Project created successfully
   - Options for original task handling

## 🎓 Tips

### When to Use Each

| Keymap | When to Use |
|--------|-------------|
| `<leader>cp` | Creating brand new project from scratch |
| `<leader>cP` | Task exists and needs to become a project |

### Smart Conversions

- **Task in Area?** → Project stays in same Area (editable)
- **Has ZK note?** → Reuses existing note
- **Has dates?** → Pre-fills defer/due dates
- **Has tags?** → Preserves tags on project

### Audit Trail

Every converted project has:
```org
:PROPERTIES:
:CONVERTED_FROM: 20250102120000    ← Original task ID
:END:
```

This lets you trace project origins!

## 🔧 Customization

If you prefer a different keymap:

```lua
-- In ~/.config/nvim/lua/mappings/gtd.lua
-- Change <leader>cP to something else:

map("n", "<leader>ct", function() gtd.convert_task_to_project({}) end,
  vim.tbl_extend("force", base, { desc = "GTD: Convert task → project" }))
```

## 📚 Documentation

See full documentation:
```
~/.config/nvim/lua/gtd/CONVERT_TASK_TO_PROJECT.md
```

## 🎉 Benefits

1. **Workflow Consistency** - Same `<leader>c` prefix as all GTD actions
2. **Mnemonic** - `p`/`P` pattern (new/promote)
3. **WhichKey Visible** - Shows in which-key popup
4. **No Data Loss** - Everything from task is preserved
5. **Flexible** - Choose what happens to original task

---

**Happy converting!** 🚀

Your GTD system just got even more powerful with seamless task→project evolution!
