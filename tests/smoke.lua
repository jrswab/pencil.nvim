local pencil = require("pencil")
local api = vim.api

local function check(condition, message)
  assert(condition, message)
end
local function fresh(lines, filetype)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "text" })
  vim.bo[buf].filetype = filetype or "text"
  return buf
end
local function reset(buf)
  pcall(pencil.disable, { buf = buf })
  api.nvim_buf_delete(buf, { force = true })
end

check(api.nvim_get_commands({}).Pencil ~= nil, "runtime loader did not define :Pencil")

-- Modelines are read without executing them, including the first and last regions.
for _, value in ipairs({ "80", "0" }) do
  local buf = fresh({ "vim: set textwidth=" .. value .. ":", "short" })
  pencil.enable({ buf = buf })
  check(pencil.mode({ buf = buf }) == (value == "0" and "soft" or "hard"), "vim modeline")
  reset(buf)
end
for _, marker in ipairs({ "vi:", "ex:" }) do
  local buf = fresh({ "short", marker .. " set tw=77:" })
  pencil.enable({ buf = buf })
  check(pencil.mode({ buf = buf }) == "hard" and vim.bo[buf].textwidth == 77, marker .. " modeline")
  reset(buf)
end
for _, marker in ipairs({ "vim:", "Vim:" }) do
  local b = fresh({ marker .. " tw=77", "short" }); pencil.enable({ buf = b })
  check(pencil.mode({ buf = b }) == "hard" and vim.bo[b].textwidth == 77, marker .. " shorthand modeline"); reset(b)
end
for _, marker in ipairs({ "VIM:", "modeline:" }) do
  local b = fresh({ marker .. " tw=77", string.rep("x", 131) }); pencil.setup({ fallback = "hard", textwidth = 42 }); pencil.enable({ buf = b })
  check(pencil.mode({ buf = b }) == "soft", marker .. " must not be recognized"); reset(b)
end
local buf = fresh({ "short", "short", "short", "short", "short", "short", "short", "short", "short", "vim: set tw=66:" })
pencil.enable({ buf = buf })
check(vim.bo[buf].textwidth == 66, "last modeline region")
reset(buf)
for _, bad in ipairs({ "vim: set tw=-1:", "vim: set textwidth=wat:", "vim: set tw=12x:" }) do
  local b = fresh({ bad, string.rep("x", 131) })
  pencil.setup({ fallback = "hard", textwidth = 42 })
  pencil.enable({ buf = b })
  check(pencil.mode({ buf = b }) == "soft", "malformed modeline must be ignored")
  reset(b)
end

-- Display width uses the target buffer context, including tabstop, and honors the boundary.
pencil.setup({ fallback = "hard", textwidth = 42 })
local exact = fresh({ string.rep("x", 130) }, "unknown"); pencil.enable({ buf = exact }); check(pencil.mode({ buf = exact }) == "hard", "130 columns stay hard"); reset(exact)
local unicode = fresh({ string.rep("界", 66) }, "unknown"); pencil.enable({ buf = unicode }); check(pencil.mode({ buf = unicode }) == "soft", "Unicode display width"); reset(unicode)
local tabs = fresh({ "\t" .. string.rep("x", 8) }, "unknown"); vim.bo[tabs].tabstop = 4; pencil.enable({ buf = tabs }); check(pencil.mode({ buf = tabs }) == "hard", "target buffer tabstop context"); reset(tabs)

