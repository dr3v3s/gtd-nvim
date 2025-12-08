# nvim-gtd Plugin Development Guide

Comprehensive roadmap for turning your GTD tools into a proper public Neovim plugin.

## Current State Summary

### What Exists

```
~/projects/gtd-nvim/           # Plugin project (git repo)
├── lua/gtd-nvim/
│   ├── init.lua               # Main entry, setup()
│   ├── health.lua             # :checkhealth support
│   ├── gtd/                   # Core GTD (14 files, ~8000 lines)
│   ├── zettelkasten/          # ZK system (6 files)
│   ├── audit/                 # Org compliance (5 files)
│   └── utils/                 # link_insert, link_open
├── plugin/gtd-nvim.lua        # User commands (56 commands!)
├── README.md                  # Good documentation
├── WORKFLOW.md                # GTD methodology guide
├── PLUGIN_ANALYSIS.md         # Detailed analysis (already done!)
└── sync-to-plugin.sh          # Sync from ~/.config/nvim

~/.config/nvim/lua/
├── gtd/                       # → syncs to plugin
├── utils/zettelkasten/        # → syncs to plugin
├── utils/gtd-audit/           # → syncs to plugin
├── utils/link_insert.lua      # symlink TO plugin
├── utils/link_open.lua        # symlink TO plugin
├── core/gtd.lua               # Mappings/loader?
├── mappings/gtd.lua           # Keybindings
└── configs/links.lua          # Link config
```

### GitHub Remote
- `https://github.com/dr3v3s/gtd-nvim.git`
- Currently **private** (not yet public)
- Version: 2.0.0

### Development Workflow
You edit in `~/.config/nvim/lua/gtd/*`, then run `sync-to-plugin.sh` to copy to the plugin directory. The link utilities are symlinked the other way (plugin → config).

---

## Issues to Fix Before Public Release

### 1. Require Paths (CRITICAL)

The synced GTD modules still use old `require("gtd.*")` paths internally. When installed as a standalone plugin, these will **break**.

**Current (broken when standalone):**
```lua
-- In lua/gtd-nvim/gtd/capture.lua
local ui = require("gtd.ui")
local shared = require("gtd.shared")
```

**Should be:**
```lua
local ui = require("gtd-nvim.gtd.ui")
local shared = require("gtd-nvim.gtd.shared")
```

**Files needing fixes:**

```bash
# Find all internal requires that need updating
cd ~/projects/gtd-nvim/lua/gtd-nvim
grep -rn 'require.*"gtd\.' --include="*.lua" .
```

**Fix script:**
```bash
cd ~/projects/gtd-nvim/lua/gtd-nvim

# Replace gtd. → gtd-nvim.gtd.
find . -name "*.lua" -exec sed -i '' \
  's/require("gtd\./require("gtd-nvim.gtd./g' {} \;
find . -name "*.lua" -exec sed -i '' \
  's/require('\''gtd\./require('\''gtd-nvim.gtd./g' {} \;

# Verify
grep -rn 'require.*"gtd\.' --include="*.lua" .
```

### 2. Hardcoded Paths

Many files have `~/Documents/GTD` hardcoded as **defaults** — this is **fine** for defaults, but should always be overridable via `setup()`.

**Verify config flows through:**
```lua
-- In capture.lua
M.cfg = {
  gtd_dir = "~/Documents/GTD",  -- Default
}

function M.setup(opts)
  M.cfg = vim.tbl_deep_extend("force", M.cfg, opts or {})
end
```

### 3. Personal Data Check

**Already clean:**
- ✅ No personal emails in GTD code
- ✅ No API keys or tokens
- ✅ No private server names (except config examples)

**Needs attention:**
- ⚠️ `secrets*.txt` files in nvim config (not in plugin)
- ⚠️ Some files have `Author: plague` comments (cosmetic)

### 4. Standardize Config Pattern

Some modules use `M.cfg`, others use `M.config`:

