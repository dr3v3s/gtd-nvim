-- ============================================================================
-- DATE PICKER
-- ============================================================================
-- Visual floating calendar for selecting DEFER and DUE dates with time.
--
-- Features:
-- - Side-by-side calendars for defer/due
-- - Keyboard navigation (hjkl, arrows)
-- - Quick shortcuts (t=today, +1d, +1w)
-- - Time selection with presets
-- - Calendar event creation option
--
-- @module gtd-nvim.capture.ui.datepicker
-- @version 1.1.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.1.0"
M._UPDATED = "2025-12-23"

-- ============================================================================
-- CONFIG
-- ============================================================================

M.config = {
  width = 62,
  height = 18,
  due_days_after_defer = 3,
  day_names = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" },
  month_names = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  },
  time_presets = {
    { label = "󰖌 Morning", time = "09:00" },
    { label = "󰖙 Midday", time = "12:00" },
    { label = "󰖚 Afternoon", time = "14:00" },
    { label = "󰖛 Evening", time = "18:00" },
  },
}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  buf = nil,
  win = nil,
  focus = "defer",  -- "defer", "due", or "time"
  defer_date = nil,
  due_date = nil,
  defer_time = nil,  -- "HH:MM" or nil
  due_time = nil,
  defer_month = nil,
  due_month = nil,
  defer_cursor = nil,
  due_cursor = nil,
  on_complete = nil,
  create_calendar_event = false,
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function days_in_month(year, month)
  local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if month == 2 and ((year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)) then
    return 29
  end
  return days[month]
end

local function first_day_of_month(year, month)
  local t = os.time({ year = year, month = month, day = 1 })
  local wday = tonumber(os.date("%w", t))
  return wday == 0 and 7 or wday
end

local function format_date(year, month, day)
  return string.format("%04d-%02d-%02d", year, month, day)
end

local function parse_date(str)
  if not str then return nil, nil end
  local y, m, d = str:match("(%d+)-(%d+)-(%d+)")
  local time = str:match("(%d%d:%d%d)")
  if y then 
    return { year = tonumber(y), month = tonumber(m), day = tonumber(d) }, time
  end
  return nil, nil
end

local function today()
  local t = os.date("*t")
  return { year = t.year, month = t.month, day = t.day }
end

local function add_days(date, days)
  local t = os.time({ year = date.year, month = date.month, day = date.day }) + days * 86400
  local new = os.date("*t", t)
  return { year = new.year, month = new.month, day = new.day }
end

local function date_equal(a, b)
  if not a or not b then return false end
  return a.year == b.year and a.month == b.month and a.day == b.day
end

local function cursor_to_date(cursor, view_year, view_month)
  local first_dow = first_day_of_month(view_year, view_month)
  local day = cursor - (first_dow - 1)
  local max_days = days_in_month(view_year, view_month)
  
  if day < 1 then
    local prev_month = view_month == 1 and 12 or view_month - 1
    local prev_year = view_month == 1 and view_year - 1 or view_year
    return { year = prev_year, month = prev_month, day = days_in_month(prev_year, prev_month) + day }
  elseif day > max_days then
    local next_month = view_month == 12 and 1 or view_month + 1
    local next_year = view_month == 12 and view_year + 1 or view_year
    return { year = next_year, month = next_month, day = day - max_days }
  end
  return { year = view_year, month = view_month, day = day }
end

local function date_to_cursor(date, view_year, view_month)
  if not date or date.year ~= view_year or date.month ~= view_month then return nil end
  return (first_day_of_month(view_year, view_month) - 1) + date.day
end

-- ============================================================================
-- RENDERING
-- ============================================================================