-- Sampling stops at 20 non-blank lines and does not read the whole buffer.
pencil.setup({ fallback = "hard", textwidth = 42 })
local sampled = {}
for _ = 1, 20 do sampled[#sampled + 1] = "short" end
sampled[#sampled + 1] = string.rep("x", 131)
buf = fresh(sampled, "unknown")
pencil.enable({ buf = buf })
check(pencil.mode({ buf = buf }) == "hard", "sampling must stop after 20 nonblank lines")
reset(buf)

-- Hard mode owns only its flags, without duplicate formatoptions.
buf = fresh({ "short" })
vim.bo[buf].formatoptions = "qjtc"
pencil.enable({ buf = buf, mode = "hard", textwidth = 70 })
check(vim.bo[buf].formatoptions == "qjtcn", "formatoptions contributes unique t and n")
pencil.disable({ buf = buf })
check(vim.bo[buf].formatoptions == "qjtc", "formatoptions restoration")
reset(buf)

-- All valid concealcursor combinations work; invalid and duplicate values fail atomically.
local valid = { "", "n", "v", "i", "c", "nvi", "nvic" }
for _, cursor in ipairs(valid) do
  local ok = pcall(pencil.setup, { conceal = { cursor = cursor } })
  check(ok, "valid concealcursor " .. cursor)
end
for _, cursor in ipairs({ "nn", "x", "nivx" }) do
  check(not pcall(pencil.setup, { conceal = { cursor = cursor } }), "invalid concealcursor " .. cursor)
  check(not pcall(pencil.enable, { conceal = { cursor = cursor } }), "invalid per-call concealcursor " .. cursor)
end
check(not pcall(pencil.setup, { filetypes = { markdown = { conceal = { level = "bad" } } } }), "nested conceal validation")
check(not pcall(pencil.setup, { filetypes = { markdown = { textwidth = 0 } } }), "nested setting validation")

-- Configuration is atomic, rejects false/non-tables, and keeps keyed precedence.
local before = vim.deepcopy(pencil)
check(not pcall(pencil.setup, false), "setup(false) must fail")
check(not pcall(pencil.setup, "bad"), "non-table setup must fail")
check(not pcall(pencil.setup, { mode = "bad", textwidth = 0, filetypes = { [0] = "text", [2] = "text" }, unknown = true }), "invalid setup must fail")
local precedence = fresh({ "short" }, "rst")
pencil.setup({ textwidth = 61, fallback = "soft", filetypes = { rst = { textwidth = 62 } } })
pencil.enable({ buf = precedence, mode = "hard", textwidth = 63 })
check(vim.bo[precedence].textwidth == 63, "per-call width precedence")
pencil.disable({ buf = precedence }); pencil.enable({ buf = precedence, mode = "hard" })
check(vim.bo[precedence].textwidth == 62, "keyed width precedence")
pencil.disable({ buf = precedence }); vim.bo[precedence].textwidth = 64; pencil.enable({ buf = precedence, mode = "hard" })
check(vim.bo[precedence].textwidth == 64, "existing width precedence")
pencil.disable({ buf = precedence }); reset(precedence)

-- Every built-in automatic preset is selectable, while an explicit empty set is not.
for name in pairs({ gitcommit=true, mail=true, markdown=true, text=true, rst=true, tex=true, asciidoc=true, textile=true }) do
  pencil.setup({ filetypes = { name } })
  local b = fresh({ "short" }, name); vim.cmd("doautocmd FileType")
  local expected = ({ gitcommit={ mode="hard", width=72 }, mail={ mode="hard", width=72 }, markdown={ mode="soft" }, text={ mode="soft" }, rst={ mode="hard", width=79 }, tex={ mode="hard", width=79 }, asciidoc={ mode="hard", width=79 }, textile={ mode="soft" } })[name]
  check(pencil.mode({ buf=b }) == expected.mode, "preset mode " .. name)
  check(expected.width == nil or vim.bo[b].textwidth == expected.width, "preset width " .. name); reset(b)
end
pencil.setup({ filetypes = {} }); local empty = fresh({ "short" }, "markdown"); vim.cmd("doautocmd FileType"); check(pencil.mode({buf=empty}) == nil, "empty filetypes disables auto activation"); reset(empty)
pencil.setup({ mode = "detect", textwidth = 61, fallback = "soft", filetypes = { "rst", unknown = {}, markdown = { mode = "hard", textwidth = 62 } } })
local preset = fresh({ "short" }, "rst"); pencil.enable({ buf = preset }); check(pencil.mode({ buf = preset }) == "hard" and vim.bo[preset].textwidth == 79, "selected preset precedence"); reset(preset)
pencil.setup({ mode = "soft", textwidth = 61, fallback = "soft", filetypes = { rst = {}, markdown = { mode = "hard", textwidth = 62 } } })
local preset_fields = fresh({ "short" }, "rst"); pencil.enable({ buf = preset_fields, mode = "hard" }); check(vim.bo[preset_fields].textwidth == 79, "preset width must override global width"); reset(preset_fields)
local unknown = fresh({ "short" }, "unknown"); pencil.enable({ buf = unknown }); check(pencil.mode({ buf = unknown }) == "soft", "unknown list fallback"); reset(unknown)
local keyed = fresh({ "short" }, "markdown"); pencil.enable({ buf = keyed }); check(vim.bo[keyed].textwidth == 62, "keyed override precedence"); reset(keyed)

-- Conceal restoration maps config keys to window options and preserves external edits.
pencil.setup({ conceal = { level = 1, cursor = "n" } })
local concealed = fresh({ "short" }, "text"); vim.wo.conceallevel, vim.wo.concealcursor = 0, ""
pencil.enable({ buf = concealed }); pencil.disable({ buf = concealed })
check(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "conceal restoration")
vim.wo.conceallevel = 3; pencil.enable({ buf = concealed }); vim.wo.conceallevel = 2; pencil.disable({ buf = concealed })
check(vim.wo.conceallevel == 2, "conceal external edit preservation"); reset(concealed)
local changed = fresh({ "short" }, "text"); vim.bo[changed].textwidth = 91; vim.bo[changed].formatoptions = "q"
pencil.enable({ buf = changed, mode = "hard", textwidth = 70 }); vim.bo[changed].textwidth = 92; vim.bo[changed].formatoptions = "qj"
pencil.disable({ buf = changed }); check(vim.bo[changed].textwidth == 92 and vim.bo[changed].formatoptions == "qj", "buffer edits must survive disable"); reset(changed)
local reconfigured = fresh({ "short" }, "text"); vim.wo.conceallevel, vim.wo.concealcursor = 0, ""
pencil.enable({ buf = reconfigured, conceal = { level = 1, cursor = "n" } }); pencil.enable({ buf = reconfigured, conceal = false })
check(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "reconfiguration removes owned conceal changes")
pencil.disable({ buf = reconfigured }); check(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "reconfiguration final restoration"); reset(reconfigured)

-- User window edits survive scheduled reconciliation while Pencil remains active.
pencil.setup({}); local edited = fresh({ "short" }, "text"); vim.wo.wrap = false; pencil.enable({ buf = edited, mode = "soft" }); vim.wo.wrap = false
vim.cmd("doautocmd BufEnter"); vim.wait(20); check(vim.wo.wrap == false, "reconciliation must not overwrite user window edits"); pencil.disable({ buf = edited }); check(vim.wo.wrap == false, "user window edit remains after disable"); reset(edited)

-- Mapping groups install independently and restore safely.
pencil.setup({ filetypes = {}, mappings = { navigation = true, undo_breaks = false } })
local mapped = fresh({ "wrapped prose" }, "text")
pencil.enable({ buf = mapped, mode = "soft" })
local function get_map(buf, mode, lhs)
  for _, map in ipairs(api.nvim_buf_get_keymap(buf, mode)) do if map.lhs == lhs then return map end end
end
local function has_map(buf, mode, lhs) return get_map(buf, mode, lhs) ~= nil end
check(has_map(mapped, "n", "j") and has_map(mapped, "n", "gj") and not has_map(mapped, "i", "."), "mapping groups are independent")
pencil.disable({ buf = mapped }); check(not has_map(mapped, "n", "j"), "owned navigation mapping teardown")
pencil.setup({ filetypes = {}, mappings = { navigation = false, undo_breaks = true } })
pencil.enable({ buf = mapped, mode = "soft" })
check(not has_map(mapped, "n", "j") and not has_map(mapped, "n", "gj") and has_map(mapped, "i", "."), "undo mapping group configuration")
pencil.disable({ buf = mapped }); reset(mapped)
local conflict = fresh({ "text" }, "text")
api.nvim_buf_set_keymap(conflict, "n", "j", "echo", {})
pencil.setup({ filetypes = {} }); pencil.enable({ buf = conflict, mode = "soft" })
check(has_map(conflict, "n", "j") and has_map(conflict, "n", "k"), "conflicting mapping does not abort installation")
-- An existing Insert mapping remains untouched when Pencil cannot own it.
api.nvim_buf_set_keymap(conflict, "i", "<CR>", "<Esc>", {})
pencil.enable({ buf = conflict, mode = "soft" })
local conflict_cr = get_map(conflict, "i", "<CR>")
check(conflict_cr and conflict_cr.rhs == "<Esc>", "conflicting CR survives")
pencil.disable({ buf = conflict }); check(has_map(conflict, "n", "j"), "conflicting mapping survives teardown"); reset(conflict)

-- Navigation uses display lines while explicit g alternatives retain physical movement.
pencil.setup({ filetypes = {}, mappings = { navigation = true, undo_breaks = false } })
local wrapped = fresh({ string.rep("x", 200), "short" }, "text")
vim.wo.wrap, vim.wo.linebreak = true, false
vim.bo[wrapped].textwidth = 0
vim.o.columns = 30
pencil.enable({ buf = wrapped, mode = "soft" })
local function feed(keys) api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "xt", false) end
api.nvim_win_set_cursor(0, { 1, 0 }); feed("j")
local display_cursor = api.nvim_win_get_cursor(0)
api.nvim_win_set_cursor(0, { 1, 0 }); feed("gj")
local physical_cursor = api.nvim_win_get_cursor(0)
check(display_cursor[2] > physical_cursor[2], "j and gj diverge on wrapped text")
api.nvim_win_set_cursor(0, { 1, 0 }); feed("$")
local display_end = api.nvim_win_get_cursor(0)
api.nvim_win_set_cursor(0, { 1, 0 }); feed("g$")
local physical_end = api.nvim_win_get_cursor(0)
check(display_end[2] < physical_end[2], "$ and g$ diverge on wrapped text")
for _, pair in ipairs({ { "j", "gj" }, { "k", "gk" }, { "0", "g0" }, { "$", "g$" }, { "<Down>", "gj" }, { "<Up>", "gk" }, { "<Home>", "g0" }, { "<End>", "g$" } }) do
  local simple, physical = get_map(wrapped, "n", pair[1]), get_map(wrapped, "n", pair[2])
  check(simple and simple.rhs == (pair[1] == "j" and "gj" or pair[1] == "k" and "gk" or pair[1] == "$" and "g$" or pair[1] == "0" and "g0" or pair[1] == "<Down>" and "gj" or pair[1] == "<Up>" and "gk" or pair[1] == "<Home>" and "g0" or "g$"), "display mapping " .. pair[1])
  check(physical and physical.rhs ~= nil, "physical mapping " .. pair[2])
end
-- Counts remain native mapping semantics rather than being consumed by a callback.
api.nvim_buf_set_lines(wrapped, 0, -1, false, { "one", "two", "three", "four" })
api.nvim_win_set_cursor(0, { 1, 0 }); feed("2j")
check(api.nvim_win_get_cursor(0)[1] == 3, "counted navigation")
pencil.disable({ buf = wrapped }); reset(wrapped)

-- Recreating a mapping with copied public metadata is external and survives teardown.
pencil.setup({ filetypes = {}, mappings = { navigation = true, undo_breaks = false } })
local replacement = fresh({ "short" }, "text")
pencil.enable({ buf = replacement, mode = "soft" })
local owned_desc = get_map(replacement, "n", "j").desc
api.nvim_buf_del_keymap(replacement, "n", "j")
api.nvim_buf_set_keymap(replacement, "n", "j", "gj", { noremap = true, silent = false, desc = owned_desc })
pencil.disable({ buf = replacement })
local external = get_map(replacement, "n", "j")
check(external and external.rhs == "gj" and external.desc == owned_desc and external.silent == 0, "copied token with changed option survives")
api.nvim_buf_del_keymap(replacement, "n", "j"); reset(replacement)

-- A copied ownership token with changed description is also external.
local changed_desc = fresh({ "short" }, "text")
pencil.enable({ buf = changed_desc, mode = "soft" })
local original = get_map(changed_desc, "n", "j")
api.nvim_buf_del_keymap(changed_desc, "n", "j")
api.nvim_buf_set_keymap(changed_desc, "n", "j", "gj", { noremap = true, silent = true, desc = "external replacement" })
pencil.disable({ buf = changed_desc })
check(get_map(changed_desc, "n", "j").desc == "external replacement", "changed description survives")
reset(changed_desc)

-- Undo-break mappings preserve editing keys and actual undo behavior.
local saved_deletions = {}
for _, lhs in ipairs({ "<CR>", "<C-U>", "<C-W>" }) do
  for _, map in ipairs(api.nvim_get_keymap("i")) do if map.lhs == lhs then saved_deletions[lhs] = map; api.nvim_del_keymap("i", lhs) end end
end
pencil.setup({ filetypes = {}, mappings = { navigation = false, undo_breaks = true } })
local undo_buf = fresh({ "" }, "text")
pencil.enable({ buf = undo_buf, mode = "soft" })
for _, lhs in ipairs({ ".", "!", "?", ",", ";", ":", "<CR>", "<C-U>", "<C-W>" }) do
  check(get_map(undo_buf, "i", lhs) ~= nil, "undo mapping " .. lhs)
end
local undo_map = get_map(undo_buf, "i", ".")
check(undo_map.callback == nil and undo_map.rhs == ".<C-G>u", "punctuation uses a native nonrecursive RHS")
api.nvim_win_set_cursor(0, { 1, 0 }); feed("ihello. world<Esc>")
check(api.nvim_buf_get_lines(undo_buf, 0, -1, false)[1] == "hello. world", "continuous insert typeahead")
vim.cmd("undo")
check(api.nvim_buf_get_lines(undo_buf, 0, -1, false)[1] == "hello.", "punctuation creates undo boundary")
pencil.disable({ buf = undo_buf }); reset(undo_buf)
for lhs, map in pairs(saved_deletions) do
  api.nvim_set_keymap("i", lhs, map.rhs or "", { noremap = map.noremap == 1, silent = map.silent == 1, expr = map.expr == 1, desc = map.desc })
end

-- Hard-mode automatic formatting owns t/n and adds temporary a only for eligible Insert.
pencil.setup({})
local auto = fresh({ "short" }, "text")
pencil.enable({ buf = auto, mode = "hard", textwidth = 70 })
check(pencil.status({ buf = auto }) == "A" and vim.bo[auto].formatoptions:find("a", 1, true) == nil, "hard mode starts armed")
vim.cmd("Pencil format suspend")
check(pencil.status({ buf = auto }) == "H", "suspend changes status")
vim.cmd("Pencil format enable")
check(pencil.status({ buf = auto }) == "A", "format enable clears suspension")
vim.cmd("PFormatOff")
check(pencil.status({ buf = auto }) == "H", "format alias disables preference")
vim.cmd("PFormat")
check(pencil.status({ buf = auto }) == "A", "format alias enables preference")
vim.bo[auto].filetype = "markdown"
check(pencil.status({ buf = auto }) == "H", "structured filetype is ineligible")
vim.bo[auto].filetype = "text"
check(pencil.status({ buf = auto }) == "A", "plain filetype is eligible")
pencil.disable({ buf = auto }); reset(auto)
local configured_auto = fresh({ "short" }, "text")
pencil.setup({ autoformat = false }); pencil.enable({ buf = configured_auto, mode = "hard", textwidth = 70 })
check(pencil.status({ buf = configured_auto }) == "H", "global autoformat preference")
pencil.disable({ buf = configured_auto }); reset(configured_auto)

-- M003 transition, suspension, ownership, validation, and filetype smoke coverage.
pencil.setup({ status = { off = "OFF", soft = "SOFT", auto = "AUTO", hard = "HARD" } })
local transitions = fresh({ "1. This prose is long enough to exercise native formatting behavior when it wraps." }, "text")
pencil.enable({ buf = transitions, mode = "hard", textwidth = 30 })
check(vim.bo[transitions].formatoptions:find("t", 1, true) and vim.bo[transitions].formatoptions:find("n", 1, true), "hard formatoptions flags")
check(pencil.status({ buf = transitions }) == "AUTO", "configured auto status")
vim.cmd("doautocmd InsertEnter")
check(vim.bo[transitions].formatoptions:find("a", 1, true) ~= nil, "eligible Insert adds a")
vim.cmd("doautocmd InsertLeave")
check(vim.bo[transitions].formatoptions:find("a", 1, true) == nil, "InsertLeave removes temporary a")
pencil.set_autoformat("suspend", { buf = transitions })
check(pencil.status({ buf = transitions }) == "HARD", "pending suspension status")
vim.cmd("doautocmd InsertEnter")
check(vim.bo[transitions].formatoptions:find("a", 1, true) == nil, "pending suspension consumed once")
vim.cmd("doautocmd InsertLeave")
vim.cmd("doautocmd InsertEnter")
check(vim.bo[transitions].formatoptions:find("a", 1, true) ~= nil, "suspension does not queue")
vim.cmd("doautocmd InsertLeave")
vim.bo[transitions].filetype = "markdown"
vim.cmd("doautocmd FileType")
check(pencil.status({ buf = transitions }) == "HARD" and vim.bo[transitions].formatoptions:find("a", 1, true) == nil, "FileType removes a for ineligible buffer")
vim.bo[transitions].filetype = "text"
vim.cmd("doautocmd FileType")
check(pencil.status({ buf = transitions }) == "AUTO", "FileType restores eligibility")
local owned_value = vim.bo[transitions].formatoptions
vim.bo[transitions].formatoptions = "q"
check(pencil.status({ buf = transitions }) == "HARD", "external formatoptions ownership")
vim.cmd("doautocmd InsertEnter"); vim.cmd("doautocmd InsertLeave")
pencil.disable({ buf = transitions })
check(vim.bo[transitions].formatoptions == "q", "external formatoptions survives cleanup")
reset(transitions)
local baseline = fresh({ "short" }, "text")
vim.bo[baseline].formatoptions = "aqqc"
pencil.enable({ buf = baseline, mode = "hard", textwidth = 70 })
check(vim.bo[baseline].formatoptions == "qqctn", "baseline a removed while owned")
pencil.disable({ buf = baseline })
check(vim.bo[baseline].formatoptions == "aqqc", "exact baseline restoration")
reset(baseline)
local invalid_args = fresh({ "short" }, "text")
pencil.enable({ buf = invalid_args, mode = "soft" })
check(not pcall(vim.cmd, "Pencil format enable extra"), "extra format args rejected")
check(not pcall(vim.cmd, "Pencil enable extra"), "extra top-level args rejected")
check(not pcall(pencil.set_autoformat, "bad", { buf = invalid_args }), "invalid action rejected")
check(vim.api.nvim_get_commands({}).Pencil.complete(nil, "Pencil format ", "") [1] == "enable", "nested completion")
pencil.disable({ buf = invalid_args }); reset(invalid_args)
local off = fresh({ "short" }, "text")
pencil.disable({ buf = off })
check(pencil.status({ buf = off }) == "OFF", "configured off status")
reset(off)

-- Commands, aliases, and completion expose the same observable state as Lua.
pencil.setup({})
buf = fresh({ "short" }, "text"); vim.cmd("Pencil hard"); check(pencil.mode({buf=buf}) == "hard", "command mode"); vim.cmd("PencilOff"); check(pencil.mode({buf=buf}) == "off", "alias mode"); vim.cmd("PencilToggle"); check(pencil.mode({buf=buf}) ~= "off", "toggle alias"); reset(buf)
local completion = vim.api.nvim_get_commands({}).Pencil.complete(nil, "", "")
check(#completion == 6, "command completion")

-- Modelines tokenize options after :set and never execute unrelated options.
local modeline = fresh({ "vim: set paste tw=67 list:", "short" }, "text")
pencil.enable({buf=modeline}); check(pencil.mode({buf=modeline}) == "hard" and vim.bo[modeline].textwidth == 67, "multi-option modeline"); check(not vim.o.paste, "modeline must not execute options"); reset(modeline)

-- Each displaying window keeps its own baseline across away/back cycles.
pencil.setup({})
local multi = fresh({ "short" }, "text"); vim.wo.wrap = false
vim.cmd("vsplit"); local right = api.nvim_get_current_win(); vim.wo[right].wrap = true
vim.cmd("wincmd h"); local left = api.nvim_get_current_win(); vim.wo[left].wrap = false
local left_baseline, right_baseline = vim.wo[left].wrap, vim.wo[right].wrap
pencil.enable({buf=multi})
check(vim.wo[left].wrap == true and vim.wo[right].wrap == true, "split presentation")
for _, win in ipairs({ left, right }) do
  api.nvim_set_current_win(win)
  for _ = 1, 3 do
    local away = api.nvim_create_buf(true, false)
    api.nvim_set_current_buf(away); vim.wait(10)
    check(vim.wo[win].wrap == (win == left and left_baseline or right_baseline), "away restores window baseline")
    api.nvim_set_current_buf(multi); vim.wait(10)
    check(vim.wo[win].wrap == true, "back reapplies presentation")
    api.nvim_buf_delete(away, { force = true })
  end
end
pencil.disable({ buf=multi }); check(vim.wo[left].wrap == left_baseline and vim.wo[right].wrap == right_baseline, "disable restores original baselines"); reset(multi)
-- Inactive cleanup cannot restore a released baseline over another buffer or edit.
pencil.setup({ filetypes = {} })
local owner_a = fresh({ "short" }, "text"); vim.wo.wrap = false; pencil.enable({ buf = owner_a, mode = "soft" })
local owner_b = api.nvim_create_buf(true, false); api.nvim_set_current_buf(owner_b); vim.bo[owner_b].filetype = "text"; vim.wo.wrap = false
pencil.disable({ buf = owner_a }); check(vim.wo.wrap == false, "inactive disable preserves unrelated buffer window")
local owner_c = fresh({ "short" }, "text"); vim.wo.wrap = false; pencil.enable({ buf = owner_c, mode = "soft" })
api.nvim_set_current_buf(owner_b); vim.wo.wrap = true; pencil.disable({ buf = owner_c }); check(vim.wo.wrap == true, "inactive disable preserves unrelated user edit")
api.nvim_buf_delete(owner_a, { force = true }); api.nvim_buf_delete(owner_b, { force = true }); reset(owner_c)

-- Away/back captures the latest baseline for final disable.
local latest = fresh({ "short" }, "text"); vim.wo.wrap = false; pencil.enable({ buf = latest, mode = "soft" })
local latest_away = api.nvim_create_buf(true, false); api.nvim_set_current_buf(latest_away); vim.wo.wrap = true
api.nvim_set_current_buf(latest); vim.wait(20); vim.cmd("doautocmd BufEnter"); vim.wait(20); vim.wo.wrap = true
pencil.disable({ buf = latest }); check(vim.wo.wrap == true, "final disable restores latest away baseline")
api.nvim_buf_delete(latest_away, { force = true }); reset(latest)

-- Re-enable treats user edits as fresh baselines, including same-mode wrap and textwidth edits.
local reenable = fresh({ "short" }, "text"); vim.wo.wrap = false; pencil.enable({ buf = reenable, mode = "soft" }); vim.wo.wrap = false
pencil.enable({ buf = reenable, mode = "soft" }); check(vim.wo.wrap == false, "same-mode re-enable preserves user presentation edit")
pencil.enable({ buf = reenable, mode = "soft" }); pencil.disable({ buf = reenable }); check(vim.wo.wrap == false, "same-mode wrap edit survives disable")
vim.bo[reenable].textwidth = 91; pencil.enable({ buf = reenable, mode = "hard", textwidth = 70 }); vim.bo[reenable].textwidth = 92
pencil.enable({ buf = reenable, mode = "hard", textwidth = 70 }); pencil.disable({ buf = reenable }); check(vim.bo[reenable].textwidth == 92, "textwidth edit survives re-enable and disable"); reset(reenable)

-- Simultaneous buffers retain independent modes and presentation.
local hard_buf = fresh({ "short" }, "text"); local soft_buf = api.nvim_create_buf(true, false); api.nvim_buf_set_lines(soft_buf, 0, -1, false, { "short" }); vim.bo[soft_buf].filetype = "text"
pencil.enable({ buf = hard_buf, mode = "hard", textwidth = 70 }); pencil.enable({ buf = soft_buf, mode = "soft" })
check(pencil.mode({ buf = hard_buf }) == "hard" and pencil.mode({ buf = soft_buf }) == "soft", "simultaneous buffers keep different modes"); reset(hard_buf); reset(soft_buf)

-- Disabled buffers are removed on wipeout even when inactive.
pencil.setup({ filetypes = {} }); local stale = fresh({ "short" }, "text"); pencil.disable({ buf = stale }); api.nvim_buf_delete(stale, { force = true }); vim.wait(20); check(pcall(pencil.mode, { buf = stale }) == false, "wiped disabled buffer is not retained")

-- Wiping the displayed buffer must not leave Pencil's presentation in the replacement buffer.
pencil.setup({ conceal = { level = 2, cursor = "n" }, filetypes = {} })
local wiped = fresh({ "short" }, "text")
vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent = false, true, false
vim.wo.conceallevel, vim.wo.concealcursor = 0, ""
local wiped_baseline = { vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent, vim.wo.conceallevel, vim.wo.concealcursor }
pencil.enable({ buf = wiped, mode = "soft" })
api.nvim_buf_delete(wiped, { force = true })
vim.wait(100, function() return vim.wo.wrap == wiped_baseline[1] and vim.wo.linebreak == wiped_baseline[2] and vim.wo.breakindent == wiped_baseline[3] end)
check(not (vim.wo.wrap and vim.wo.linebreak and vim.wo.breakindent), "wipeout removes Pencil layout presentation")
check(vim.wo.conceallevel ~= 2 or vim.wo.concealcursor ~= "n", "wipeout removes Pencil conceal presentation")

-- A single-window :buffer away must restore the exact window without a callback win id.
pencil.setup({ conceal = false }); local single = fresh({ "short" }, "text"); vim.wo.wrap = false; pencil.enable({ buf = single, mode = "soft" })
local single_other = api.nvim_create_buf(true, false); vim.cmd("buffer " .. single_other); vim.wait(10); check(vim.wo.wrap == false, "single-window buffer switch must restore presentation")
pencil.disable({ buf = single }); reset(single); api.nvim_buf_delete(single_other, { force = true })

-- :buffer must restore the window that displayed the enabled buffer, including vnew.
local switched = fresh({ "short" }, "text"); vim.wo.wrap = false; pencil.enable({ buf = switched, mode = "soft" })
vim.cmd("vnew"); local switched_win = api.nvim_get_current_win(); local other = api.nvim_create_buf(true, false); api.nvim_set_current_buf(other); vim.cmd("buffer " .. switched); vim.wait(10)
check(vim.wo[switched_win].wrap == true, "buffer switch must restore actual window"); pencil.disable({ buf = switched }); reset(switched); api.nvim_buf_delete(other, { force = true })

print("pencil smoke tests passed")
vim.cmd("qa!")
