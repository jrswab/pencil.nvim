local original = vim.version
vim.version = function() return { major = 0, minor = 9, patch = 0 } end
local ok, err = pcall(require, "pencil")
vim.version = original
assert(not ok and tostring(err):match("Neovim 0%.10 or newer"), "unsupported version must fail clearly")
assert(vim.api.nvim_get_commands({}).Pencil == nil, "unsupported load must not register command")
print("unsupported version acceptance passed")
vim.cmd("qa!")
