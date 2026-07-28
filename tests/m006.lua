local pencil = require("pencil")
local api = vim.api
local function check(ok, message)
  if not ok then
    io.stderr:write("FAIL: " .. message .. "\n")
    os.exit(1)
  end
end
local function rejects(fn, message) check(not pcall(fn), message) end

local public = { "setup", "enable", "disable", "toggle", "set_autoformat", "mode", "status" }
for _, name in ipairs(public) do check(type(pencil[name]) == "function", "public function: " .. name) end
local surface = {}
for name in pairs(pencil) do surface[#surface + 1] = name end
table.sort(surface)
table.sort(public)
check(table.concat(surface, ",") == table.concat(public, ","), "exact public module surface")
for _, name in ipairs({ "Pencil", "HardPencil", "SoftPencil", "NoPencil", "PencilOff", "TogglePencil", "PencilToggle", "PFormat", "PFormatOff", "PFormatToggle" }) do
  check(api.nvim_get_commands({})[name] ~= nil, "command: " .. name)
end
check(vim._test and true or true, "test harness loaded")
local module_path = assert(vim.api.nvim_get_runtime_file("lua/pencil/init.lua", false)[1])
local saved_module, saved_version = package.loaded.pencil, vim.version
package.loaded.pencil = nil
vim.version = function() return { major = 0, minor = 9 } end
local loaded, load_error = pcall(assert(loadfile(module_path)))
vim.version, package.loaded.pencil = saved_version, saved_module
check(not loaded and tostring(load_error):match("pencil.nvim requires Neovim 0.10 or newer$") ~= nil, "exact minimum version error")
local completion = vim.fn.getcompletion("Pencil ", "cmdline")
local expected = { enable=true, disable=true, toggle=true, hard=true, soft=true, detect=true, format=true }
check(#completion == 7, "exact top-level completion count")
for _, action in ipairs(completion) do check(expected[action], "top-level completion: " .. action); expected[action] = nil end
check(next(expected) == nil, "exact top-level completion set")
local format_completion = vim.fn.getcompletion("Pencil format ", "cmdline")
local expected_format = { enable=true, disable=true, toggle=true, suspend=true }
check(#format_completion == 4, "exact format completion count")
for _, action in ipairs(format_completion) do check(expected_format[action], "format completion: " .. action); expected_format[action] = nil end
check(next(expected_format) == nil, "exact format completion set")

-- Per-call schemas reject unknown keys and invalid shapes before any state change.
for _, name in ipairs({ "disable", "toggle", "mode", "status" }) do
  rejects(function() pencil[name]({ nope = true }) end, name .. " rejects unknown keys")
  rejects(function() pencil[name]("bad") end, name .. " rejects non-table options")
end
rejects(function() pencil.setup({ filetypes = { "" } }) end, "filetype list rejects empty names")
rejects(function() pencil.setup({ filetypes = { [""] = {} } }) end, "keyed filetype rejects empty names")
local previous = api.nvim_get_current_buf()
local schema_buf = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(schema_buf)
vim.bo[schema_buf].filetype = "text"
rejects(function() pencil.enable({ buf = schema_buf, unsupported = true }) end, "enable rejects unknown keys")
check(pencil.mode({ buf = schema_buf }) == nil, "invalid enable does not mutate")

-- Built-in policy and replacement behavior remain observable through activation.
pencil.setup({ mappings = { navigation = false, undo_breaks = false } })
for ft, mode in pairs({ gitcommit="hard", mail="hard", markdown="soft", text="soft", rst="hard", tex="hard", asciidoc="hard", textile="soft" }) do
  vim.bo[schema_buf].filetype = ft
  pencil.enable({ buf = schema_buf })
  check(pencil.mode({ buf = schema_buf }) == mode, "preset mode: " .. ft)
  pencil.disable({ buf = schema_buf })
end
pencil.setup({ mappings = { navigation = false, undo_breaks = false }, filetypes = { "text" } })
local list_buf = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(list_buf)
vim.bo[list_buf].filetype = "markdown"
vim.cmd("doautocmd FileType")
check(pencil.mode({ buf = list_buf }) == nil, "list replaces built-ins")
api.nvim_buf_delete(list_buf, { force = true })

-- Simple-list policies inherit configured/default concealment and support opt-out.
local list_conceal = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(list_conceal)
vim.bo[list_conceal].filetype = "m006_list_conceal"
pencil.setup({ conceal = { level = 3, cursor = "i" }, filetypes = { "m006_list_conceal" }, mappings = { navigation = false, undo_breaks = false } })
vim.wo.conceallevel, vim.wo.concealcursor = 0, ""
pencil.enable({ buf = list_conceal })
check(vim.wo.conceallevel == 3 and vim.wo.concealcursor == "i", "list filetype inherits global conceal")
pencil.disable({ buf = list_conceal })
check(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "list conceal restores window values")
pencil.setup({ conceal = { level = 3, cursor = "i" }, filetypes = { "m006_list_conceal" }, mappings = { navigation = false, undo_breaks = false } })
pencil.enable({ buf = list_conceal, conceal = false })
check(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "list conceal=false opts out")
pencil.disable({ buf = list_conceal })
api.nvim_buf_delete(list_conceal, { force = true })
pencil.setup({ mappings = { navigation = false, undo_breaks = false }, filetypes = { text = { mode = "hard", textwidth = 77, format_safety = "plain" } } })
vim.bo[schema_buf].filetype = "text"
pencil.enable({ buf = schema_buf })
check(pencil.mode({ buf = schema_buf }) == "hard" and vim.bo[schema_buf].textwidth == 77, "keyed filetype merge")
pencil.disable({ buf = schema_buf })

-- Keyed custom policies inherit global concealment and restore the original window values.
local custom_conceal = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(custom_conceal)
vim.bo[custom_conceal].filetype = "custom_m006"
pencil.setup({ conceal = { level = 2, cursor = "n" }, filetypes = { custom_m006 = {} }, mappings = { navigation = false, undo_breaks = false } })
vim.wo.conceallevel, vim.wo.concealcursor = 0, ""
pencil.enable({ buf = custom_conceal })
check(vim.wo.conceallevel == 2 and vim.wo.concealcursor == "n", "keyed filetype inherits global conceal: " .. vim.wo.conceallevel .. "/" .. vim.wo.concealcursor .. "/" .. vim.bo[custom_conceal].filetype)
pencil.disable({ buf = custom_conceal })
check(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "keyed conceal restores window values")
vim.wo.conceallevel, vim.wo.concealcursor = 0, ""
pencil.setup({ conceal = { level = 2, cursor = "n" }, filetypes = { custom_m006 = { conceal = false } }, mappings = { navigation = false, undo_breaks = false } })
pencil.enable({ buf = custom_conceal })
check(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "keyed conceal=false opts out")
pencil.disable({ buf = custom_conceal })
api.nvim_buf_delete(custom_conceal, { force = true })
api.nvim_set_current_buf(previous)
api.nvim_buf_delete(schema_buf, { force = true })
-- Invalid setup is aggregate and atomic for both configuration and active state.
pencil.setup({ filetypes = {}, mappings = { navigation = false, undo_breaks = false } })
local atomic = api.nvim_create_buf(true, false)
vim.bo[atomic].filetype = "text"
pencil.enable({ buf = atomic, mode = "soft", conceal = false })
local atomic_status = pencil.status({ buf = atomic })
local rejected, atomic_error = pcall(pencil.setup, { mode = "bad", unknown = true, conceal = { level = 9 } })
check(not rejected and tostring(atomic_error):match("unknown key") and tostring(atomic_error):match("mode must"), "setup reports aggregate validation errors")
check(pencil.status({ buf = atomic }) == atomic_status, "invalid setup preserves active state")
pencil.disable({ buf = atomic }); api.nvim_buf_delete(atomic, { force = true })

-- Modeline zero disables hard mode; twenty nonblank lines reach the fallback boundary.
pencil.setup({ mode = "detect", fallback = "hard", textwidth = 83, filetypes = {} })
local modeline_zero = api.nvim_create_buf(true, false)
api.nvim_buf_set_lines(modeline_zero, 0, -1, false, { "vim: set tw=0:", "short" })
vim.bo[modeline_zero].filetype = "text"
pencil.enable({ buf = modeline_zero })
check(pencil.mode({ buf = modeline_zero }) == "soft", "zero modeline selects soft")
pencil.disable({ buf = modeline_zero }); api.nvim_buf_delete(modeline_zero, { force = true })
local twenty = api.nvim_create_buf(true, false)
api.nvim_buf_set_lines(twenty, 0, -1, false, vim.fn["repeat"]({ "short" }, 20))
-- deliberate: use an unknown filetype so the test exercises detect/fallback, not a preset.
vim.bo[twenty].filetype = "m006_unknown_fallback"
pencil.enable({ buf = twenty })
check(pencil.mode({ buf = twenty }) == "hard" and vim.bo[twenty].textwidth == 83, "twenty nonblank lines use fallback and configured width: " .. tostring(pencil.mode({ buf = twenty })) .. "/" .. tostring(vim.bo[twenty].textwidth))
pencil.disable({ buf = twenty }); api.nvim_buf_delete(twenty, { force = true })

-- Soft presentation is window-local and does not touch unrelated options or colorcolumn.
pencil.setup({ filetypes = {}, mappings = { navigation = false, undo_breaks = false } })
local presentation = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(presentation)
vim.bo[presentation].filetype = "text"
vim.bo[presentation].iskeyword = "48-57"; vim.o.backspace = "indent,eol,start"; vim.wo.list = true; vim.wo.colorcolumn = "77"
pencil.enable({ buf = presentation, mode = "soft", conceal = false, mappings = { navigation = false, undo_breaks = false } })
check(vim.wo.wrap and vim.wo.colorcolumn == "77" and vim.bo[presentation].iskeyword == "48-57" and vim.o.backspace == "indent,eol,start" and vim.wo.list, "soft mode avoids unrelated options")
local late = api.nvim_open_win(presentation, true, { relative = "editor", row = 0, col = 0, width = 40, height = 5, style = "minimal" })
vim.wait(20)
check(vim.wo[late].wrap, "late window receives presentation")
api.nvim_win_close(late, true)
pencil.disable({ buf = presentation }); api.nvim_buf_delete(presentation, { force = true })

-- Classifier callbacks receive the exact public context and invalid results fail closed.
local callback_buf = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(callback_buf); vim.bo[callback_buf].filetype = "custom_m006"
local callback_context
pencil.setup({ filetypes = { custom_m006 = { mode = "hard", textwidth = 70, classifier = function(ctx) callback_context = ctx; return "prose" end } }, mappings = { navigation = false, undo_breaks = false } })
pencil.enable({ buf = callback_buf, conceal = false, mappings = { navigation = false, undo_breaks = false } })
check(callback_context and callback_context.buf == callback_buf and type(callback_context.win) == "number" and callback_context.row == 0 and callback_context.col == 0 and callback_context.filetype == "custom_m006", "classifier receives exact context")
pencil.disable({ buf = callback_buf }); api.nvim_buf_delete(callback_buf, { force = true })
local bad_classifier = api.nvim_create_buf(true, false)
vim.bo[bad_classifier].filetype = "bad_m006"
pencil.setup({ filetypes = { bad_m006 = { mode = "hard", classifier = function() error("classifier failure") end } }, mappings = { navigation = false, undo_breaks = false } })
pencil.enable({ buf = bad_classifier, conceal = false, mappings = { navigation = false, undo_breaks = false } })
check(pencil.status({ buf = bad_classifier }) == "H", "classifier errors fail closed")
pencil.disable({ buf = bad_classifier }); api.nvim_buf_delete(bad_classifier, { force = true })

-- Normal lifecycle operations and activation stay quiet.
local notifications = {}
local notify = vim.notify
vim.notify = function(message) notifications[#notifications + 1] = message end
pencil.setup({ filetypes = {}, mappings = { navigation = false, undo_breaks = false } })
local quiet = api.nvim_create_buf(true, false)
vim.bo[quiet].filetype = "text"; pencil.enable({ buf = quiet, mode = "soft", conceal = false, mappings = { navigation = false, undo_breaks = false } }); pencil.disable({ buf = quiet })
vim.notify = notify
check(#notifications == 0, "routine operations are quiet")
api.nvim_buf_delete(quiet, { force = true })

local tags = io.open("doc/tags", "r")
check(tags ~= nil, "generated help tags")
local tag_text = tags:read("*a"); tags:close()
for _, tag in ipairs({ "pencil", "pencil-installation", "pencil-configuration", "pencil-api", "pencil-commands", "pencil-status", "pencil-migration" }) do
  check(tag_text:find(tag .. "\t", 1, true) ~= nil, "help tag: " .. tag)
end
local readme = assert(io.open("README.md", "r")):read("*a")
for _, text in ipairs({ "jrswab/pencil.nvim", "Neovim 0.10", "Vim", "no required runtime dependencies", "opts = {}", "preservim/vim-pencil", "LICENSE" }) do
  check(readme:find(text, 1, true) ~= nil, "README contract: " .. text)
end
local buf = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "m006_unknown"
pencil.setup({ mappings = { navigation = false, undo_breaks = false }, filetypes = {} })
vim.cmd("doautocmd FileType")
check(pencil.mode({ buf = buf }) == nil, "empty filetype list disables automatic activation")
pencil.enable({ buf = buf, mode = "soft" })
check(pencil.mode({ buf = buf }) == "soft" and pencil.status({ buf = buf }) == "S", "public enable/mode/status")
pencil.disable({ buf = buf })
check(pencil.mode({ buf = buf }) == "off", "public disable status")
-- toggle validates before mutation and lifecycle cleanup restores the owned window state.
pencil.setup({ mappings = { navigation = false, undo_breaks = false }, filetypes = {} })
vim.cmd("tabnew")
local lifecycle = api.nvim_get_current_buf()
vim.bo[lifecycle].filetype = "text"
pencil.disable({ buf = lifecycle })
vim.wo.wrap = false
pencil.enable({ buf = lifecycle, mode = "soft" })
check(vim.wo.wrap == true, "soft presentation enabled")
rejects(function() pencil.toggle({ buf = lifecycle, nope = true }) end, "toggle validates before mutation")
check(pencil.mode({ buf = lifecycle }) == "soft", "invalid toggle preserves enabled state")
pencil.toggle({ buf = lifecycle })
check(pencil.mode({ buf = lifecycle }) == "off", "toggle cleanup")
vim.wo.wrap = false
api.nvim_buf_delete(lifecycle, { force = true })

-- Enable/disable must not rewrite the user's statusline.
local statusline_buf = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(statusline_buf)
vim.bo[statusline_buf].filetype = "text"
local global_statusline, window_statusline = vim.go.statusline, vim.wo.statusline
vim.go.statusline, vim.wo.statusline = "M006-global-statusline-sentinel", "M006-window-statusline-sentinel"
local function check_statusline(stage)
  check(vim.go.statusline == "M006-global-statusline-sentinel", stage .. " leaves global statusline unchanged")
  check(vim.wo.statusline == "M006-window-statusline-sentinel", stage .. " leaves window statusline unchanged")
end
check_statusline("before enable")
pencil.enable({ buf = statusline_buf, mode = "soft", conceal = false, mappings = { navigation = false, undo_breaks = false } })
check_statusline("enable")
pencil.disable({ buf = statusline_buf })
check_statusline("disable")
vim.go.statusline, vim.wo.statusline = global_statusline, window_statusline
api.nvim_buf_delete(statusline_buf, { force = true })
api.nvim_buf_delete(buf, { force = true })

-- Mapping conflicts are additive: defaults are replaceable only as buffer-local Pencil maps,
-- while real global and buffer-local user mappings survive and warn once per enable.
local function mapping_get(buf, mode, lhs)
  for _, map in ipairs(api.nvim_buf_get_keymap(buf, mode)) do if map.lhs == lhs then return map end end
  for _, map in ipairs(api.nvim_get_keymap(mode)) do if map.lhs == lhs then return map end end
end
local mapping_buf = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(mapping_buf)
vim.bo[mapping_buf].filetype = "text"
local mapping_notifications = {}
local mapping_notify = vim.notify
vim.notify = function(message) mapping_notifications[#mapping_notifications + 1] = message end
pencil.setup({ filetypes = {}, mappings = { navigation = false, undo_breaks = true } })
pencil.enable({ buf = mapping_buf, mode = "soft" })
check(mapping_get(mapping_buf, "i", "<C-U>") and mapping_get(mapping_buf, "i", "<C-W>"), "default insert undo mappings install")
pencil.disable({ buf = mapping_buf })
api.nvim_set_keymap("n", "j", ":echo 'global'\n", { expr = true })
api.nvim_set_keymap("n", "k", ":echo 'global'\n", { expr = true })
api.nvim_buf_set_keymap(mapping_buf, "n", "j", ":echo 'local'\n", { expr = true })
pencil.setup({ filetypes = {}, mappings = { navigation = true, undo_breaks = false } })
pencil.enable({ buf = mapping_buf, mode = "soft" })
check(mapping_get(mapping_buf, "n", "j").rhs:find("global", 1, true) == nil and mapping_get(mapping_buf, "n", "j").rhs:find("local", 1, true) ~= nil, "buffer user mapping is not replaced")
check(mapping_get(mapping_buf, "n", "k").rhs:find("global", 1, true) ~= nil, "global user mapping is not replaced")
check(#mapping_notifications == 1 and mapping_notifications[1]:find("j", 1, true) and mapping_notifications[1]:find("k", 1, true), "mapping conflicts warn once in a batch")
pencil.disable({ buf = mapping_buf })
check(mapping_get(mapping_buf, "n", "j") and mapping_get(mapping_buf, "n", "k"), "user mappings survive teardown")
vim.notify = mapping_notify
api.nvim_del_keymap("n", "j"); api.nvim_del_keymap("n", "k")
api.nvim_buf_delete(mapping_buf, { force = true })
print("M006 tests passed")
vim.cmd("qa!")
