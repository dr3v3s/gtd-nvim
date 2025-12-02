# GTD-Nvim Workflow Guide

A complete guide to using GTD-Nvim for terminal-based productivity. This document walks you through the entire Getting Things Done workflow, from capturing your first item to completing your weekly review.

## Table of Contents

1. [Quick Start](#quick-start)
2. [The GTD Workflow](#the-gtd-workflow)
3. [Daily Workflow](#daily-workflow)
4. [Weekly Review](#weekly-review)
5. [Zettelkasten Integration](#zettelkasten-integration)
6. [Advanced Tips](#advanced-tips)

---

## Quick Start

### First Time Setup

After installing GTD-Nvim, create your GTD directories:

```bash
mkdir -p ~/.gtd
mkdir -p ~/Documents/Notes
```

### Essential Keybindings

Add these to your Neovim config for the optimal workflow:

```lua
local gtd = require("gtd-nvim.gtd")
local zk = require("gtd-nvim.zettelkasten")

-- GTD Capture & Process
vim.keymap.set("n", "<leader>cc", gtd.capture.capture, { desc = "GTD: Quick Capture" })
vim.keymap.set("n", "<leader>clt", gtd.clarify.process_inbox, { desc = "GTD: Process Inbox" })

-- GTD Lists
vim.keymap.set("n", "<leader>cln", gtd.lists.show_next_actions, { desc = "GTD: Next Actions" })
vim.keymap.set("n", "<leader>clw", gtd.lists.show_waiting_for, { desc = "GTD: Waiting For" })
vim.keymap.set("n", "<leader>cls", gtd.lists.show_someday_maybe, { desc = "GTD: Someday/Maybe" })
vim.keymap.set("n", "<leader>clP", gtd.projects.show_projects, { desc = "GTD: Projects" })

-- GTD Manage
vim.keymap.set("n", "<leader>cmt", gtd.manage.manage_tasks, { desc = "GTD: Manage All" })
vim.keymap.set("n", "<leader>cr", gtd.organize.organize, { desc = "GTD: Organize" })

-- Zettelkasten
vim.keymap.set("n", "<leader>zn", zk.new_note, { desc = "Zettel: New Note" })
vim.keymap.set("n", "<leader>zf", zk.find_notes, { desc = "Zettel: Find Note" })
vim.keymap.set("n", "<leader>zi", require("gtd-nvim.utils.link_insert").insert_link, { desc = "Insert Link" })
vim.keymap.set("n", "gx", require("gtd-nvim.utils.link_open").open_link, { desc = "Open Link" })
```

---

## The GTD Workflow

GTD-Nvim implements David Allen's five-step methodology:

### 1. 📥 CAPTURE

**Goal:** Get everything out of your head and into your inbox.

**When to use:** Throughout the day, whenever something crosses your mind.

**How to capture:**

```
<leader>cc  # Open capture interface
```

**What to capture:**
- Tasks you need to do
- Ideas you want to explore
- Information you need to remember
- Commitments you've made
- Things that are bothering you

**Examples:**
```
- Call dentist about appointment
- Research Lua metaprogramming
- Buy birthday gift for Sarah
- Review Q4 budget proposal
- Why does the deploy script fail on Fridays?
```

**Pro tip:** Capture FAST. Don't organize yet - that comes later. Just get it out of your head.

---

### 2. 🤔 CLARIFY

**Goal:** Process each inbox item and decide what it means and what to do about it.

**When to use:** Daily (preferably end of day or start of next day)

**How to process:**

```
<leader>clt  # Start processing inbox
```

**The Clarify Questions:**

For each item, ask:

1. **Is it actionable?**
   - **NO** → 
     - Trash it (delete)
     - File it as reference
     - Put it in Someday/Maybe
   
   - **YES** → Continue...

2. **What's the next action?**
   - Be specific: "Call John" not "John"
   - Make it physical: "Draft email to..." not "Email about..."

3. **Will it take less than 2 minutes?**
   - **YES** → Do it NOW
   - **NO** → Continue...

4. **Is it a single action or multiple steps?**
   - **Single** → Add to Next Actions
   - **Multiple** → Create a Project

5. **Should someone else do it?**
   - **YES** → Add to Waiting For (with who and when)
   - **NO** → Add to Next Actions

**Clarify Interface:**

When you press `<leader>clt`, you'll see each inbox item with options:

```
Actions:
- [N]ext Action    - Single-step task you can do now
- [P]roject        - Multi-step outcome (creates project + first action)
- [W]aiting For    - Delegated to someone else
- [S]omeday/Maybe  - Not now, but maybe later
- [R]eference      - Just information to keep
- [D]elete         - Trash it
```

**Example Clarify Session:**

```
Inbox: "Website is slow"
→ Ask: Is this actionable? YES
→ Ask: Next action? "Profile database queries in production"
→ Ask: <2min? NO
→ Ask: Single action? NO (need to profile, analyze, fix, test)
→ Create Project: "Fix website performance"
→ First Action: "Profile database queries with pgBadger"
```

---

### 3. 🗂️ ORGANIZE

**Goal:** Put everything in its proper place with proper context.

**When to use:** As part of clarifying, or when reviewing your system

**How to organize:**

```
<leader>cr  # Open organize interface
```

**Organization Categories:**

**Contexts** - Where or with what can you do this?
- `@computer` - Need a computer
- `@home` - Must be at home
- `@phone` - Phone calls
- `@errands` - Out and about
- `@office` - Need to be at the office
- `@online` - Need internet
- `@email` - Email-based tasks

**Tags** - Additional metadata
- `#urgent` - Needs immediate attention
- `#important` - High priority
- `#quick` - 15 minutes or less
- `#deep` - Requires focus time
- `#waiting` - Blocked by something

**Energy Levels** - How much mental energy required?
- `energy:high` - Complex, creative work
- `energy:medium` - Standard tasks
- `energy:low` - Mindless tasks for when you're tired

**Time Estimates**
- `15m`, `30m`, `1h`, `2h` - How long will it take?

**Example Organization:**

```
Task: "Draft blog post about GTD-Nvim"
Context: @computer
Tags: #deep #writing
Energy: high
Time: 2h
Scheduled: 2024-10-25 (Friday morning - deep work block)
```

---

### 4. 🔍 REFLECT

**Goal:** Review your system regularly to keep it trusted and current.

**Daily Review** (5-10 minutes)
```
<leader>cln  # Review Next Actions
<leader>cc  # Capture today's open loops
<leader>clt  # Process new inbox items
```

**Weekly Review** (30-60 minutes) - See [Weekly Review](#weekly-review) section

---

### 5. ⚡ ENGAGE

**Goal:** Do the work! Choose and execute tasks with confidence.

**When to use:** Throughout your day, when you have time to work

**How to engage:**

```
<leader>cln  # See all Next Actions
```

**Choosing What To Do:**

Ask yourself:
1. **Context** - Where am I? What tools do I have?
2. **Time** - How much time do I have available?
3. **Energy** - How mentally fresh am I?
4. **Priority** - What's most important right now?

**Example Engagement:**

```
Situation: At computer, 30 minutes before meeting, medium energy

Filter your list:
- Context: @computer ✓
- Time: ≤30 minutes ✓  
- Energy: medium ✓

Choose from filtered list:
- "Review PR#142" (15m, medium energy)
- "Reply to 3 emails" (20m, low energy)
- "Update documentation" (30m, medium energy)

Pick: "Review PR#142" - good fit for time and energy!
```

---

## Daily Workflow

### Morning Routine (10 minutes)

```bash
# 1. Open Neovim
nvim

# 2. Review what's on deck
<leader>cln    # Check Next Actions

# 3. Check calendar/appointments
# (Integration with your calendar app)

# 4. Capture overnight thoughts
<leader>cc    # Anything from yesterday evening?

# 5. Pick your "MIT" (Most Important Task) for today
# Flag it or move it to top of list
```

### During the Day

**Capture mode:** Always on
```
Something crosses your mind → <leader>cc → Dump it → Back to work
```

**Quick checks** (Between meetings/tasks):
```
<leader>cln    # Quick scan of Next Actions
              # Pick next task based on context/time/energy
```

### Evening Routine (15 minutes)

```bash
# 1. Brain dump
<leader>cc    # Capture everything still in your head

# 2. Process inbox
<leader>clt    # Clarify today's captures

# 3. Review tomorrow
<leader>cln    # Scan for tomorrow's tasks

# 4. Plan morning
# Pick 3 MITs for tomorrow

# 5. Close loops
<leader>clw    # Check Waiting For - any follow-ups needed?
```

---

## Weekly Review

**When:** Every Friday afternoon or Sunday evening  
**Duration:** 30-60 minutes  
**Goal:** Get current, clear, creative, and confident

### The Weekly Review Checklist

#### 1. GET CLEAR (15 min)

```bash
# Empty your head
<leader>cc    # Capture EVERYTHING bothering you

# Empty your inbox
<leader>clt    # Process every item to zero

# Empty your notes
<leader>zf    # Review zettelkasten notes for action items
```


#### 2. GET CURRENT (20 min)

```bash
# Review Next Actions
<leader>cln    # Mark completed items DONE
              # Delete obsolete items
              # Update stale items

# Review Projects
<leader>clP    # For each project:
              # - Is the next action still correct?
              # - Has progress been made?
              # - Is it still active?

# Review Waiting For
<leader>clw    # For each item:
              # - Has it been too long? Follow up?
              # - Can I close this loop?
              # - Still waiting or time to act?

# Review Someday/Maybe
<leader>cls    # Anything ready to activate?
              # Anything to delete?
```

#### 3. GET CREATIVE (10 min)

```bash
# Review Goals & Vision
# - What are my current goals?
# - What projects support these goals?
# - What new projects should I start?

# Brainstorm New Projects
<leader>cc    # Capture ideas for:
              # - Things you want to learn
              # - Things you want to create
              # - Things you want to improve

# Review Zettelkasten
<leader>zf    # Browse your notes
              # - Discover connections
              # - Find dormant ideas
              # - Spot patterns
```

#### 4. GET COMFORTABLE (5 min)

```bash
# Organize your environment
# - Clean desk (physical/digital)
# - Update contexts if needed
# - Adjust tags/priorities

# Plan next week
# - What are the 3-5 key outcomes?
# - Block time for deep work
# - Schedule the next review
```

**Weekly Review Outcome:**  
You should feel: Current, Clear, Confident, and ready for the week ahead.

---

## Zettelkasten Integration

GTD-Nvim integrates seamlessly with Zettelkasten for knowledge management.

### When to Create Notes

**During Capture:**
```
Capturing: "Research Lua coroutines"
→ Create Zettel note immediately
→ Link it to the task in GTD
```

**During Projects:**
```
Working on: "Blog post about Docker"
→ Create notes as you research
→ Link notes together
→ Reference from project
```

**During Reviews:**
```
Reviewing: Someday/Maybe list
→ Spot interesting topic
→ Create exploratory note
→ Link to Someday item
```

### Zettelkasten Workflow

#### Creating a New Note

```
<leader>zn    # New note
              # Title: "Lua Coroutines Overview"
              # Automatically gets timestamp ID: 202410241530
              # Opens in Neovim for editing
```

#### Note Structure

```markdown
---
title: Lua Coroutines Overview
created: 2024-10-24 15:30
tags: #lua #concurrency #programming
---

# Lua Coroutines Overview

Coroutines in Lua are collaborative multitasking...

## Key Concepts

- [[202410241520-lua-basics]] - Foundation
- [[202410241535-coroutine-yield]] - How yield works

## Questions

- How do coroutines compare to async/await?
- When should I use coroutines vs threads?

## Tasks

- TODO: Write example coroutine script
  - ID:: [[gtd:20241024153045]]
```

#### Linking Notes

```
<leader>zi    # Insert link
              # Fuzzy find note
              # Creates: [[202410241530-lua-coroutines-overview]]
```

#### Finding Notes

```
<leader>zf    # Fuzzy find all notes
              # Search by title, content, tags
```

#### Opening Links

```
gx            # On a link → opens the linked file
              # On a URL → opens in browser
              # On mailto → opens email client
```

### GTD ↔ Zettelkasten Bridges

**From GTD to Zettel:**
```
In a GTD task:
"Research topic X"
→ Add note reference: NOTE:: [[202410241530-topic-x-research]]
→ Link connects task to knowledge
```

**From Zettel to GTD:**
```
In a note:
"This needs action!"
→ Add task reference: TASK:: [[gtd:20241024153045]]
→ Link connects knowledge to action
```

**Bidirectional Flow:**
```
GTD: Capture → Process → Action
     ↓           ↑
Zettel: Learn → Connect → Discover
```

---

## Advanced Tips

### Power User Shortcuts

#### Quick Capture from Terminal

Add to your `.zshrc`:

```bash
# Quick capture without opening full Neovim
gtd-quick() {
    echo "* TODO $*" >> ~/.gtd/Inbox.org
    echo "✓ Captured: $*"
}

# Usage: gtd-quick "Call dentist"
```

#### Context-Based Lists

Create custom list commands:

```lua
-- Show only @home tasks
vim.keymap.set("n", "<leader>ch", function()
  require("gtd-nvim.gtd.lists").show_by_context("@home")
end, { desc = "GTD: Home Tasks" })

-- Show only quick tasks
vim.keymap.set("n", "<leader>cq", function()
  require("gtd-nvim.gtd.lists").show_by_tag("#quick")
end, { desc = "GTD: Quick Tasks" })
```

#### Energy-Based Working


Match tasks to your current energy level:

```bash
# High energy (morning, post-coffee)
<leader>cln → Filter: energy:high
# Deep work, creative tasks, complex problem-solving

# Medium energy (mid-day)
<leader>cln → Filter: energy:medium
# Meetings, code reviews, documentation

# Low energy (post-lunch, evening)
<leader>cln → Filter: energy:low
# Email, admin tasks, organizing
```

### Batch Processing

Process similar tasks together:

```bash
# Email batch (every few hours)
<leader>cln → Filter: @email
# Process all emails at once

# Phone calls batch (twice daily)
<leader>cln → Filter: @phone
# Make all calls in one session

# Errands batch (weekly)  
<leader>cln → Filter: @errands
# Plan efficient route
```

### Project Templates

Create templates for recurring project types:

```bash
# In ~/Documents/Notes/Templates/

# project-template-blog-post.md
---
title: [Blog Post Title]
project-type: blog
---

## Tasks
- [ ] Research topic
- [ ] Outline post
- [ ] Write first draft
- [ ] Edit and refine
- [ ] Create graphics
- [ ] Publish
- [ ] Promote on social

## Notes
[Links to zettelkasten notes]

## Resources
[Links to references]
```

### Integration with Other Tools

#### tmux Integration

Add to your `tmux.conf`:

```bash
# Quick GTD capture from anywhere
bind-key C-g run-shell "tmux popup -E 'nvim -c \"lua require('gtd-nvim.gtd.capture').capture()\"'"

# Quick Next Actions view
bind-key C-n run-shell "tmux popup -E 'nvim -c \"lua require('gtd-nvim.gtd.lists').show_next_actions()\"'"
```

#### Calendar Integration

Sync your GTD scheduled items with calendar:

```bash
# Export scheduled items to iCal
# (Future feature - or build your own!)
```

#### Git Integration

Track your productivity:

```bash
# Add to post-commit hook
#!/bin/bash
# After each commit, capture completed work
echo "* DONE Committed: $(git log -1 --pretty=%B)" >> ~/.gtd/Inbox.org
```

### Maintenance Tips

#### Keep Your System Lean

**Weekly:**
- Archive completed projects
- Delete obsolete Someday/Maybe items
- Update stale next actions

**Monthly:**
- Review and prune tags
- Clean up zettelkasten orphan notes
- Reassess active projects (close inactive ones)

**Quarterly:**
- Big picture review
- Align projects with goals
- Update contexts if life changed

#### Avoid Common Pitfalls

**❌ Don't:**
- Make your system too complex
- Skip the weekly review
- Let your inbox grow to 50+ items
- Create vague next actions ("Deal with X")
- Organize before you clarify

**✓ Do:**
- Keep next actions specific and physical
- Trust your system (don't keep backup lists)
- Process inbox to zero regularly
- Make 2-minute actions immediately
- Review at least weekly

### Customization Examples

#### Custom Status States

Extend beyond TODO/DONE:

```lua
-- In your config
require("gtd-nvim").setup({
  custom_states = {
    "TODO",      -- Not started
    "NEXT",      -- Priority action
    "STARTED",   -- In progress
    "WAITING",   -- Blocked
    "REVIEW",    -- Needs review
    "DONE",      -- Complete
    "CANCELLED"  -- Abandoned
  }
})
```

#### Custom Contexts

Match your actual life:

```
@home-office     # Work from home setup
@couch          # Relaxed environment
@workshop       # Maker space / garage
@coffee-shop    # Public workspace
@commute        # Train/bus time
@waiting-room   # Anywhere you wait
```

#### Custom Tags for Your Domain

**For Developers:**
```
#bug #feature #refactor #documentation #review #deploy
```

**For Writers:**
```
#research #outline #draft #edit #publish #promote
```

**For Students:**
```
#reading #homework #study #project #exam #paper
```

---

## Best Practices

### The 2-Minute Rule

If something takes less than 2 minutes, **do it immediately** during processing:

```
Inbox: "Reply to John's email"
→ Takes 1 minute → Do it NOW
→ Don't add to Next Actions
```

### The Weekly Review is Sacred

**Block time for your weekly review:**
- Same time every week
- Undistracted environment  
- Turn off notifications
- Treat it like an important meeting with yourself

### One System to Rule Them All

Don't keep multiple systems:
- No backup paper lists
- No "just in case" spreadsheets
- No parallel todo apps

Trust your GTD system or fix it.

### Make Next Actions Visible

The next action should be:
- **Physical:** "Draft email" not "Email"
- **Specific:** "Call John re: budget" not "John"
- **Doable:** "Outline chapter 3" not "Write book"

### Start Small

Don't try to capture your entire life on day one:

**Week 1:** Just capture and process
**Week 2:** Add contexts
**Week 3:** Add energy levels
**Week 4:** Add time estimates
**Week 5:** Start weekly reviews

---

## Troubleshooting

### "My inbox is overwhelming!"


**Solution:**
1. Block 2 hours uninterrupted time
2. Process ruthlessly - be willing to delete/trash
3. Use the "Someday/Maybe" liberally for the maybes
4. Remember: You can't do everything. Choose what matters.

### "I never do my weekly review"

**Solution:**
1. Make it smaller - start with 15 minutes
2. Schedule it like a meeting
3. Link it to something you already do (Friday lunch, Sunday coffee)
4. Track your streak - don't break the chain
5. Remember: The weekly review IS the system

### "I have too many Next Actions"

**Solution:**
1. Move some to Someday/Maybe
2. Delete the ones you'll never actually do
3. Convert some into projects (maybe they're too big)
4. Be honest: Are these really "next actions" or wishes?

### "I forget to capture things"

**Solution:**
1. Make capturing easier - faster keybinding
2. Set up capture shortcuts everywhere (tmux, terminal, etc)
3. Capture in batches at transition times (end of meetings, etc)
4. Use the evening routine as a "sweep" for missed items

### "My lists are stale"

**Solution:**
1. Do your weekly review!
2. Mark DONE items as done during the week
3. Delete obsolete items immediately when you spot them
4. If something sits for weeks, move it to Someday/Maybe

---

## Real-World Examples

### Example 1: Software Developer

**Morning:**
```bash
8:00 AM  - <leader>cln → @computer energy:high
         → Pick: "Refactor authentication module" (2h, deep work)

10:00 AM - <leader>cln → @computer energy:medium
         → Pick: "Review 3 PRs" (30m each)

11:30 AM - <leader>cc → Capture: "Investigate slow query in reports"
```

**Throughout day:**
- Every time you think "I should..." → Capture it
- Between tasks → Quick scan of Next Actions
- Random idea? → New Zettelkasten note

**Evening:**
```bash
5:00 PM  - <leader>cc → Brain dump
5:10 PM  - <leader>clt → Process 8 inbox items
5:20 PM  - <leader>clw → Follow up on "Waiting for design mockups"
5:25 PM  - Tomorrow's MITs identified → Done for the day
```

### Example 2: Content Creator

**Weekly Review (Sunday):**
```bash
1. Review analytics → Capture insights
2. Check Someday/Maybe → 3 ideas promoted to active
3. Review active projects:
   - Blog post series (4/10 done)
   - YouTube video (script ready)
   - Podcast prep (needs scheduling)
4. Next week's focus: Finish blog series
```

**Daily:**
```bash
Morning:   Research + write (energy:high work)
Midday:    Edit + graphics (energy:medium)
Evening:   Social media + email (energy:low)
```

### Example 3: Student

**Before exam period:**
```bash
# Create project
<leader>cc → "Final Exams - Spring 2024"

# Break into subjects
- Physics exam (May 15)
  - Review chapters 1-8
  - Practice problems
  - Study group session
  
- Math exam (May 18)  
  - Calculus review
  - Past papers
  - Office hours questions
```

**Use Zettelkasten:**
```bash
# Study notes become Zettel notes
<leader>zn → "Newton's Laws of Motion"
<leader>zn → "Derivatives - Chain Rule"

# Link concepts together
# Review by browsing linked notes
```

---

## Keyboard-First Workflow

GTD-Nvim is designed for keyboard warriors. Here's a complete keyboard-only workflow:

```bash
# Open Neovim
nvim

# Capture (no mouse)
<leader>cc
[type your thought]
<CR> (enter) to save

# Process (all keyboard)
<leader>clt
[see item]
n (next action)
[type action]
@computer #quick (add context/tags)
<CR> (save)

# Review (fuzzy find)
<leader>cln
[type to filter]
<CR> to open
gx to open links
:q to close

# Create note (seamless)
<leader>zn
[title]
[write]
<leader>zi (insert link to other note)
```

**No mouse required. Ever.**

---

## Philosophy

### Why Plain Text?

- **Portable:** Works everywhere, survives technology changes
- **Searchable:** grep, ripgrep, any tool works
- **Version-controllable:** Git tracks every change
- **Future-proof:** You'll be able to read it in 20 years
- **Fast:** Text is instant, no loading, no databases

### Why Terminal-Based?

- **Always available:** Where you already work
- **Keyboard-driven:** Fast, efficient, flow-friendly
- **Distraction-free:** No notifications, no chrome, just work
- **Composable:** Integrates with all your tools (tmux, git, etc)
- **Yours:** Complete control and customization

### Why GTD + Zettelkasten?

**GTD** = What needs to be DONE  
**Zettelkasten** = What needs to be KNOWN

Together = **Thinking + Doing** in one system

---

## Next Steps

### Getting Started

1. **Install** - Follow [README.md](README.md)
2. **Configure** - Set up keybindings above
3. **Capture** - Spend 1 day just capturing everything
4. **Process** - Spend 1 hour processing your captures
5. **Do** - Start working from your lists
6. **Review** - Schedule your first weekly review

### Going Deeper

- Read "Getting Things Done" by David Allen
- Read "How to Take Smart Notes" by Sönke Ahrens
- Experiment with contexts that match YOUR life
- Build your Zettelkasten over time
- Make the system yours

### Community

- Share your workflow adaptations
- Contribute improvements to GTD-Nvim
- Help others get started
- Build plugins and integrations

---

## Quick Reference Card

### Essential Commands

```
CAPTURE
<leader>cc    Quick capture

PROCESS
<leader>clt    Process inbox

LISTS  
<leader>cln    Next Actions
<leader>clw    Waiting For
<leader>cls    Someday/Maybe
<leader>clP    Projects

MANAGE
<leader>cmt    Manage all tasks
<leader>cr    Organize tasks

ZETTELKASTEN
<leader>zn    New note
<leader>zf    Find note
<leader>zi    Insert link
gx            Open link
```

### The GTD Questions

1. Is it actionable?
2. What's the next physical action?
3. Will it take less than 2 minutes?
4. Am I the one to do it?
5. Is it one action or a project?

### The Weekly Review

1. GET CLEAR - Empty inbox, capture loops
2. GET CURRENT - Review all lists, update items
3. GET CREATIVE - Brainstorm, review someday/maybe
4. GET COMFORTABLE - Plan next week, organize

---

**Remember:** The best GTD system is the one you actually use. Start simple. Build habits. Trust the process.

Happy capturing! 🚀📝✨
