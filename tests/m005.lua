local pencil = require("pencil")
local api = vim.api
local function assert_(ok, msg) assert(ok, msg) end
local function buffer(ft)
  local b = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(b)
  api.nvim_buf_set_lines(b, 0, -1, false, { "plain text", "protected-looking ``` text" })
  vim.bo[b].filetype = ft
  return b
end
local function drop(b) pcall(pencil.disable, { buf = b }); api.nvim_buf_delete(b, { force = true }) end

-- Explicit plain policy bypasses structural classification, including for built-ins.
for _, ft in ipairs({ "markdown", "rst", "tex", "asciidoc", "textile" }) do
  local b = buffer(ft)
  pencil.setup({ filetypes = { [ft] = { mode = "hard", format_safety = "plain" } } })
  pencil.enable({ buf = b })
  assert_(pencil.status({ buf = b }) == "A", "plain override " .. ft)
  assert_(not vim.bo[b].formatoptions:find("a", 1, true), "plain policy outside Insert")
  drop(b)
end
local plain = buffer("notes")
pencil.setup({ filetypes = { notes = { mode = "hard", format_safety = "plain" } } })
pencil.enable({ buf = plain })
assert_(pencil.status({ buf = plain }) == "A", "unknown explicit plain")
drop(plain)

-- Unknown policy is fail closed and custom policy is the sole classifier.
local calls, seen = 0, {}
local custom = buffer("mymarkup")
pencil.setup({ filetypes = { mymarkup = { mode = "hard", classifier = function(ctx)
  calls = calls + 1; seen = ctx; return "prose" end } } })
pencil.enable({ buf = custom })
assert_(calls == 1 and seen.buf == custom and seen.win == api.nvim_get_current_win(), "initial classifier context")
assert_(seen.row == 0 and seen.col == 0 and seen.filetype == "mymarkup", "classifier coordinates")
assert_(pencil.status({ buf = custom }) == "A", "custom prose status")
vim.cmd("doautocmd InsertEnter")
local after_enter = calls
vim.cmd("doautocmd CursorMovedI")
assert_(calls == after_enter + 1, "CursorMovedI classifier")
local invalid = buffer("unknown_ft")
pencil.setup({ filetypes = { unknown_ft = { mode = "hard" } } })
pencil.enable({ buf = invalid })
assert_(pencil.status({ buf = invalid }) == "H", "unknown fail closed")
drop(invalid)
drop(custom)

-- Invalid returns and callback errors fail closed quietly.
for _, invalid in ipairs({ false, 1, {}, " PROSE" }) do
  local b = buffer("badclass")
  pencil.setup({ filetypes = { badclass = { mode = "hard", classifier = function() return invalid end } } })
  pencil.enable({ buf = b })
  assert_(pencil.status({ buf = b }) == "H", "invalid classifier result")
  drop(b)
end
local nil_result = buffer("badclass")
pencil.setup({ filetypes = { badclass = { mode = "hard", classifier = function() return nil end } } })
pencil.enable({ buf = nil_result })
assert_(pencil.status({ buf = nil_result }) == "H", "nil classifier result")
drop(nil_result)
local yielded = buffer("yieldclass")
pencil.setup({ filetypes = { yieldclass = { mode = "hard", classifier = function() coroutine.yield() end } } })
pencil.enable({ buf = yielded })
assert_(pencil.status({ buf = yielded }) == "H", "yielding classifier fails closed")
drop(yielded)
local errored = buffer("errorclass")
pencil.setup({ filetypes = { errorclass = { mode = "hard", classifier = function() error("routine") end } } })
pencil.enable({ buf = errored })
assert_(pencil.status({ buf = errored }) == "H", "classifier error")
drop(errored)

