# GTD-Nvim Plugin Analysis & Roadmap

A thorough analysis of the current state and recommendations for publishing as proper Neovim plugins.

## Current State

### Repository Location
- **Plugin project:** `/Users/plague/projects/gtd-nvim`
- **GitHub:** `https://github.com/dr3v3s/gtd-nvim.git`
- **Version:** 2.0.0 (already committed)

### Development Workflow
```
~/.config/nvim/lua/gtd/          →  (symlinked TO plugin)
~/.config/nvim/lua/utils/zettelkasten/  →  (symlinked TO plugin)
~/.config/nvim/lua/utils/link_*.lua     →  (symlinked TO plugin)

sync-to-plugin.sh:
  ~/.config/nvim/lua/gtd/        →  ~/projects/gtd-nvim/lua/gtd-nvim/gtd/
  ~/.config/nvim/lua/utils/zettelkasten/  →  ~/projects/gtd-nvim/lua/gtd-nvim/zettelkasten/
```

### Current Structure
```
~/projects/gtd-nvim/
├── lua/
│   └── gtd-nvim/
│       ├── init.lua              # Main entry (v2.0.0)
│       ├── health.lua            # :checkhealth support
│       ├── gtd/                  # GTD system (14 files)
│       │   ├── init.lua
│       │   ├── capture.lua       # 973 lines - Inbox capture
│       │   ├── clarify.lua       # 900+ lines - Process inbox
│       │   ├── organize.lua      # 800+ lines - Refile tasks
│       │   ├── manage.lua        # 1100+ lines - Task management
│       │   ├── lists.lua         # 900+ lines - Next actions, etc.
│       │   ├── projects.lua      # 1100+ lines - Project management
│       │   ├── areas.lua         # Areas of Focus
│       │   ├── calendar.lua      # Calendar integration
│       │   ├── reminders.lua     # macOS reminders
│       │   ├── status.lua        # Status line
│       │   ├── shared.lua        # Shared utilities
│       │   ├── ui.lua            # UI components
│       │   ├── scripts/          # Migration scripts
│       │   └── utils/            # task_id, org_dates
│       ├── zettelkasten/         # Zettelkasten system (8 files)
│       │   ├── init.lua
│       │   ├── capture.lua
│       │   ├── manage.lua
│       │   ├── people.lua
│       │   ├── project.lua
│       │   └── reading.lua
│       ├── audit/                # GTD audit tools (5 files)
│       │   ├── init.lua
│       │   ├── parser.lua
│       │   ├── validators.lua
│       │   ├── insights.lua
│       │   └── reports.lua
│       └── utils/
│           ├── link_insert.lua   # 493 lines
│           └── link_open.lua
├── plugin/
│   └── gtd-nvim.lua              # Auto-load, user commands
├── examples/
│   ├── gtd_mappings.lua
│   └── zettel_mappings.lua
├── README.md
├── WORKFLOW.md
├── DEPENDENCIES.md
├── DEVELOPMENT.md
└── LICENSE
```


## Issues Identified

### 1. **Inconsistent Require Paths**

The GTD modules use old paths that don't match the plugin namespace:

```lua
-- In lua/gtd-nvim/gtd/init.lua (CURRENT - BROKEN)
local capture = safe_require "gtd.capture"
local clarify = safe_require "gtd.clarify"

-- Should be:
local capture = safe_require "gtd-nvim.gtd.capture"
local clarify = safe_require "gtd-nvim.gtd.clarify"
```

**Affected files:**
- `lua/gtd-nvim/gtd/init.lua` - requires `gtd.*`
- `lua/gtd-nvim/gtd/capture.lua` - requires `gtd.utils.task_id`
- Most GTD modules have this issue

### 2. **Bundled Components Should Be Separate**

