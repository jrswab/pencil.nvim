local M, api = {}, vim.api
local version = vim.version()
if version.major == 0 and version.minor < 10 then error("pencil.nvim requires Neovim 0.10 or newer") end

local defaults = { mode = "detect", fallback = "soft", textwidth = 80,
  conceal = { level = 2, cursor = "" },
  status = { hard = "H", auto = "A", soft = "S", off = "" } }
local presets = {
  gitcommit = { mode = "hard", textwidth = 72 }, mail = { mode = "hard", textwidth = 72 },
  markdown = { mode = "detect", fallback = "soft" }, text = { mode = "detect", fallback = "soft" },
  rst = { mode = "detect", fallback = "hard", textwidth = 79 }, tex = { mode = "detect", fallback = "hard", textwidth = 79 },
  asciidoc = { mode = "detect", fallback = "hard", textwidth = 79 }, textile = { mode = "detect", fallback = "soft" }, }
local config, user_config, configured = vim.deepcopy(defaults), {}, false
local active, disabled, installed = {}, {}, false

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
  known(value, { mode=true, fallback=true, textwidth=true, conceal=true, status=true, filetypes=true }, "configuration")
  mode(value.mode, "mode"); fallback(value.fallback, "fallback"); width(value.textwidth, "textwidth")
  conceal(value.conceal, "conceal")
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
          known(entry, { mode=true, fallback=true, textwidth=true, conceal=true }, "filetypes." .. name)
          mode(entry.mode, "filetypes." .. name .. ".mode"); fallback(entry.fallback, "filetypes." .. name .. ".fallback"); width(entry.textwidth, "filetypes." .. name .. ".textwidth"); conceal(entry.conceal, "filetypes." .. name .. ".conceal")
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
    if vim.trim(line) ~= "" then seen = seen + 1; if vim.fn.strdisplaywidth(line) > 130 then return "soft" end; if seen == 20 then return settings.fallback end end
  end end
  return settings.fallback
end
local function validate_enable(opts)
  if type(opts) ~= "table" then error("enable() expects a table") end
  local errors = {}
  for key in pairs(opts) do if not ({ buf=true, mode=true, textwidth=true, conceal=true })[key] then errors[#errors + 1] = "enable has unknown key " .. tostring(key) end end
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
local function capture(state, win)
  if api.nvim_win_is_valid(win) and not state.windows[win] then state.windows[win] = { wrap=vim.wo[win].wrap, linebreak=vim.wo[win].linebreak, breakindent=vim.wo[win].breakindent, conceallevel=vim.wo[win].conceallevel, concealcursor=vim.wo[win].concealcursor } end
end
local function apply_window(state, win)
  if not api.nvim_win_is_valid(win) then return end; capture(state, win)
  vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].breakindent = state.mode == "soft", state.mode == "soft", state.mode == "soft"
  if state.conceal then vim.wo[win].conceallevel, vim.wo[win].concealcursor = state.conceal.level, state.conceal.cursor end
end
local function restore_window(state, win, force)
  local old = state.windows[win]; if not old or not api.nvim_win_is_valid(win) then state.windows[win] = nil; state.displayed[win] = nil; return end
  for _, key in ipairs({ "wrap", "linebreak", "breakindent" }) do if force or vim.wo[win][key] == state.owned[key] then vim.wo[win][key] = old[key] end end
  for key, option in pairs({ level = "conceallevel", cursor = "concealcursor" }) do
    if state.owned[option] ~= nil and (force or vim.wo[win][option] == state.owned[option]) then vim.wo[win][option] = old[option] end
  end
  -- deliberate: keep one baseline per window for the active buffer; dropping it on
  -- leave would capture Pencil's presentation again if reconciliation is delayed.
  state.displayed[win] = nil
end
local function cleanup(state, force)
  if api.nvim_buf_is_valid(state.buf) then
    if vim.bo[state.buf].textwidth == state.owned.textwidth then vim.bo[state.buf].textwidth = state.old.textwidth end
    local formatoptions = vim.bo[state.buf].formatoptions
    for flag in state.owned_flags:gmatch(".") do if not state.old.formatoptions:find(flag, 1, true) and formatoptions:find(flag, 1, true) then formatoptions = formatoptions:gsub(flag, "") end end
    vim.bo[state.buf].formatoptions = formatoptions
  end
  for win in pairs(state.windows) do
    restore_window(state, win, force)
    state.windows[win] = nil
  end
