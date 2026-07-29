# Comfortable Column Public Surface Cleanup Implementation

## Context Summary

Milestones 008–010 already deliver Pencil as a binary, buffer-local presentation state: the bare `:Pencil` command and `setup`, `enable`, `disable`, and `toggle` Lua functions activate a centered, visual-only column using a preferred display width (80 by default), preserve buffer text, reconcile windows and resizing, and restore owned presentation values without overwriting external edits. Milestone 011 makes the release surface truthful by replacing historical hard/soft/detect, formatting, classification, mapping, concealment, status, and filetype documentation and tests with the current contract, removing unused classification seams, preserving the minimal command/API loader, and keeping the isolated comfortable-column and unsupported-version checks green.

## Implementation Checklist

### Slice A — Publish the current comfortable-column product

- [ ] `README.md: complete public documentation` — replace the historical feature/configuration/usage sections with installation, Neovim 0.10+ and no-runtime-dependency requirements, the optional `setup({ width = N })` contract, default width 80, bare `:Pencil`, and the four Lua entry points (`setup`, `enable`, `disable`, `toggle`). State that `setup()` is not required, width changes affect future activations only, narrow windows contract safely, active windows reconcile through resize and lifecycle events, wrapping is visual-only, buffer text remains unchanged, and disable restores owned presentation subject to external ownership changes.
- [ ] `README.md: non-goals and license/attribution` — remove all historical promises and examples; retain only a concise clean-rewrite/non-compatibility non-goal covering hard breaks, autoformat, filetype auto-enable, mappings, concealment, classification, statusline integration, and old commands/configuration. Preserve the existing repository link, MIT license link, copyright notice reference, and attribution.
- [ ] `doc/pencil.txt: help sections` — rewrite `pencil`, `pencil-installation`, `pencil-configuration`, `pencil-api`, `pencil-commands`, `pencil-status` (or a renamed safety section), and `pencil-license` so `:help pencil` gives the README-equivalent normative contract. Document exact call shapes, optional `{ buf = bufnr }` targeting, setup validation and atomicity, future-only width changes, bare `:Pencil` with no arguments/aliases, visual-only safety, lifecycle/restoration behavior, supported Neovim version, no runtime dependencies, and license/attribution. Delete migration and superseded feature sections rather than documenting compatibility.
- [ ] `doc/tags: generated help index` — regenerate or update tags to include every final help section exactly once, including `pencil`, and remove tags for deleted hard/soft/detect/configuration/status/migration sections. Verify every `:help` link in `doc/pencil.txt` resolves.

### Slice B — Remove stale runtime and repository public surface

- [ ] `plugin/pencil.lua: runtime loader` and `lua/pencil/init.lua: module exports and command registration` — retain only the minimal `require("pencil")` loader, the bare zero-argument `:Pencil` command, and the four documented Lua exports. Confirm no aliases, command subcommands, completion, mode/status/format APIs, mappings, concealment, auto-enable, or classification exports remain; preserve the 008–010 runtime behavior unchanged.
- [ ] `lua/pencil/classification.lua: obsolete module` — repository-search all production and acceptance references, then delete this module once no current consumer remains. Do not replace it with a compatibility layer or classifier.
- [ ] `lua/pencil/_test.lua: obsolete classification seam` — delete the test-only classification export after confirming no current acceptance path requires it.
- [ ] `LICENSE: existing MIT text` — leave the file unchanged and verify its MIT terms, `Copyright (c) 2026 Jaron Swab`, and attribution text remain present.

### Slice C — Align the isolated headless acceptance suite

- [ ] `tests/comfortable_column.lua: current-product acceptance coverage` — retain or extend real-code assertions for plugin loading without setup, bare `:Pencil`, Lua command parity, current/explicit buffer targeting, idempotent enable/disable/toggle, default/custom/setup-reset widths, valid and invalid setup atomicity, visual-only preservation for empty/short/long/Unicode/tabbed content, centered/safe narrow presentation, resize, multiple windows, late splits, buffer switching, cleanup, exact restoration, and external ownership edits.
- [ ] `tests/comfortable_column.lua: public-surface assertions` — assert the module exports exactly `setup`, `enable`, `disable`, and `toggle`; the command table contains only `Pencil` for Pencil's command surface; removed command/API terms are absent; README/help contain required current terms and no stale feature claims; every final help tag exists and no stale tag remains. Keep these assertions repository-local and dependency-free.
- [ ] `tests/unsupported_version.lua: isolated unsupported-runtime check` — retain the separate-process version override and assert a clear Neovim 0.10 requirement error before command registration or activation state. Keep the supported process uncontaminated.
- [ ] `tests/run.sh: normal verification entry point` — execute only the current comfortable-column and unsupported-version scripts in isolated headless Neovim processes, retain load/help/parse checks, `git diff --check`, and nonzero failure behavior. Ensure no deleted historical script is invoked.
- [ ] `tests/bare_install.lua`, `tests/smoke.lua`, `tests/m005.lua`, and `tests/m006.lua: superseded acceptance entry points` — delete the historical scripts or replace them with current-product checks; do not retain assertions for modes, hard formatting, autoformat, classification, concealment, mappings, status helpers, presets, aliases, or migration behavior.

### Slice D — Final repository verification

- [ ] `tests/run.sh: full suite` — run the suite on supported Neovim and confirm successful plugin load, `:help pencil`, current comfortable-column behavior, unsupported-version failure, and whitespace validation.
- [ ] `repository-wide references` — search executable files, README, help, tags, and executed tests for stale public terms (`hard`, `soft`, `detect`, `autoformat`, `format`, `mapping`, `conceal`, `classification`, `status`, legacy aliases, and filetype auto-enable) and distinguish historical plan-document references from public/runtime claims. Resolve every executable/public hit required by the spec.
- [ ] `repository-wide load check` — require `pencil` through `plugin/pencil.lua`, verify the command is registered only on supported Neovim, verify removed Lua artifacts have no consumers, and confirm `LICENSE` is unchanged.

Parallel work: README and `doc/pencil.txt` can be rewritten independently after the final API/command contract is fixed; `doc/tags` can be regenerated once help section names settle; obsolete module/test deletion can proceed independently after repository-wide consumer search; runtime acceptance extensions and public-surface assertions can be developed independently and combined through `tests/run.sh`; license and load/parse checks are independent of prose edits.