```lua
-- capture.lua uses:
M.cfg = { ... }

-- init.lua uses:
M.config = { ... }
```

**Recommendation:** Standardize on `M.config` everywhere.

---

## Recommended Plugin Split

Your PLUGIN_ANALYSIS.md already covers this well. Here's the refined version:

### Plugin 1: nvim-gtd (Primary)

**Scope:** GTD workflow only

```
nvim-gtd/
├── lua/
│   └── gtd/
│       ├── init.lua           # setup(), API
│       ├── capture.lua        # Quick capture to inbox
│       ├── clarify.lua        # Process inbox items
│       ├── organize.lua       # Refile to projects
│       ├── projects.lua       # Project management
│       ├── lists.lua          # Next actions, waiting, etc.
│       ├── manage.lua         # Task manager UI
│       ├── areas.lua          # Areas of focus
│       ├── audit.lua          # Org compliance (merge in)
│       ├── calendar.lua       # (optional) Calendar view
│       ├── reminders.lua      # (optional) macOS integration
│       ├── health.lua         # :checkhealth
│       ├── ui.lua             # UI components
│       └── utils/
│           ├── task_id.lua    # Task ID generation
│           └── org_dates.lua  # Org date parsing
├── plugin/
│   └── gtd.lua               # User commands
├── doc/
│   └── gtd.txt               # Vim help
├── README.md
├── WORKFLOW.md
└── LICENSE
```

**Changes from current:**
- Remove `zettelkasten/` entirely
- Remove `utils/link_*.lua` (move to zettelkasten)
- Merge `audit/` into main `gtd/` directory
- Rename namespace: `gtd-nvim.gtd.*` → `gtd.*`

### Plugin 2: nvim-zettelkasten (Separate)

**Scope:** Note-taking system

```
nvim-zettelkasten/
├── lua/
│   └── zettelkasten/
│       ├── init.lua           # setup(), API
│       ├── note.lua           # Create notes
│       ├── find.lua           # Search/find
│       ├── links.lua          # Link insert/open (from utils/)
│       ├── backlinks.lua      # Backlink tracking
│       ├── templates/
│       │   ├── daily.lua
│       │   ├── project.lua
│       │   ├── person.lua
│       │   └── reading.lua
│       └── health.lua
├── plugin/
│   └── zettelkasten.lua
├── doc/
│   └── zettelkasten.txt
└── README.md
```

### Plugin 3: nvim-writing (Future)

**Scope:** Prose/writing tools

```
nvim-writing/
├── lua/
│   └── writing/
│       ├── init.lua
│       ├── focus.lua          # Focus mode (from your zen config)
│       ├── zen.lua            # Distraction-free
│       ├── prose.lua          # Prose linting
│       └── markdown.lua       # MD enhancements
└── ...
```

---

## Integration Between Plugins

When separate, they can still work together via hooks:

```lua
-- User's config
require("gtd").setup({
  on_capture = function(task)
    -- Hook to create linked note
    local zk = pcall(require, "zettelkasten")
    if zk then
      -- Create note linked to task
    end
  end,
})

require("zettelkasten").setup({
  on_new_note = function(note)
    -- Hook to create GTD task
    local gtd = pcall(require, "gtd")
    if gtd then
      -- Optionally capture as task
    end
  end,
})
```


---

## Step-by-Step Migration

### Phase 1: Fix Current Plugin (Do First)

Before splitting, make the current monolith work as a standalone plugin.

#### 1.1 Sync Latest Changes

```bash
cd ~/projects/gtd-nvim
./sync-to-plugin.sh
git status
```

#### 1.2 Fix Require Paths

```bash
cd ~/projects/gtd-nvim/lua/gtd-nvim

# Automated fix
find . -name "*.lua" -exec sed -i '' \
  's/require("gtd\./require("gtd-nvim.gtd./g' {} \;
find . -name "*.lua" -exec sed -i '' \
  's/require('\''gtd\./require('\''gtd-nvim.gtd./g' {} \;

# Manual verification
grep -rn 'require.*"gtd\.' --include="*.lua" . | grep -v gtd-nvim
```

