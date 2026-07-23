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
check(vim.bo[buf].formatoptions == "qjtc", "formatoptions flags must be unique and preserved")
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
pencil.enable({ buf = reenable, mode = "soft" }); check(vim.wo.wrap == true, "same-mode re-enable reapplies presentation without losing ownership")
vim.wo.wrap = false; pencil.enable({ buf = reenable, mode = "soft" }); pencil.disable({ buf = reenable }); check(vim.wo.wrap == false, "same-mode wrap edit survives disable")
vim.bo[reenable].textwidth = 91; pencil.enable({ buf = reenable, mode = "hard", textwidth = 70 }); vim.bo[reenable].textwidth = 92
pencil.enable({ buf = reenable, mode = "hard", textwidth = 70 }); pencil.disable({ buf = reenable }); check(vim.bo[reenable].textwidth == 92, "textwidth edit survives re-enable and disable"); reset(reenable)

-- Simultaneous buffers retain independent modes and presentation.
local hard_buf = fresh({ "short" }, "text"); local soft_buf = api.nvim_create_buf(true, false); api.nvim_buf_set_lines(soft_buf, 0, -1, false, { "short" }); vim.bo[soft_buf].filetype = "text"
pencil.enable({ buf = hard_buf, mode = "hard", textwidth = 70 }); pencil.enable({ buf = soft_buf, mode = "soft" })
check(pencil.mode({ buf = hard_buf }) == "hard" and pencil.mode({ buf = soft_buf }) == "soft", "simultaneous buffers keep different modes"); reset(hard_buf); reset(soft_buf)

-- Disabled buffers are removed on wipeout even when inactive.
pencil.setup({ filetypes = {} }); local stale = fresh({ "short" }, "text"); pencil.disable({ buf = stale }); api.nvim_buf_delete(stale, { force = true }); vim.wait(20); check(pcall(pencil.mode, { buf = stale }) == false, "wiped disabled buffer is not retained")

-- Wiping the displayed buffer must restore every window option Pencil owns.
pencil.setup({ conceal = { level = 2, cursor = "n" }, filetypes = {} })
local wiped = fresh({ "short" }, "text")
vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent = false, true, false
vim.wo.conceallevel, vim.wo.concealcursor = 0, ""
local wiped_baseline = { vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent, vim.wo.conceallevel, vim.wo.concealcursor }
pencil.enable({ buf = wiped, mode = "soft" })
api.nvim_buf_delete(wiped, { force = true })
vim.wait(100, function() return vim.wo.wrap == wiped_baseline[1] and vim.wo.linebreak == wiped_baseline[2] and vim.wo.breakindent == wiped_baseline[3] end)
check(vim.wo.wrap == wiped_baseline[1] and vim.wo.linebreak == wiped_baseline[2] and vim.wo.breakindent == wiped_baseline[3], "wipeout restores layout options")
check(vim.wo.conceallevel == wiped_baseline[4] and vim.wo.concealcursor == wiped_baseline[5], "wipeout restores conceal options")

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
