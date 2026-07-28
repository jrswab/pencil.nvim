local pencil = require("pencil")
local api = vim.api
local buf = api.nvim_create_buf(true, false)
vim.bo[buf].filetype = "text"
vim.cmd("doautocmd FileType")
assert(pencil.mode({ buf = buf }) == nil, "bare install must not auto-activate")
pencil.enable({ buf = buf, mode = "soft", conceal = false, mappings = { navigation = false, undo_breaks = false } })
assert(pencil.mode({ buf = buf }) == "soft", "bare install direct controls remain available")
pencil.disable({ buf = buf })
api.nvim_buf_delete(buf, { force = true })
print("bare installation activation boundary passed")
vim.cmd("qa!")
