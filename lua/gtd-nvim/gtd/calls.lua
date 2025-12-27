-- ============================================================================
-- GTD-NVIM CALLS MODULE
-- ============================================================================
-- Phone calls tracking: people to call and waiting for callbacks
-- Integrates with Apple Contacts via chronos-bridge
--
-- @module gtd-nvim.gtd.calls
-- @version 1.0.0
-- @updated 2025-12-23
-- ============================================================================

local M = {}

M._VERSION = "1.0.0"
M._UPDATED = "2025-12-23"

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local function safe_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local shared = safe_require("gtd-nvim.gtd.shared")
local chronos = safe_require("gtd-nvim.gtd.chronos-client")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.config = {
  -- Colors (Catppuccin Mocha)
  colors = {
    reset     = "\27[0m",
    bold      = "\27[1m",
    dim       = "\27[2m",
    green     = "\27[38;2;166;227;161m",
    yellow    = "\27[38;2;249;226;175m",
    peach     = "\27[38;2;250;179;135m",
    blue      = "\27[38;2;137;180;250m",
    lavender  = "\27[38;2;180;190;254m",
    text      = "\27[38;2;205;214;244m",
    subtext0  = "\27[38;2;166;173;200m",
    overlay1  = "\27[38;2;127;132;156m",
    surface0  = "\27[38;2;49;50;68m",
  },
}

local C = M.config.colors

-- ============================================================================
-- HELPERS
-- ============================================================================

local function get_glyphs()
  if shared and shared.glyphs then
    return shared.glyphs
  end
  return {
    state = { NEXT = "󱥦", TODO = "", WAITING = "", SOMEDAY = "󰋊" },
    ui = { phone = "󰏲", call_out = "󰏶", call_in = "󰏵" },
  }
end

--- Safely convert vim.NIL to empty table
local function safe_table(val)
  if val == nil or val == vim.NIL then
    return {}
  end
  if type(val) ~= "table" then
    return {}
  end
  return val
end

-- ============================================================================
-- DATA FETCHING
-- ============================================================================

--- Fetch calls data from daemon
---@return table|nil { to_call, waiting_calls }, string|nil error
function M.fetch_calls()
  if not chronos or not chronos.is_available() then
    return nil, "Chronos daemon not available"
  end
  
  local data, err = chronos.gtd_calls()
  if not data then
    return nil, err or "Failed to fetch calls"
  end
  
  -- Normalize fields
  return {
    to_call = safe_table(data.to_call),
    waiting_calls = safe_table(data.waiting_calls),
    total_to_call = data.total_to_call or 0,
    total_waiting = data.total_waiting or 0,
  }, nil
end

--- Search contacts by name
---@param query string Search query
---@param limit number|nil Max results (default 10)
---@return table|nil contacts, string|nil error
function M.search_contacts(query, limit)
  if not chronos then
    return nil, "Chronos not available"
  end
  
  local data, err = chronos.query_bridge("contacts", "search", {
    query = query,
    limit = limit or 10,
  })
  
  if not data then
    return nil, err
  end
  
  return safe_table(data.contacts), nil
end

--- Get contact by ID
---@param id string Contact identifier
---@return table|nil contact, string|nil error
function M.get_contact(id)
  if not chronos then
    return nil, "Chronos not available"
  end
  
  local data, err = chronos.query_bridge("contacts", "get", { id = id })
  return data, err
end

-- ============================================================================
-- DISPLAY
-- ============================================================================

