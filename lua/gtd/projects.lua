-- ~/.config/nvim/lua/gtd/projects.lua
-- GTD Projects (Org) — create, open, search, ZK integration (fzf-lua)
-- - Prompts for Title, Description, Defer (SCHEDULED), Due (DEADLINE)
-- - Seeds :PROPERTIES: with ID, Effort, ASSIGNED, ZK_NOTE (and optional :DESCRIPTION:)
-- - fzf-lua pickers for projects & ZK links
-- - Open org [[file:...]] links under cursor
-- - Sync backlinks into the ZK note

local M = {}

-- ------------------------------------------------------------
-- Config
-- ------------------------------------------------------------
local cfg = {
  projects_dir     = "~/Documents/GTD/Projects",
  zk_project_root  = "~/Documents/Notes/Projects",
  default_effort   = "2:00",
  default_assigned = "",
}

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------
local function xp(p) return vim.fn.expand(p or "") end
local function ensure_dir(p) local e = xp(p); vim.fn.mkdir(e, "p"); return e end
local function file_exists(p) return vim.fn.filereadable(xp(p)) == 1 end
local function readfile(p) if not file_exists(p) then return {} end return vim.fn.readfile(xp(p)) end
local function writefile(p, L) ensure_dir(vim.fn.fnamemodify(xp(p), ":h")); vim.fn.writefile(L, xp(p)) end
local function have_fzf() return pcall(require, "fzf-lua") end

