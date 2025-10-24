-- ~/.config/nvim/lua/utils/link_open.lua
-- Fixed and simplified link opener

local M = {}

-- Config
M.config = {
  browser = "Safari",
  mutt_cmd = "neomutt",
  float = { border = "rounded", width = 0.85, height = 0.85, winblend = 0 },
}

-- Cached OS detection
local _is_macos = nil
local function is_macos()
  if _is_macos == nil then
    local s = vim.loop.os_uname().sysname or ""
    _is_macos = s:match("Darwin") ~= nil
  end
  return _is_macos
end

local function sys_open_url(url)
  if is_macos() then
    vim.fn.jobstart({ "open", "-a", M.config.browser, url }, { detach = true })
  else
    if vim.fn.executable("xdg-open") == 1 then
      vim.fn.jobstart({ "xdg-open", url }, { detach = true })
    else
      vim.notify("No URL opener found (xdg-open).", vim.log.levels.WARN, { title = "LinkOpen" })
    end
  end
end

local function urldecode(s)
  if not s then return s end
  s = s:gsub("+", " ")
  s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  return s
end

local function parse_mailto(uri)
  local addr, qs = uri:match("^mailto:([^%?]+)%??(.*)$")
  addr = urldecode(addr or "")
  local q = {}
  if qs and qs ~= "" then
    for kv in qs:gmatch("[^&]+") do
      local k, v = kv:match("^([^=]+)=(.*)$")
      if k then q[k:lower()] = urldecode(v) else q[kv:lower()] = "" end
    end
  end
  return addr, q
end

local function floating_term(cmd)
  local cols, lines = vim.o.columns, vim.o.lines
  local w = math.floor(cols * (M.config.float.width or 0.85))
  local h = math.floor(lines * (M.config.float.height or 0.85))
  local row = math.floor((lines - h) / 2)
  local col = math.floor((cols - w) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = w, height = h,
    style = "minimal", border = M.config.float.border or "rounded",
  })
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "terminal"
  vim.wo[win].winblend = M.config.float.winblend or 0

  vim.fn.termopen(cmd)
  vim.cmd("startinsert")

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set({ "n", "t" }, "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ "n", "t" }, "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

-- Simplified path cleaning
local function clean_abs(p)
  if not p or p == "" then return nil end

  -- Handle Org links properly: [[file:/path][label]]
  local embedded = p:match("^%[%[file:([^%]]+)%]%[[^%]]*%]%]$")
  if embedded then
    p = "file:" .. embedded
  end

  -- Strip common wrappers
  p = p:gsub("^%s*<", ""):gsub(">%s*$", "")
  p = p:gsub("^%s*%[", ""):gsub("%]%s*$", "")
  p = p:gsub("^%s*['\"]", ""):gsub("['\"]%s*$", "")

  -- Trim and drop file: scheme
  p = vim.trim(p)
  p = p:gsub("^file:", "")

  -- Expand ~ and make absolute
  p = vim.fn.expand(p)
  p = vim.fn.fnamemodify(p, ":p")
  return p
end

-- Robust Org link detection
local function org_target_from_line_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1

  local first_target = nil
  local i = 1
  while true do
    local s, e, target = line:find("%[%[file:([^%]]+)%]%[[^%]]*%]%]", i)
    if not s then break end
    if not first_target then first_target = target end
    if col >= s and col <= e then
      return "file:" .. target
    end
    i = e + 1
  end

  if first_target then
    return "file:" .. first_target
  end
  return nil
end

-- Simple markdown link detection
local function markdown_target_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col0 = vim.api.nvim_win_get_cursor(0)[2]
  local left = line:sub(1, col0 + 1)
  local right = line:sub(col0 + 1)
  local rb = left:reverse():find("%]")
  local lb = left:reverse():find("%[")
  local rp = right:find("%)")
  local lp = right:find("%(")
  if rb and lb and rp and lp then
    local target = right:sub(lp + 1, rp - 1)
    return target
  end
  -- Fallback: find any markdown link on the line
  local _, _, t = line:find("%[[^%]]+%]%(([^%)]+)%)")
  return t
end

-- Public actions
function M.open_mailto(uri)
  local addr, q = parse_mailto(uri)
  if addr == "" then
    return vim.notify("Invalid mailto: address", vim.log.levels.ERROR, { title = "LinkOpen" })
  end
  local cmd = { M.config.mutt_cmd }
  if q.subject and q.subject ~= "" then table.insert(cmd, "-s"); table.insert(cmd, q.subject) end
  if q.cc and q.cc ~= "" then table.insert(cmd, "-c"); table.insert(cmd, q.cc) end
  if q.bcc and q.bcc ~= "" then table.insert(cmd, "-b"); table.insert(cmd, q.bcc) end
  if q.body and q.body ~= "" then
    local tmp = vim.fn.tempname() .. ".txt"
    vim.fn.writefile(vim.split(q.body, "\n"), tmp)
    table.insert(cmd, "-i"); table.insert(cmd, tmp)
  end
  table.insert(cmd, addr)
  floating_term(cmd)
end

function M.open_url(url)
  sys_open_url(url)
end

function M.open_file(path)
  local p = clean_abs(path)
  if not p then
    vim.notify("Invalid file path", vim.log.levels.ERROR, { title = "LinkOpen" })
    return
  end
  
  if vim.fn.filereadable(p) == 0 then
    vim.notify("Linked file not found on disk:\n" .. p, vim.log.levels.ERROR, { title = "LinkOpen" })
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(p))
end

function M.preview_markdown(path)
  local p = clean_abs(path)
  if not p then
    vim.notify("Invalid file path", vim.log.levels.ERROR, { title = "LinkOpen" })
    return
  end
  
  if vim.fn.filereadable(p) == 0 then
    return vim.notify("File not found: " .. p, vim.log.levels.ERROR, { title = "LinkOpen" })
  end
  
  local cols, lines = vim.o.columns, vim.o.lines
  local w = math.floor(cols * (M.config.float.width or 0.85))
  local h = math.floor(lines * (M.config.float.height or 0.85))
  local row = math.floor((lines - h) / 2)
  local col = math.floor((cols - w) / 2)
  
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, p)
  local content = vim.fn.readfile(p)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = w, height = h,
    style = "minimal", border = M.config.float.border or "rounded",
    title = " Preview — " .. vim.fn.fnamemodify(p, ":t"), title_pos = "center",
  })
  
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, { buffer = buf, silent = true })
end

-- Main open-at-point function
function M.open_at_point(opts)
  opts = opts or {}
  local ft = vim.bo.filetype

  local target = nil
  
  -- Try filetype-specific detection first
  if ft == "org" then
    target = org_target_from_line_under_cursor()
  elseif ft == "markdown" or ft == "markdown.mdx" then
    target = markdown_target_under_cursor()
  end
  
  -- Fallback: bare URL/file under cursor
  if not target then
    local w = vim.fn.expand("<cfile>") or ""
    if w ~= "" then
      target = w
    end
  end
  
  if not target then
    vim.notify("Nothing openable under cursor.", vim.log.levels.INFO, { title = "LinkOpen" })
    return
  end

  -- Route based on target type
  if target:match("^mailto:") then 
    return M.open_mailto(target) 
  end
  if target:match("^https?://") then 
    return M.open_url(target) 
  end
  
  -- File path
  if opts.floating_preview then
    return M.preview_markdown(target)
  else
    return M.open_file(target)
  end
end

return M