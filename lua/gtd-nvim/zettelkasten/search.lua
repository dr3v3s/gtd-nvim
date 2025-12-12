-- ============================================================================
-- ZETTELKASTEN SEARCH MODULE
-- ============================================================================
-- Find, search, browse, and navigate notes
--
-- @module gtd-nvim.zettelkasten.search
-- @version 2.0.0
-- @requires gtd-nvim.zettelkasten.core
-- ============================================================================

local M = {}

local core = require("gtd-nvim.zettelkasten.core")
local cfg = core.cfg
local g = core.glyphs

-- ============================================================================
-- FIND NOTES (file picker)
-- ============================================================================

function M.find_notes()
  local fzf = core.have_fzf()

  if fzf then
    local notes = core.get_all_notes()

    -- Build display items
    local items = {}
    local meta = {}

    for _, note in ipairs(notes) do
      local display = core.format_note(note, { colored = true, show_dir = true })
      table.insert(items, display)
      table.insert(meta, note)
    end

    fzf.fzf_exec(items, {
      prompt = g.ui.brain .. " Notes> ",
      fzf_opts = {
        ["--ansi"] = true,
        ["--header"] = core.fzf_header({ preview = true, backlinks = true }),
      },
      actions = {
        ["default"] = function(selected)
          if selected and selected[1] then
            local idx = vim.fn.index(items, selected[1]) + 1
            local note = meta[idx]
            if note and note.path then
              vim.cmd("edit " .. vim.fn.fnameescape(note.path))
            end
          end
        end,
        ["ctrl-p"] = function(selected)
          if selected and selected[1] then
            local idx = vim.fn.index(items, selected[1]) + 1
            local note = meta[idx]
            if note and note.path then
              vim.cmd("vsplit " .. vim.fn.fnameescape(note.path))
            end
          end
        end,
        ["ctrl-b"] = function(selected)
          if selected and selected[1] then
            local idx = vim.fn.index(items, selected[1]) + 1
            local note = meta[idx]
            if note and note.path then
              M.show_backlinks(note.path)
            end
          end
        end,
      },
    })
  elseif core.have_telescope() then
    require("telescope.builtin").find_files({
      prompt_title = g.ui.brain .. " Notes",
      cwd = cfg.notes_dir,
      file_ignore_patterns = core.fd_excludes,
    })
  else
    core.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

-- ============================================================================
-- SEARCH NOTES (content grep)
-- ============================================================================

function M.search_notes()
  local fzf = core.have_fzf()

  if fzf then
    local rg_excludes = core.get_rg_excludes()

    fzf.live_grep({
      cwd = cfg.notes_dir,
      prompt = g.workflow.search .. " Search> ",
      file_icons = false,
      git_icons = false,
      rg_opts = table.concat(vim.list_extend({
        "--column",
        "--line-number",
        "--no-heading",
        "--color=always",
        "--smart-case",
        "--type", "md",
      }, rg_excludes), " "),
      fzf_opts = {
        ["--ansi"] = true,
        ["--header"] = "Search note contents",
      },
    })
  elseif core.have_telescope() then
    require("telescope.builtin").live_grep({
      prompt_title = g.workflow.search .. " Search Notes",
      cwd = cfg.notes_dir,
      additional_args = function()
        return vim.list_extend({ "--type", "md" }, core.get_rg_excludes())
      end,
    })
  else
    core.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

-- ============================================================================
-- SEARCH ALL (notes + GTD)
-- ============================================================================

function M.search_all()
  local fzf = core.have_fzf()
  if not fzf then
    core.notify("fzf-lua required for unified search", vim.log.levels.WARN)
    return
  end

  -- Build search directories
  local search_dirs = { cfg.notes_dir }
  if cfg.gtd_integration.enabled and core.is_dir(cfg.gtd_dir) then
    table.insert(search_dirs, cfg.gtd_dir)
  end

  -- Simple rg options - let fzf-lua handle most of it
  local rg_opts = "--column --line-number --no-heading --color=always --smart-case --type=md --type=org"
  
  -- Add simple excludes
  for _, pattern in ipairs(core.fd_excludes) do
    rg_opts = rg_opts .. " -g '!" .. pattern .. "'"
  end

  fzf.live_grep({
    prompt = g.workflow.search .. " All> ",
    search_dirs = search_dirs,
    rg_opts = rg_opts,
    file_icons = false,
    git_icons = false,
    fzf_opts = {
      ["--ansi"] = true,
      ["--header"] = " Notes & GTD │ Enter: Open │ C-v: VSplit",
      ["--info"] = "inline-right",
      ["--pointer"] = "▶",
    },
    actions = {
      ["default"] = require("fzf-lua").actions.file_edit,
      ["ctrl-v"] = require("fzf-lua").actions.file_vsplit,
      ["ctrl-s"] = require("fzf-lua").actions.file_split,
    },
  })
end

-- ============================================================================
-- RECENT NOTES
-- ============================================================================

function M.recent_notes()
  local fzf = core.have_fzf()

  if fzf then
    fzf.oldfiles({
      cwd = cfg.notes_dir,
      cwd_only = true,
      prompt = g.ui.clock .. " Recent> ",
      file_icons = false,
      git_icons = false,
      fzf_opts = {
        ["--ansi"] = true,
      },
    })
  elseif core.have_telescope() then
    require("telescope.builtin").oldfiles({
      prompt_title = g.ui.clock .. " Recent Notes",
      cwd = cfg.notes_dir,
      cwd_only = true,
    })
  else
    core.notify("Install fzf-lua or telescope.nvim", vim.log.levels.WARN)
  end