end
function M.setup(value)
  local ok, errors = validate(value)
  if not ok then error("invalid pencil configuration:\n- " .. table.concat(errors, "\n- ")) end
  config, user_config, configured = merge(defaults, value), vim.deepcopy(value), true
end
function M.enable(opts)
  if opts == nil then opts = {} end; validate_enable(opts); local buf = target(opts)
  local previous = active[buf]
  if previous then cleanup(previous) end
  local settings, supported = settings_for(buf); settings = settings or merge({}, config)
  settings = merge(settings, opts)
  local ml, requested = modeline_width(buf), settings.mode
  local mode = requested == "detect" and detect(buf, settings) or requested
  local width = mode == "hard" and (opts.textwidth or (ml and ml > 0 and ml) or (vim.bo[buf].textwidth > 0 and vim.bo[buf].textwidth) or settings.textwidth) or nil
  if mode == "hard" and (type(width) ~= "number" or width < 1) then error("hard mode requires a positive textwidth") end
  local state = previous or { old={ textwidth=vim.bo[buf].textwidth, formatoptions=vim.bo[buf].formatoptions }, windows={}, displayed={}, owned={} }
  state.displayed = state.displayed or {}
  state.buf = buf
  state.mode, state.width, state.settings = mode, width, settings
  local conceal = opts.conceal ~= nil and opts.conceal or settings.conceal
  state.conceal = (conceal ~= false and (supported or opts.conceal ~= nil)) and conceal or nil
  local current_textwidth = vim.bo[buf].textwidth
  if mode == "hard" then
    vim.bo[buf].textwidth = width
  elseif not previous or current_textwidth == previous.owned.textwidth then
    vim.bo[buf].textwidth = state.old.textwidth
  end
  local fo, owned = vim.bo[buf].formatoptions, state.owned_flags or ""
  if mode == "hard" then for flag in ("tcq"):gmatch(".") do if not fo:find(flag, 1, true) then fo, owned = fo .. flag, owned .. flag end end elseif not previous or fo == previous.owned.formatoptions then for flag in owned:gmatch(".") do fo = fo:gsub(flag, "") end; owned = "" end
  vim.bo[buf].formatoptions, state.owned_flags = fo, owned
  state.owned.textwidth, state.owned.formatoptions = vim.bo[buf].textwidth, fo
  state.owned.wrap, state.owned.linebreak, state.owned.breakindent = mode == "soft", mode == "soft", mode == "soft"
  if state.conceal then state.conceal = merge({ level=2, cursor="" }, state.conceal) end
  state.owned.conceallevel, state.owned.concealcursor = state.conceal and state.conceal.level or nil, state.conceal and state.conceal.cursor or nil
  for _, win in ipairs(api.nvim_list_wins()) do if api.nvim_win_get_buf(win) == buf then apply_window(state, win); state.displayed[win] = buf end end
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
  local reconcile
  reconcile = function()
    local valid = {}
    for _, win in ipairs(api.nvim_list_wins()) do
      valid[win] = true
      local buf = api.nvim_win_get_buf(win)
      for _, state in pairs(active) do
        if state.displayed[win] and state.displayed[win] ~= buf then restore_window(state, win) end
      end
      local state = active[buf]
      if state then apply_window(state, win); state.displayed[win] = buf end
    end
    for _, state in pairs(active) do
      for win in pairs(state.windows) do
        if not valid[win] then restore_window(state, win) end
      end
    end
  end
  api.nvim_create_autocmd({"BufWinEnter", "BufWinLeave", "BufEnter", "BufLeave", "WinEnter", "WinClosed"},{group=group,callback=function() vim.schedule(reconcile) end})
  api.nvim_create_autocmd("BufWipeout",{group=group,callback=function(a)
    local state = active[a.buf]
    if not state or state.pending_cleanup then return end
    -- deliberate: BufWipeout can reinitialize window options before this callback;
    -- retain the state until the scheduled forced restoration has run.
    state.pending_cleanup = true
    vim.schedule(function()
      vim.schedule(function()
        if active[a.buf] ~= state then return end
        cleanup(state, true)
        active[a.buf], disabled[a.buf] = nil, nil
        vim.schedule(reconcile)
      end)
    end)
  end})
end
M._setup_autocmds()
return M
