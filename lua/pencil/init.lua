local M, api = {}, vim.api
local classification = require("pencil.classification")
local function version_error(version)
  if version.major == 0 and version.minor < 10 then return "pencil.nvim requires Neovim 0.10 or newer" end
end
local version = vim.version()
if version_error(version) then error(version_error(version)) end

local defaults = { mode = "detect", fallback = "soft", textwidth = 80, autoformat = true,
  conceal = { level = 2, cursor = "" }, mappings = { navigation = true, undo_breaks = true },
  status = { hard = "H", auto = "A", soft = "S", off = "" } }
local presets = {
  gitcommit = { mode = "hard", textwidth = 72 }, mail = { mode = "hard", textwidth = 72 },
  markdown = { mode = "detect", fallback = "soft" }, text = { mode = "detect", fallback = "soft" },
  rst = { mode = "detect", fallback = "hard", textwidth = 79 }, tex = { mode = "detect", fallback = "hard", textwidth = 79 },
  asciidoc = { mode = "detect", fallback = "hard", textwidth = 79 }, textile = { mode = "detect", fallback = "soft" }, }
local structured_filetypes = { markdown=true, rst=true, tex=true, asciidoc=true, textile=true }
local plain_filetypes = { text=true, gitcommit=true, mail=true }
local config, user_config, configured = vim.deepcopy(defaults), {}, false
local active, disabled, installed = {}, {}, false
local formatoptions_owned, formatoptions_write, formatoptions_value, same_formatoptions
local window_owner, transition_baseline, pending_leave = {}, {}, {}
local function ownership_token()
  local file = io.open("/dev/urandom", "rb")
  local entropy = file and file:read(32) or tostring(vim.loop.hrtime())
  if file then file:close() end
  -- deliberate: hex encoding keeps /dev/urandom entropy textual for Neovim 0.10 sha256.
  return vim.fn.sha256((entropy:gsub(".", function(byte) return string.format("%02x", byte:byte()) end)) .. tostring({})):sub(1, 32)
