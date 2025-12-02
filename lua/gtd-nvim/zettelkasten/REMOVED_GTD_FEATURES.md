# GTD Features Removed - Summary

## Date: 2025-12-02

## Rationale
Removed redundant GTD management features from Zettelkasten system as they duplicate functionality already present in the GTD module.

## What Was Removed

### From `zettelkasten.lua` (core):
1. **Function:** `M.browse_gtd_tasks()` - Browse and manage GTD tasks
2. **Function:** `M.create_note_for_gtd_task(task_text)` - Create note from GTD task
3. **Command:** `:ZettelGTD` - Browse GTD tasks command
4. **Comment:** Replaced with note about using GTD module

### From `capture.lua`:
1. **Function:** `M.gtd_capture(text)` - Capture to GTD inbox
2. **Command:** `:ZettelCapture` - GTD capture command
3. **Keymap:** `<leader>zc` - GTD capture keymap

### From `init.lua`:
1. **Export:** `M.gtd_capture` - Removed from module exports
2. **Export:** `M.browse_gtd_tasks` - Removed from module exports

### From Documentation:
1. Updated `QUICK_REFERENCE.md` to remove GTD management references
2. Added clarification that GTD integration is read-only for display

## What Was KEPT

### GTD Read Integration (Display Only):
- ✅ `get_gtd_tasks()` internal function (reads tasks from org files)
- ✅ GTD task display in daily notes
- ✅ Task syncing in `daily_note()` function
- ✅ GTD task links in daily notes
- ✅ GTD configuration in setup

**Reason:** These features READ GTD data for display in notes but don't MANAGE tasks.

## Files Modified

1. `/Users/plague/.config/nvim/lua/utils/zettelkasten.lua`
   - Removed 90 lines (browse_gtd_tasks and helper)
   - Removed 1 command registration
   
2. `/Users/plague/.config/nvim/lua/utils/zettelkasten/capture.lua`
   - Removed 52 lines (gtd_capture function)
   - Removed 1 command registration
   - Removed 1 keymap

3. `/Users/plague/.config/nvim/lua/utils/zettelkasten/init.lua`
   - Removed 2 export lines

4. `/Users/plague/.config/nvim/lua/mappings/zettel.lua`
   - Removed `<leader>zg` keymap (browse_gtd_tasks)
   - Removed `<leader>zg` from which-key integration
   - Updated header comment

5. `/Users/plague/.config/nvim/lua/utils/zettelkasten/QUICK_REFERENCE.md`
   - Updated to clarify read-only GTD integration
   - Removed capture keymap documentation

## Result

**Before:**
- Zettelkasten could browse GTD tasks (redundant)
- Zettelkasten could capture to GTD inbox (redundant)
- Zettelkasten could create notes from GTD tasks (redundant)
- ~150 lines of duplicate functionality

**After:**
- Zettelkasten reads GTD tasks for display only
- GTD module handles all task management
- Clean separation of concerns
- ~150 lines removed

## Migration Notes

Users should now use the existing GTD module for:
- Task browsing
- Task capture to inbox
- Task management
- Task state changes

Zettelkasten system still provides:
- Daily notes with GTD task display (read-only)
- Links to GTD org files
- Task count in stats

## Commands That Still Work

✅ `:ZettelDaily` - Creates daily note with GTD tasks (read-only)
✅ `:ZettelStats` - Shows stats including GTD task count
✅ `:ZettelSearchAll` - Searches notes + GTD files

## Commands Removed

❌ `:ZettelGTD` - Use your GTD module instead
❌ `:ZettelCapture` - Use your GTD module instead

## Keymaps Removed

❌ `<leader>zg` - Was for browse GTD tasks (from lua/mappings/zettel.lua)

Note: `<leader>zc` is still mapped to "clear_all_cache" (not GTD capture)

## Testing Checklist

After restart, verify:
- [ ] `:ZettelDaily` still creates daily note with GTD tasks
- [ ] `:ZettelGTD` command is gone (expected)
- [ ] `:ZettelCapture` command is gone (expected)
- [ ] `<leader>zc` keymap is gone (expected)
- [ ] GTD tasks still display in daily notes
- [ ] No errors on startup

## Benefits

1. **DRY Principle** - No duplicate code
2. **Single Responsibility** - GTD module manages tasks
3. **Cleaner API** - Fewer exported functions
4. **Less Confusion** - One way to manage GTD tasks
5. **Maintainability** - Changes to GTD logic in one place

---

**Summary:** Removed ~150 lines of redundant GTD management code. Kept read-only GTD integration for daily notes. Users should use the existing GTD module for all task management.
