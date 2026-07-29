# Comfortable Column Toggle Specification

## 1. Context & Constraints

### Product intent

This milestone establishes the first usable slice of the comfortable-column rewrite. The writer has one primary presentation toggle: Pencil is either on or off for the current buffer. When it is on, the current window presents a centered prose column with a preferred measure of 80 characters and visual wrapping. When it is off, the presentation returns to the state that existed before Pencil was enabled.

The product is a Neovim plugin for writers editing prose. The primary entry point is the bare `:Pencil` command. The first Lua API slice also includes `require("pencil").enable`, `disable`, and `toggle`, with optional `setup` support only where needed to make the API callable; `setup()` is not required before `:Pencil` works.

### Relevant repository evidence

- `lua/pencil/init.lua` is currently the main module and currently exposes a substantially larger hard/soft/detect product. Its current `soft_statuscolumn` behavior adds left padding and is not sufficient evidence of the required symmetric centered-column behavior.
- The current module already performs a Neovim version check, owns window presentation options, and tracks restoration baselines. These are existing behaviors to replace or reuse only when they satisfy this specification.
- `plugin/pencil.lua` is the runtime-loading surface that makes the command available when the plugin is on `runtimepath`.
- `tests/run.sh` is the headless test entry point. Existing smoke, bare-install, `m005`, and `m006` tests assert the superseded hard/soft/detect product and are not acceptance criteria for this milestone. The milestone's acceptance tests must instead exercise the comfortable-column behavior.
- `README.md` and `doc/pencil.txt` currently document the superseded product. Documentation cleanup is explicitly outside this milestone and belongs to milestone 011.

### Decisions already made

- Default measure is 80 characters.
- Pencil state is buffer-local: enabling a buffer makes the buffer's presentation active, although this milestone verifies only the single-window case. Multi-window propagation and late-created splits are milestone 009.
- The first API slices are `enable`, `disable`, and `toggle`; no public `mode`, `status`, or `set_autoformat` API is required for this milestone.
- The bare `:Pencil` command toggles the current buffer/window presentation and must work without a prior `setup()` call.
- Centering must produce a genuinely centered column with symmetric margins. Left-padding-only status-column behavior is not acceptable.
- Wrapping is visual only. Pencil must not insert, delete, or reflow buffer text.
- Hard wrapping, insert-time autoformat, filetype auto-enable, per-filetype widths, conceal management, plugin-owned navigation or undo mappings, rich statusline integration, classifiers, and compatibility with the old pencil.nvim or vim-pencil surfaces are excluded.
- Neovim 0.10+ is supported. Unsupported versions must fail clearly and must not partially activate.
- There are no runtime dependencies.

### Scope boundary

Milestone 008 covers one window, the default measure of 80, empty and non-empty buffers, visual wrapping, symmetric centering, exact restoration on disable, and unsupported-version failure. It does not cover resize reconciliation, multiple windows, splits opened while active, configurable width, filetype-specific behavior, or documentation/public-surface cleanup.

### Constraints and restoration rules

- Buffer contents must remain byte-for-byte unchanged across enable, toggle, and disable.
- Pencil may change only presentation state needed for the comfortable column. It must not install mappings or alter unrelated editor settings.
- Every presentation value changed by Pencil must have an exact pre-enable baseline for restoration. On disable, a value changed externally while Pencil is active is not owned by Pencil anymore and must be preserved rather than overwritten.
- A failed enable must leave both buffer content and presentation in their pre-enable state; no partial activation is permitted.
- A repeated enable while already enabled must not create a second layer of ownership or lose the original baseline.
- Disabling an already-disabled buffer is a no-op and must not create presentation changes.

## 2. Requirements

### Vertical slice A: Load and expose the binary toggle

1. Loading the plugin on Neovim 0.10 or newer must succeed without runtime dependencies.
2. The plugin must provide a bare `:Pencil` command.
3. Running `:Pencil` when Pencil is off must enable the comfortable-column presentation for the current buffer in the current window.
4. Running `:Pencil` again must disable Pencil and restore the prior presentation exactly.
5. The Lua API must provide:
   - `enable(opts?)`, targeting the current buffer when no options are supplied;
   - `disable(opts?)`, targeting the current buffer when no options are supplied; and
   - `toggle(opts?)`, targeting the current buffer when no options are supplied.
