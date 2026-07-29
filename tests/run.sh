#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
NVIM_BIN=${NVIM_BIN:-nvim}
printf '%s\n' "Using: $NVIM_BIN"
"$NVIM_BIN" --version | head -3
"$NVIM_BIN" --headless --clean -u NONE +'set rtp^=.' +'lua local ok, err = pcall(require, "pencil"); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") end' +qa
"$NVIM_BIN" --headless --clean -u NONE +'set rtp^=.' +'lua local ok, err = pcall(vim.cmd, "help pencil"); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") end' +qa
test -f doc/tags
run_suite() {
  name=$1
  printf '%s\n' "Running $name"
  # deliberate: bound each isolated Neovim process so a failing standalone script cannot hang CI.
  timeout "${TEST_TIMEOUT:-30}s" "$NVIM_BIN" --headless --clean -u NONE +'set rtp^=.' -c "luafile tests/$name.lua"
}
run_suite comfortable_column
run_suite unsupported_version
git diff --check