#### 1.3 Standardize Config

In each module, ensure:
```lua
M.config = {
  -- defaults
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end
```

#### 1.4 Test as Standalone

```bash
# Create test environment
mkdir -p /tmp/nvim-test
cd /tmp/nvim-test

# Minimal init.lua
cat > init.lua << 'EOF'
vim.opt.rtp:prepend("/Users/plague/projects/gtd-nvim")
require("gtd-nvim").setup({
  gtd_root = "/tmp/test-gtd",
})
EOF

# Create test directories
mkdir -p /tmp/test-gtd/{Projects,Areas}
echo "* Inbox" > /tmp/test-gtd/Inbox.org

# Run test
nvim -u init.lua -c ":checkhealth gtd-nvim"
```

#### 1.5 Commit & Tag

```bash
cd ~/projects/gtd-nvim
git add -A
git commit -m "fix: update require paths for standalone installation"
git tag -a v2.1.0 -m "Standalone installation support"
git push origin main --tags
```

### Phase 2: Clean Up for Public Release

#### 2.1 Remove Development Artifacts

```bash
cd ~/projects/gtd-nvim

# Remove backup files
find . -name "*.bak" -delete
find . -name "*~" -delete
find . -name "*.lua-" -delete
find . -name ".DS_Store" -delete

# Remove development scripts (or move to .github/)
mkdir -p .github/scripts
mv sync-to-plugin.sh .github/scripts/
mv quick-push.sh .github/scripts/
```

#### 2.2 Add .gitignore

```bash
cat > .gitignore << 'EOF'
# Development
*.bak
*~
*.lua-
.DS_Store

# Local testing
/test/
/tmp/

# IDE
.idea/
.vscode/
*.swp
*.swo
EOF
```

#### 2.3 Update README

Add:
- Badges (GitHub stars, license, Neovim version)
- Screenshot/GIF demo
- Installation for multiple plugin managers
- Troubleshooting section
- Link to Wiki (if extensive docs)

#### 2.4 Add Vim Help Documentation

```bash
mkdir -p doc
cat > doc/gtd-nvim.txt << 'EOF'
*gtd-nvim.txt*  Getting Things Done system for Neovim

                        GTD-NVIM REFERENCE MANUAL

==============================================================================
CONTENTS                                                  *gtd-nvim-contents*

  1. Introduction ............................ |gtd-nvim-introduction|
  2. Installation ............................ |gtd-nvim-installation|
  3. Configuration ........................... |gtd-nvim-configuration|
  4. Commands ................................ |gtd-nvim-commands|
  5. API ..................................... |gtd-nvim-api|
  6. Workflow ................................ |gtd-nvim-workflow|

==============================================================================
1. INTRODUCTION                                       *gtd-nvim-introduction*

GTD-Nvim implements David Allen's Getting Things Done methodology in Neovim.
Built in pure Lua for terminal-based productivity.

Features:
  • Quick capture to inbox
  • Process/clarify inbox items
  • Organize tasks into projects
  • View next actions, waiting for, someday/maybe
  • Project and area management
  • Org-mode compliance auditing

==============================================================================
2. INSTALLATION                                       *gtd-nvim-installation*

Using lazy.nvim: >lua
  {
    "dr3v3s/gtd-nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "ibhagwan/fzf-lua",
    },
    config = function()
      require("gtd-nvim").setup({
        gtd_root = vim.fn.expand("~/Documents/GTD"),
      })
    end,
  }
<

... etc
EOF
```

### Phase 3: Extract nvim-zettelkasten (Later)

Only after GTD is stable and published.

