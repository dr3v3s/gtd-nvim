# GTD-Nvim Development Workflow

This document explains the symlinked development setup for GTD-Nvim.

## Structure

Your Neovim configuration now uses symlinks to the public repository:

```
~/.config/nvim/lua/
├── gtd/                    → ~/projects/gtd-nvim/lua/gtd-nvim/gtd/
├── zettelkasten.lua        → ~/projects/gtd-nvim/lua/gtd-nvim/zettelkasten/init.lua
├── zk.lua                  → ~/projects/gtd-nvim/lua/gtd-nvim/zettelkasten/zk.lua
└── utils/
    ├── zettelkasten.lua    → ~/projects/gtd-nvim/lua/gtd-nvim/zettelkasten/zettelkasten.lua
    ├── link_insert.lua     → ~/projects/gtd-nvim/lua/gtd-nvim/utils/link_insert.lua
    └── link_open.lua       → ~/projects/gtd-nvim/lua/gtd-nvim/utils/link_open.lua
```

## Development Workflow

### Making Changes

**Edit as usual in Neovim** - all changes are automatically made to the git repository!

```bash
# Just edit your files normally
nvim ~/.config/nvim/lua/gtd/capture.lua
# Changes are made directly to ~/projects/gtd-nvim/lua/gtd-nvim/gtd/capture.lua
```

### Publishing Changes

When you're ready to publish your changes:

```bash
cd ~/projects/gtd-nvim
git status                  # See what changed
git add -A                  # Stage all changes
git commit -m "Your message"
git push origin main
```

### Quick Push Script

Use the provided helper script for fast commits:

```bash
cd ~/projects/gtd-nvim
./quick-push.sh "Added new feature"
```

Or use the git alias:

```bash
cd ~/projects/gtd-nvim
git quick-push "Fixed bug in capture"
```

## Backup

Your original files are backed up in:
```
~/backups/nvim-gtd-backup-20251024/
```

## Reverting to Original Setup

If you ever need to revert:

```bash
# Remove symlinks
rm ~/.config/nvim/lua/gtd
rm ~/.config/nvim/lua/zettelkasten.lua
rm ~/.config/nvim/lua/zk.lua
rm ~/.config/nvim/lua/utils/zettelkasten.lua
rm ~/.config/nvim/lua/utils/link_insert.lua
rm ~/.config/nvim/lua/utils/link_open.lua

# Restore from backup
cp -r ~/backups/nvim-gtd-backup-20251024/* ~/.config/nvim/lua/
```

## Benefits

✅ **Single source of truth** - Edit in one place  
✅ **Auto-synced** - Changes immediately reflected in git repo  
✅ **Version controlled** - All changes tracked in git  
✅ **Easy publishing** - Simple commit and push workflow  
✅ **Community contributions** - Share improvements easily  

## Testing

After making changes, test that everything still works:

```bash
# Start Neovim and run GTD commands
nvim
:lua require('gtd.capture').capture()
```

## Git Tips

### View recent changes
```bash
cd ~/projects/gtd-nvim
git log --oneline -10
```

### See what you've edited
```bash
cd ~/projects/gtd-nvim
git diff
```

### Create feature branch
```bash
cd ~/projects/gtd-nvim
git checkout -b feature/new-enhancement
# Make changes, commit, push
git push -u origin feature/new-enhancement
```

## Questions?

The symlink approach means:
- **Editing** happens wherever you normally edit (in your nvim config paths)
- **Changes** are actually made in `~/projects/gtd-nvim/`
- **Publishing** happens from `~/projects/gtd-nvim/`

It's the best of both worlds! 🎉