local function render_calendar(view_year, view_month, selected_date, cursor_pos, is_focused)
  local lines = {}
  local month_name = M.config.month_names[view_month]
  local header = string.format("◀ %s %d ▶", month_name, view_year)
  header = string.rep(" ", math.floor((21 - #header) / 2)) .. header
  table.insert(lines, header)
  table.insert(lines, table.concat(M.config.day_names, " "))
  
  local first_dow = first_day_of_month(view_year, view_month)
  local max_days = days_in_month(view_year, view_month)
  local prev_month = view_month == 1 and 12 or view_month - 1
  local prev_year = view_month == 1 and view_year - 1 or view_year
  local prev_days = days_in_month(prev_year, prev_month)
  local today_date = today()
  local day_num = 1 - (first_dow - 1)
  
  for week = 1, 6 do
    local week_str = ""
    for dow = 1, 7 do
      local cell_pos = (week - 1) * 7 + dow
      local display_day, is_other = day_num, false
      
      if day_num < 1 then
        display_day, is_other = prev_days + day_num, true
      elseif day_num > max_days then
        display_day, is_other = day_num - max_days, true
      end
      
      local is_cursor = is_focused and cell_pos == cursor_pos
      local is_selected = not is_other and date_equal({ year = view_year, month = view_month, day = day_num }, selected_date)
      local is_today_cell = not is_other and date_equal({ year = view_year, month = view_month, day = day_num }, today_date)
      
      local cell
      if is_cursor then
        cell = string.format("[%2d]", display_day)
      elseif is_selected then
        cell = string.format("<%2d>", display_day)
      elseif is_today_cell then
        cell = string.format("*%2d ", display_day)
      elseif is_other then
        cell = string.format(" %2d ", display_day):gsub("%d", "·")
      else
        cell = string.format(" %2d ", display_day)
      end
      
      week_str = week_str .. cell:sub(1, is_cursor and 4 or 3)
      day_num = day_num + 1
    end
    table.insert(lines, week_str)
  end
  return lines
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  
  local lines = {}
  local defer_hl = state.focus == "defer" and "󰄲 " or "  "
  local due_hl = state.focus == "due" and "󰄲 " or "  "
  
  table.insert(lines, defer_hl .. "DEFER                      " .. due_hl .. "DUE")
  table.insert(lines, string.rep("─", M.config.width - 2))
  
  local defer_lines = render_calendar(state.defer_month.year, state.defer_month.month, state.defer_date, state.defer_cursor, state.focus == "defer")
  local due_lines = render_calendar(state.due_month.year, state.due_month.month, state.due_date, state.due_cursor, state.focus == "due")
  
  for i = 1, math.max(#defer_lines, #due_lines) do
    local left = (defer_lines[i] or "") .. string.rep(" ", 26 - #(defer_lines[i] or ""))
    table.insert(lines, "  " .. left .. "  " .. (due_lines[i] or ""))
  end
  
  table.insert(lines, string.rep("─", M.config.width - 2))
  
  -- Time row
  local defer_time_str = state.defer_time or "--:--"
  local due_time_str = state.due_time or "--:--"
  local time_row = string.format("  Time: [%s]                Time: [%s]", defer_time_str, due_time_str)
  table.insert(lines, time_row)
  
  -- Calendar event option
  local cal_icon = state.create_calendar_event and "󰄲" or "󰄱"
  table.insert(lines, string.format("  %s Create calendar event (c to toggle)", cal_icon))
  
  table.insert(lines, string.rep("─", M.config.width - 2))
  table.insert(lines, "  t=today m=+1d w=+1w  T=set time  H/L=month  <Tab>=switch")
  table.insert(lines, "  <Enter>=select  <Esc>=done  q=cancel  c=calendar event")
  
  -- Status line
  local defer_str = state.defer_date and format_date(state.defer_date.year, state.defer_date.month, state.defer_date.day) or "—"
  local due_str = state.due_date and format_date(state.due_date.year, state.due_date.month, state.due_date.day) or "—"
  if state.defer_time then defer_str = defer_str .. " " .. state.defer_time end
  if state.due_time then due_str = due_str .. " " .. state.due_time end
  table.insert(lines, string.format("  Defer: %s    Due: %s", defer_str, due_str))
  
  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
end

-- ============================================================================
-- NAVIGATION
-- ============================================================================

local function move_cursor(dir)
  if state.focus == "time" then return end
  local ck = state.focus == "defer" and "defer_cursor" or "due_cursor"
  local mk = state.focus == "defer" and "defer_month" or "due_month"
  local c, m = state[ck], state[mk]
  
  if dir == "left" then c = c - 1
  elseif dir == "right" then c = c + 1
  elseif dir == "up" then c = c - 7
  elseif dir == "down" then c = c + 7
  end
  
  if c < 1 then
    m.month = m.month - 1
    if m.month < 1 then m.month, m.year = 12, m.year - 1 end
    c = c + 35
  elseif c > 42 then
    m.month = m.month + 1
    if m.month > 12 then m.month, m.year = 1, m.year + 1 end
    c = c - 35
  end
  
  state[ck], state[mk] = math.max(1, math.min(42, c)), m
  render()
end

local function switch_focus()
  state.focus = state.focus == "defer" and "due" or "defer"
  render()
end

local function select_current()
  if state.focus == "time" then return end
  local ck = state.focus == "defer" and "defer_cursor" or "due_cursor"
  local mk = state.focus == "defer" and "defer_month" or "due_month"
  local dk = state.focus == "defer" and "defer_date" or "due_date"
  
  state[dk] = cursor_to_date(state[ck], state[mk].year, state[mk].month)
  
  if state.focus == "defer" then
    state.focus = "due"
    if not state.due_date then
      state.due_date = add_days(state[dk], M.config.due_days_after_defer)
      state.due_month = { year = state.due_date.year, month = state.due_date.month }
      state.due_cursor = date_to_cursor(state.due_date, state.due_month.year, state.due_month.month) or 15
    end
  end
  render()
end

local function jump_date(days)
  local t = add_days(today(), days)
  local mk = state.focus == "defer" and "defer_month" or "due_month"
  local ck = state.focus == "defer" and "defer_cursor" or "due_cursor"
  local dk = state.focus == "defer" and "defer_date" or "due_date"
  
  state[mk] = { year = t.year, month = t.month }
  state[ck] = date_to_cursor(t, t.year, t.month) or 15
  state[dk] = t
  render()
end

local function change_month(delta)
  local mk = state.focus == "defer" and "defer_month" or "due_month"
  state[mk].month = state[mk].month + delta
  if state[mk].month < 1 then state[mk].month, state[mk].year = 12, state[mk].year - 1
  elseif state[mk].month > 12 then state[mk].month, state[mk].year = 1, state[mk].year + 1 end
  render()
end

local function toggle_calendar_event()
  state.create_calendar_event = not state.create_calendar_event
  render()
end

-- ============================================================================
-- TIME PICKER
-- ============================================================================

local function pick_time()
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    -- Fallback to input
    local tk = state.focus == "defer" and "defer_time" or "due_time"
    vim.ui.input({ prompt = "Time (HH:MM): ", default = state[tk] or "" }, function(input)
      if input and input:match("^%d%d:%d%d$") then
        state[tk] = input
      end
      render()
    end)
    return
  end
  
  local items = {}
  for _, preset in ipairs(M.config.time_presets) do
    table.insert(items, string.format("%s  %s", preset.label, preset.time))
  end
  table.insert(items, " Custom time...")
  table.insert(items, "󰜺 No time (clear)")
  
  local tk = state.focus == "defer" and "defer_time" or "due_time"
  
  fzf.fzf_exec(items, {
    prompt = "Time ❯ ",
    winopts = { height = 0.35, width = 0.35 },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then
          render()
          return
        end
        
        local choice = sel[1]
        if choice:match("No time") then
          state[tk] = nil
        elseif choice:match("Custom") then
          vim.schedule(function()
            vim.ui.input({ prompt = "Time (HH:MM): ", default = state[tk] or "09:00" }, function(input)
              if input and input:match("^%d%d:%d%d$") then
                state[tk] = input
              end
              render()
            end)
          end)
          return
        else
          local time = choice:match("(%d%d:%d%d)")
          if time then state[tk] = time end
        end
        render()
      end,
    },
  })
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local function close(cancelled)
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_delete(state.buf, { force = true }) end
  state.win, state.buf = nil, nil
  
  if state.on_complete then
    if cancelled then
      state.on_complete(nil, nil, nil, nil, false)
    else
      local defer_str = state.defer_date and format_date(state.defer_date.year, state.defer_date.month, state.defer_date.day)
      local due_str = state.due_date and format_date(state.due_date.year, state.due_date.month, state.due_date.day)
      state.on_complete(defer_str, due_str, state.defer_time, state.due_time, state.create_calendar_event)
    end
  end
end

local function setup_keymaps()
  local o = { buffer = state.buf, noremap = true, silent = true }
  vim.keymap.set("n", "h", function() move_cursor("left") end, o)
  vim.keymap.set("n", "j", function() move_cursor("down") end, o)
  vim.keymap.set("n", "k", function() move_cursor("up") end, o)
  vim.keymap.set("n", "l", function() move_cursor("right") end, o)
  vim.keymap.set("n", "<Left>", function() move_cursor("left") end, o)
  vim.keymap.set("n", "<Down>", function() move_cursor("down") end, o)
  vim.keymap.set("n", "<Up>", function() move_cursor("up") end, o)
  vim.keymap.set("n", "<Right>", function() move_cursor("right") end, o)
  vim.keymap.set("n", "<CR>", select_current, o)
  vim.keymap.set("n", "<Space>", select_current, o)
  vim.keymap.set("n", "<Tab>", switch_focus, o)
  vim.keymap.set("n", "t", function() jump_date(0) end, o)
  vim.keymap.set("n", "m", function() jump_date(1) end, o)
  vim.keymap.set("n", "w", function() jump_date(7) end, o)
  vim.keymap.set("n", "W", function() jump_date(14) end, o)
  vim.keymap.set("n", "H", function() change_month(-1) end, o)
  vim.keymap.set("n", "L", function() change_month(1) end, o)
  vim.keymap.set("n", "<", function() change_month(-1) end, o)
  vim.keymap.set("n", ">", function() change_month(1) end, o)
  vim.keymap.set("n", "T", pick_time, o)
  vim.keymap.set("n", "c", toggle_calendar_event, o)
  vim.keymap.set("n", "<Esc>", function() close(false) end, o)
  vim.keymap.set("n", "q", function() close(true) end, o)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function M.open(opts)
  opts = opts or {}
  local t = today()
  
  state.defer_date, state.defer_time = parse_date(opts.defer)
  state.due_date, state.due_time = parse_date(opts.due)
  state.defer_time = opts.defer_time or state.defer_time
  state.due_time = opts.due_time or state.due_time
  state.defer_month = state.defer_date and { year = state.defer_date.year, month = state.defer_date.month } or { year = t.year, month = t.month }
  state.due_month = state.due_date and { year = state.due_date.year, month = state.due_date.month } or { year = t.year, month = t.month }
  state.defer_cursor = date_to_cursor(state.defer_date or t, state.defer_month.year, state.defer_month.month) or 15
  state.due_cursor = date_to_cursor(state.due_date, state.due_month.year, state.due_month.month) or 15
  state.focus = "defer"
  state.on_complete = opts.on_complete
  state.create_calendar_event = opts.create_calendar_event or false
  
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(state.buf, "bufhidden", "wipe")
  
  local ui = vim.api.nvim_list_uis()[1]
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    row = math.floor((ui.height - M.config.height) / 2),
    col = math.floor((ui.width - M.config.width) / 2),
    width = M.config.width,
    height = M.config.height,
    style = "minimal",
    border = "rounded",
    title = " 󰃰 Select Dates ",
    title_pos = "center",
  })
  
  setup_keymaps()
  render()
end

function M.pick(callback)
  M.open({ on_complete = callback })
end

return M
