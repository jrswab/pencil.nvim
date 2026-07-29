# Comfortable Column Preferred Measure Implementation

## Context Summary

Milestone 010 adds the narrow optional configuration seam to the existing binary Pencil presentation: `setup({ width = N })` selects the preferred display-column measure for future activations, while setup remains optional and defaults to 80. The existing 009 buffer-wide lifecycle, centered visual wrapping, per-window ownership, exact restoration, and no-hard-wrap behavior remain unchanged. Configuration validation must be atomic; invalid input cannot alter the configured width or active presentations. Filetype behavior, auto-enable, width commands, and milestone-011 public-surface cleanup are outside this slice.

## Implementation Checklist

### Slice A — Configure and use a preferred measure

- [x] `lua/pencil/init.lua: preferred_width` and `M.setup()` — retain one global preferred width, accept `nil`, `{}`, and `{ width = N }`, validate positive finite integers, reject unknown keys and non-table input, and commit only after complete validation.
- [x] `lua/pencil/init.lua: M.enable()` / `apply()` / `desired()` — snapshot the preferred width into each activation and calculate each window's centered, safely contracted presentation from that snapshot; preserve existing command, `enable()`, and `toggle()` behavior.
- [x] `tests/comfortable_column.lua: configured activation assertions` — verify custom width is used, active buffers remain stable after later valid setup, later activations use the replacement, and buffer contents remain unchanged.

### Slice B — Preserve defaults and lifecycle behavior

- [x] `lua/pencil/init.lua: setup state and existing reconciliation callbacks` — retain default 80, `setup({})` reset, per-window resize/split/buffer lifecycle reconciliation, and exact restoration without adding a width-specific command or active reconfiguration path.
- [x] `tests/comfortable_column.lua: default and lifecycle assertions` — verify command/Lua parity, narrow-window safety, multi-window and late-split behavior, disable restoration, and default behavior after an empty setup.

### Slice C — Reject invalid setup atomically

- [x] `lua/pencil/init.lua: M.setup()` — reject malformed tables, unknown keys, non-positive/fractional/non-finite/non-number widths as one failed operation; leave prior configuration and active presentation untouched.
- [x] `tests/comfortable_column.lua: setup failure assertions` — exercise invalid values and mixed invalid entries, then verify the prior setting remains effective and active state can still be disabled/restored.

Parallel work: configured layout tests and setup failure tests can be developed independently after the setup contract exists; existing lifecycle tests verify the unchanged 009 seam.

## Verification

- [x] `tests/run.sh` — run isolated headless acceptance scripts and `git diff --check`.
- [x] `lua/pencil/init.lua` — parse/load through the headless suite.
