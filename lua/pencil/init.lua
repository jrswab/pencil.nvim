local M, api = {}, vim.api
local version = vim.version()
if version.major == 0 and version.minor < 10 then error("pencil.nvim requires Neovim 0.10 or newer") end

local defaults = { mode = "detect", fallback = "soft", textwidth = 80,
  conceal = { level = 2, cursor = "" }, mappings = { navigation = true, undo_breaks = true },
  status = { hard = "H", auto = "A", soft = "S", off = "" } }
local presets = {
  gitcommit = { mode = "hard", textwidth = 72 }, mail = { mode = "hard", textwidth = 72 },
  markdown = { mode = "detect", fallback = "soft" }, text = { mode = "detect", fallback = "soft" },
  rst = { mode = "detect", fallback = "hard", textwidth = 79 }, tex = { mode = "detect", fallback = "hard", textwidth = 79 },
  asciidoc = { mode = "detect", fallback = "hard", textwidth = 79 }, textile = { mode = "detect", fallback = "soft" }, }
local config, user_config, configured = vim.deepcopy(defaults), {}, false
local active, disabled, installed = {}, {}, false
local window_owner, transition_baseline, pending_leave = {}, {}, {}
local mapping_owner = "pencil.nvim:owned-mapping:v1"
local function mapping_callback(rhs)
  local keys = vim.api.nvim_replace_termcodes(rhs, true, false, true)
  return function() vim.api.nvim_feedkeys(keys, "n", false) end
end

local function merge(a, b)
  local out = vim.deepcopy(a)
  for key, value in pairs(b or {}) do
    out[key] = type(value) == "table" and type(out[key]) == "table" and merge(out[key], value) or vim.deepcopy(value)
  end
  return out