```bash
# Create new repo
mkdir -p ~/projects/nvim-zettelkasten/{lua/zettelkasten,plugin,doc}
cd ~/projects/nvim-zettelkasten
git init

# Copy files from gtd-nvim
cp -r ~/projects/gtd-nvim/lua/gtd-nvim/zettelkasten/* lua/zettelkasten/
cp ~/projects/gtd-nvim/lua/gtd-nvim/utils/link_*.lua lua/zettelkasten/

# Update requires
find lua -name "*.lua" -exec sed -i '' \
  's/gtd-nvim\.zettelkasten/zettelkasten/g' {} \;
find lua -name "*.lua" -exec sed -i '' \
  's/gtd-nvim\.utils/zettelkasten/g' {} \;

# Create init.lua, plugin/, etc.
# ...

# Remove from gtd-nvim
cd ~/projects/gtd-nvim
rm -rf lua/gtd-nvim/zettelkasten
rm lua/gtd-nvim/utils/link_*.lua
# Update init.lua to remove ZK references
```

### Phase 4: Rename to nvim-gtd (Optional)

If you want cleaner naming without the `-nvim` suffix in the module name:

```bash
cd ~/projects/gtd-nvim
mv lua/gtd-nvim lua/gtd

# Update all requires
find lua -name "*.lua" -exec sed -i '' \
  's/gtd-nvim\./gtd./g' {} \;

# Rename repo
# (Do this on GitHub: Settings → Rename)
```


---

## File-by-File Analysis

### Core GTD Modules

| File | Lines | Purpose | Issues |
|------|-------|---------|--------|
| `gtd/init.lua` | ~180 | Entry point, setup | Check require paths |
| `gtd/capture.lua` | ~970 | Inbox capture | Uses `M.cfg` not `M.config` |
| `gtd/clarify.lua` | ~900 | Process inbox | Large file, could split |
| `gtd/organize.lua` | ~800 | Refile tasks | Hardcoded paths in comments |
| `gtd/projects.lua` | ~1100 | Project CRUD | **Largest file**, split candidate |
| `gtd/manage.lua` | ~1100 | Task manager UI | **Large**, complex |
| `gtd/lists.lua` | ~900 | View lists | Good structure |
| `gtd/areas.lua` | ~75 | Areas of focus | Simple, clean |
| `gtd/calendar.lua` | ~750 | Calendar view | Optional feature |
| `gtd/reminders.lua` | ~750 | macOS Reminders | macOS-specific |
| `gtd/shared.lua` | ~270 | Shared utilities | Good |
| `gtd/ui.lua` | ~450 | UI components | Reusable |
| `gtd/status.lua` | ~150 | Status line | Small, clean |

### GTD Utils

| File | Lines | Purpose |
|------|-------|---------|
| `gtd/utils/task_id.lua` | ~100 | Task ID generation |
| `gtd/utils/org_dates.lua` | ~150 | Org date parsing |

### Audit Module

| File | Lines | Purpose |
|------|-------|---------|
| `audit/init.lua` | ~140 | Entry point |
| `audit/parser.lua` | ~200 | Parse org files |
| `audit/validators.lua` | ~230 | Validate compliance |
| `audit/insights.lua` | ~250 | Generate insights |
| `audit/reports.lua` | ~190 | Format reports |

### Zettelkasten Module

| File | Lines | Purpose |
|------|-------|---------|
| `zettelkasten/init.lua` | ~300 | Entry point |
| `zettelkasten/capture.lua` | ~400 | Note capture |
| `zettelkasten/manage.lua` | ~350 | Note management |
| `zettelkasten/project.lua` | ~200 | Project notes |
| `zettelkasten/people.lua` | ~150 | People notes |
| `zettelkasten/reading.lua` | ~200 | Reading notes |

### Link Utilities

| File | Lines | Purpose | Notes |
|------|-------|---------|-------|
| `utils/link_insert.lua` | ~490 | Insert links | Symlinked to plugin |
| `utils/link_open.lua` | ~200 | Open links | Symlinked to plugin |

---

## Pre-Release Checklist

### Code Quality