Currently bundled as one monolith:
- **gtd/** - Core GTD workflow
- **zettelkasten/** - Note-taking system
- **audit/** - Compliance checking
- **utils/link_*.lua** - Link handling

**Recommendation:** Split into 3-4 separate plugins.

### 3. **Hardcoded Comment Paths**

Many files have comment headers with development paths:
```lua
-- ~/.config/nvim/lua/gtd/capture.lua   ← Should be removed
```

### 4. **Mixed Config Patterns**

Some modules use `M.cfg = {}`, others use `M.config = {}`:
```lua
-- capture.lua uses:
M.cfg = { gtd_dir = "~/Documents/GTD" }

-- init.lua uses:
M.config = { gtd_root = "~/Documents/GTD" }
```

### 5. **Development Symlinks Are Backwards**

Current setup:
```
~/.config/nvim/lua/gtd → /Users/plague/projects/gtd-nvim/lua/gtd-nvim/gtd
```

This means edits in nvim config edit the plugin directly. Better:
- Develop in `~/projects/gtd-nvim/`
- Symlink plugin into `~/.local/share/nvim/lazy/` or use lazy.nvim dev mode


## Recommended Plugin Architecture

### Split Into Separate Plugins

```
┌─────────────────────────────────────────────────────────────┐
│                      User's Config                          │
│  require("gtd").setup({ zk_integration = true })            │
│  require("zettelkasten").setup({ gtd_integration = true })  │
│  require("writing").setup({})                               │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
    ┌─────────────┐  ┌──────────────┐  ┌───────────┐
    │   nvim-gtd  │  │nvim-zettelkasten│ │nvim-writing│
    │             │  │              │  │           │
    │ • capture   │  │ • new_note   │  │ • focus   │
    │ • clarify   │  │ • find       │  │ • zen     │
    │ • organize  │  │ • backlinks  │  │ • prose   │
    │ • projects  │  │ • daily      │  │ • spell   │
    │ • lists     │  │ • templates  │  │           │
    │ • audit     │  │              │  │           │
    └─────────────┘  └──────────────┘  └───────────┘
              │               │
              └───────┬───────┘
                      ▼
           ┌─────────────────────┐
           │  Shared: link utils │
           │  (optional dep)     │
           └─────────────────────┘
```

### Plugin 1: nvim-gtd

**Focus:** Getting Things Done workflow

```
nvim-gtd/
├── lua/
│   └── gtd/
│       ├── init.lua           # Setup, config, API
│       ├── capture.lua        # Quick capture
│       ├── clarify.lua        # Process inbox
│       ├── organize.lua       # Refile, categorize
│       ├── projects.lua       # Project management
│       ├── lists.lua          # Next actions, waiting, etc.
│       ├── areas.lua          # Areas of focus
│       ├── audit.lua          # Org compliance (merged)
│       ├── calendar.lua       # Optional calendar
│       ├── reminders.lua      # Optional macOS reminders
│       └── utils/
│           ├── task_id.lua
│           ├── org_dates.lua
│           └── ui.lua
├── plugin/
│   └── gtd.lua               # Commands: :GtdCapture, etc.
├── doc/
│   └── gtd.txt               # Vim help
├── README.md
├── WORKFLOW.md
└── LICENSE
```

### Plugin 2: nvim-zettelkasten

**Focus:** Zettelkasten note-taking

```
nvim-zettelkasten/
├── lua/
│   └── zettelkasten/
│       ├── init.lua           # Setup, API
│       ├── note.lua           # Note creation
│       ├── find.lua           # Search, find
│       ├── links.lua          # Link insert/open
│       ├── backlinks.lua      # Backlink tracking
│       ├── templates/         # Note templates
│       │   ├── daily.lua
│       │   ├── project.lua
│       │   ├── person.lua
│       │   └── reading.lua
│       └── utils/
│           └── id.lua         # ZK ID generation
├── plugin/
│   └── zettelkasten.lua      # Commands: :ZkNew, etc.
├── doc/
│   └── zettelkasten.txt
└── README.md
```

### Plugin 3: nvim-writing (Future)

**Focus:** Writing/prose tools

```
nvim-writing/
├── lua/
│   └── writing/
│       ├── init.lua
│       ├── focus.lua         # Focus mode
│       ├── zen.lua           # Zen mode
│       ├── prose.lua         # Prose linting
│       └── spell.lua         # Enhanced spell
├── plugin/
│   └── writing.lua
└── README.md
```


## Proper Neovim Plugin Structure

### Required Elements

```
plugin-name/
├── lua/
│   └── plugin-name/
│       └── init.lua           # REQUIRED: Entry point with setup()
├── plugin/
│   └── plugin-name.lua        # REQUIRED: Auto-load, commands
├── doc/
│   └── plugin-name.txt        # RECOMMENDED: :help support
├── README.md                  # REQUIRED: Documentation
└── LICENSE                    # REQUIRED: License file
```

### init.lua Template

```lua
-- lua/gtd/init.lua
local M = {}

M._VERSION = "1.0.0"

-- Default configuration
M.defaults = {
  gtd_root = vim.fn.expand("~/Documents/GTD"),
  inbox_file = "Inbox.org",
  projects_dir = "Projects",
  areas_dir = "Areas",
  -- Integration hooks
  on_capture = nil,      -- function(task) called after capture
  on_complete = nil,     -- function(task) called after completion
  -- Optional integrations
  zettelkasten = {
    enabled = false,
    link_tasks = true,   -- Link tasks to ZK notes
  },
}

-- Merged config
M.config = {}

-- Safe require helper
local function safe_require(name)
  local ok, mod = pcall(require, name)
  if not ok then
    vim.notify("gtd: failed to load " .. name, vim.log.levels.WARN)
    return nil
  end
  return mod
end

-- Setup function (lazy.nvim compatible)
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})
  
  -- Initialize subsystems
  local capture = safe_require("gtd.capture")
  if capture then capture.setup(M.config) end
  
  local clarify = safe_require("gtd.clarify")
  if clarify then clarify.setup(M.config) end
  
  -- ... etc
end

-- Public API
function M.capture(opts)
  local capture = require("gtd.capture")
  return capture.capture_quick(opts or {})
end

function M.clarify(opts)
  local clarify = require("gtd.clarify")
  return clarify.at_cursor(opts or {})
end

-- Health check
function M.health()
  return require("gtd.health").check()
end

return M
```

### plugin/gtd.lua Template

```lua
-- plugin/gtd.lua
-- Auto-loaded by Neovim

if vim.g.loaded_gtd then return end
vim.g.loaded_gtd = true

-- Version check
if vim.fn.has("nvim-0.9.0") ~= 1 then
  vim.api.nvim_err_writeln("GTD requires Neovim >= 0.9.0")
  return
end

-- User commands
local function create_commands()
  vim.api.nvim_create_user_command("GtdCapture", function(opts)
    require("gtd").capture({ priority = opts.args })
  end, { nargs = "?", desc = "Capture to GTD inbox" })
  
  vim.api.nvim_create_user_command("GtdClarify", function()
    require("gtd").clarify()
  end, { desc = "Clarify item at cursor" })
  
  -- ... more commands
end

create_commands()
```

### doc/gtd.txt Template

```
*gtd.txt*  Getting Things Done for Neovim

CONTENTS                                                    *gtd-contents*

  1. Introduction ............................ |gtd-introduction|
  2. Installation ............................ |gtd-installation|
  3. Configuration ........................... |gtd-configuration|
  4. Commands ................................ |gtd-commands|
  5. API ..................................... |gtd-api|
  6. Mappings ................................ |gtd-mappings|

==============================================================================
1. INTRODUCTION                                          *gtd-introduction*

GTD (Getting Things Done) is a Neovim plugin implementing David Allen's
GTD methodology for personal productivity.

==============================================================================
2. INSTALLATION                                          *gtd-installation*

Using lazy.nvim: >lua
  {
    "dr3v3s/nvim-gtd",
    dependencies = { "ibhagwan/fzf-lua" },
    config = function()
      require("gtd").setup({
        gtd_root = "~/Documents/GTD",
      })
    end,
  }
<

==============================================================================
3. COMMANDS                                                  *gtd-commands*

:GtdCapture [priority]                                        *:GtdCapture*
    Capture a new item to inbox. Optional priority: A, B, C.

:GtdClarify                                                    *:GtdClarify*
    Process the item under cursor.

... etc
```


## Migration Steps

### Phase 1: Fix Current Plugin (nvim-gtd)

Before splitting, fix the existing codebase:

#### 1.1 Fix Require Paths

```bash
cd ~/projects/gtd-nvim/lua/gtd-nvim

# Find all incorrect requires
grep -r "require.*\"gtd\." --include="*.lua" .

# Replace with correct namespace
# gtd.capture → gtd-nvim.gtd.capture
# gtd.utils.task_id → gtd-nvim.gtd.utils.task_id
```

**Files to fix:**
- [ ] `gtd/init.lua`
- [ ] `gtd/capture.lua`
- [ ] `gtd/clarify.lua`
- [ ] `gtd/organize.lua`
- [ ] `gtd/manage.lua`
- [ ] `gtd/lists.lua`
- [ ] `gtd/projects.lua`

#### 1.2 Remove Development Comments

Remove lines like:
```lua
-- ~/.config/nvim/lua/gtd/capture.lua
```

#### 1.3 Standardize Config Pattern

Use `M.config` everywhere, not `M.cfg`:
```lua
M.config = {
  gtd_root = vim.fn.expand("~/Documents/GTD"),
  -- ...
}
```

#### 1.4 Add Proper Health Check

Update `lua/gtd-nvim/health.lua` to use `vim.health` API properly.

### Phase 2: Extract Zettelkasten

Create new repo `nvim-zettelkasten`:

```bash
mkdir -p ~/projects/nvim-zettelkasten/{lua/zettelkasten,plugin,doc}

# Copy files
cp -r ~/projects/gtd-nvim/lua/gtd-nvim/zettelkasten/* \
      ~/projects/nvim-zettelkasten/lua/zettelkasten/

# Copy link utilities
cp ~/projects/gtd-nvim/lua/gtd-nvim/utils/link_*.lua \
   ~/projects/nvim-zettelkasten/lua/zettelkasten/
```

#### Update requires:
```lua
-- Change from:
require("gtd-nvim.zettelkasten.capture")
-- To:
require("zettelkasten.capture")
```

### Phase 3: Remove Zettelkasten from GTD

After extraction:
```bash
cd ~/projects/gtd-nvim
rm -rf lua/gtd-nvim/zettelkasten
rm lua/gtd-nvim/utils/link_*.lua

# Update init.lua to remove ZK references
# Add optional integration hook instead
```

### Phase 4: Rename to nvim-gtd

```bash
# Rename repo
mv ~/projects/gtd-nvim ~/projects/nvim-gtd

# Update internal references
# gtd-nvim → gtd
cd ~/projects/nvim-gtd
mv lua/gtd-nvim lua/gtd
# Update all requires
```

### Phase 5: Add Documentation

For each plugin:
- [ ] Write `doc/plugin-name.txt` for `:help`
- [ ] Update README with badges, screenshots
- [ ] Add CHANGELOG.md
- [ ] Add CONTRIBUTING.md

### Phase 6: Testing

```bash
# Test fresh install
cd /tmp
git clone ~/projects/nvim-gtd test-gtd
nvim --cmd "set rtp+=test-gtd" -c ":checkhealth gtd"
```


## Pre-Release Checklist

### Code Quality

- [ ] All `require()` paths use correct plugin namespace
- [ ] No hardcoded personal paths (`/Users/plague/`)
- [ ] No hardcoded personal emails
- [ ] No API keys, tokens, or secrets
- [ ] No `.gpg` or sensitive files
- [ ] All `M.cfg` changed to `M.config`
- [ ] Development comment headers removed
- [ ] Backup files excluded (*.bak, *~, *.lua-)

### Plugin Structure

- [ ] `lua/plugin-name/init.lua` exists with `setup()`
- [ ] `plugin/plugin-name.lua` exists with commands
- [ ] `doc/plugin-name.txt` exists with help
- [ ] `README.md` is comprehensive
- [ ] `LICENSE` file exists
- [ ] `.gitignore` excludes dev files

### Functionality

- [ ] `:checkhealth plugin-name` works
- [ ] All user commands work
- [ ] Fresh install works (no pre-existing state)
- [ ] Config validation works
- [ ] Error messages are helpful

### Documentation

- [ ] Installation instructions (lazy.nvim, packer, manual)
- [ ] Configuration options documented
- [ ] All commands documented
- [ ] Example keymaps provided
- [ ] Screenshots/demos if applicable

### GitHub

- [ ] Repository is public
- [ ] Topics/tags added (neovim, lua, gtd, etc.)
- [ ] Description filled in
- [ ] Release created with tag (v1.0.0)

## File Size Analysis

Current line counts (largest files):

| File | Lines | Notes |
|------|-------|-------|
| `gtd/projects.lua` | ~1100 | Could split into project CRUD + project UI |
| `gtd/manage.lua` | ~1100 | Task management |
| `gtd/capture.lua` | ~970 | Capture workflows |
| `gtd/lists.lua` | ~900 | List views |
| `gtd/clarify.lua` | ~900 | Inbox processing |
| `gtd/organize.lua` | ~800 | Refile operations |
| `utils/link_insert.lua` | ~490 | Link utilities |
| `gtd/calendar.lua` | ~750 | Calendar (optional) |
| `gtd/reminders.lua` | ~750 | macOS reminders (optional) |

**Recommendation:** Files over 500 lines should be considered for splitting.

## Integration Between Plugins

If GTD and Zettelkasten are separate, they can still integrate:

```lua
-- In nvim-gtd setup
require("gtd").setup({
  integrations = {
    zettelkasten = {
      enabled = true,
      on_capture = function(task)
        -- Optionally create a linked note
        local zk = require("zettelkasten")
        if zk and task.create_note then
          zk.new_note({ title = task.title, link_to = task.id })
        end
      end,
    },
  },
})
```

## Summary

**Current state:** Working but monolithic, has minor issues with require paths.

**Recommendation:**
1. Fix require paths in current repo (quick win)
2. Keep as monolith for now if it works for you
3. Extract to separate plugins when ready to publish publicly
4. Start with GTD plugin, then Zettelkasten, then Writing

**Priority order:**
1. 🔧 Fix require paths (breaks as standalone plugin)
2. 🧹 Clean up personal data remnants
3. 📝 Add vim help documentation
4. 🎨 Screenshots/demo GIFs for README
5. 🔀 Split plugins (if desired)

---

*Analysis generated: 2024-12-07*
*For: /Users/plague/projects/gtd-nvim*