6. The API calls must have the same on/off behavior as the command. No `setup()` call may be required for these default behaviors.
7. Routine successful enable, disable, and toggle operations must not require statusline changes or user keymaps.

### Vertical slice B: Present a centered 80-character column

1. Enabling Pencil in a window wide enough to display the preferred measure must visibly establish an 80-character writing column centered in the available text area.
2. The left and right margins around the writing column must be equal whenever the window has spare horizontal space. A presentation that merely pads the left side is not compliant.
3. Text longer than the preferred measure must wrap visually within the centered column.
4. Visual wrapping must not insert hard line breaks or otherwise mutate the buffer. The original long line must remain the original long line after enable and disable.
5. The centered column must be present for an empty buffer and for a buffer containing only short lines; it must not depend on long content being present.
6. Short lines must remain short while being displayed inside the centered column; enabling Pencil must not pad buffer lines with spaces.
7. The presentation must apply to the writing text area after accounting for normal window decoration such as the existing sign, fold, or number area. Unrelated decoration and options must not be changed merely to create the column.
8. If the available text area is narrower than 80 characters, the presentation must remain usable without negative or invalid spacing. The column may contract to the available text area, but it must not create horizontal overflow, invalid option values, or asymmetric artificial padding.
9. Unicode display width and tabs must be handled according to Neovim's display-width rules: the measure is a visual character/display-width measure, not a byte count.

### Vertical slice C: Restore the prior presentation

1. Before enabling, acceptance tests must be able to set non-default presentation values, including wrapping-related options and any presentation option used for centering. Disable must restore those values exactly.
2. Disable must restore the prior presentation for both an empty buffer and a non-empty buffer.
3. Disable must not alter buffer text, cursor content, unrelated window options, buffer options, statusline values, or user mappings.
4. If the user changes a Pencil-owned presentation value while Pencil is enabled, disabling Pencil must preserve the user's changed value rather than restoring over it.
5. Re-enabling after a completed disable must take a fresh baseline and must restore that new baseline on the next disable.
6. A failed or interrupted enable must restore any values changed before the failure and leave the buffer in the off state.

### Vertical slice D: Unsupported-version failure

1. Loading the module on Neovim versions below 0.10 must fail with a clear error identifying that Neovim 0.10 or newer is required.
2. The failure must occur before the plugin can report a successful active state or apply the comfortable-column presentation.
3. The unsupported-version path must not leave partially registered commands, modified options, modified buffers, or other activation state.
4. The supported-version check must be exercised in an isolated headless process or equivalent test so the normal running Neovim process is not contaminated by the simulated version.

### Edge cases

- Empty buffers and one-line/short buffers receive the same centered-column presentation as long prose buffers.
- A window exactly at the preferred width has no spare margin; it must still wrap correctly and must not add negative padding.
- A window narrower than the preferred width must degrade safely as described above rather than fail partially.
- A long physical line must visually wrap without changing its physical line count or contents.
- Repeated toggles must alternate predictably: on, off, on, off, with each off restoring the corresponding pre-enable state.
- Calling `enable` twice while already on must preserve the original restoration baseline and must not compound visual padding or ownership.
- Calling `disable` while off must not change the current presentation.
- Non-prose filetypes are not special in this milestone: the manual toggle must work regardless of filetype, and no FileType-based auto-enable is required.
- Existing user mappings must remain untouched; Pencil must not install navigation or undo mappings.
- Existing conceal settings must remain untouched; conceal management is deferred.

### Parallelizable work

- The one-window presentation behavior and its exact-restore behavior can be specified and tested in parallel once the binary activation contract is fixed.
- Empty/short-buffer coverage and long-line visual-wrap coverage can be developed in parallel because both use the same default measure and presentation contract.
- The supported-version loading checks and isolated unsupported-version failure check can be developed independently of layout assertions.
- Command/API parity tests can be developed independently of the visual layout tests, provided both use the same single-buffer state contract.

### Verification expectations

The milestone is complete only when isolated headless tests verify all of the following: bare `:Pencil` works without setup; Lua enable/disable/toggle work; the default measure is 80; empty and non-empty buffers visibly receive centered presentation; long lines wrap visually without text mutation; pre-existing presentation is restored exactly; external edits are preserved on disable; repeated enable/disable does not compound state; and unsupported Neovim versions fail clearly without partial activation.
