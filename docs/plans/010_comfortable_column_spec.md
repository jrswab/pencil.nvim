# Comfortable Column Preferred Measure Specification

## 1. Context & Constraints

### Product intent

Milestone 010 adds the only configuration needed for the comfortable-column product's primary job: a writer may choose the preferred visual measure used when Pencil is enabled. Pencil remains a binary, buffer-local presentation toggle. The default preferred measure remains 80 display columns, and `:Pencil` remains usable without calling `setup()`.

When Pencil is on, every applicable window presents a visual-only, centered column at the configured preferred measure whenever the window has enough available text width. Narrow windows contract safely to their available text area. Buffer contents, hard line breaks, and unrelated editor state remain unchanged.

### Repository evidence and continuity

- `docs/plans/007_comfortable_column_product-design.md` defines `setup({ ... })` as an optional configuration entry point, identifies width as the minimal configuration key, and recommends 80 as the default measure.
- `docs/plans/008_comfortable_column_milestones.md` makes 010 responsible only for an optional preferred measure and atomic invalid-configuration rejection. Filetype-specific widths and auto-enable remain deferred.
- `docs/plans/008_comfortable_column_spec.md` establishes the binary command/Lua surface, visual-only wrapping, centered presentation, exact restoration, and no-setup default behavior.
- `docs/plans/009_comfortable_column_spec.md` establishes that the active buffer's presentation applies to every window displaying it, recalculates against each window's available width, handles resize and late splits, and keeps independent per-window restoration ownership. The configured measure must participate in those same lifecycle rules rather than creating a second presentation model.
- `lua/pencil/init.lua` currently exposes `setup()` as a placeholder that accepts no non-empty options, uses a hard-coded preferred measure of 80, and already has the buffer/window lifecycle seam delivered by 009. This milestone changes the accepted setup contract and the measure used by future activations; it does not broaden the public surface.
- Existing worktree tests and historical plans may still mention the superseded hard/soft/detect product. They are not requirements for this rewrite. Milestone 011 owns final documentation, help, and public-surface cleanup.

### Decisions already made

- The public configuration key is `width`; it represents the preferred measure in display columns. `measure` is not a second spelling and is not required.
- The default width is 80.
- `setup()` is optional. The default command and Lua behavior must work before setup.
- Setup configuration is global and applies to future enable operations. It does not create filetype-specific behavior, auto-enable buffers, or a width command.
- A valid setup replaces the prior global preferred width. An empty setup selects the default width of 80.
- Existing active buffers keep the measure they received for their current activation. A later valid setup does not unexpectedly move an active writer's column; disabling and re-enabling uses the new configuration.
- Invalid setup is rejected as one failed operation. The previous valid configuration and all active presentations remain unchanged.
- A preferred width is a positive integer number of display columns. Fractional, zero, negative, non-numeric, non-finite, and otherwise malformed values are invalid. Values do not need to be capped merely because a particular window is narrower; the presentation contracts at the window boundary.
- Unknown setup keys are invalid. This keeps the configuration surface narrow and prevents accidental introduction of filetype maps or unrelated legacy options.
- Setup validation is atomic across the complete input: if any key or value is invalid, no part of the new configuration is installed and no active buffer is reconfigured.
- Neovim 0.10+ and no runtime dependencies remain supported-platform constraints. Unsupported-version failure and the existing 009 lifecycle safety contract remain in force.

### Scope boundary

This milestone includes:

- Accepting `require("pencil").setup({ width = N })` for a valid preferred measure.
- Applying that measure when Pencil is enabled through `:Pencil` or the Lua control API.
- Applying the active measure consistently to all windows, resize reconciliation, and windows that begin displaying an active buffer.
- Replacing the configured default atomically and preserving it across future enable/disable cycles.
- Rejecting malformed setup input without changing configuration, active presentation, buffer text, or restoration ownership.
- Headless verification of default, configured, narrow-window, lifecycle, and failure behavior.

This milestone excludes:

- Filetype-specific widths, width maps, filetype auto-enable, or any automatic activation.
- A command or runtime API for changing width on an already-active buffer.
- Hard wrapping, insert-time autoformat, classification, concealment, plugin mappings, navigation, undo behavior, statusline integration, and compatibility with the superseded product.
- The release-level documentation and public-surface cleanup assigned to milestone 011, except for any minimal test or API seam necessary to verify this configuration.

### Configuration and activation rules

- Before any valid setup, enabling uses width 80.
- After `setup({ width = N })` succeeds, each subsequent activation uses N, including activation through the bare command and `enable`/`toggle` Lua calls.
- `disable()` restores the presentation baseline captured for that activation; it does not reset or mutate the global preferred width.
- `setup({})` is valid and restores the default preferred width of 80 for subsequent activations.
- Calling `setup(nil)` retains the existing optional-setup behavior and does not alter the configured width.
- Calling `setup()` with a non-table value other than nil is invalid.
- Repeated valid setup calls replace the setting for future activations only. No active buffer is implicitly disabled, re-enabled, resized to a new measure, or given a new restoration baseline.
- A failed setup must not partially change the setting, even if multiple invalid keys or values are present. It must report a clear error identifying the invalid configuration; exact error wording is not part of the public contract.
- A valid width larger than the current window is not an error. The active presentation uses the same safe contraction behavior already required by 009.

## 2. Requirements

### Vertical slice A: Configure and use a preferred measure