-- Validation is aggregate and atomic: the valid prior policy remains installed.
pencil.setup({ filetypes = { stable = { mode = "hard", format_safety = "plain" } } })
local stable = buffer("stable")
pencil.enable({ buf = stable })
local ok, err = pcall(pencil.setup, { format_safety = "plain", filetypes = {
  [""] = { format_safety = "plain" },
  bad = { format_safety = "structured", classifier = true },
  other = { format_safety = "plain", classifier = function() return "prose" end },
} })
assert_(not ok and tostring(err):find("format_safety", 1, true) and tostring(err):find("classifier", 1, true), "aggregate validation")
assert_(pencil.status({ buf = stable }) == "A", "atomic setup")
drop(stable)

-- Final-review regressions: classification belongs to the requesting window.
do
  local window_calls = {}
  local b = buffer("windowclass")
  pencil.setup({ filetypes = { windowclass = { mode = "hard", classifier = function(ctx)
    window_calls[#window_calls + 1] = ctx.win
    return ctx.win == api.nvim_get_current_win() and "prose" or "protected"
  end } } })
  pencil.enable({ buf = b })
  local left = api.nvim_get_current_win()
  vim.cmd("vsplit")
  local right = api.nvim_get_current_win()
  api.nvim_set_current_win(left)
  vim.cmd("doautocmd InsertEnter")
  assert_(pencil.status({ buf = b }) == "A", "classification is prose in requesting window")
  local before_switch = #window_calls
  api.nvim_set_current_win(right)
  assert_(pencil.status({ buf = b }) == "H", "classification does not leak across windows")
  assert_(#window_calls == before_switch, "window switch fails closed before a required event")
  vim.cmd("doautocmd InsertLeave")
  assert_(pencil.status({ buf = b }) == "A", "outside-insert status reclassifies requesting window")
  assert_(window_calls[#window_calls] == right, "status classifies in requesting window")
  vim.cmd("only")
  drop(b)
end

-- Explicit re-enable in Insert performs one classification at the boundary.
do
  local calls = 0
  local b = buffer("reenableclass")
  pencil.setup({ filetypes = { reenableclass = { mode = "hard", classifier = function() calls = calls + 1; return "prose" end } } })
  pencil.enable({ buf = b })
  calls = 0
  vim.cmd("doautocmd InsertEnter")
  calls = 0
  pencil.enable({ buf = b })
  assert_(calls == 1, "re-enable classifies at most once")
  vim.cmd("doautocmd InsertLeave")
  drop(b)
end

-- InsertLeave clears insertion state without a classification callback or stale a.
do
  local calls = 0
  local b = buffer("leaveclass")
  pencil.setup({ filetypes = { leaveclass = { mode = "hard", classifier = function() calls = calls + 1; return "prose" end } } })
  pencil.enable({ buf = b })
  vim.cmd("doautocmd InsertEnter")
  local before_leave = calls
  vim.cmd("doautocmd InsertLeave")
  assert_(calls == before_leave, "InsertLeave does not classify")
  assert_(not vim.bo[b].formatoptions:find("a", 1, true), "InsertLeave removes temporary a")
  local before_status = calls
  assert_(pencil.status({ buf = b }) == "A" and calls == before_status + 1, "next outside-insert status reclassifies")
  drop(b)
end

-- Explicit disable wins over FileType cleanup; untouched eligible buffers still auto-activate.
do
  local calls = 0
  pencil.setup({ filetypes = { disabledclass = { mode = "hard", classifier = function() calls = calls + 1; return "prose" end } } })
  local b = buffer("disabledclass")
  pencil.enable({ buf = b })
  local before_disable = calls
  pencil.disable({ buf = b })
  vim.bo[b].filetype = "disabledclass"
  vim.cmd("doautocmd FileType")
  assert_(calls == before_disable and pencil.mode({ buf = b }) == "off", "FileType does not re-enable disabled buffer")
  drop(b)
  local automatic = buffer("automaticclass")
  pencil.setup({ filetypes = { automaticclass = { mode = "soft" } } })
  vim.cmd("doautocmd FileType")
  assert_(pencil.mode({ buf = automatic }) == "soft", "FileType activates never-managed buffer")
  drop(automatic)
end

print("M005 tests passed")
vim.cmd("qa!")