--- Build calls display for fzf
---@param calls_data table Data from fetch_calls
---@return table display_lines, table meta_items
function M.build_display(calls_data)
  local g = get_glyphs()
  local display = {}
  local meta = {}
  
  -- Section header helper
  local function add_section(title, icon, color)
    if #display > 0 then
      table.insert(display, "")
      table.insert(meta, { type = "separator" })
    end
    local header = string.format("%s%s%s %s%s", C.bold, color or C.lavender, icon, title, C.reset)
    table.insert(display, header)
    table.insert(meta, { type = "header", title = title })
    table.insert(display, C.surface0 .. string.rep("─", 50) .. C.reset)
    table.insert(meta, { type = "separator" })
  end
  
  -- CALLS TO MAKE
  local to_call = calls_data.to_call or {}
  if #to_call > 0 then
    add_section("CALLS TO MAKE", "󰏶", C.green)
    
    for _, task in ipairs(to_call) do
      local state_icon = g.state[task.state] or ""
      local state_color = task.state == "NEXT" and C.yellow or C.blue
      local project = task.project and (C.overlay1 .. " :" .. task.project .. C.reset) or ""
      
      local line = string.format("  %s%s %s%s%s%s",
        state_color, state_icon, C.text, task.title or "?", C.reset, project)
      
      table.insert(display, line)
      table.insert(meta, { type = "to_call", task = task })
    end
  end
  
  -- WAITING FOR CALLBACKS
  local waiting = calls_data.waiting_calls or {}
  if #waiting > 0 then
    add_section("WAITING FOR CALLBACK", "󰏵", C.peach)
    
    for _, task in ipairs(waiting) do
      local waiting_for = ""
      if task.properties and task.properties.WAITING_FOR then
        waiting_for = C.peach .. " → " .. task.properties.WAITING_FOR .. C.reset
      end
      local project = task.project and (C.overlay1 .. " :" .. task.project .. C.reset) or ""
      
      local line = string.format("  %s%s %s%s%s%s",
        C.peach, g.state.WAITING or "", C.text, task.title or "?", waiting_for, project)
      
      table.insert(display, line)
      table.insert(meta, { type = "waiting", task = task })
    end
  end
  
  -- Empty state
  if #to_call == 0 and #waiting == 0 then
    table.insert(display, C.subtext0 .. "  No calls to make or awaiting callbacks" .. C.reset)
    table.insert(meta, { type = "info" })
  end
  
  return display, meta
end

-- ============================================================================
-- PICKER
-- ============================================================================

--- Show calls picker
function M.show()
  -- Check fzf-lua
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required for calls display", vim.log.levels.ERROR)
    return
  end
  
  -- Ensure valid cwd
  if shared and shared.ensure_valid_cwd then
    shared.ensure_valid_cwd()
  end
  
  -- Fetch data
  local calls_data, err = M.fetch_calls()
  if not calls_data then
    vim.notify("Failed to fetch calls: " .. (err or "unknown"), vim.log.levels.ERROR)
    return
  end
  
  -- Build display
  local display, meta = M.build_display(calls_data)
  
  -- Strip ANSI helper
  local function strip_ansi(s)
    if not s then return "" end
    return s:gsub("\27%[[%d;]*m", ""):gsub("\27%[[%d;]*[A-Za-z]", "")
  end
  
  -- Find item by selection
  local function find_item(selected)
    if not selected then return nil end
    local stripped = strip_ansi(selected)
    for i, line in ipairs(display) do
      if strip_ansi(line) == stripped then
        return meta[i]
      end
    end
    return nil
  end
  
  -- Open task
  local function open_task(task)
    if task and task.file then
      vim.cmd("edit " .. vim.fn.fnameescape(task.file))
      if task.line then
        vim.api.nvim_win_set_cursor(0, { task.line, 0 })
        vim.cmd("normal! zz")
      end
    end
  end
  
  -- Summary line
  local total_calls = (calls_data.total_to_call or 0)
  local total_waiting = (calls_data.total_waiting or 0)
  local summary = string.format("Calls: %d to make, %d waiting", total_calls, total_waiting)
  
  -- Show picker
  fzf.fzf_exec(display, {
    prompt = "Calls> ",
    fzf_opts = {
      ["--ansi"] = "",
      ["--header"] = summary,
      ["--no-multi"] = "",
    },
    actions = {
      ["default"] = function(sel)
        if not sel or not sel[1] then return end
        local item = find_item(sel[1])
        if item and item.task then
          open_task(item.task)
        end
      end,
      ["ctrl-e"] = function(sel)
        if not sel or not sel[1] then return end
        local item = find_item(sel[1])
        if item and item.task then
          open_task(item.task)
          vim.schedule(function()
            M.show()
          end)
        end
      end,
      ["ctrl-r"] = function()
        vim.schedule(function()
          M.show()
        end)
      end,
      ["ctrl-c"] = function()
        -- Search contacts
        vim.ui.input({ prompt = "Search contacts: " }, function(query)
          if query and query ~= "" then
            local contacts, cerr = M.search_contacts(query, 20)
            if contacts and #contacts > 0 then
              M.show_contacts(contacts)
            else
              vim.notify("No contacts found: " .. (cerr or query), vim.log.levels.INFO)
            end
          end
        end)
      end,
    },
    winopts = {
      height = 0.6,
      width = 0.7,
      row = 0.3,
      preview = { hidden = "hidden" },
    },
  })