1. `require("pencil").setup({ width = N })` must accept every valid positive integer width.
2. After successful setup, enabling an otherwise inactive buffer through `:Pencil` must present the configured width when the available text area is at least N display columns.
3. The same configured width must be used by `enable()` and `toggle()` when they start an activation, whether targeting the current buffer or an explicit valid buffer.
4. The presentation must remain centered with symmetric spare margins around the configured column.
5. Visual wrapping must occur within the configured measure without inserting, deleting, or reflowing buffer text.
6. Empty, short, Unicode, and tabbed buffers must use the configured display-column measure just as they use the default measure.
7. Turning Pencil off must restore each window's pre-activation presentation exactly according to the 008/009 ownership rules; the configured width must not become part of the restored editor state.

### Vertical slice B: Preserve the default and narrow-window behavior

1. Without setup, or after `setup({})`, the preferred width must be 80.
2. A configured width greater than the available text area must contract safely to that area rather than fail, overflow, or create negative/asymmetric artificial spacing.
3. A configured width equal to the available text area must produce no artificial spare margin while retaining visual wrapping behavior.
4. Resizing an active window must recalculate margins using the activation's preferred width and the window's current available text area.
5. Different windows showing one active buffer may have different margins because their available widths differ, but they must use the same configured preferred width wherever it fits.
6. Repeated resize, split, buffer-switch, and return events must not compound margins, acquire a new baseline, or substitute the current global setup value for the width already used by the activation.

### Vertical slice C: Reject invalid setup atomically

1. Setup input must be rejected when it is not a table, except that nil retains the optional no-op behavior.
2. Setup input must be rejected when it contains an unknown key.
3. The `width` value must be rejected when it is missing only if another representation is supplied in its place; valid empty configuration remains supported. Specifically, accepted width values are positive integers, and zero, negative, fractional, string, boolean, function, table, NaN, infinity, and other non-finite values are invalid.
4. A failed setup must leave the previously configured width in effect for the next activation.
5. If a buffer is already active when invalid setup is attempted, its current presentation, measure, ownership records, restoration baseline, and buffer contents must remain unchanged.
6. A failed setup containing multiple invalid entries must make no partial update based on any valid-looking entry in that same input.
7. After a failed setup, a later valid setup must still replace the prior valid width normally.
8. Invalid setup must not register commands, install mappings, change filetype behavior, mutate buffers, or alter unrelated window or buffer options.

### Vertical slice D: Keep the binary surface and lifecycle boundary

1. The bare `:Pencil` command must continue to work without setup and must use the current configured width or the default 80.
2. `enable`, `disable`, and `toggle` retain their existing buffer-targeting and idempotence semantics; no width-specific API is added.
3. A valid setup must not implicitly activate inactive buffers or reconfigure active buffers.
4. Filetype must not affect width selection, and no FileType event may auto-enable a buffer as a result of this milestone.
5. Pencil must continue to change only the presentation values required for the centered visual column. It must not modify hard line breaks, mappings, conceal settings, statusline values, or unrelated editor options.
6. Unsupported Neovim versions must continue to fail before successful plugin activation, independently of setup validation.

### Edge cases

- `setup({})` after a custom width returns future activations to 80.
- A valid width of 1 is accepted and remains usable in windows with available width 1 or greater.
- Very large positive widths are accepted as preferences and contract safely in narrower windows; they do not cause setup failure solely because the current window is small.
- Widths are display-column measures, not byte counts or Lua string lengths.
- A user changes an owned presentation value while an activation uses a custom width, then resizes or switches windows; ownership transfer and restoration follow 009 and must not overwrite the user change.
- Setup is called repeatedly while one or more buffers are active; active presentations remain stable until their normal disable/re-enable boundary.
- A failed setup occurs while no buffers are active and while buffers are active; both cases preserve the prior state.
- A valid setup is followed by disable, a window split, and a later re-enable; the new activation uses the latest valid width and takes fresh per-window baselines.
- Calling disable while inactive remains a no-op regardless of the configured width.
- Non-prose filetypes remain eligible for manual activation with the configured width.

### Parallelizable work

- Setup validation and atomic state-preservation tests can be developed independently of layout tests once the width contract is fixed.
- Default/custom-width layout tests can run independently of resize and multi-window lifecycle tests because all use the same preferred-measure rule.
- Resize and late-window tests can be extended from 009 independently of setup error-path tests, provided they assert that one activation retains one preferred width.
- Command/Lua parity tests can run independently of invalid-input tests.

### Verification expectations

The milestone is complete only when isolated headless checks verify that:

- the bare command works before setup and uses the default width 80;
- valid setup changes the preferred width for later command and Lua activations;
- empty, short, long, Unicode, and tabbed content remains unchanged and wraps visually inside the configured measure;
- centering, safe contraction, resize, split, and buffer-window lifecycle behavior from 009 remains correct with a custom width;
- active buffers are not implicitly reconfigured by later valid setup calls;
- disable restores per-window baselines and preserves user edits;
- invalid types, values, and keys are rejected atomically, preserving both prior configuration and active presentation;
- `setup({})` restores the default for future activations; and
- no filetype-specific width, auto-enable behavior, or milestone-011 documentation/public-surface work is required for acceptance.

No implementation structure is prescribed; acceptance is based on the observable setup, activation, layout, lifecycle, restoration, and atomic-failure behavior above.
