local api = vim.api

local version = vim.version()
if version.major == 0 and version.minor < 10 then
  error("pencil.nvim requires Neovim 0.10 or newer")
end

local M = {}
local active = {}
local preferred_width = 80
local window_keys = { "wrap", "linebreak", "breakindent", "statuscolumn" }

local function target(opts)
  if opts == nil then return api.nvim_get_current_buf() end
  if type(opts) ~= "table" then error("pencil options must be a table") end
  for key in pairs(opts) do
    if key ~= "buf" then error("pencil options has unknown key " .. key) end
  end
  local buf = opts.buf or api.nvim_get_current_buf()
  if type(buf) ~= "number" or not api.nvim_buf_is_valid(buf) then
    error("invalid buffer " .. tostring(buf))
  end
  return buf
end

local function snapshot(win)
  local values = {}
  for _, key in ipairs(window_keys) do values[key] = vim.wo[win][key] end
  return values
end

local function gutter_width(win)
  local width = vim.wo[win].signcolumn == "no" and 0 or 2
  width = width + (tonumber(vim.wo[win].foldcolumn) or 0)
  if vim.wo[win].number or vim.wo[win].relativenumber then
    width = width + #tostring(api.nvim_buf_line_count(api.nvim_win_get_buf(win))) + 1
  end
  return width
end

local function desired(win, baseline)
  local available = math.max(1, api.nvim_win_get_width(win) - gutter_width(win))
  local measure = math.min(baseline.width, available)
  local spare = available - measure
  local left = math.floor(spare / 2)
  local column = baseline.statuscolumn
  if column == "" then
    column = "%s%C"
    if vim.wo[win].number or vim.wo[win].relativenumber then
      column = column .. "%=%{v:relnum == 0 ? v:lnum : v:relnum} "
    end
  end
  -- deliberate: statuscolumn and wrapmargin are Neovim's native visual-only
  -- seams; use the available width as the ceiling rather than creating overflow.
  return {
    wrap = true,
    linebreak = true,
    breakindent = true,
    statuscolumn = string.rep(" ", left) .. column,
    wrapmargin = spare - left,
  }
end

local function restore_record(state, win, record)
  if not api.nvim_win_is_valid(win) then return end
  for key, item in pairs(record.changed) do
    if not item.user and vim.wo[win][key] == item.ours then vim.wo[win][key] = item.old end
  end
end

local function restore_wrapmargin(state)
  local item = state.wrapmargin
  if not item.user and vim.bo[state.buf].wrapmargin == item.ours then
    vim.bo[state.buf].wrapmargin = item.old
  end
end

local function apply(state, win)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= state.buf then return end
  local record = state.windows[win]
  if not record then
    local old = snapshot(win)
    old.width = state.width
    -- deliberate: splits inherit window options; reuse the active baseline only
    -- for values that are visibly Pencil-owned, preventing leaked presentation
    -- while keeping independently configured windows untouched.
    for _, sibling in pairs(state.windows) do
      if sibling.changed then
        for key, item in pairs(sibling.changed) do
          if old[key] == item.ours and not item.user then old[key] = item.old end
        end
      end
    end
    record = { old = old, changed = {} }
    state.windows[win] = record
  end
  local values = desired(win, record.old)
  local wrapmargin = state.wrapmargin
  if vim.bo[state.buf].wrapmargin ~= wrapmargin.ours then wrapmargin.user = true end
  if not wrapmargin.user then
    wrapmargin.ours = values.wrapmargin
    vim.bo[state.buf].wrapmargin = wrapmargin.ours
  end
  for key, value in pairs(values) do
    if key ~= "wrapmargin" then
      local item = record.changed[key]
      local before = vim.wo[win][key]
      if item and before ~= item.ours then item.user = true end
      if not item then
        item = { old = before, ours = value }
        record.changed[key] = item
      elseif not item.user then
        item.ours = value
      end
      if not item.user and before ~= item.ours then vim.wo[win][key] = item.ours end
    end
  end
end

local function windows_for(buf)
  local result = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf then result[#result + 1] = win end
  end
  return result
end

local function reconcile(buf)
  local state = active[buf]
  if not state or not api.nvim_buf_is_valid(buf) then return end
  local visible = {}
  for _, win in ipairs(windows_for(buf)) do
    visible[win] = true
    apply(state, win)
  end
  for win, record in pairs(state.windows) do
    if not visible[win] then
      if api.nvim_win_is_valid(win) then restore_record(state, win, record) end
      state.windows[win] = nil
    end
  end
  if next(visible) == nil then restore_wrapmargin(state) end
end

function M.setup(opts)
  if opts == nil then return end
  if type(opts) ~= "table" then error("pencil.setup() expects a table") end
  local width = 80
  for key, value in pairs(opts) do
    if key ~= "width" then error("pencil.setup() has unknown key " .. tostring(key)) end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value <= 0 or value ~= math.floor(value) then
      error("pencil.setup() width must be a positive integer")
    end
    width = value
  end
  preferred_width = width
end

function M.enable(opts)
  local buf = target(opts)
  if active[buf] then reconcile(buf); return end
  local state = { buf = buf, width = preferred_width, windows = {}, wrapmargin = { old = vim.bo[buf].wrapmargin } }
  state.wrapmargin.ours = state.wrapmargin.old
  active[buf] = state
  local ok, err = pcall(reconcile, buf)
  if not ok then
    for win, record in pairs(state.windows) do restore_record(state, win, record) end
    restore_wrapmargin(state)
    active[buf] = nil
    error(err)
  end
end

function M.disable(opts)
  local buf = target(opts)
  local state = active[buf]
  if not state then return end
  for win, record in pairs(state.windows) do restore_record(state, win, record) end
  restore_wrapmargin(state)
  active[buf] = nil
end

function M.toggle(opts)
  local buf = target(opts)
  if active[buf] then M.disable({ buf = buf }) else M.enable({ buf = buf }) end
end

local group = api.nvim_create_augroup("pencil_lifecycle", { clear = true })
api.nvim_create_autocmd({ "BufWinEnter", "BufEnter", "WinEnter", "WinNew" }, {
  group = group,
  callback = function(args)
    for buf in pairs(active) do reconcile(buf) end
  end,
})
api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
  group = group,
  callback = function()
    for buf in pairs(active) do reconcile(buf) end
  end,
})
api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(args)
    local win = tonumber(args.match)
    for _, state in pairs(active) do state.windows[win] = nil end
  end,
})
api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(args) active[args.buf] = nil end,
})

api.nvim_create_user_command("Pencil", function() M.toggle() end, { nargs = 0 })

return M