end

--- Show contacts picker (from search results)
---@param contacts table Array of contact objects
function M.show_contacts(contacts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return end
  
  local display = {}
  local meta = {}
  
  for _, contact in ipairs(contacts) do
    local name = contact.full_name or ""
    local org = contact.organization and (C.overlay1 .. " @ " .. contact.organization .. C.reset) or ""
    local phone = contact.primary_phone and (C.green .. " " .. contact.primary_phone .. C.reset) or ""
    
    local line = string.format("%s󰀄 %s%s%s%s", C.blue, C.text, name, org, phone)
    table.insert(display, line)
    table.insert(meta, contact)
  end
  
  fzf.fzf_exec(display, {
    prompt = "Contacts> ",
    fzf_opts = { ["--ansi"] = "" },
    actions = {
      ["default"] = function(sel, opts)
        if not sel or not sel[1] then return end
        local idx = opts.fzf_lines and opts.fzf_lines[sel[1]] or 1
        local contact = meta[idx] or meta[1]
        if contact then
          -- Show contact details
          local details = {
            "Name: " .. (contact.full_name or "?"),
            "Organization: " .. (contact.organization or "-"),
            "Phone: " .. (contact.primary_phone or "-"),
            "Email: " .. (contact.primary_email or "-"),
          }
          vim.notify(table.concat(details, "\n"), vim.log.levels.INFO)
        end
      end,
    },
    winopts = { height = 0.5, width = 0.5 },
  })
end

--- Get summary for status line
---@return table { to_call, waiting }
function M.summary()
  local calls_data = M.fetch_calls()
  if calls_data then
    return {
      to_call = calls_data.total_to_call or 0,
      waiting = calls_data.total_waiting or 0,
    }
  end
  return { to_call = 0, waiting = 0 }
end

-- ============================================================================
-- AGENDA INTEGRATION
-- ============================================================================

--- Get calls data for agenda display
--- Returns formatted tasks ready for agenda sections
---@return table { to_call, waiting_calls }
function M.for_agenda()
  local calls_data = M.fetch_calls()
  if not calls_data then
    return { to_call = {}, waiting_calls = {} }
  end
  return calls_data
end

-- ============================================================================
-- SETUP
-- ============================================================================

function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  
  -- Register commands
  vim.api.nvim_create_user_command("GtdCalls", function()
    M.show()
  end, { desc = "Show calls to make and waiting callbacks" })
  
  vim.api.nvim_create_user_command("GtdContactSearch", function(cmd_opts)
    local query = cmd_opts.args
    if query and query ~= "" then
      local contacts, err = M.search_contacts(query, 20)
      if contacts and #contacts > 0 then
        M.show_contacts(contacts)
      else
        vim.notify("No contacts found: " .. (err or query), vim.log.levels.INFO)
      end
    else
      vim.ui.input({ prompt = "Search contacts: " }, function(q)
        if q and q ~= "" then
          local contacts, err = M.search_contacts(q, 20)
          if contacts and #contacts > 0 then
            M.show_contacts(contacts)
          else
            vim.notify("No contacts found: " .. (err or q), vim.log.levels.INFO)
          end
        end
      end)
    end
  end, { nargs = "?", desc = "Search Apple Contacts" })
end

return M
