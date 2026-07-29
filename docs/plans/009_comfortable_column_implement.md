# Comfortable Column Resize and Multi-Window Implementation

## Context Summary

Milestone 009 extends the binary, buffer-local 80-column Pencil presentation from the current window to every window displaying the buffer and keeps it reconciled through resize and window/buffer lifecycle events. Each window owns its own pre-Pencil presentation baseline; Pencil remains visual-only, does not configure width, and must preserve externally changed values.

## Implementation Checklist

### Slice A — Buffer-wide activation

- [ ] `lua/pencil/init.lua: windows_for_buffer()` / `enable()` — discover every valid window displaying the selected buffer and apply the existing centered visual-wrap presentation once per window without replacing active baselines.
- [ ] `tests/comfortable_column.lua: multi-window activation and restoration` — verify different-width splits, independent baselines, command/API parity, unchanged buffer text, and buffer-wide disable.

### Slice B — Resize reconciliation

- [ ] `lua/pencil/init.lua: desired()` / `reconcile()` — recompute each active window's safe centered margins from its current available width on `WinResized` and `VimResized`, preserving ownership and original restore values.
- [ ] `tests/comfortable_column.lua: resize assertions` — verify expansion, contraction, exact/narrow widths, repeated convergence, and external edits surviving resize and disable.

### Slice C — Window and buffer lifecycle

- [ ] `lua/pencil/init.lua: reconcile_window()` / lifecycle autocmd callbacks — apply active state when a split or buffer switch displays an enabled buffer, restore the prior window presentation when it leaves, and discard closed/wiped records without errors.
- [ ] `tests/comfortable_column.lua: split, switch, close, and wipe assertions` — verify no presentation leaks to other buffers, safe return without compounding, sibling isolation, and cleanup.

### Slice D — Regression verification

- [ ] `tests/run.sh: headless suite` — run the comfortable-column and unsupported-version processes plus Lua parse and diff checks; preserve the 008 acceptance behavior and exclude configurable width/documentation work.

Slices B and C can be developed independently after Slice A's per-window ownership contract exists. Cleanup tests can run independently of normal activation tests.