- [ ] All `require()` paths use correct namespace
- [ ] No hardcoded `/Users/plague/` paths
- [ ] No personal emails (except author comments)
- [ ] No API keys, tokens, secrets
- [ ] No `.gpg` files in repo
- [ ] Standardized on `M.config` pattern
- [ ] Development comment headers removed
- [ ] Backup files cleaned (`*.bak`, `*~`, `*.lua-`)

### Plugin Structure

- [ ] `lua/gtd-nvim/init.lua` has `setup()` function
- [ ] `plugin/gtd-nvim.lua` has user commands
- [ ] `doc/gtd-nvim.txt` has vim help
- [ ] `README.md` is comprehensive
- [ ] `LICENSE` file exists (MIT)
- [ ] `.gitignore` excludes dev files

### Functionality

- [ ] `:checkhealth gtd-nvim` passes
- [ ] All `:Gtd*` commands work
- [ ] Fresh install works (no pre-existing state)
- [ ] Config validation provides helpful errors
- [ ] Works with both fzf-lua and telescope

### Documentation

- [ ] Installation instructions (lazy.nvim, packer, vim-plug)
- [ ] All config options documented
- [ ] All commands documented in README
- [ ] All commands documented in `:help`
- [ ] Example keymaps provided
- [ ] WORKFLOW.md explains GTD methodology
- [ ] Screenshots or demo GIF

### Testing

- [ ] Test fresh install in clean nvim
- [ ] Test with minimal dependencies
- [ ] Test all user commands
- [ ] Test `:checkhealth`
- [ ] Test config merging

### GitHub

- [ ] Repository description filled
- [ ] Topics: `neovim`, `neovim-plugin`, `gtd`, `lua`, `productivity`
- [ ] License selected (MIT)
- [ ] Release created (v2.1.0 or v3.0.0)
- [ ] README visible on repo page

---

## Recommended Order of Work

### Now (While You Continue Using It)

1. Keep developing in `~/.config/nvim/lua/gtd/`
2. Sync periodically with `sync-to-plugin.sh`
3. Don't worry about public release yet

### When Ready to Publish GTD

1. **Fix require paths** — Critical, 30 min
2. **Test standalone** — Create test environment, 15 min
3. **Clean repo** — Remove dev artifacts, 10 min
4. **Add vim help** — `doc/gtd-nvim.txt`, 1-2 hours
5. **Update README** — Badges, screenshots, 30 min
6. **Tag release** — v2.1.0 or v3.0.0
7. **Make public** — GitHub settings

### Later (After GTD is Stable)

1. Extract `nvim-zettelkasten` to separate repo
2. Remove ZK from `gtd-nvim`
3. Add integration hooks
4. Extract `nvim-writing` (if desired)

---

## Quick Commands Reference

```bash
# Sync development → plugin
cd ~/projects/gtd-nvim && ./sync-to-plugin.sh

# Fix require paths
cd ~/projects/gtd-nvim/lua/gtd-nvim
grep -rn 'require.*"gtd\.' --include="*.lua" . | grep -v gtd-nvim

# Check for personal data
grep -rn "plague\|return-path\|michael@" --include="*.lua" .

# Test standalone
nvim -u /tmp/nvim-test/init.lua -c ":checkhealth gtd-nvim"

# Commit and push
cd ~/projects/gtd-nvim
git add -A && git commit -m "..." && git push

# Create release
git tag -a v2.1.0 -m "Description" && git push origin --tags
```

---

## Related Files in Your Config

These files in `~/.config/nvim/` are **not** part of the plugin but help integrate it:

| File | Purpose |
|------|---------|
| `lua/core/gtd.lua` | Loads GTD, sets up integration |
| `lua/mappings/gtd.lua` | Your personal keybindings |
| `lua/configs/links.lua` | Link configuration |
| `lua/plugins/gp.lua` | AI integration (has GTD prompts?) |

When you publish, users will create their own versions of these.

---

*Last updated: 2024-12-07*
*Location: ~/dotfiles/nvim/.config/nvim/lua/gtd/PLUGIN_DEV_GUIDE.md*
