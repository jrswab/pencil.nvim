local api = vim.api
local pencil = require("pencil")
local function fresh(lines)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end
local function check(value, message) assert(value, message) end

local exports = {}
for name in pairs(pencil) do exports[name] = true end
for _, name in ipairs({ "setup", "enable", "disable", "toggle" }) do
  check(exports[name], "public export: " .. name)
  exports[name] = nil
end
check(next(exports) == nil, "no stale Lua exports")
for _, name in ipairs({ "HardPencil", "SoftPencil", "NoPencil", "PencilOff", "TogglePencil", "PencilToggle", "PFormat", "PFormatOff", "PFormatToggle" }) do
  check(api.nvim_get_commands({})[name] == nil, "removed command: " .. name)
end
local help = assert(io.open("doc/pencil.txt", "r")):read("*a")
for _, tag in ipairs({ "pencil", "pencil-installation", "pencil-configuration", "pencil-api", "pencil-commands", "pencil-safety", "pencil-license" }) do
  check(help:find("*" .. tag .. "*", 1, true) ~= nil, "help section: " .. tag)
end
local tags = assert(io.open("doc/tags", "r")):read("*a")
for _, tag in ipairs({ "pencil", "pencil-installation", "pencil-configuration", "pencil-api", "pencil-commands", "pencil-safety", "pencil-license" }) do
  check(tags:find(tag .. "\t", 1, true) ~= nil, "help tag: " .. tag)
end
local readme = assert(io.open("README.md", "r")):read("*a")
for _, term in ipairs({ "Neovim 0.10", "No runtime dependencies", ":Pencil", "setup({ width = 80 })", "visual", "future activations" }) do
  check(readme:find(term, 1, true) ~= nil, "README term: " .. term)
end

local buf = fresh({ string.rep("x", 200) })
local original = api.nvim_buf_get_lines(buf, 0, -1, false)
vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent = false, false, false
vim.wo.statuscolumn = ""
vim.bo[buf].wrapmargin = 0
vim.wo.colorcolumn = "17"
vim.o.columns = 120
api.nvim_win_set_width(0, 120)
vim.cmd("Pencil")
check(vim.wo.wrap and vim.wo.linebreak and vim.wo.breakindent, "visual wrapping")
check(vim.wo.statuscolumn:match("^ +") ~= nil, "left column margin")
check(vim.bo[buf].wrapmargin > 0, "right column margin")
check(api.nvim_buf_get_lines(buf, 0, -1, false)[1] == original[1], "buffer unchanged on enable")
local enabled_column = vim.wo.statuscolumn
pencil.enable({ buf = buf })
check(vim.wo.statuscolumn == enabled_column, "repeated enable is idempotent")
vim.bo[buf].wrapmargin = 3
pencil.disable({ buf = buf })
check(not vim.wo.wrap and not vim.wo.linebreak and not vim.wo.breakindent, "restores window options")
check(vim.bo[buf].wrapmargin == 3, "external edit survives disable")
check(vim.wo.statuscolumn == "" and vim.wo.colorcolumn == "17", "restores presentation baseline")
check(api.nvim_buf_get_lines(buf, 0, -1, false)[1] == original[1], "buffer unchanged on disable")

local empty = fresh({ "" })
api.nvim_win_set_width(0, 60)
pencil.toggle({ buf = empty })
check(vim.wo.wrap and vim.bo[empty].wrapmargin >= 0, "narrow empty buffer remains usable")
pencil.toggle({ buf = empty })
check(not vim.wo.wrap, "toggle restores empty buffer")

local command_buf = fresh({ "short" })
vim.cmd("Pencil")
check(vim.wo.wrap, "bare command enables")
vim.cmd("Pencil")
check(not vim.wo.wrap, "bare command disables")

