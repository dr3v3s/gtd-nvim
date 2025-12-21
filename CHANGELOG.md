# Changelog

All notable changes to gtd-nvim are documented in this file.

## [0.13.1] - 2025-12-21

### Added
- **Area capture destination** in task wizard
  - New "Area..." option in destination picker
  - Captures to `{area}/Inbox.org` as standalone area task
  - Area property automatically set

- **Area management** in Areas picker
  - `Ctrl-N` - Create new area (prompts for number + name)
  - `Ctrl-A` - Archive area with timestamp preservation
  - Archives to `Archive/Areas/{area-id}_{timestamp}/`
  - Multiple archives of same area preserved

### Changed
- Task destination picker height increased for new option

## [0.13.0] - 2025-12-21

### Added
- **Areas of Responsibility picker** (`<leader>xoa`)
  - `M.areas()` - Get all areas from daemon
  - `M.area_info(area_id)` - Get single area details
  - `M.pick_areas()` - fzf picker with actions
  - Display shows project count and task statistics
  - `:ChronosAreas` command

- **Areas picker actions**
  - `Enter` - Open `_AREA.md` definition
  - `Ctrl-P` - Show projects in area
  - `Ctrl-T` - Show all tasks in area
  - `Ctrl-R` - Area review dashboard with statistics

## [0.12.3] - 2025-12-21

### Fixed
- **Picker refresh timing** after file modifications
  - Increased delay to 250ms (50ms + 200ms) for daemon re-indexing
  - Fixed stale data appearing after toggle/archive operations
  - Applied to all pickers: tasks, archive, projects

## [0.12.2] - 2025-12-21

### Added
- **ON_HOLD toggle** for projects
  - `toggle_on_hold()` function
  - `Ctrl-H` in project pickers
  - On-hold projects excluded from active view
  - Visual indicator: ⏸

### Changed
- Project picker header updated: "^O:ongoing ^H:hold"

## [0.12.1] - 2025-12-21

### Added
- **ONGOING toggle** for projects
  - `toggle_ongoing()` function
  - `Ctrl-O` in project pickers
  - Ongoing areas excluded from active project picker
  - Visual indicator: 󰑖

## [0.12.0] - 2025-12-21

### Added
- **Project pickers with daemon integration**
  - `M.pick_projects()` - Active projects only
  - `M.pick_all_projects()` - All projects in sorted sections
  - Sections: Active → On Hold → Ongoing → Reminders
  - `:ChronosProjects` and `:ChronosAllProjects` commands

- **Project info from daemon**
  - `M.projects_info()` - Get all projects with timeline
  - `M.project_info(project_id)` - Get single project details
  - Timeline display in project picker

### Changed
- Keymap prefix optimized from `<leader>C` to `<leader>x`

## [0.11.0] - 2025-12-20

### Added
- **Project creation wizard**
  - Multi-step guided project creation
  - Area selection (or standalone)
  - Outcome and first action prompts
  - ZK note linking option
  - Active vs Ongoing type selection

### Changed
- Capture glyphs consolidated

## [0.10.0] - 2025-12-20

### Added
- **Full capture wizard**
  - State selection (NEXT/TODO/WAITING/SOMEDAY)
  - Destination selection (Inbox/Project)
  - Date entry with smart parsing (+1d, +2w, +3m)
  - Tag entry

- **Quick capture** for brain dumps

## [0.9.0] - 2025-12-19

### Added
- **Task pickers** with fzf-lua
  - Filter by state
  - Open file at task line
  - State cycling
  - Delete and archive actions

## [0.8.0] - 2025-12-19

### Added
- **Chronos daemon integration**
  - Unix socket communication
  - JSON protocol queries
  - Real-time metrics

## [0.1.0 - 0.7.0] - Earlier

- Initial GTD implementation
- Audit system
- Review workflows
- Refile operations
