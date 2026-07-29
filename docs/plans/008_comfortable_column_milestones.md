# Comfortable Column Milestones

## 1. Research Findings

### Product intent

The product-design record in `docs/plans/007_comfortable_column_product-design.md` defines two primary jobs:

1. Present a centered, comfortable prose column with visual wrapping only.
2. Let the writer toggle that presentation with `:Pencil` at any time, regardless of filetype or prior state.

The writer-facing model is one binary Pencil on/off state and one preferred measure, not hard versus soft modes. The recommended default measure is 80 characters. Turning Pencil on must visibly center the column, wrap long lines visually inside that measure, and leave buffer text unchanged; turning it off must restore the prior presentation exactly. Empty and short buffers must receive the same obvious centered writing column.

The following are deferred: filetype auto-enable, per-filetype widths, hard wrapping or insert-time autoformat, plugin-owned navigation or undo mappings, conceal management, rich statusline integration, and custom classifiers. Non-goals are compatibility with vim-pencil or pre-rewrite pencil.nvim configuration, and the Hard/Soft/PFormat command families. Pencil must not insert hard breaks, install navigation or undo mappings, or require `setup()` for `:Pencil`.

**Source:** `docs/plans/007_comfortable_column_product-design.md` (Jobs, Entry points, Core flows, Non-goals).

### Current implementation

`lua/pencil/init.lua` is a large single-module implementation with a broad writer-facing surface:

- It models `hard`, `soft`, and `detect`, plus format subcommands, aliases, mappings, concealment, status reporting, and classification (`lua/pencil/init.lua`, `defaults`, `presets`, `validate`, command completion, and autocmd setup).
- Soft mode owns `wrap`, `linebreak`, and `breakindent`, then uses `soft_statuscolumn` to add left padding. This is not true centering of a maximum-width prose column with symmetric margins; in soft mode `textwidth` is unused (`lua/pencil/init.lua`, `window_options`, `soft_statuscolumn`, `desired_window`).
- The module owns window presentation options `wrap`, `linebreak`, `breakindent`, `conceallevel`, `concealcursor`, and `statuscolumn`; buffer `textwidth` and `formatoptions` are owned for hard mode (`lua/pencil/init.lua`, `window_options`, `reconcile_buffer`, `reconcile_formatoptions`).
- Active state is buffer-level. Window baselines are tracked independently, enabling presentation in all windows showing the buffer and resize reconciliation; window ownership and restore are handled by `apply_window`, `restore_window`, and the autocmd lifecycle (`lua/pencil/init.lua`).
- Classification and hard-format behavior account for substantial code in `classification.lua` and `lua/pencil/init.lua`; that surface becomes unnecessary when hard autoformat/classification is removed.

The headless test entry point is `tests/run.sh`, which runs the current smoke, bare, `m005`, and `m006` coverage with `rtp^=.`. Those tests describe the existing product and will need to be rewritten for the comfortable-column behavior rather than preserving hard/soft expectations.

### Approach decisions

Continuing vim-pencil parity, or retaining hard/soft/detect as the primary model, is rejected because it does not satisfy the two jobs in `docs/plans/007_comfortable_column_product-design.md`. An additive in-place “center mode” beside the full old surface is also rejected because it leaves two competing products and a messy dual API.

The accepted approach is a UX-led rewrite replacing the writer-facing model with a binary comfortable-column experience. Existing ownership, exact-restore, multi-window, resize, and presentation mechanics may be reused only where they serve that experience. For v1, auto-enable, per-filetype width, statusline helper, plugin mappings, conceal, hard autoformat, and classification remain rejected/deferred.

### Resolved decisions