-- 009: activation and restoration are buffer-wide, while window presentation stays independent.
local multi = fresh({ string.rep("m", 160) })
local first = api.nvim_get_current_win()
vim.o.columns = 220
vim.cmd("vsplit")
local second = api.nvim_get_current_win()
api.nvim_win_set_width(first, 120)
api.nvim_win_set_width(second, 60)
vim.wo[first].wrap, vim.wo[first].linebreak, vim.wo[first].breakindent = false, false, false
vim.wo[second].wrap, vim.wo[second].linebreak, vim.wo[second].breakindent = false, false, false
vim.wo[first].statuscolumn, vim.wo[second].statuscolumn = "", "%s%C"
vim.bo[multi].wrapmargin = 7
pencil.enable({ buf = multi })
check(vim.wo[first].wrap and vim.wo[second].wrap, "all visible windows enabled")
check(vim.wo[first].statuscolumn ~= vim.wo[second].statuscolumn, "window widths have independent margins")
local first_on, second_on = vim.wo[first].statuscolumn, vim.wo[second].statuscolumn
vim.cmd("resize 70")
vim.wait(20)
check(vim.wo[api.nvim_get_current_win()].statuscolumn ~= nil, "resize remains usable")
pencil.disable({ buf = multi })
check(not vim.wo[first].wrap and not vim.wo[second].wrap, "multi-window disable restores both windows")
check(vim.wo[first].statuscolumn == "" and vim.wo[second].statuscolumn == "%s%C", "independent baselines restored")
check(vim.bo[multi].wrapmargin == 7, "buffer baseline restored")

local other = fresh({ "other" })
local lifecycle = api.nvim_get_current_win()
api.nvim_set_current_buf(multi)
pencil.enable({ buf = multi })
api.nvim_set_current_buf(other)
vim.wait(20)
check(not vim.wo[lifecycle].wrap, "switching away removes active presentation")
api.nvim_set_current_buf(multi)
vim.wait(20)
check(vim.wo[lifecycle].wrap, "switching back reapplies active presentation")
vim.cmd("split")
local late = api.nvim_get_current_win()
vim.wait(20)
check(vim.wo[late].wrap, "late split receives active presentation")
vim.cmd("close")
pencil.disable({ buf = multi })
api.nvim_set_current_buf(other)
check(not vim.wo[lifecycle].wrap, "disable does not leak to another buffer")
local wiped = fresh({ "wiped" })
pencil.enable({ buf = wiped })
api.nvim_buf_delete(wiped, { force = true })
vim.wait(20)

-- 010: setup changes only future activations and rejects invalid input atomically.
pencil.setup({ width = 30 })
local configured = fresh({ string.rep("c", 100) })
api.nvim_win_set_width(0, 100)
pencil.enable({ buf = configured })
check(vim.bo[configured].wrapmargin > 0, "configured width applies")
local configured_margin = vim.bo[configured].wrapmargin
pencil.setup({ width = 10 })
check(vim.bo[configured].wrapmargin == configured_margin, "active width remains stable")
local ok = pcall(pencil.setup, { width = 20, unknown = true })
check(not ok and vim.bo[configured].wrapmargin == configured_margin, "invalid setup is atomic while active")
pencil.setup(nil)
pencil.disable({ buf = configured })
ok = pcall(pencil.setup, { width = 20, unknown = true })
check(not ok, "unknown setup key rejected")
local next_buf = fresh({ "next" })
pencil.enable({ buf = next_buf })
check(vim.bo[next_buf].wrapmargin ~= configured_margin, "valid setup replaces future width")
pencil.disable({ buf = next_buf })
for _, invalid in ipairs({ 0, -1, 1.5, "20", false, {}, function() end, math.huge, 0 / 0 }) do
  ok = pcall(pencil.setup, { width = invalid })
  check(not ok, "invalid width rejected")
end
pencil.setup({})
local default_buf = fresh({ "default" })
pencil.enable({ buf = default_buf })
check(vim.bo[default_buf].wrapmargin > 0, "empty setup restores default width")
pencil.disable({ buf = default_buf })

print("comfortable column acceptance passed")
vim.cmd("qa!")