end
local mapping_owner = "pencil.nvim:owned-mapping:v1:" .. ownership_token()

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
  known(value, { mode=true, fallback=true, textwidth=true, autoformat=true, conceal=true, mappings=true, status=true, filetypes=true }, "configuration")
  mode(value.mode, "mode"); fallback(value.fallback, "fallback"); width(value.textwidth, "textwidth")
  if value.autoformat ~= nil and type(value.autoformat) ~= "boolean" then errors[#errors + 1] = "autoformat must be a boolean" end
  mappings(value.mappings, "mappings"); conceal(value.conceal, "conceal")
  if value.status ~= nil then
    if type(value.status) ~= "table" then errors[#errors + 1] = "status must be a table" else
      known(value.status, { hard=true, auto=true, soft=true, off=true }, "status")
      for _, k in ipairs({ "hard", "auto", "soft", "off" }) do if value.status[k] ~= nil and type(value.status[k]) ~= "string" then errors[#errors + 1] = "status." .. k .. " must be a string" end end
    end
  end
  if value.filetypes ~= nil then
    if type(value.filetypes) ~= "table" then errors[#errors + 1] = "filetypes must be a list or table" else
      local has_list, has_keyed = false, false
      for k in pairs(value.filetypes) do
        if type(k) == "number" then has_list = true elseif type(k) == "string" then has_keyed = true end
      end
      if has_list and has_keyed then errors[#errors + 1] = "filetypes cannot mix list and keyed declarations" end
      local max = 0
      for k in pairs(value.filetypes) do
        if type(k) == "number" then
          if k <= 0 or k % 1 ~= 0 then errors[#errors + 1] = "filetypes list keys must be positive integers" else max = math.max(max, k) end
        elseif type(k) ~= "string" then errors[#errors + 1] = "filetypes keys must be strings or list indices" end
      end
      local list_names = {}
      for i = 1, max do
        if value.filetypes[i] == nil then errors[#errors + 1] = "filetypes list must not be sparse"
        elseif type(value.filetypes[i]) ~= "string" then errors[#errors + 1] = "filetypes list entries must be strings"
        elseif value.filetypes[i] == "" then errors[#errors + 1] = "filetypes list entries must be nonempty"
        elseif list_names[value.filetypes[i]] then errors[#errors + 1] = "filetypes list contains duplicate " .. value.filetypes[i]
        else list_names[value.filetypes[i]] = true end
      end
      for name, entry in pairs(value.filetypes) do if type(name) == "string" then
        if type(entry) ~= "table" then errors[#errors + 1] = "filetypes." .. name .. " must be a table" else
          known(entry, { mode=true, fallback=true, textwidth=true, autoformat=true, conceal=true, mappings=true, format_safety=true, classifier=true }, "filetypes." .. name)
          mode(entry.mode, "filetypes." .. name .. ".mode"); fallback(entry.fallback, "filetypes." .. name .. ".fallback"); width(entry.textwidth, "filetypes." .. name .. ".textwidth"); if entry.autoformat ~= nil and type(entry.autoformat) ~= "boolean" then errors[#errors + 1] = "filetypes." .. name .. ".autoformat must be a boolean" end; mappings(entry.mappings, "filetypes." .. name .. ".mappings"); conceal(entry.conceal, "filetypes." .. name .. ".conceal")
          if name == "" then errors[#errors + 1] = "filetypes name must be nonempty" end
          if entry.format_safety ~= nil and entry.format_safety ~= "plain" then errors[#errors + 1] = "filetypes." .. name .. ".format_safety must be plain" end
          if entry.classifier ~= nil and type(entry.classifier) ~= "function" then errors[#errors + 1] = "filetypes." .. name .. ".classifier must be a function" end
          if entry.format_safety ~= nil and entry.classifier ~= nil then errors[#errors + 1] = "filetypes." .. name .. " cannot define both format_safety and classifier" end
        end
      end end
    end
  end
  return #errors == 0, errors
end
local function target(opts)
  local buf = opts and opts.buf or api.nvim_get_current_buf()
  if type(buf) ~= "number" or buf % 1 ~= 0 or not api.nvim_buf_is_valid(buf) then error("invalid buffer " .. tostring(buf)) end
  return buf
end
local function validate_buf_opts(opts, name)
  if opts == nil then return {} end
  if type(opts) ~= "table" then error(name .. " options must be a table") end
  for key in pairs(opts) do if key ~= "buf" then error(name .. " has unknown key " .. tostring(key)) end end
  if opts.buf ~= nil and (type(opts.buf) ~= "number" or opts.buf % 1 ~= 0) then error(name .. ".buf must be an integer") end
  return opts
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
  local keyed_entry = type(selected) == "table" and type(selected[ft]) == "table"
  local entry = keyed_entry and selected[ft] or {}
  local use_preset = presets[ft] ~= nil
  local preset = use_preset and presets[ft] or {}
  local settings = merge(merge(merge(defaults, user_config), preset), entry)
  local safety = entry.format_safety or (preset.mode and (plain_filetypes[ft] and "plain" or "structured") or "unknown")
  local automatic = selected == nil
  if type(selected) == "table" then
    if type(selected[1]) == "string" then automatic = vim.tbl_contains(selected, ft)
    else automatic = selected[ft] ~= nil end
  end
  -- Explicit list entries and keyed policies inherit configured/default concealment;
  -- conceal=false remains the opt-out.
  local list_entry = type(selected) == "table" and type(selected[1]) == "string" and automatic
  return settings, use_preset or keyed_entry or list_entry or entry.conceal ~= nil, { safety = safety, classifier = entry.classifier, filetype = ft }, automatic
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
  for key in pairs(opts) do if not ({ buf=true, mode=true, textwidth=true, autoformat=true, conceal=true, mappings=true })[key] then errors[#errors + 1] = "enable has unknown key " .. tostring(key) end end
  if opts.mappings ~= nil then
    if type(opts.mappings) ~= "table" then errors[#errors + 1] = "enable.mappings must be a table" else
      for key in pairs(opts.mappings) do if key ~= "navigation" and key ~= "undo_breaks" then errors[#errors + 1] = "enable.mappings has unknown key " .. tostring(key) end end
      for _, key in ipairs({ "navigation", "undo_breaks" }) do if opts.mappings[key] ~= nil and type(opts.mappings[key]) ~= "boolean" then errors[#errors + 1] = "enable.mappings." .. key .. " must be a boolean" end end
    end
  end
  if opts.mode and opts.mode ~= "hard" and opts.mode ~= "soft" and opts.mode ~= "detect" then errors[#errors + 1] = "enable.mode must be hard, soft, or detect" end
  if opts.autoformat ~= nil and type(opts.autoformat) ~= "boolean" then errors[#errors + 1] = "enable.autoformat must be a boolean" end
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
local window_options = { "wrap", "linebreak", "breakindent", "conceallevel", "concealcursor", "statuscolumn" }
local function soft_statuscolumn(state, win)
  local width = api.nvim_win_get_width(win)
  local number = vim.wo[win].number or vim.wo[win].relativenumber
  local digits = #tostring(api.nvim_buf_line_count(state.buf))
  local gutter = (vim.wo[win].signcolumn == "no" and 0 or 2) + (tonumber(vim.wo[win].foldcolumn) or 0)
  if number then gutter = gutter + digits + 1 end
  local pad = math.max(0, width - state.width - gutter)
  local previous = state.windows[win] and state.windows[win].statuscolumn
  local column = previous and previous.old or vim.wo[win].statuscolumn
  if column == "" then
    column = "%s%C"
    if number then column = column .. "%=%{v:relnum == 0 ? v:lnum : v:relnum} " end
  end
  return string.rep(" ", pad) .. column
end
local function desired_window(state, key, win)
  if key == "wrap" or key == "linebreak" or key == "breakindent" then return state.mode == "soft" end
  if key == "statuscolumn" then return state.mode == "soft" and soft_statuscolumn(state, win) or nil end
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
      local desired = desired_window(state, key, win)
      if desired ~= nil then owned[key] = { old = baseline[key], ours = desired }; vim.wo[win][key] = desired end
    end
    return
  end
  -- A user edit ends ownership until this buffer leaves the window.
  for _, key in ipairs(window_options) do
    local record, desired = owned[key], desired_window(state, key, win)
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
local protected_treesitter_rules = {
  markdown={exact={"fenced_code_block","indented_code_block","code_fence","front_matter","table","html_block","html_tag","link_reference_definition","math"},prefix={"embedded","raw"}},
  rst={exact={"directive","directive_argument","directive_option","literal_block","doctest_block","comment","target","substitution_definition","table","field_list","raw","parsed_literal"}},
  tex={exact={"comment","math","inline_formula","displayed_equation","verbatim","raw","command","label","reference","cite"},prefix={"preamble","control"}},
  asciidoc={exact={"source_block","listing_block","literal_block","example_block","sidebar","quote_block","table","attribute_entry","attribute_reference","comment","passthrough","block_title","block_id"},prefix={"block_option"}},
  textile={exact={"code_block","pre_block","table","html","comment","block_attributes","raw","passthrough"}},
}
local protected_syntax_rules = {
  markdown={exact={"markdown_code","markdown_table","markdown_front_matter","markdown_link_definition","markdown_html","markdown_math"},prefix={"markdown_code","markdown_table","markdown_front_matter","markdown_link_definition","markdown_html","markdown_math"}},
  rst={exact={"rst_directive","rst_literal_block","rst_doctest_block","rst_comment","rst_hyperlink_target","rst_substitution_definition","rst_table","rst_field_list"},prefix={"rst_raw_block"}},
  tex={exact={"tex_comment","tex_math","tex_math_zone","tex_verb","tex_verbatim","tex_listing","tex_minted","tex_cmd","tex_section","tex_label","tex_ref"},prefix={"tex_math_zone"}},
  asciidoc={exact={"asciidoc_block","asciidoc_listing_block","asciidoc_literal_block","asciidoc_table","asciidoc_attribute","asciidoc_comment","asciidoc_passthrough"},prefix={"asciidoc_delimiter","asciidoc_title","asciidoc_option"}},
  textile={exact={"textile_code","textile_pre","textile_table","textile_html","textile_comment","textile_block"},prefix={"textile_delimiter","textile_attribute"}},
}
local normalize_structure_name = classification.normalize
local function match_protected_name(ft, name, rules)
  local rule = rules[ft]; if not rule then return false end
  name = normalize_structure_name(name)
  for _, exact in ipairs(rule.exact or {}) do if name == exact then return true end end
  for _, prefix in ipairs(rule.prefix or {}) do
    local suffix = name:sub(#prefix + 1)
    if name == prefix or suffix:sub(1, 1) == "_" or suffix:match("^%d+[a-z]") then return true end
  end
  return false
end
local function utf8_boundary(line, col)
  return type(col) == "number" and col >= 0 and col <= #line and (col == 0 or col == #line or line:byte(col + 1) < 128 or line:byte(col + 1) >= 192)
end
local function insertion_probes(buf, win)
  if not api.nvim_buf_is_valid(buf) or not api.nvim_win_is_valid(win) then return nil end
  local pos = api.nvim_win_get_cursor(win); local row, col = pos[1] - 1, pos[2]
  -- deliberate: a stale cursor/window event is unusable evidence, not a reason to read outside the buffer.
  if row < 0 or row >= api.nvim_buf_line_count(buf) then return nil end
  local lines = api.nvim_buf_get_lines(buf, row, row + 1, false); local line = lines[1]
  if not line or not utf8_boundary(line, col) then return nil end
  local probes = {{row=row, start=col, finish=col, point=true}}
  if col < #line then
    local finish = col + 1
    while finish < #line and line:byte(finish + 1) >= 128 and line:byte(finish + 1) < 192 do finish = finish + 1 end
    probes[#probes + 1] = {row=row, start=col, finish=finish}
  end
  if col > 0 then
    local start = col - 1
    while start > 0 and line:byte(start + 1) >= 128 and line:byte(start + 1) < 192 do start = start - 1 end
    probes[#probes + 1] = {row=row, start=start, finish=col}
  end
  return probes
end
local combine_evidence = classification.combine
local tex_environment_from_text = classification.tex_environment
local tex_environment_result = classification.tex_environment_result

local function syntax_stack(buf, probe)
  return api.nvim_buf_call(buf, function()
    local ids = vim.fn.synstack(probe.row + 1, math.max(1, probe.start + 1))
    local names = {}
    for _, id in ipairs(ids) do
      local raw = vim.fn.synIDattr(id, "name")
      local translated = vim.fn.synIDattr(vim.fn.synIDtrans(id), "name")
      names[#names + 1] = raw
      if translated ~= raw then names[#names + 1] = translated end
    end
    return names
  end)
end
local function syntax_path(buf, ft, probes)
  if vim.bo[buf].syntax ~= ft or vim.b[buf].current_syntax == nil or vim.b[buf].current_syntax == "" then return "unknown" end
  local activity = false
  local rows = {probes[1].row}
  -- deliberate: inspect at most three lines per direction, skipping blank lines
  -- only inside that fixed bound; this proves activity without scanning the buffer.
  for direction = -1, 1, 2 do
    for distance = 1, 3 do
      local row = probes[1].row + direction * distance
      if row < 0 or row >= api.nvim_buf_line_count(buf) then break end
      local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
      if vim.trim(line) ~= "" then rows[#rows + 1] = row; break end
    end
  end
  for _, row in ipairs(rows) do
    local ok, stack = pcall(function() return api.nvim_buf_call(buf, function() return vim.fn.synstack(row + 1, 1) end) end)
    if not ok or type(stack) ~= "table" then return "unknown" end
    if type(stack) ~= "table" or #stack == 0 then
      -- deliberate: require one bounded nonempty stack to distinguish active syntax
      -- from a disabled definition; later empty insertion stacks still mean prose.
      goto next_activity_row
    end
    activity = true
    ::next_activity_row::
  end
  if not activity then return "unknown" end
  local result
  for _, probe in ipairs(probes) do
    local ok, stack = pcall(syntax_stack, buf, probe); if not ok or type(stack) ~= "table" then return "unknown" end
    local protected = false
    for _, name in ipairs(stack) do
      if match_protected_name(ft, name, protected_syntax_rules) then protected = true end
    end
    local evidence = protected and "protected" or "prose"
    if ft == "tex" and not protected then
      -- deliberate: syntax fallback only matches a complete environment on the
      -- current line; multiline ownership requires an exact Treesitter node.
      local line = api.nvim_buf_get_lines(buf, probe.row, probe.row + 1, false)[1] or ""
      local name = tex_environment_from_text(line)
      if name then evidence = tex_environment_result(name)
      elseif line:find("\\begin") or line:find("\\end") then evidence = "unknown" end
    end
    if result and result ~= evidence then return "unknown" end
    result = evidence
  end
  return result or "unknown"
end
local function treesitter_path(buf, ft, probes)
  -- deliberate: highlighter.active is the supported existing-parser state; never create or reacquire a parser here.
  local active_highlighter = vim.treesitter.highlighter and vim.treesitter.highlighter.active
  local tree = active_highlighter and active_highlighter[buf] and active_highlighter[buf].tree
  if not tree then return "unknown" end
  -- deliberate: inspect only the highlighter's existing current tree; reacquiring a parser
  -- would parse synchronously and violate the bounded, fail-closed contract.
  local ok_trees, trees = pcall(tree.trees, tree); if not ok_trees or type(trees) ~= "table" or not trees[1] then return "unknown" end
  -- The active highlighter stores a parser in `tree`; validate the current tree,
  -- not the parser wrapper (whose validity flag is false while regions are settling).
  for _, current in ipairs(trees) do
    if type(current.is_valid) == "function" then
      local ok_valid, valid = pcall(current.is_valid, current)
      if not ok_valid or valid == false then return "unknown" end
    end
  end
  local ok_root, root = pcall(trees[1].root, trees[1]); if not ok_root or not root then return "unknown" end
  local ok_root_range, rsr, rsc, rer, rec = pcall(root.range, root)
  if not ok_root_range then return "unknown" end
  for _, probe in ipairs(probes) do
    if rsr > probe.row or rer < probe.row or (rsr == probe.row and rsc > probe.start) or (rer == probe.row and rec < probe.finish) then return "unknown" end
  end
  local result
  local records = {}
  local protected = {}
  for _, probe in ipairs(probes) do
    local ok_node, node = pcall(root.named_descendant_for_range, root, probe.row, probe.start, probe.row, probe.finish)
    if not ok_node or not node then return "unknown" end
    local evidence = "prose"; local probe_protected; local depth = 0
    while node and depth < 32 do
      local ok_range, sr, sc, er, ec = pcall(node.range, node)
      if not ok_range or sr > probe.row or er < probe.row or (sr == probe.row and sc > probe.start) or (er == probe.row and ec < probe.finish) then return "unknown" end
      local ok_type, name = pcall(node.type, node); if not ok_type or not name then return "unknown" end
      if name == "ERROR" then return "unknown" end
      local normalized = normalize_structure_name(name)
      local generic = {document=true, paragraph=true, text=true, heading=true, atx_heading=true, setext_heading=true, section=true, list=true, item=true, block_quote=true, emphasis=true, strong=true, link=true, inline=true, root=true}
      local heading_marker = normalized:match("^atx_h%d_marker$") or normalized:match("^setext_h%d_underline$")
      if not generic[normalized] and not heading_marker and not match_protected_name(ft, name, protected_treesitter_rules) and not (ft == "tex" and normalized == "environment") then return "unknown" end
      if match_protected_name(ft, name, protected_treesitter_rules) then
        probe_protected = node
        evidence = "protected"
      elseif ft == "tex" and normalize_structure_name(name) == "environment" then
        local ok_node_range, sr, sc, er, ec = pcall(node.range, node)
        if not ok_node_range or er < sr or (er == sr and ec < sc) then return "unknown" end
        -- deliberate: reject oversized nodes before allocation; bounded extraction is enough for classification.
        if er - sr > 65536 or (er - sr == 65536 and ec > sc) then return "unknown" end
        local ok_text, chunks = pcall(api.nvim_buf_get_text, buf, sr, sc, er, ec, {})
        if not ok_text or type(chunks) ~= "table" then return "unknown" end
        local text = table.concat(chunks, "\n")
        if #text > 65536 then return "unknown" end
        local env_name = tex_environment_from_text(text)
        if not env_name then return "unknown" end
        local env_result = tex_environment_result(env_name)
        if env_result == "protected" then probe_protected = node; evidence = "protected"
        elseif env_result == "unknown" then return "unknown" end
      end
      local ok_parent, parent = pcall(node.parent, node); if not ok_parent then return "unknown" end
      node, depth = parent, depth + 1
    end
    if depth >= 32 then return "unknown" end
    records[#records + 1] = { result = evidence, protected = probe_protected }
    if probe_protected then
      local ok_range, psr, psc, per, pec = pcall(probe_protected.range, probe_protected)
      if not ok_range then return "unknown" end
      protected[#protected + 1] = { node = probe_protected, bounds = {psr, psc, per, pec} }
    end
  end
  -- Reduce after collecting all probes so protected containment does not depend on order.
  local first_protected = protected[1]
  local evidence_records = {}
  for index, item in ipairs(records) do
    if item.result == "prose" and first_protected then
      local b = first_protected.bounds
      -- Find this item's probe by its stable insertion order.
      local probe = probes[index]
      local contained = b[1] < probe.row or (b[1] == probe.row and b[2] <= probe.start)
      contained = contained and (b[3] > probe.row or (b[3] == probe.row and b[4] >= probe.finish))
      if contained then item.result = "protected" else return "unknown" end
    end
    if item.result == "protected" and first_protected and item.protected and item.protected ~= first_protected.node then return "unknown" end
    evidence_records[index] = item.result
    if result and result ~= item.result then return "unknown" end
    result = item.result
  end
  -- Keep the reduction rule in the production path; the helper is also the pure
  -- representation of fail-closed Treesitter evidence.
  return classification.reduce_treesitter(evidence_records)
end
local function classify_location(state, win)
  local buf, ft = state.buf, vim.bo[state.buf].filetype
  if state.policy.safety == "plain" then return "prose" end
  if state.policy.safety == "custom" then
    if not win or not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf then return "unknown" end
    local pos = api.nvim_win_get_cursor(win)
    local context = { buf=buf, win=win, row=pos[1] - 1, col=pos[2], filetype=state.policy.filetype or ft }
    local ok, result = pcall(state.policy.classifier, context)
    if ok and (result == "prose" or result == "protected" or result == "unknown") then return result end
    return "unknown"
  end
  if state.policy.safety ~= "structured" then return "unknown" end
  local probes = insertion_probes(buf, win); if not probes then return "unknown" end
  local ok_ts, ts = pcall(treesitter_path, buf, ft, probes); if not ok_ts then ts = "unknown" end
  local ok_syn, syn = pcall(syntax_path, buf, ft, probes); if not ok_syn then syn = "unknown" end
  return combine_evidence(ts, syn)
end
local structural_delimiter_bytes = {
  markdown={0x60,0x3c,0x5b,0x21}, rst={0x3a,0x2e,0x5b,0x5f}, tex={0x5c,0x25,0x24,0x7b,0x7d},
  asciidoc={0x2d,0x2a,0x2e,0x3d,0x5b,0x5d,0x60,0x3a}, textile={0x22,0x2a,0x23,0x2e,0x3d,0x7c,0x3c,0x3e},
}
local function insert_char_pre(state, value)
  local result = state.classification
  if not result or result.result ~= "prose" or not formatoptions_owned(state) then return end
  local bytes = structural_delimiter_bytes[vim.bo[state.buf].filetype]; if not bytes then return end
  if classification.has_delimiter(value, bytes) then
    formatoptions_write(state, formatoptions_value(state.format.baseline, false))
  end
end
local function reconcile_classification(state, win)
  if state.policy.safety == "plain" then state.classification = { win=win, result="prose", generation=state.generation, filetype=state.policy.filetype }; return "prose" end
  if state.policy.safety == "unknown" then state.classification = { win=win, result="unknown", generation=state.generation, filetype=state.policy.filetype }; return "unknown" end
  if not win or not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= state.buf then
    state.classification = { win = win, result = "unknown", generation=state.generation, filetype=state.policy.filetype }
    return "unknown"
  end
  local result = classify_location(state, win)
  state.classification = { win=win, result=result, generation=state.generation, filetype=state.policy.filetype }
  return result
end
local function eligible_filetype(state, win)
  win = win or api.nvim_get_current_win()
  return state.policy.safety == "plain" or (state.classification
    and state.classification.generation == state.generation
    and state.classification.filetype == state.policy.filetype
    and state.classification.win == win
    and api.nvim_win_is_valid(win)
    and api.nvim_win_get_buf(win) == state.buf
    and state.classification.result == "prose")
end
local function formatoptions_canonical(value, baseline)
  -- deliberate: Vim normalizes `j` to `n` and may add/remove `l` at FileType.
  value = value:gsub("l", ""):gsub("j", "n")
  if not baseline:find("c", 1, true) then value = value:gsub("c", "") end
  return value
end
formatoptions_owned = function(state)
  local format = state.format
  if not format then return false end
  local current = vim.bo[state.buf].formatoptions
  if format.external then return false end
  if current ~= format.last then
    local filetype_change = format.filetype ~= vim.bo[state.buf].filetype
    local normalized = formatoptions_canonical(current, format.baseline)
    local expected = formatoptions_canonical(formatoptions_value(format.baseline, false), format.baseline)
    local expected_insert = formatoptions_canonical(formatoptions_value(format.baseline, true), format.baseline)
    if (format.filetype_event or filetype_change) and (same_formatoptions(normalized, expected) or same_formatoptions(normalized, expected_insert)) then
      -- deliberate: accept only Vim's equivalent FileType normalization, never arbitrary user edits.
      format.filetype_event = true
      format.last = current
    else
      format.external = true
      format.external_value = current
      return false
    end
  end
  return true
end
formatoptions_value = function(baseline, insert)
  local value, seen = "", {}
  for flag in baseline:gmatch(".") do
    if flag ~= "a" then value = value .. flag; seen[flag] = true end
  end
  if not seen.t then value = value .. "t" end
  if not seen.n then value = value .. "n" end
  if insert then value = value .. "a" end
  return value
end
same_formatoptions = function(a, b)
  local seen = {}
  for flag in a:gmatch(".") do seen[flag] = true end
  local other = {}
  for flag in b:gmatch(".") do other[flag] = true end
  for flag in pairs(seen) do if not other[flag] then return false end end
  for flag in pairs(other) do if not seen[flag] then return false end end
  return true
end
formatoptions_write = function(state, value)
  local format = state.format
  format.guard = true
  vim.bo[state.buf].formatoptions = value
  format.guard = false
  format.last = value
end
local function reconcile_formatoptions(state)
  local format = state.format
  if state.mode == "hard" and not format then
    format = { baseline = vim.bo[state.buf].formatoptions, filetype = vim.bo[state.buf].filetype }
    format.last = format.baseline
    state.format = format
  end
  if not format or not formatoptions_owned(state) then return end
  if state.mode ~= "hard" or not state.autoformat then
    if state.mode ~= "hard" then formatoptions_write(state, format.baseline)
    else formatoptions_write(state, formatoptions_value(format.baseline, false)) end
    return
  end
  local insert = state.in_insert == true
  local win = api.nvim_get_current_win()
  if insert and not state.classification then reconcile_classification(state, win) end
  insert = insert and eligible_filetype(state, win) and not state.suspended and not state.pending_suspend
  formatoptions_write(state, formatoptions_value(format.baseline, insert))
end
local function reconcile_buffer(state, mode, width)
  local buf = state.buf
  local desired = { textwidth = mode == "hard" and width or nil, formatoptions = nil }
  state.owned = state.owned or {}
  reconcile_formatoptions(state)
  for _, key in ipairs({ "textwidth" }) do
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
local function is_default_insert_mapping(buf, spec)
  if spec.mode ~= "i" or (spec.lhs ~= "<C-U>" and spec.lhs ~= "<C-W>") then return false end
  if #api.nvim_buf_get_keymap(buf, spec.mode) > 0 then
    for _, map in ipairs(api.nvim_buf_get_keymap(buf, spec.mode)) do
      if map.lhs == spec.lhs then return false end
    end
  end
  for _, map in ipairs(api.nvim_get_keymap(spec.mode)) do
    if map.lhs == spec.lhs then
      local default_desc = spec.lhs == "<C-U>" and ":help i_CTRL-U-default" or ":help i_CTRL-W-default"
      return map.buffer == 0 and map.rhs == "<C-G>u" .. spec.lhs and map.desc == default_desc
    end
  end
  return false
end
local function mapping_identity(spec)
  return { mode = spec.mode, lhs = spec.lhs, rhs = spec.rhs, buffer = nil,
    desc = mapping_owner, noremap = true, silent = true, expr = false,
    nowait = false, script = false, callback = false, replace_keycodes = false }
end
local function mapping_matches(buf, record)
  local map = find_mapping(buf, record.mode, record.lhs)
  if not map or map.buffer ~= buf then return false end
  for _, field in ipairs({ "rhs", "desc", "noremap", "silent", "expr", "nowait", "script", "replace_keycodes" }) do
    local expected = record[field]
    if map[field] ~= nil and map[field] ~= (type(expected) == "boolean" and (expected and 1 or 0) or expected) then return false end
  end
  return (map.callback ~= nil) == record.callback
end
local function reconcile_mappings(state)
  state.mappings = state.mappings or {}
  local skipped = {}
  local wanted = {}
  for _, spec in ipairs(mapping_list(state)) do
    local id = spec.mode .. "\0" .. spec.lhs
    wanted[id] = spec
    local record = state.mappings[id]
    if record and not mapping_matches(state.buf, record) then state.mappings[id] = nil; record = nil end
    if not record then
      if find_mapping(state.buf, spec.mode, spec.lhs) and not is_default_insert_mapping(state.buf, spec) then
        skipped[#skipped + 1] = spec.lhs
      elseif not find_mapping(state.buf, spec.mode, spec.lhs) or is_default_insert_mapping(state.buf, spec) then
        local identity = mapping_identity(spec)
        vim.keymap.set(spec.mode, spec.lhs, identity.rhs, {
          buffer = state.buf, noremap = identity.noremap, silent = identity.silent, desc = identity.desc,
        })
        identity.buffer = state.buf
        state.mappings[id] = identity
      end
    end
  end
  if #skipped > 0 then
    -- deliberate: one notification per enable cycle keeps conflict-heavy buffers quiet.
    vim.notify("Pencil skipped conflicting mappings " .. table.concat(skipped, ", ") .. " in buffer " .. state.buf, vim.log.levels.WARN)
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
    if state.format and not state.format.external and formatoptions_owned(state) then vim.bo[state.buf].formatoptions = state.format.baseline end
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
  local settings, supported, policy = settings_for(buf); settings = settings or merge({}, config)
  settings = merge(settings, opts)
  local ml, requested = modeline_width(buf), settings.mode
  local mode = requested == "detect" and detect(buf, settings) or requested
  local width = opts.textwidth or (ml and ml > 0 and ml) or (vim.bo[buf].textwidth > 0 and vim.bo[buf].textwidth) or settings.textwidth
  if type(width) ~= "number" or width < 1 then error("pencil requires a positive textwidth") end
  local state = previous or { windows={}, displayed={}, owned={} }
  state.displayed = state.displayed or {}
  state.buf = buf
  state.generation = (state.generation or 0) + 1
  state.mode, state.width, state.soft_width, state.settings, state.policy = mode, width, width, settings, policy
  state.policy.safety = state.policy.classifier and "custom" or state.policy.safety
  state.policy.filetype = vim.bo[buf].filetype
  if opts.autoformat ~= nil then state.autoformat = opts.autoformat else state.autoformat = settings.autoformat end
  if previous then state.suspended, state.pending_suspend = nil, nil end
  state.classification = nil
  local conceal = opts.conceal ~= nil and opts.conceal or settings.conceal
  state.conceal = (conceal ~= false and (supported or opts.conceal ~= nil)) and conceal or nil
  if state.conceal then state.conceal = merge({ level=2, cursor="" }, state.conceal) end
  reconcile_buffer(state, mode, width)
  if mode == "hard" and state.policy.safety == "custom" and not state.classification then
    local win
    for _, candidate in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(candidate) == buf then
        win = candidate
        if candidate == api.nvim_get_current_win() then break end
      end
    end
    reconcile_classification(state, win)
    reconcile_formatoptions(state)
  end
  reconcile_mappings(state)
  for _, win in ipairs(api.nvim_list_wins()) do if api.nvim_win_get_buf(win) == buf then apply_window(state, win, not previous or not state.windows[win]); state.displayed[win] = buf; window_owner[win] = state end end
  active[buf], disabled[buf] = state, nil
end
function M.disable(opts)
  opts = validate_buf_opts(opts, "disable"); local buf = target(opts); local state = active[buf]; if not state then disabled[buf] = true; return end
  cleanup(state)
  active[buf], disabled[buf] = nil, true
end
function M.toggle(opts)
  opts = validate_buf_opts(opts, "toggle")
  local buf = target(opts); if active[buf] then M.disable({buf=buf}) else M.enable(opts or {buf=buf}) end
end
function M.mode(opts)
  opts = validate_buf_opts(opts, "mode")
  local buf=target(opts); return active[buf] and active[buf].mode or (disabled[buf] and "off" or nil)
end
local function semantic_status(state)
  if state.mode == "soft" then return "soft" end
  local requested_win
  if api.nvim_get_current_buf() == state.buf then requested_win = api.nvim_get_current_win() end
  if state.policy.safety ~= "plain" and not state.in_insert then
    local win = requested_win
    if not win then for _, candidate in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(candidate) == state.buf then win = candidate; break end
    end end
    if not win then return "hard" end
    reconcile_classification(state, win)
    requested_win = win
  end
  if state.mode == "hard" and state.autoformat and eligible_filetype(state, requested_win) and not state.suspended and not state.pending_suspend and formatoptions_owned(state) then return "auto" end
  return "hard"
end
function M.status(opts)
  opts = validate_buf_opts(opts, "status")
  local buf = target(opts)
  local state = active[buf]
  if not state then return config.status.off or "" end
  return state.settings.status[semantic_status(state)] or ""
end
local function validate_autoformat_action_opts(opts)
  return validate_buf_opts(opts, "set_autoformat")
end
function M.set_autoformat(action, opts)
  if action ~= "enable" and action ~= "disable" and action ~= "toggle" and action ~= "suspend" then error("invalid autoformat action " .. tostring(action)) end
  opts = validate_autoformat_action_opts(opts); local buf = target(opts); local state = active[buf]
  if not state or state.mode ~= "hard" then
    if action == "enable" or action == "toggle" then
      vim.notify("Pencil format " .. action .. " requires hard mode", vim.log.levels.WARN)
    end
    return
  end
  formatoptions_owned(state)
  if action == "suspend" then
    if not state.autoformat then return end
    if state.in_insert then state.suspended = true else state.pending_suspend = true end
  elseif action == "disable" then state.autoformat, state.suspended, state.pending_suspend = false, nil, nil
  elseif action == "enable" then state.autoformat, state.suspended, state.pending_suspend = true, nil, nil
  elseif action == "toggle" then state.autoformat = not state.autoformat; if state.autoformat then state.suspended, state.pending_suspend = nil, nil end end
  reconcile_formatoptions(state)
end

local function format_command_completion(_, line)
  local top = { "enable", "disable", "toggle", "hard", "soft", "detect", "format" }
  if line:match("^%s*Pencil%s+format%s+") then return { "enable", "disable", "toggle", "suspend" } end
  local partial = line:match("^%s*Pencil%s+(%S*)$")
  if partial then
    local result = {}; for _, action in ipairs(top) do if action:sub(1, #partial) == partial then result[#result + 1] = action end end; return result
  end
  return top
end
local function command(args)
  local action = args.fargs[1]
  if not action then return M.enable() end
  local actions = { enable=M.enable, disable=M.disable, toggle=M.toggle,
    hard=function() M.enable({mode="hard"}) end, soft=function() M.enable({mode="soft"}) end,
    detect=function() M.enable({mode="detect"}) end }
  if action == "format" then
    if #args.fargs ~= 2 or not ({enable=true, disable=true, toggle=true, suspend=true})[args.fargs[2]] then
      error("Pencil: format expects exactly one action: enable, disable, toggle, or suspend")
    end
    return M.set_autoformat(args.fargs[2])
  end
  if #args.fargs ~= 1 or not actions[action] then error("Pencil: expected exactly one valid action") end
  actions[action]()
end
local function setup_autocmds()
  if installed then return end; installed=true; local group=api.nvim_create_augroup("Pencil", {clear=true})
  api.nvim_create_user_command("Pencil", command, {nargs="*", complete=format_command_completion})
  for name, action in pairs({HardPencil="hard",SoftPencil="soft",NoPencil="disable",PencilOff="disable",PencilToggle="toggle",TogglePencil="toggle"}) do api.nvim_create_user_command(name,function() command({fargs={action}}) end,{}) end
  for name, action in pairs({PFormat="enable", PFormatOff="disable", PFormatToggle="toggle"}) do api.nvim_create_user_command(name,function() M.set_autoformat(action) end,{}) end
  api.nvim_create_autocmd("FileType",{group=group,callback=function(a)
    if active[a.buf] then
      local state = active[a.buf]
      if state.format then
        local format = state.format
        if not format.external then formatoptions_owned(state) end
        if format.external then
          -- deliberate: FileType is hands-off after external ownership transfers; the user's
          -- exact value must survive native FileType processing unchanged.
        else
          -- deliberate: only an owned value may use Vim's j/n/l normalization equivalence.
          local current = formatoptions_canonical(vim.bo[a.buf].formatoptions, format.baseline)
          local expected = formatoptions_canonical(formatoptions_value(format.baseline, false), format.baseline)
          local expected_insert = formatoptions_canonical(formatoptions_value(format.baseline, true), format.baseline)
          if vim.bo[a.buf].formatoptions ~= format.last
            and not (same_formatoptions(current, expected) or same_formatoptions(current, expected_insert)) then
            format.external, format.external_value = true, vim.bo[a.buf].formatoptions
          else
            format.filetype_event = true
          end
        end
      end
      state.classification = nil
      local _, _, policy = settings_for(a.buf)
      state.policy = policy or { safety = "unknown", filetype = vim.bo[a.buf].filetype }
      state.policy.safety = state.policy.classifier and "custom" or state.policy.safety
      state.policy.filetype = vim.bo[a.buf].filetype
      state.generation = (state.generation or 0) + 1
      if state.in_insert and state.policy.safety ~= "unknown" then
        local win = a.win and api.nvim_win_is_valid(a.win) and api.nvim_win_get_buf(a.win) == a.buf and a.win or nil
        if not win and api.nvim_get_current_buf() == a.buf then win = api.nvim_get_current_win() end
        reconcile_classification(state, win)
      end
      if state.format and not state.format.external then
        -- FileType normalization is the only owned-value comparison boundary.
        state.format.filetype_event = true
        state.format.last = vim.bo[a.buf].formatoptions
      end
      if state.format and not state.format.external then
        reconcile_buffer(state, state.mode, state.width)
      end
      if state.format and not state.format.external then
        -- deliberate: Vim may add/remove the filetype's local `l` flag; it is not user ownership loss.
        reconcile_formatoptions(state)
        state.format.last = vim.bo[a.buf].formatoptions
      end
      if state.format then
        state.format.filetype_event = nil
        if not state.format.external then state.format.external_candidate = nil end
        state.format.filetype = vim.bo[a.buf].filetype
      end
    else
      local _, _, _, automatic = settings_for(a.buf)
      if configured and automatic and not disabled[a.buf] then pcall(M.enable,{buf=a.buf}) end
    end
  end})
  api.nvim_create_autocmd({"InsertEnter", "InsertLeave", "CursorMovedI", "TextChangedI", "TextChangedP", "CompleteChanged"},{group=group,callback=function(a)
    local state=active[a.buf]
    if state then
      local insert = a.event == "InsertEnter"
      if a.event == "InsertLeave" then
        state.classification = nil
        if state.format then
          local current = vim.bo[a.buf].formatoptions
          if current == state.format.last then
            formatoptions_write(state, formatoptions_value(state.format.baseline, false))
          else
            state.format.external = true
          end
        end
      end
      if a.event == "InsertLeave" then
        state.in_insert = false
      elseif a.event == "InsertEnter" then
        state.in_insert = true
      end
      local event_win = (a.win and api.nvim_win_is_valid(a.win) and api.nvim_win_get_buf(a.win) == a.buf) and a.win or nil
      if not event_win and api.nvim_get_current_buf() == a.buf then event_win = api.nvim_get_current_win() end
      if a.event == "InsertLeave" and state.format and not state.format.external and formatoptions_owned(state) then
        -- Remove the temporary flag before clearing insertion state; never re-add it on leave.
        formatoptions_write(state, formatoptions_value(state.format.baseline, false))
      end
      if state.in_insert and state.policy.safety ~= "unknown" then reconcile_classification(state, event_win) end
      if state.in_insert and state.pending_suspend and eligible_filetype(state, event_win) then
        state.pending_suspend=nil; state.suspended=true
      elseif a.event == "InsertLeave" then
        state.suspended=nil
      end
      if a.event ~= "InsertLeave" then reconcile_formatoptions(state) end
    end
  end})
  api.nvim_create_autocmd("OptionSet",{group=group,pattern="formatoptions",callback=function(a)
    -- OptionSet reports the current buffer as 0 for local options on supported Neovim versions.
    local state = active[a.buf] or active[api.nvim_get_current_buf()]
    if state and state.format and not state.format.guard and not state.format.external then
      local value = vim.bo[state.buf].formatoptions
      local normalized = formatoptions_canonical(value, state.format.baseline)
      local expected = formatoptions_canonical(formatoptions_value(state.format.baseline, false), state.format.baseline)
      local expected_insert = formatoptions_canonical(formatoptions_value(state.format.baseline, true), state.format.baseline)
      if not same_formatoptions(normalized, expected) and not same_formatoptions(normalized, expected_insert) then
        -- deliberate: non-guarded non-normalization writes transfer ownership immediately;
        -- canonical comparison is permitted only while the Pencil value is still owned.
        state.format.external, state.format.external_value = true, value
      end
    end
  end})
  api.nvim_create_autocmd("InsertCharPre",{group=group,callback=function(a) local state=active[a.buf]; if state and state.in_insert and state.policy.safety == "structured" then insert_char_pre(state, vim.v.char or "") end end})
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
  api.nvim_create_autocmd({"WinResized", "VimResized"},{group=group,callback=function(a)
    for _, state in pairs(active) do
      if state.mode == "soft" then
        local wins = a.event == "WinResized" and a.windows or api.nvim_list_wins()
        for _, win in ipairs(wins or {}) do
          if state.windows[win] and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == state.buf then apply_window(state, win, false) end
        end
      end
    end
  end})
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
setup_autocmds()
return M