| Question | Decision | Source |
|---|---|---|
| Default measure | 80 characters | `docs/plans/007_comfortable_column_product-design.md` recommendation and prior defaults in `lua/pencil/init.lua` |
| Split model | Pencil on/off is buffer-local; every window displaying that buffer receives the centered column, with independent window-option ownership and restore | Existing multi-window contract in `lua/pencil/init.lua` and `docs/plans/000_pencil_nvim_milestones.md`; “one obvious state” in `docs/plans/007_comfortable_column_product-design.md` |
| First Lua API slices | Minimal `enable`, `disable`, and `toggle` (with optional `setup`) are acceptable and expected so headless tests can drive the behavior; no new `mode`, `status`, or `set_autoformat` surface | Testability decision and `docs/plans/007_comfortable_column_product-design.md` entry points |
| Compatibility | No drop-in compatibility with old pencil.nvim commands/configuration or vim-pencil globals | Non-goals in `docs/plans/007_comfortable_column_product-design.md` and compatibility decisions in `docs/plans/000_pencil_nvim_milestones.md` |
| Prior milestones | `001`–`006` are historical and superseded for this product direction; new work is tracked as `008_*` onward | `docs/plans/007_comfortable_column_product-design.md` rewrite decision and existing `docs/plans/001_*` through `docs/plans/006_*` |
| Centering quality | Success requires the prose measure to be centered in the window with symmetric margins and visual wrapping within it; left-padding-only `statuscolumn` behavior is insufficient | `docs/plans/007_comfortable_column_product-design.md` design and `lua/pencil/init.lua` `soft_statuscolumn` |
| Must not | Do not insert hard breaks, install navigation/undo mappings, or require setup before `:Pencil` works | `docs/plans/007_comfortable_column_product-design.md` Core flows and Implementation notes |

### Constraints

- Support Neovim 0.10+ and fail clearly and without partial activation on unsupported versions (`lua/pencil/init.lua`, version check; `docs/plans/000_pencil_nvim_milestones.md`).
- Require no runtime dependencies.
- Restore every owned option exactly on disable, subject to ownership remaining with Pencil; do not leave width hacks or partial presentation state (`docs/plans/007_comfortable_column_product-design.md`; ownership rules in `docs/plans/000_pencil_nvim_milestones.md`).
- Sequential specifications will use `docs/plans/008_*.md`, `009_*.md`, and so on.

### Assumptions

- Replacing the public surface means old tests and documentation are rewritten against the new behavior as part of later milestone acceptance; they are not kept green for hard/soft behavior.
- `lua/pencil/init.lua` may be replaced or substantially reorganized. `lua/pencil/classification.lua` is likely deleted once hard autoformat and classification are gone.
- The current ownership and restoration mechanics are evidence, not a commitment to preserve the old module structure.

### Milestone acceptance boundaries

- **008** establishes the smallest end-to-end toggle: one window, measure 80, empty and non-empty buffers, visual wrapping and symmetric centering, exact restore, and clean unsupported-version failure. It does not cover resize, multiple windows, configurable width, or documentation cleanup.
- **009** extends the working toggle across resize and all windows displaying the buffer, including splits created while Pencil is on. It does not add configuration or broaden the public product.
- **010** adds only an optional preferred measure configuration applied on enable, with atomic rejection of invalid configuration. It does not add filetype-specific widths or auto-enable.
- **011** is the release-level comfortable-column surface: documentation, help, commands, Lua API, and headless tests describe and verify only the binary comfortable-column UX, with hard/soft/detect/autoformat/mappings/classification removed from the product surface.

## 2. Milestones

- [ ] 008: Deliver `:Pencil` as a binary toggle for a centered, visual-wrap comfortable column at measure 80, with exact presentation restore on off for a single window and both empty and non-empty buffers, and a clean failure without partial state on unsupported Neovim versions.
- [ ] 009: Deliver correct comfortable-column behavior through window resize and across multiple windows showing the same buffer, including splits opened while Pencil is on, while preserving the buffer-local toggle and each window’s independent ownership and restore.
- [ ] 010: Deliver optional `setup` configuration for a preferred measure (width) applied on enable, with invalid configuration rejected atomically and without partial state; filetype auto-enable and per-filetype widths remain excluded.
- [ ] 011: Deliver a documented and tested public surface containing only the comfortable-column UX—cleaned help, README, commands, and Lua API without hard/soft/detect/autoformat/mappings/classification—and a green headless suite for the new behavior.