local function slugify(title)
  title = tostring(title or "")
  local s = title:gsub("[/%\\%:%*%?%\"%<%>%|]", "-")
  s = s:gsub("%s+", "-")
  s = s:gsub("^%-+", ""):gsub("%-+$", "")
  return (#s > 0) and s or ("project-" .. os.date("%Y%m%d%H%M%S"))
end

local function gen_id() return os.date("%Y%m%d%H%M%S") end

-- Small prompt helpers
local function input_nonempty(opts, cb)
  vim.ui.input(opts, function(s)
    if not s or s == "" then return end
    cb(s)
  end)
end

local function maybe_input(opts, cb)
  vim.ui.input(opts, function(s) cb(s or "") end)
end

local function valid_yyyy_mm_dd(s)
  if s == "" then return true end
  return s:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

-- ------------------------------------------------------------
-- ZK notes
-- ------------------------------------------------------------
local function zk_note_for_project(title, id)
  ensure_dir(cfg.zk_project_root)
  local fname = id .. "-" .. slugify(title) .. ".md"
  local path = xp(cfg.zk_project_root .. "/" .. fname)
  if not file_exists(path) then
    writefile(path, {
      "# " .. title,
      "",
      "**Dato:** " .. os.date("%Y-%m-%d %H:%M:%S"),
      "**ID:** " .. id,
      "",
      "## Beskrivelse",
      "",
      "## Indhold",
      "",
      "## Backlinks",
      "",
    })
  end
  return path
end

-- ------------------------------------------------------------
-- Org helpers
-- ------------------------------------------------------------
local function org_find_first_heading(lines)
  for i, ln in ipairs(lines) do
    if ln:match("^%*+%s") then return i end
  end
  return nil
end

local function org_subtree_range(lines, head_idx)
  local head = lines[head_idx]; if not head then return nil end
  local stars = head:match("^(%*+)%s"); if not stars then return nil end
  local lvl = #stars
  local i = head_idx + 1
  while i <= #lines do
    local s = lines[i]:match("^(%*+)%s")
    if s and #s <= lvl then break end
    i = i + 1
  end
  return head_idx, i - 1
end

local function find_properties_drawer(lines, start_idx, end_idx)
  start_idx = start_idx or 1
  end_idx = end_idx or #lines
  local s_i, e_i = nil, nil
  for i = start_idx, end_idx do
    if not s_i and lines[i]:match("^%s*:PROPERTIES:%s*$") then
      s_i = i
    elseif s_i and lines[i]:match("^%s*:END:%s*$") then
      e_i = i
      break
    end
  end
  return s_i, e_i
end

local function ensure_properties_drawer(lines, insert_at)
  local s_i, e_i = find_properties_drawer(lines)
  if s_i and e_i then return s_i, e_i end
  insert_at = insert_at or 2
  table.insert(lines, insert_at, ":PROPERTIES:")
  table.insert(lines, insert_at + 1, ":END:")
  return insert_at, insert_at + 1
end

local function upsert_property(lines, key, value)
  local head_idx = org_find_first_heading(lines) or 1
  local _, sub_e = org_subtree_range(lines, head_idx)
  local s_i, e_i = find_properties_drawer(lines, head_idx, sub_e or #lines)
  if not s_i then
    s_i, e_i = ensure_properties_drawer(lines, head_idx + 1)
  end
  local found = false
  for i = s_i + 1, e_i - 1 do
    local k = lines[i]:match("^%s*:(%w+):")
    if k and k:upper() == key:upper() then
      lines[i] = (":%s: %s"):format(key, value)
      found = true
      break
    end
  end
  if not found then
    table.insert(lines, e_i, (":%s: %s"):format(key, value))
  end
  return lines
end

local function get_property(lines, key)
  local s_i, e_i = find_properties_drawer(lines)
  if not s_i then return nil end
  for i = s_i + 1, e_i - 1 do
    local k, v = lines[i]:match("^%s*:(%w+):%s*(.*)%s*$")
    if k and k:upper() == key:upper() then return v end
  end
  return nil
end

-- ------------------------------------------------------------
-- Project template & creation
-- ------------------------------------------------------------
local function project_template(opts)
  local title     = opts.title
  local id        = opts.id
  local zk_path   = opts.zk_path
  local desc      = opts.description
  local scheduled = opts.scheduled  -- YYYY-MM-DD or ""
  local deadline  = opts.deadline   -- YYYY-MM-DD or ""

  local lines = {}
  table.insert(lines, "* PROJECT " .. title .. " [0/0]")

  if scheduled ~= "" then table.insert(lines, "SCHEDULED: <" .. scheduled .. ">") end
  if deadline  ~= "" then table.insert(lines, "DEADLINE:  <" .. deadline  .. ">") end

  table.insert(lines, ":PROPERTIES:")
  table.insert(lines, ":ID:        " .. id)
  table.insert(lines, ":Effort:    " .. cfg.default_effort)
  table.insert(lines, ":ASSIGNED:  " .. cfg.default_assigned)
  if zk_path and zk_path ~= "" then
    table.insert(lines, ":ZK_NOTE:   [[file:" .. zk_path .. "][" .. vim.fn.fnamemodify(zk_path, ":t") .. "]]")
  end
  if desc and desc ~= "" then
    table.insert(lines, ":DESCRIPTION: " .. desc)
  end
  table.insert(lines, ":END:")
  table.insert(lines, "")
  table.insert(lines, "** NEXT Første skridt")
  return lines
end

local function open_and_seed(file, lines)
  if not file_exists(file) then
    ensure_dir(vim.fn.fnamemodify(file, ":h"))
    writefile(file, lines or { "" })
  end
  vim.cmd("edit " .. file)
end

-- Public: create a new project (prompts for everything)
function M.create()
  input_nonempty({ prompt = "Project name: " }, function(title)
    local id = gen_id()

    -- Ask description (optional)
    maybe_input({ prompt = "Description (optional): " }, function(desc)
      -- Defer / Due with defaults (empty = skip)
      local today = os.date("%Y-%m-%d")
      local plus7 = os.date("%Y-%m-%d", os.time() + 7*24*3600)

      local scheduled = ""
      local deadline  = ""

      local function finalize()
        ensure_dir(cfg.projects_dir)
        local slug   = slugify(title)
        local file   = xp(cfg.projects_dir .. "/" .. slug .. ".org")
        local zkpath = zk_note_for_project(title, id) -- always create & link
        local lines  = project_template({
          title       = title,
          id          = id,
          zk_path     = zkpath,
          description = desc,
          scheduled   = scheduled,
          deadline    = deadline,
        })
        open_and_seed(file, lines)
        vim.notify("📂 Created project: " .. title, vim.log.levels.INFO)
      end

      -- Defer (SCHEDULED)
      maybe_input({ prompt = ("Defer (YYYY-MM-DD) [Enter=skip, e.g. %s]"):format(today) }, function(d1)
        if d1 ~= "" and not valid_yyyy_mm_dd(d1) then
          vim.notify("Invalid date, expected YYYY-MM-DD (defer skipped).", vim.log.levels.WARN)
          d1 = ""
        end
        scheduled = d1

        -- Due (DEADLINE)
        maybe_input({ prompt = ("Due   (YYYY-MM-DD) [Enter=skip, e.g. %s]"):format(plus7) }, function(d2)
          if d2 ~= "" and not valid_yyyy_mm_dd(d2) then
            vim.notify("Invalid date, expected YYYY-MM-DD (due skipped).", vim.log.levels.WARN)
            d2 = ""
          end
          deadline = d2
          finalize()
        end)
      end)
    end)
  end)
end

-- ------------------------------------------------------------
-- Browsing/search (FIXED fzf-lua navigation)
-- ------------------------------------------------------------
function M.open_project_dir()
  local root = xp(cfg.projects_dir)
  if have_fzf() then
    require("fzf-lua").files({ 
      cwd = root, 
      prompt = "Projects> ",
      fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    })
  else
    vim.cmd("edit " .. root)
  end
end

function M.find_files()
  local root = xp(cfg.projects_dir)
  if have_fzf() then
    require("fzf-lua").files({ 
      cwd = root, 
      prompt = "Projects> ",
      fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    })
  else
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
  end
end

function M.search()
  local root = xp(cfg.projects_dir)
  if have_fzf() then
    require("fzf-lua").live_grep({ 
      cwd = root, 
      prompt = "Projects> ",
      fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    })
  else
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
  end
end

-- ------------------------------------------------------------
-- Ensure metadata on current project file
-- ------------------------------------------------------------
function M.ensure_metadata_current()
  local path = xp("%:p")
  if not path:match("%.org$") then
    vim.notify("Not an org file.", vim.log.levels.WARN); return
  end
  local lines = readfile(path)
  if #lines == 0 then
    vim.notify("Empty file?", vim.log.levels.WARN); return
  end

  -- Determine project title from first heading
  local head_idx = org_find_first_heading(lines) or 1
  local head = lines[head_idx] or ""
  local title = head:gsub("^%*+%s+PROJECT%s+", "")
  if title == head then title = head:gsub("^%*+%s+", "") end
  if title == "" then title = vim.fn.fnamemodify(path, ":t:r") end

  local has_desc = get_property(lines, "DESCRIPTION") ~= nil
  local has_zk   = get_property(lines, "ZK_NOTE") ~= nil

  if has_desc or has_zk then
    vim.notify("Project metadata OK (DESCRIPTION or ZK_NOTE present).", vim.log.levels.INFO)
    return
  end

  -- Neither present → create ZK and link it
  local id = get_property(lines, "ID") or gen_id()
  local zkpath = zk_note_for_project(title, id)
  upsert_property(lines, "ID", id)
  upsert_property(lines, "ZK_NOTE",
    ("[[file:%s][%s]]"):format(zkpath, vim.fn.fnamemodify(zkpath, ":t")))
  writefile(path, lines)
  vim.notify("Added ZK_NOTE to project (no DESCRIPTION found).", vim.log.levels.INFO)
end

-- ------------------------------------------------------------
-- ZK links browser & backlink sync (FIXED fzf-lua navigation)
-- ------------------------------------------------------------
local function collect_zk_links_from_file(path)
  local res = {}
  local lines = readfile(path)
  local current_heading = nil
  for i = 1, #lines do
    local ln = lines[i]
    local h = ln:match("^%*+%s+(.*)")
    if h and h ~= "" then current_heading = h end

    local prop_link = ln:match(":ZK_NOTE:%s*%[%[file:(.-)%]%]")
    if prop_link and prop_link ~= "" then
      table.insert(res, { project = path, lnum = i, heading = current_heading or "(no heading)", zk_path = prop_link })
    end

    local body_link = ln:match("^%s*Notes:%s*%[%[file:(.-)%]%]")
    if body_link and body_link ~= "" then
      table.insert(res, { project = path, lnum = i, heading = current_heading or "(no heading)", zk_path = body_link })
    end
  end
  return res
end

local function gather_all_zk_links()
  local out = {}
  local root = xp(cfg.projects_dir)
  local files = vim.fn.glob(root .. "/*.org", false, true)
  for _, f in ipairs(files) do
    local list = collect_zk_links_from_file(f)
    for _, item in ipairs(list) do
      table.insert(out, item)
    end
  end
  return out
end

function M.list_zk_links()
  if not have_fzf() then
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
    return
  end
  
  local items = gather_all_zk_links()
  if #items == 0 then
    vim.notify("No ZK links found in project files.", vim.log.levels.INFO)
    return
  end

  local display = {}
  for _, it in ipairs(items) do
    local pfile = vim.fn.fnamemodify(it.project, ":t")
    local zfile = vim.fn.fnamemodify(it.zk_path, ":t")
    table.insert(display, pfile .. " │ " .. it.heading .. " │ " .. zfile)
  end

  local fzf = require("fzf-lua")
  fzf.fzf_exec(display, {
    prompt = "ZK Links> ",
    fzf_opts = { ["--no-info"] = true, ["--tiebreak"] = "index" },
    winopts = { height = 0.55, width = 0.80, row = 0.15 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local it = items[idx]
        if it and it.zk_path then vim.cmd("edit " .. xp(it.zk_path)) end
      end,
      ["ctrl-e"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local it = items[idx]
        if it then
          vim.cmd("edit " .. it.project)
          pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, 0 })
        end
      end,
      ["ctrl-s"] = function(sel)
        if not sel or not sel[1] then return end
        local idx = vim.fn.index(display, sel[1]) + 1
        local it = items[idx]
        if it and it.zk_path then vim.cmd("split " .. xp(it.zk_path)) end
      end,
    },
  })
end

-- Find ZK path for subtree at/above current cursor (in org)
local function zk_path_under_cursor(bufnr, lnum)
  bufnr = bufnr or 0
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Climb up to nearest heading
  local start = lnum
  while start > 1 do
    if lines[start]:match("^%*+%s+") then break end
    start = start - 1
  end

  -- Scan downward within this subtree for either :ZK_NOTE: or Notes: line
  local level = lines[start]:match("^(%*+)")
  local subtree_prefix = level and string.rep("%*", #level) or "%*"
  local i = start
  while i <= #lines do
    local ln = lines[i]
    if i > start and ln:match("^" .. subtree_prefix .. "%s") then break end
    local prop = ln:match(":ZK_NOTE:%s*%[%[file:(.-)%]%]")
    if prop and prop ~= "" then return prop, start end
    local body = ln:match("^%s*Notes:%s*%[%[file:(.-)%]%]")
    if body and body ~= "" then return body, start end
    i = i + 1
  end
  return nil, start
end

function M.open_zk_from_cursor()
  local path = xp("%:p")
  if not path:match("%.org$") then
    vim.notify("Not an org file.", vim.log.levels.WARN); return
  end
  local zk, _ = zk_path_under_cursor(0, nil)
  if zk then
    vim.cmd("edit " .. xp(zk))
  else
    vim.notify("No ZK link found in this subtree.", vim.log.levels.INFO)
  end
end

-- Backlink support
local function ensure_backlinks_section(lines)
  for i, ln in ipairs(lines) do
    if ln:match("^##%s*Backlinks") then return i end
  end
  table.insert(lines, "")
  table.insert(lines, "## Backlinks")
  table.insert(lines, "")
  return #lines
end

local function append_backlink(zk_path, project_path, heading)
  local lines = readfile(zk_path)
  local idx = ensure_backlinks_section(lines)
  local disp_proj = vim.fn.fnamemodify(project_path, ":t")
  local disp_head = heading or "(task)"
  local link = string.format("- [[file:%s::*%s][%s → %s]]", project_path, disp_head, disp_proj, disp_head)
  table.insert(lines, link)
  writefile(zk_path, lines)
end

function M.sync_backlink_under_cursor()
  local project_path = xp("%:p")
  if not project_path:match("%.org$") then
    vim.notify("Not an org project file.", vim.log.levels.WARN); return
  end

  local zk, head_start = zk_path_under_cursor(0, nil)
  if not zk then
    vim.notify("No ZK link found in this subtree.", vim.log.levels.INFO); return
  end

  local heading = "(task)"
  local ln = vim.api.nvim_buf_get_lines(0, head_start - 1, head_start, false)[1]
  local h = ln and ln:match("^%*+%s+(.*)") or nil
  if h and h ~= "" then heading = h end

  append_backlink(xp(zk), project_path, heading)
  vim.notify("🔗 Backlink appended to ZK note.", vim.log.levels.INFO)
end

-- ------------------------------------------------------------
-- Org [[file:...]] link opener
-- ------------------------------------------------------------
local function parse_org_file_link_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local s1, _, inner = line:find("%[%[(.-)%]%]")
  if not s1 then return nil end
  local target = inner:match("^file:([^%]]+)%]") or inner:match("^file:(.+)$")
  if not target or target == "" then return nil end
  return xp(target)
end

function M.open_link_under_cursor()
  local path = parse_org_file_link_at_cursor()
  if path then vim.cmd("edit " .. vim.fn.fnameescape(path))
  else vim.notify("No org [[file:...]] link on this line.", vim.log.levels.INFO) end
end

function M.split_link_under_cursor()
  local path = parse_org_file_link_at_cursor()
  if path then vim.cmd("split " .. vim.fn.fnameescape(path))
  else vim.notify("No org [[file:...]] link on this line.", vim.log.levels.INFO) end
end

function M.tab_link_under_cursor()
  local path = parse_org_file_link_at_cursor()
  if path then vim.cmd("tabedit " .. vim.fn.fnameescape(path))
  else vim.notify("No org [[file:...]] link on this line.", vim.log.levels.INFO) end
end

-- ------------------------------------------------------------
-- Setup
-- ------------------------------------------------------------
function M.setup(opts)
  cfg = vim.tbl_deep_extend("force", cfg, opts or {})
  ensure_dir(cfg.projects_dir)
  ensure_dir(cfg.zk_project_root)
end

return M