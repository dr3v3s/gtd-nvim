-- lua/gtd/scripts/migrate_task_ids.lua
-- Align :TASK_ID: with ZK IDs and ensure ID:: [[zk:ID]] breadcrumb.
local M = {}

local cfg = {
  base_dir = "~/Documents/GTD",
  include_top = true,
  depth_glob = "**/*.org",
  backup_extension = ".bak",
  insert_missing_zk_link = true,
}

local has_plenary, scandir = pcall(function() return require("plenary.scandir") end)
local task_id = require("gtd-nvim.gtd.utils.task_id")

local function xp(p) return vim.fn.expand(p) end
local function read_file(p) local ok, d = pcall(vim.fn.readfile, p); return ok and d or nil end
local function write_file(p, L) return vim.fn.writefile(L, p) == 0 end
local function backup_file(p)
  local ts = os.date("!%Y%m%d%H%M%S")
  local bak = p .. "." .. ts .. (cfg.backup_extension or ".bak")
  local lines = read_file(p); if not lines then return false, "read failed" end
  return write_file(bak, lines), bak
end

local function list_org_files()
  local base = xp(cfg.base_dir)
  local files = {}
  if has_plenary then
    for _, f in ipairs(scandir.scan_dir(base, { depth = 10, add_dirs = false })) do
      if f:match("%.org$") then table.insert(files, f) end
    end
  else
    if cfg.include_top then
      for _, f in ipairs(vim.fn.globpath(base, "*.org", false, true)) do table.insert(files, f) end
    end
    for _, f in ipairs(vim.fn.globpath(base, cfg.depth_glob, false, true)) do table.insert(files, f) end
  end
  table.sort(files)
  local seen, out = {}, {}
  for _, f in ipairs(files) do if not seen[f] then seen[f] = true; out[#out+1] = f end end
  return out
end

local function heading_level(line) local s = line:match("^(%*+)%s+") return s and #s or nil end
local function collect_tasks(lines)
  local tasks = {}
  for i = 1, #lines do
    local lvl = heading_level(lines[i])
    if lvl then
      local j = i + 1
      while j <= #lines do local lv2 = heading_level(lines[j]); if lv2 and lv2 <= lvl then break end; j = j + 1 end
      tasks[#tasks+1] = { start = i, finish = j - 1, level = lvl }
    end
  end
  return tasks
end

local function find_properties_block(lines, t_start, t_end)
  local i = t_start + 1
  while i <= t_end and lines[i]:match("^%s*$") do i = i + 1 end
  if i <= t_end and lines[i]:match("^%s*:PROPERTIES:%s*$") then
    local j = i + 1
    while j <= t_end do if lines[j]:match("^%s*:END:%s*$") then return i, j end; j = j + 1 end
  end
  return nil, nil
end

local function extract_task_id(lines, p_start, p_end)
  for i = p_start + 1, p_end - 1 do
    local k, v = lines[i]:match("^%s*:(%u[%u_]*):%s*(.-)%s*$")
    if k == "TASK_ID" and v ~= "" then return v end
  end
  return nil
end

local function is_zk_id(s)
  if not s then return false end
  if s:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d$") then return true end
  if s:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d[a-z]$") then return true end
  if s:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d[a-z][a-z]$") then return true end
  return false
end

local function normalize_task_id(s)
  if is_zk_id(s) then return s end
  local ts = s and s:match("^(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)%-.+$") or nil
  return (ts and #ts == 14) and ts or task_id.generate()
end

local function find_first_zk_link(lines, start_i, end_i)
  for i = start_i, end_i do
    local id = lines[i]:match("%[%[zk:(%d%d%d%d%d%d%d%d%d%d%d%d%d%d[a-z]?[a-z]?)%]%]")
    if id and is_zk_id(id) then return id end
  end
  return nil
end

local function ensure_zk_link(lines, t_start, t_end, id)
  if find_first_zk_link(lines, t_start, t_end) then return false end
  local _, p_end = find_properties_block(lines, t_start, t_end)
  local insert_pos = (p_end and (p_end + 1)) or (t_start + 1)
  table.insert(lines, insert_pos, "ID:: [[zk:" .. id .. "]]")
  return true
end

function M.start(opts)
  opts = opts or {}
  local dry = opts.dry_run ~= false
  local files = list_org_files()
  local changed_files, changed_tasks = 0, 0
  local used = {}

  -- Seed used IDs (to avoid accidental duplicates)
  for _, path in ipairs(files) do
    local lines = read_file(path)
    if lines then
      local tasks = collect_tasks(lines)
      for _, t in ipairs(tasks) do
        local p1, p2 = find_properties_block(lines, t.start, t.finish)
        if p1 and p2 then
          local tid = extract_task_id(lines, p1, p2)
          if tid then used[normalize_task_id(tid)] = true end
        end
        local zk = find_first_zk_link(lines, t.start, t.finish)
        if zk then used[zk] = true end
      end
    end
  end

  local function unique_id(desired)
    if not used[desired] then used[desired] = true; return desired end
    local prefix, s1, s2 = desired:match("^(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)([a-z]?)([a-z]?)$")
    local sfx = (s1 or "") .. (s2 or "")
    local function next_suffix(s)
      if s == "" then return "a" end
      local b = { s:byte(1, #s) }
      local i = #b
      while i >= 0 do
        if i == 0 then table.insert(b, 1, string.byte("a")); break end
        if b[i] < string.byte("z") then b[i] = b[i] + 1; break
        else b[i] = string.byte("a"); i = i - 1 end
      end
      local unpack_fn = table.unpack or unpack
      return string.char(unpack_fn(b))
    end
    repeat sfx = next_suffix(sfx) until not used[prefix .. sfx]
    local final = prefix .. sfx
    used[final] = true
    return final
  end

  for _, path in ipairs(files) do
    local lines = read_file(path)
    if not lines then goto continue end
    local tasks = collect_tasks(lines)
    local file_changes = 0

    for _, t in ipairs(tasks) do
      local p1, p2 = find_properties_block(lines, t.start, t.finish)
      local tid = p1 and extract_task_id(lines, p1, p2) or nil
      local zk  = find_first_zk_link(lines, t.start, t.finish)
      local desired = zk or (tid and normalize_task_id(tid)) or task_id.generate()
      local uid = unique_id(desired)

      -- ensure properties drawer
      if not (p1 and p2) then
        local insert_pos = t.start + 1
        table.insert(lines, insert_pos, ":PROPERTIES:")
        table.insert(lines, insert_pos + 1, ":END:")
        p1, p2 = insert_pos, insert_pos + 1
      end

      -- write TASK_ID if different
      local current_norm = tid and normalize_task_id(tid) or nil
      if current_norm ~= uid then
        local placed = false
        for i = p1 + 1, p2 - 1 do
          local k = lines[i]:match("^%s*:(%u[%u_]*):")
          if k == "TASK_ID" then lines[i] = ":TASK_ID: " .. uid; placed = true; break end
        end
        if not placed then table.insert(lines, p2, ":TASK_ID: " .. uid); p2 = p2 + 1 end
        file_changes = file_changes + 1
      end

      if ensure_zk_link(lines, t.start, t.finish, uid) then
        file_changes = file_changes + 1
      end
    end

    if file_changes > 0 then
      if dry then
        vim.notify(("DRY %s (%d changes)"):format(path, file_changes), vim.log.levels.DEBUG)
      else
        local ok, bak = backup_file(path)
        if not ok then
          vim.notify(("Backup failed for %s, skipping write"):format(path), vim.log.levels.ERROR)
        else
          write_file(path, lines)
          changed_files = changed_files + 1
          changed_tasks = changed_tasks + file_changes
          vim.notify(("WROTE %s (backup %s)"):format(path, bak), vim.log.levels.INFO)
        end
      end
    end
    ::continue::
  end

  vim.notify(("TASK-ID migration: %s — files changed: %d, tasks changed: %d")
    :format(dry and "DRY-RUN" or "APPLIED", changed_files, changed_tasks), vim.log.levels.INFO)

  return { changed_files = changed_files, changed_tasks = changed_tasks, dry_run = dry }
end

return M