end
local function integer(value, name, errors, minimum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < minimum then errors[#errors + 1] = name .. " must be an integer >= " .. minimum end
end
local function validate(value)
  local errors = {}
  if type(value) ~= "table" then return false, { "setup() expects a table" } end
  local function known(t, keys, name) for k in pairs(t) do if not keys[k] then errors[#errors + 1] = name .. " has unknown key " .. tostring(k) end end end
  local function mode(x, name) if x ~= nil and x ~= "hard" and x ~= "soft" and x ~= "detect" then errors[#errors + 1] = name .. " must be hard, soft, or detect" end end
  local function fallback(x, name) if x ~= nil and x ~= "hard" and x ~= "soft" then errors[#errors + 1] = name .. " must be hard or soft" end end
  local function width(x, name) if x ~= nil then integer(x, name, errors, 1) end end
  local function mappings(x, name)
    if x == nil then return end
    if type(x) ~= "table" then errors[#errors + 1] = name .. " must be a table"; return end
    known(x, { navigation=true, undo_breaks=true }, name)
    for _, key in ipairs({ "navigation", "undo_breaks" }) do if x[key] ~= nil and type(x[key]) ~= "boolean" then errors[#errors + 1] = name .. "." .. key .. " must be a boolean" end end
  end
  local function conceal(x, name)
    if x == nil or x == false then return end
    if type(x) ~= "table" then errors[#errors + 1] = name .. " must be false or a table"; return end
    known(x, { level=true, cursor=true }, name)
    if x.level ~= nil then integer(x.level, name .. ".level", errors, 0); if type(x.level) == "number" and x.level > 3 then errors[#errors + 1] = name .. ".level must be <= 3" end end
    if x.cursor ~= nil then
      if type(x.cursor) ~= "string" or not x.cursor:match("^[nvic]*$") then errors[#errors + 1] = name .. ".cursor must contain only n, v, i, and c"
      else local seen = {}; for mode in x.cursor:gmatch(".") do if seen[mode] then errors[#errors + 1] = name .. ".cursor must not contain duplicate modes" end; seen[mode] = true end end
    end
  end
  known(value, { mode=true, fallback=true, textwidth=true, conceal=true, mappings=true, status=true, filetypes=true }, "configuration")
  mode(value.mode, "mode"); fallback(value.fallback, "fallback"); width(value.textwidth, "textwidth")
  mappings(value.mappings, "mappings"); conceal(value.conceal, "conceal")
  if value.status ~= nil then
    if type(value.status) ~= "table" then errors[#errors + 1] = "status must be a table" else
      known(value.status, { hard=true, auto=true, soft=true, off=true }, "status")
      for _, k in ipairs({ "hard", "auto", "soft", "off" }) do if value.status[k] ~= nil and type(value.status[k]) ~= "string" then errors[#errors + 1] = "status." .. k .. " must be a string" end end
    end
  end
  if value.filetypes ~= nil then
    if type(value.filetypes) ~= "table" then errors[#errors + 1] = "filetypes must be a list or table" else
      local max = 0
      for k in pairs(value.filetypes) do
        if type(k) == "number" then
          if k <= 0 or k % 1 ~= 0 then errors[#errors + 1] = "filetypes list keys must be positive integers" else max = math.max(max, k) end
        elseif type(k) ~= "string" then errors[#errors + 1] = "filetypes keys must be strings or list indices" end
      end
      for i = 1, max do if value.filetypes[i] == nil then errors[#errors + 1] = "filetypes list must not be sparse" elseif type(value.filetypes[i]) ~= "string" then errors[#errors + 1] = "filetypes list entries must be strings" end end
      for name, entry in pairs(value.filetypes) do if type(name) == "string" then
        if type(entry) ~= "table" then errors[#errors + 1] = "filetypes." .. name .. " must be a table" else
          known(entry, { mode=true, fallback=true, textwidth=true, conceal=true, mappings=true }, "filetypes." .. name)
          mode(entry.mode, "filetypes." .. name .. ".mode"); fallback(entry.fallback, "filetypes." .. name .. ".fallback"); width(entry.textwidth, "filetypes." .. name .. ".textwidth"); mappings(entry.mappings, "filetypes." .. name .. ".mappings"); conceal(entry.conceal, "filetypes." .. name .. ".conceal")
        end
      end end
    end
  end
  return #errors == 0, errors
end
local function target(opts)
  local buf = opts and opts.buf or api.nvim_get_current_buf()
  if type(buf) ~= "number" or not api.nvim_buf_is_valid(buf) then error("invalid buffer " .. tostring(buf)) end
  return buf
end
local function modeline_width(buf)
  local count, lines = api.nvim_buf_line_count(buf), {}
  for _, line in ipairs(api.nvim_buf_get_lines(buf, 0, math.min(5, count), false)) do lines[#lines + 1] = line end
  if count > 5 then for _, line in ipairs(api.nvim_buf_get_lines(buf, count - 5, count, false)) do lines[#lines + 1] = line end end
  for _, line in ipairs(lines) do for _, marker in ipairs({ "vim:", "Vim:", "vi:", "ex:" }) do
    local start = 1
    while true do
      local at = line:find(marker, start, true); if not at then break end
      if at == 1 or line:sub(at - 1, at - 1):match("%s") then
        local body = line:sub(at + #marker):match("^(.-):") or line:sub(at + #marker)
        if body then
          body = body:gsub("^%s*set%s+", "")
          local valid = true
          for token in body:gmatch("[^%s;]+") do
            if token ~= "set" and token ~= "setlocal" and token ~= "paste" and token ~= "list" then
              local key, value = token:match("^(tw)=(%-?%d+)$")
              if not key then key, value = token:match("^(textwidth)=(%-?%d+)$") end
              if key and tonumber(value) >= 0 then return tonumber(value) end
              valid = false
            end
          end
          if not valid then break end
        end
      end
      start = at + #marker
    end
  end end
end
local function settings_for(buf)
  local ft, selected = vim.bo[buf].filetype, config.filetypes
  if selected == nil then return merge(merge(defaults, user_config), presets[ft] or {}), presets[ft] ~= nil end
  local entry = type(selected[ft]) == "table" and selected[ft] or nil
  if not entry then for _, name in ipairs(selected) do if name == ft then entry = {} end end end
  if not entry then return nil, false end
  local settings
  if type(selected[ft]) == "table" then
    settings = merge(merge(merge(defaults, user_config), presets[ft] or {}), entry)
  elseif presets[ft] then
    -- deliberate: built-in presets win per field; explicit filetype entries and calls still win.
    settings = merge(merge(defaults, user_config), presets[ft])
  else
    settings = merge(defaults, user_config)
  end
  return settings, presets[ft] ~= nil or entry.conceal ~= nil
end
local function detect(buf, settings)
  local ml = modeline_width(buf)
  if ml and ml > 0 then return "hard", ml elseif ml == 0 then return "soft" end
  local seen = 0
  for first = 0, api.nvim_buf_line_count(buf) - 1, 100 do for _, line in ipairs(api.nvim_buf_get_lines(buf, first, math.min(first + 100, api.nvim_buf_line_count(buf)), false)) do
    if vim.trim(line) ~= "" then seen = seen + 1; if api.nvim_buf_call(buf, function() return vim.fn.strdisplaywidth(line) end) > 130 then return "soft" end; if seen == 20 then return settings.fallback end end
  end end
  return settings.fallback
end
local function validate_enable(opts)
  if type(opts) ~= "table" then error("enable() expects a table") end
  local errors = {}
  for key in pairs(opts) do if not ({ buf=true, mode=true, textwidth=true, conceal=true, mappings=true })[key] then errors[#errors + 1] = "enable has unknown key " .. tostring(key) end end
  if opts.mappings ~= nil then
    if type(opts.mappings) ~= "table" then errors[#errors + 1] = "enable.mappings must be a table" else
      for key in pairs(opts.mappings) do if key ~= "navigation" and key ~= "undo_breaks" then errors[#errors + 1] = "enable.mappings has unknown key " .. tostring(key) end end
      for _, key in ipairs({ "navigation", "undo_breaks" }) do if opts.mappings[key] ~= nil and type(opts.mappings[key]) ~= "boolean" then errors[#errors + 1] = "enable.mappings." .. key .. " must be a boolean" end end
    end
  end
  if opts.mode and opts.mode ~= "hard" and opts.mode ~= "soft" and opts.mode ~= "detect" then errors[#errors + 1] = "enable.mode must be hard, soft, or detect" end
  if opts.textwidth ~= nil then integer(opts.textwidth, "enable.textwidth", errors, 1) end
  if opts.buf ~= nil and (type(opts.buf) ~= "number" or opts.buf % 1 ~= 0) then errors[#errors + 1] = "enable.buf must be an integer" end
  if opts.conceal ~= nil and opts.conceal ~= false then
    if type(opts.conceal) ~= "table" then errors[#errors + 1] = "enable.conceal must be false or a table" else
      for key in pairs(opts.conceal) do if key ~= "level" and key ~= "cursor" then errors[#errors + 1] = "enable.conceal has unknown key " .. tostring(key) end end
      if opts.conceal.level ~= nil then integer(opts.conceal.level, "enable.conceal.level", errors, 0); if type(opts.conceal.level) == "number" and opts.conceal.level > 3 then errors[#errors + 1] = "enable.conceal.level must be <= 3" end end
      if opts.conceal.cursor ~= nil then
        if type(opts.conceal.cursor) ~= "string" or not opts.conceal.cursor:match("^[nvic]*$") then errors[#errors + 1] = "enable.conceal.cursor is invalid"
        else local seen = {}; for mode in opts.conceal.cursor:gmatch(".") do if seen[mode] then errors[#errors + 1] = "enable.conceal.cursor must not contain duplicate modes" end; seen[mode] = true end end
      end
    end
  end
  if #errors > 0 then error("invalid pencil enable options:\n- " .. table.concat(errors, "\n- ")) end
end
local window_options = { "wrap", "linebreak", "breakindent", "conceallevel", "concealcursor" }
local function desired_window(state, key)
  if key == "wrap" or key == "linebreak" or key == "breakindent" then return state.mode == "soft" end
  if not state.conceal then return nil end
  return key == "conceallevel" and state.conceal.level or state.conceal.cursor
end
local function snapshot_window(win)
  local values = {}
  for _, key in ipairs(window_options) do values[key] = vim.wo[win][key] end
  return values
end
local function apply_window(state, win, entering)
  if not api.nvim_win_is_valid(win) then return end
  local owned = state.windows[win]
  if not owned then
    if not entering then return end
    local transition = transition_baseline[win]
    local baseline = transition and transition.values or snapshot_window(win)
    transition_baseline[win] = nil
    owned = {}; state.windows[win] = owned
    for _, key in ipairs(window_options) do
      local desired = desired_window(state, key)
      if desired ~= nil then owned[key] = { old = baseline[key], ours = desired }; vim.wo[win][key] = desired end
    end
    return
  end
  -- A user edit ends ownership until this buffer leaves the window.
  for _, key in ipairs(window_options) do
    local record, desired = owned[key], desired_window(state, key)
    if record and record.user then
      -- Do not reacquire an option the user changed during this activation.
    elseif record then
      if vim.wo[win][key] == record.ours then
        if desired == nil then vim.wo[win][key] = record.old; owned[key] = nil
        else vim.wo[win][key], record.ours = desired, desired end
      else owned[key] = { user = true }
      end
    elseif desired ~= nil then
      owned[key] = { old = vim.wo[win][key], ours = desired }; vim.wo[win][key] = desired
    end
  end
end
local function restore_window(state, win, force)
  local owned = state.windows[win]
  if owned and api.nvim_win_is_valid(win) and (force or api.nvim_win_get_buf(win) == state.buf) then
    for key, record in pairs(owned) do if not record.user and vim.wo[win][key] == record.ours then vim.wo[win][key] = record.old end end
  end
  state.windows[win], state.displayed[win] = nil, nil
  if window_owner[win] == state then window_owner[win] = nil end
end
local function reconcile_buffer(state, mode, width)
  local buf = state.buf
  local desired = { textwidth = mode == "hard" and width or nil, formatoptions = nil }
  local current = vim.bo[buf].formatoptions
  if mode == "hard" then
    desired.formatoptions = current
    for flag in ("tcq"):gmatch(".") do if not desired.formatoptions:find(flag, 1, true) then desired.formatoptions = desired.formatoptions .. flag end end
  end
  state.owned = state.owned or {}
  for _, key in ipairs({ "textwidth", "formatoptions" }) do
    local record = state.owned[key]
    if record and record.user then
      -- Do not reacquire an option the user changed during this activation.
    elseif record then
      local value = vim.bo[buf][key]
      if value == record.ours then
        if desired[key] == nil then vim.bo[buf][key], state.owned[key] = record.old, nil
        else vim.bo[buf][key], record.ours = desired[key], desired[key] end
      else state.owned[key] = { user = true } end
    elseif desired[key] ~= nil then
      state.owned[key] = { old = vim.bo[buf][key], ours = desired[key] }; vim.bo[buf][key] = desired[key]
    end
  end
end
local navigation_specs = {
  { mode="n", lhs="j", rhs="gj" }, { mode="n", lhs="k", rhs="gk" },
  { mode="n", lhs="<Down>", rhs="gj" }, { mode="n", lhs="<Up>", rhs="gk" },
  { mode="n", lhs="0", rhs="g0" }, { mode="n", lhs="$", rhs="g$" },
  { mode="n", lhs="<Home>", rhs="g0" }, { mode="n", lhs="<End>", rhs="g$" },
  { mode="n", lhs="gj", rhs="j" }, { mode="n", lhs="gk", rhs="k" },
  { mode="n", lhs="g0", rhs="0" }, { mode="n", lhs="g$", rhs="$" },
}
local undo_specs = {}
for _, lhs in ipairs({ ".", "!", "?", ",", ";", ":", "<CR>" }) do
  undo_specs[#undo_specs + 1] = { mode="i", lhs=lhs, rhs=lhs .. "<C-G>u" }
end
for _, lhs in ipairs({ "<C-U>", "<C-W>" }) do
  undo_specs[#undo_specs + 1] = { mode="i", lhs=lhs, rhs="<C-G>u" .. lhs }
end
local function mapping_list(state)
  local specs = {}
  if state.settings.mappings.navigation then for _, spec in ipairs(navigation_specs) do specs[#specs + 1] = spec end end
  if state.settings.mappings.undo_breaks then for _, spec in ipairs(undo_specs) do specs[#specs + 1] = spec end end
  return specs
end
local function find_mapping(buf, mode, lhs)
  for _, map in ipairs(api.nvim_buf_get_keymap(buf, mode)) do if map.lhs == lhs then return map end end
  for _, map in ipairs(api.nvim_get_keymap(mode)) do if map.lhs == lhs then return map end end
end
local function mapping_identity(spec)
  return { mode = spec.mode, lhs = spec.lhs, rhs = spec.rhs, buffer = true,
    callback = mapping_callback(spec.rhs), desc = mapping_owner, noremap = true, silent = true,
    expr = false, nowait = false, script = false, replace_keycodes = false }
end
local function mapping_matches(buf, record)
  local map = find_mapping(buf, record.mode, record.lhs)
  if not map or map.buffer ~= buf or map.callback ~= record.callback then return false end
  return true
end
local function warn_mapping_conflict(state, lhs)
  state.mapping_warnings = state.mapping_warnings or {}
  if state.mapping_warnings[lhs] then return end
  state.mapping_warnings[lhs] = true
  vim.notify("Pencil skipped conflicting mapping " .. lhs .. " in buffer " .. state.buf, vim.log.levels.WARN)
end
local function reconcile_mappings(state)
  state.mappings, state.mapping_warnings = state.mappings or {}, state.mapping_warnings or {}
  local wanted = {}
  for _, spec in ipairs(mapping_list(state)) do
    local id = spec.mode .. "\0" .. spec.lhs
    wanted[id] = spec
    local record = state.mappings[id]
    if record and not mapping_matches(state.buf, record) then state.mappings[id] = nil; record = nil end
    if not record then
      if find_mapping(state.buf, spec.mode, spec.lhs) then warn_mapping_conflict(state, spec.lhs)
      else
        local identity = mapping_identity(spec)
        vim.keymap.set(spec.mode, spec.lhs, identity.callback, {
          buffer = state.buf, noremap = identity.noremap, silent = identity.silent, desc = identity.desc,
        })
        state.mappings[id] = identity
        state.mapping_warnings[spec.lhs] = nil
      end
    end
  end
  for id, record in pairs(state.mappings) do
    if not wanted[id] then
      if mapping_matches(state.buf, record) then api.nvim_buf_del_keymap(state.buf, record.mode, record.lhs) end
      state.mappings[id] = nil
    end
  end
end
local function cleanup(state, force)
  if api.nvim_buf_is_valid(state.buf) then
    for _, record in pairs(state.mappings or {}) do if mapping_matches(state.buf, record) then api.nvim_buf_del_keymap(state.buf, record.mode, record.lhs) end end
    state.mappings, state.mapping_warnings = {}, {}
  end
  if api.nvim_buf_is_valid(state.buf) then
    for key, record in pairs(state.owned or {}) do if not record.user and vim.bo[state.buf][key] == record.ours then vim.bo[state.buf][key] = record.old end end
  end
  for win in pairs(state.windows) do restore_window(state, win, force) end
end
function M.setup(value)
  local ok, errors = validate(value)
  if not ok then error("invalid pencil configuration:\n- " .. table.concat(errors, "\n- ")) end
  config, user_config, configured = merge(defaults, value), vim.deepcopy(value), true
end
function M.enable(opts)
  if opts == nil then opts = {} end; validate_enable(opts); local buf = target(opts)
  local previous = active[buf]
  local settings, supported = settings_for(buf); settings = settings or merge({}, config)
  settings = merge(settings, opts)
  local ml, requested = modeline_width(buf), settings.mode
  local mode = requested == "detect" and detect(buf, settings) or requested
  local width = mode == "hard" and (opts.textwidth or (ml and ml > 0 and ml) or (vim.bo[buf].textwidth > 0 and vim.bo[buf].textwidth) or settings.textwidth) or nil
  if mode == "hard" and (type(width) ~= "number" or width < 1) then error("hard mode requires a positive textwidth") end
  local state = previous or { windows={}, displayed={}, owned={} }
  state.displayed = state.displayed or {}
  state.buf = buf
  state.mode, state.width, state.settings = mode, width, settings
  local conceal = opts.conceal ~= nil and opts.conceal or settings.conceal
  state.conceal = (conceal ~= false and (supported or opts.conceal ~= nil)) and conceal or nil
  if state.conceal then state.conceal = merge({ level=2, cursor="" }, state.conceal) end
  reconcile_buffer(state, mode, width)
  reconcile_mappings(state)
  for _, win in ipairs(api.nvim_list_wins()) do if api.nvim_win_get_buf(win) == buf then apply_window(state, win, not previous or not state.windows[win]); state.displayed[win] = buf; window_owner[win] = state end end
  active[buf], disabled[buf] = state, nil
end
function M.disable(opts)
  local buf = target(opts); local state = active[buf]; if not state then disabled[buf] = true; return end
  cleanup(state)
  active[buf], disabled[buf] = nil, true
end
function M.toggle(opts) local buf = target(opts); if active[buf] then M.disable({buf=buf}) else M.enable(opts or {buf=buf}) end end
function M.mode(opts) local buf=target(opts); return active[buf] and active[buf].mode or (disabled[buf] and "off" or nil) end
function M.status(opts) local state=active[target(opts)]; return state and (state.settings.status[state.mode] or "") or "" end

local function command(args)
  local action=args.fargs[1]; if not action then return M.enable() end
  local actions={enable=M.enable, disable=M.disable, toggle=M.toggle, hard=function() M.enable({mode="hard"}) end, soft=function() M.enable({mode="soft"}) end, detect=function() M.enable({mode="detect"}) end}
  if not actions[action] then error("Pencil: unknown action: " .. action) end; actions[action]()
end
function M._setup_autocmds()
  if installed then return end; installed=true; local group=api.nvim_create_augroup("Pencil", {clear=true})
  api.nvim_create_user_command("Pencil", command, {nargs="?", complete=function() return {"enable","disable","toggle","hard","soft","detect"} end})
  for name, action in pairs({HardPencil="hard",SoftPencil="soft",NoPencil="disable",PencilOff="disable",TogglePencil="toggle",PencilToggle="toggle"}) do api.nvim_create_user_command(name,function() command({fargs={action}}) end,{}) end
  api.nvim_create_autocmd("FileType",{group=group,callback=function(a) if configured and settings_for(a.buf) then pcall(M.enable,{buf=a.buf}) end end})
  local pending, scheduled = {}, false
  local function reconcile()
    scheduled = false
    for win in pairs(pending) do
      pending[win] = nil
      local old = window_owner[win]
      if old then
        local current = api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) or nil
        if current ~= old.buf then restore_window(old, win) end
      end
      if api.nvim_win_is_valid(win) then
        local current_buf = api.nvim_win_get_buf(win)
        local state = active[current_buf]
        if state then
          if not state.windows[win] then apply_window(state, win, true) end
          state.displayed[win] = state.buf; window_owner[win] = state
        end
      end
    end
  end
  local function queue(win)
    win = win or api.nvim_get_current_win()
    pending[win] = true
    if not scheduled then scheduled = true; vim.schedule(reconcile) end
  end
  api.nvim_create_autocmd({"BufWinEnter", "BufWinLeave", "BufEnter", "BufLeave", "WinEnter", "WinClosed"},{group=group,callback=function(a)
    local win = a.win or api.nvim_get_current_win()
    local owner = window_owner[win]
    if a.event == "BufLeave" or a.event == "BufWinLeave" then
      if owner and owner.buf == a.buf then
        local values = {}
        for key, record in pairs(owner.windows[win] or {}) do
          values[key] = record.user and vim.wo[win][key] or record.old
        end
        pending_leave[a.buf] = pending_leave[a.buf] or {}
        pending_leave[a.buf][win] = values
        vim.schedule(function()
          local windows = pending_leave[a.buf]
          if active[a.buf] and windows then windows[win] = nil; if next(windows) == nil then pending_leave[a.buf] = nil end end
        end)
        restore_window(owner, win, true)
      end
      if api.nvim_win_is_valid(win) then transition_baseline[win] = { buf = a.buf, values = snapshot_window(win) } end
    end
    if a.event == "WinClosed" then transition_baseline[win] = nil end
    queue(win)
  end})
  api.nvim_create_autocmd("BufUnload",{group=group,callback=function(a)
    local state = active[a.buf]
    if state then active[a.buf] = nil; cleanup(state, true) end
    disabled[a.buf] = nil
    local leaving = pending_leave[a.buf]
    pending_leave[a.buf] = nil
    if leaving then for win, values in pairs(leaving) do vim.schedule(function()
      if api.nvim_win_is_valid(win) and not active[api.nvim_win_get_buf(win)] then
        for key, value in pairs(values) do vim.wo[win][key] = value end
      end
    end) end end
    for win, owner in pairs(window_owner) do if owner == state then window_owner[win] = nil end end
  end})
  api.nvim_create_autocmd("BufWipeout", { group=group, callback=function(a) disabled[a.buf] = nil end })
end
M._setup_autocmds()
return M
