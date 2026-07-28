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
for tag in pencil pencil-installation pencil-configuration pencil-api pencil-commands pencil-status pencil-migration; do grep -E "^${tag}[[:space:]]" doc/tags >/dev/null; done
# Generate in a temporary copy so stale committed tags fail instead of being masked.
TAG_CHECK=$(mktemp -d)
trap 'rm -rf "$TAG_CHECK"' EXIT
cp doc/pencil.txt "$TAG_CHECK/pencil.txt"
"$NVIM_BIN" --headless --clean -u NONE +'lua local ok, err = pcall(vim.cmd, "helptags '"$TAG_CHECK"'"); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") else assert(ok) end' +qa
cmp "$TAG_CHECK/tags" doc/tags
run_suite() {
  name=$1
  printf '%s\n' "Running $name"
  # deliberate: bound each isolated Neovim process so a failing standalone script cannot hang CI.
  timeout "${TEST_TIMEOUT:-30}s" "$NVIM_BIN" --headless --clean -u NONE +'set rtp^=.' -c "luafile tests/$name.lua"
}
run_suite bare_install
run_suite smoke
run_suite m005
run_suite m006
git diff --check