end

-- ============================================================================
-- BACKLINKS
-- ============================================================================

function M.show_backlinks(file_path)
  file_path = file_path or vim.fn.expand("%:p")
  local backlinks = core.get_backlinks(file_path)

  if #backlinks == 0 then
    core.notify(g.workflow.backlink .. " No backlinks found")
    return
  end

  local fzf = core.have_fzf()
  if not fzf then
    core.notify("fzf-lua required for backlinks", vim.log.levels.WARN)
    return
  end

  local items = {}
  local meta = {}

  for _, bl in ipairs(backlinks) do
    local glyph = core.colored_note_glyph(bl.note_type or "zettel")
    table.insert(items, glyph .. " " .. bl.rel_path)
    table.insert(meta, bl)
  end

  fzf.fzf_exec(items, {
    prompt = g.workflow.backlink .. " Backlinks> ",
    fzf_opts = { ["--ansi"] = true },
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local idx = vim.fn.index(items, selected[1]) + 1
          local bl = meta[idx]
          if bl and bl.file then
            vim.cmd("edit " .. vim.fn.fnameescape(bl.file))
          end
        end
      end,
    },
  })
end

-- ============================================================================
-- TAGS
-- ============================================================================

function M.browse_tags()
  local tag_map = core.get_all_tags()

  if not next(tag_map) then
    core.notify(g.workflow.tag .. " No tags found")
    return
  end

  local fzf = core.have_fzf()
  if not fzf then
    core.notify("fzf-lua required for tag browsing", vim.log.levels.WARN)
    return
  end

  local tags = {}
  for tag, files in pairs(tag_map) do
    local colored_tag = core.zk_colorize("#" .. tag, "tag")
    table.insert(tags, string.format("%s %s (%d)", g.workflow.tag, colored_tag, #files))
  end
  table.sort(tags)

  fzf.fzf_exec(tags, {
    prompt = g.workflow.tag .. " Tags> ",
    fzf_opts = { ["--ansi"] = true },
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local tag = core.strip_decor(selected[1]):match("#([%w_%-]+)")
          if tag then
            M.browse_files_by_tag(tag)
          end
        end
      end,
    },
  })
end

function M.browse_files_by_tag(tag)
  local tag_map = core.get_all_tags()
  local files = tag_map[tag] or {}

  if #files == 0 then
    core.notify("No files found for tag: #" .. tag)
    return
  end

  local fzf = core.have_fzf()
  if not fzf then return end

  local items = {}
  local meta = {}

  for _, file in ipairs(files) do
    local glyph = core.colored_note_glyph(file.note_type or "zettel")
    local display = file.rel_path or file.title
    if file.type == "gtd_task" then
      display = display .. " " .. core.zk_colorize("[GTD]", "muted")
    end
    table.insert(items, glyph .. " " .. display)
    table.insert(meta, file)
  end

  fzf.fzf_exec(items, {
    prompt = g.workflow.tag .. " #" .. tag .. "> ",
    fzf_opts = { ["--ansi"] = true },
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local idx = vim.fn.index(items, selected[1]) + 1
          local file = meta[idx]
          if file and file.path then
            vim.cmd("edit " .. vim.fn.fnameescape(file.path))
          end
        end
      end,
    },
  })
end

-- ============================================================================
-- STATISTICS
-- ============================================================================

function M.show_stats()
  local notes = core.get_all_notes()
  local tags = core.get_all_tags()

  -- Try to get GTD tasks if available
  local gtd_count = 0
  if cfg.gtd_integration.enabled then
    local ok, gtd = pcall(require, "gtd-nvim.zettelkasten.gtd")
    if ok and gtd.get_tasks then
      gtd_count = #(gtd.get_tasks() or {})
    end
  end

  local stats = {
    "# " .. g.ui.stats .. " Zettelkasten Statistics",
    "",
    string.format("**%s Total Notes:** %d", g.note.zettel, #notes),
    string.format("**%s Total Tags:** %d", g.workflow.tag, vim.tbl_count(tags)),
    string.format("**%s GTD Tasks:** %d", core.g.container.inbox, gtd_count),
    "",
    "**Directory Breakdown:**",
  }

  local dir_counts = {}
  for _, note in ipairs(notes) do
    local dir = note.dir ~= "" and note.dir or "Root"
    dir_counts[dir] = (dir_counts[dir] or 0) + 1
  end

  for dir, count in pairs(dir_counts) do
    local note_type = core.detect_note_type(dir .. "/")
    local glyph = g.note[note_type] or g.workflow.index
    table.insert(stats, string.format("- %s %s: %d", glyph, dir, count))
  end

  -- Display in floating window
  local cols, rows = vim.o.columns, vim.o.lines
  local w, h = math.max(50, math.floor(cols * 0.4)), #stats + 4
  local row, col = math.floor((rows - h) / 2), math.floor((cols - w) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, stats)
  vim.bo[buf].filetype = "markdown"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = w,
    height = h,
    style = "minimal",
    border = "rounded",
    title = " " .. g.ui.stats .. " Statistics ",
    title_pos = "center",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

return M
