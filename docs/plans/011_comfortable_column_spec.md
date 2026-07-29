# Comfortable Column Public Surface Cleanup Specification

## 1. Context & Constraints

### Product intent

Milestones 008–010 delivered the comfortable-column product: Pencil is a binary, buffer-local presentation state. When enabled, every applicable window presents a centered visual column at the configured preferred measure; visual wrapping does not modify buffer text. The default preferred measure is 80 display columns, and `setup({ width = N })` changes the preferred measure for future activations. The bare `:Pencil` command works without setup.

Milestone 011 is the release-level cleanup slice. Its purpose is to make the repository's documented, discoverable, and tested public surface describe the product that now exists, rather than the superseded hard/soft/detect and formatting product. It does not add behavior beyond the contracts established by 008–010.

### Repository evidence

- `lua/pencil/init.lua` is now the production module and exposes the binary API: `setup`, `enable`, `disable`, and `toggle`. Its setup contract is limited to an optional `width` preferred measure, defaulting to 80.
- `plugin/pencil.lua` loads `pencil` so the bare `:Pencil` command is available when the repository is on Neovim's runtimepath. The command is the only command required by the current product.
- `tests/comfortable_column.lua` exercises the replacement behavior across the 008–010 slices, including default and configured width, visual wrapping, restoration, multi-window lifecycle, and atomic setup rejection.
- `tests/unsupported_version.lua` verifies that unsupported Neovim versions fail before command registration. `tests/run.sh` is the isolated headless acceptance entry point and currently runs the comfortable-column and unsupported-version checks.
- `README.md` and `doc/pencil.txt` still describe the historical product, including hard and soft modes, detection, hard formatting, classification, concealment, mappings, status indicators, filetype presets, and legacy command families. Their current claims conflict with the implementation and the product-design record.
- `doc/tags` currently indexes sections that belong to that historical surface.
- `lua/pencil/classification.lua` and `lua/pencil/_test.lua` are leftover classification/test seams. Classification is no longer part of the product because hard autoformat and protected-region handling were rejected by the rewrite.
- `tests/bare_install.lua`, `tests/smoke.lua`, `tests/m005.lua`, and `tests/m006.lua` assert superseded behavior. They must not remain acceptance inputs that require removed APIs or features.
- `LICENSE` contains the repository's MIT license and copyright notice. The redesign does not change the licensing or attribution contract.

### Decisions already made

- The writer-facing model is only Pencil on/off, a preferred display-column measure, and a centered visual column. There are no hard, soft, or detect modes.
- The public Lua API is exactly `setup`, `enable`, `disable`, and `toggle`. `setup` accepts nil or a table containing only `width`; omitted setup uses width 80. The existing buffer-targeting and idempotence behavior from 008–010 remains the contract.
- The only required Ex command is bare `:Pencil`, which toggles the current buffer. No command arguments, aliases, format commands, status commands, or width commands are part of this milestone.
- Pencil performs visual wrapping only. It does not insert hard breaks, enable insert-time autoformat, classify structured regions, manage concealment, install navigation or undo mappings, or auto-enable by filetype.
- `setup({ width = N })` is configuration, not a new product mode. Width is a positive integer display-column preference for future activations; narrow windows contract safely, and active activations retain their captured measure until disabled.
- Neovim 0.10+ and no runtime dependencies remain supported-platform constraints.
- Old pencil.nvim/vim-pencil configuration and command compatibility is explicitly not promised. Cleanup should remove stale claims rather than preserve compatibility shims.
- Help tags must match the final help sections and remain usable through `:help pencil`.

### Approaches ruled out

- Keeping historical commands or aliases “for compatibility” is rejected: it would leave multiple competing products and contradict the clean-rewrite decision.
- Retaining historical configuration examples, filetype presets, mode/status terminology, or migration promises is rejected: the final public surface must not advertise behavior absent from the implementation.
- Keeping classification as a private or test-only product seam is rejected: it exists solely for removed hard-format safety behavior and is not needed by comfortable-column UX.
- Treating the old tests as required regressions is rejected. The headless suite must be aligned to the current public contract instead.

### Scope boundary

This milestone includes:

- Rewriting the README to document installation, requirements, the binary toggle, width configuration, Lua API, restoration/lifecycle guarantees, and explicit non-goals.
- Rewriting the user help to document only the supported installation, configuration, API, command, behavior, safety, and license/attribution information.
- Updating `doc/tags` so all documented help sections are discoverable and no removed sections are indexed.
- Removing stale public references to hard/soft/detect, autoformat, format commands, mappings, classification, concealment, status helpers, filetype auto-enable, and legacy aliases.
- Removing obsolete classification and classification-test artifacts if they have no remaining consumers.
- Replacing or deleting historical test entry points so the configured headless suite contains only current-product acceptance coverage.
- Keeping `plugin/pencil.lua` as a minimal loader for the sole command and ensuring no stale command registration or public API remains.
- Verifying that `LICENSE` remains present and its existing MIT copyright/attribution text is preserved.

This milestone excludes:

- Changes to comfortable-column runtime behavior already delivered by 008–010.
- New product features, including filetype auto-enable, per-filetype widths, hard wrapping, autoformat, mappings, concealment, statusline integration, classifiers, or compatibility aliases.
- Release automation, version marketing, or unrelated editor UI changes.
- Changing the license or attribution.

### Constraints and acceptance rules

- Documentation must be behaviorally accurate against the current module and tests. It must not claim an API, command, option, event behavior, or safety guarantee that is not part of 008–010.
- The final documented surface must make clear that the bare command does not require `setup()`, setup is optional, and width changes affect future activations rather than reconfiguring active buffers.
- Documentation must state that wrapping is visual-only, buffer contents remain unchanged, and disable restores owned presentation while preserving external edits.
- Documentation must state the supported Neovim version and no-runtime-dependency constraint.
- The final suite must run in isolated headless Neovim processes, pass on the supported runtime, and include the unsupported-version failure path.
- The suite must cover the public command and Lua API, default/custom width, atomic invalid setup, lifecycle behavior, visual-only text preservation, exact restoration/ownership behavior, and absence of removed public surface.
- Historical tests may be deleted or rewritten; they must not be retained merely to preserve superseded behavior.
- Any removed Lua artifact must have no production or acceptance consumer. The resulting repository must load cleanly through `plugin/pencil.lua` and `require("pencil")`.

### Open questions resolved from evidence

- **Public Lua surface:** `setup`, `enable`, `disable`, and `toggle`, based on the implemented module and the 008–010 specifications. No status or mode query is required.
- **Command surface:** bare `:Pencil` only, based on `plugin/pencil.lua` and the product-design entry-point decision. It toggles; it does not accept historical subcommands.
- **Width terminology:** `width` is the sole configuration key, and it means preferred display columns, based on milestone 010.
- **Classification cleanup:** `classification.lua` and `_test.lua` are obsolete when no references remain, based on the current `init.lua` and the explicit milestone-011 boundary.
- **License handling:** retain `LICENSE` unchanged; cleanup is not a licensing change.

## 2. Requirements

### Vertical slice A: Publish the current comfortable-column product

1. The README must describe Pencil as a Neovim plugin for a centered, visually wrapped writing column.
2. The README must document Neovim 0.10+, no runtime dependencies, installation, the bare `:Pencil` command, and the Lua entry points.
3. The README must document the default width of 80 and the supported `setup({ width = N })` configuration, including that setup is optional and applies to future activations.
4. The README must describe the observable guarantees that matter to writers: visual-only wrapping, unchanged buffer text, centered presentation, multi-window/resize lifecycle behavior, and exact restoration subject to external ownership changes.
5. The README must explicitly identify excluded behavior where useful, so readers are not led to expect hard breaks, autoformat, filetype auto-enable, mappings, concealment, classification, statusline integration, or old command/configuration compatibility.
6. Help opened with `:help pencil` must provide an equivalent, normative description of the supported product and link only to sections that exist in the final help file.
7. Help must document the exact Lua call shapes and targeting behavior for `setup`, `enable`, `disable`, and `toggle`, including optional `{ buf = bufnr }` targeting where supported by the existing API.
8. Help must document the command contract as bare `:Pencil` with no historical subcommands or aliases.
9. Help must document configuration validation at the level already delivered by 010: only `width` is accepted, valid widths are positive integers, invalid setup is atomic, and active presentations are not reconfigured by later setup.
10. Help must document the supported version, runtime dependency constraint, safety behavior, and retained MIT license/attribution reference.

### Vertical slice B: Remove stale public surface

1. README and help must contain no user-facing promise or example for hard mode, soft mode, detect mode, hard formatting, autoformat, format commands, mappings, conceal management, status/mode APIs, classifiers, protected-region classification, filetype presets, or filetype auto-enable.
2. README and help must contain no active migration guidance for obsolete commands or configuration. The clean rewrite/non-compatibility position may remain only as a concise non-goal.
3. `doc/tags` must index every final help section and no removed section. `:help` navigation must not produce missing-tag or stale-section failures.
4. `plugin/pencil.lua` must not register historical aliases or command families. The runtime-loaded command surface must contain only the supported `:Pencil` command.
5. The Lua module's exported public keys must contain only `setup`, `enable`, `disable`, and `toggle`; no historical status, mode, autoformat, or test/classification export may be documented or required.
6. Classification artifacts may be removed when repository-wide references show they are unused. No replacement classifier or compatibility layer is required.
7. `LICENSE` must remain present with its existing MIT terms, copyright notice, and attribution.

### Vertical slice C: Align and green the headless suite

1. The default `tests/run.sh` path must execute the current comfortable-column acceptance suite and the isolated unsupported-version check.
2. The suite must verify that the plugin loads and registers bare `:Pencil` on supported Neovim without setup.
3. The suite must verify command/Lua parity for enabling, disabling, and toggling the current or explicitly targeted buffer.
4. The suite must verify default width 80 and configured positive-integer widths, including `setup({})` restoring the default for future activations.
5. The suite must verify empty, short, long, Unicode, and tabbed content remains unchanged while visual wrapping and centered presentation are active.
6. The suite must verify resize, multiple windows, late splits, buffer switching, cleanup, and per-window restoration according to 009.
7. The suite must verify external edits to owned presentation values survive reconciliation and disable, repeated enable is idempotent, and a failed setup leaves configuration and active presentation unchanged.
8. The suite must verify unsupported Neovim versions fail clearly before successful activation or command registration.
9. The suite must verify the final public surface: unsupported Lua exports and historical commands are absent, and the help file/tags and README contain the required current terms without stale feature claims.
10. Historical scripts that assert superseded behavior must be deleted or rewritten so the repository's normal verification commands do not execute them as acceptance criteria.
11. The headless suite must exit nonzero on any failed assertion, parse/load error, stale public-surface check, help-tag failure, or whitespace error.

### Edge cases

- A README or help example must not imply that `setup()` is required before `:Pencil`.
- A configured width larger than a window must be described as a preference that contracts safely, not as an activation error.
- A later valid setup while a buffer is active must not be documented as changing that active layout.
- Invalid setup values and unknown keys must not be documented as silently ignored.
- Help tags must remain correct after sections are renamed, removed, or consolidated.
- A stale term in historical plan documents is not a public-surface failure; stale claims in README, help, command/API registration, or executed tests are.
- A deleted obsolete artifact must not be removed if a current runtime or acceptance path still requires it; instead the remaining dependency must be resolved within this cleanup scope without adding product behavior.
- The license must not be rewritten merely to match documentation wording.
- The suite must continue to run without optional parser, plugin-manager, or external runtime dependencies.

### Parallelizable work

- README and help content can be updated in parallel after the final command/API contract is fixed.
- Help-tag regeneration/verification can proceed independently once help section names are settled.
- Obsolete artifact and historical test cleanup can proceed independently of prose documentation, provided the final suite's exact file list is agreed.
- Public-surface assertions and runtime comfortable-column regression tests can be developed independently, then run together through `tests/run.sh`.
- License preservation and load/parse checks are independent of documentation prose.

### Verification expectations

The milestone is complete only when:

- `tests/run.sh` exits successfully on the supported Neovim runtime;
- the comfortable-column acceptance behavior from 008–010 remains green;
- the unsupported-version process remains green;
- `:help pencil` and all linked help sections load successfully and `doc/tags` matches them;
- README and help describe only the comfortable-column UX and the four-function Lua API;
- no historical command, option, API, classifier, or test seam remains in the executable public surface;
- obsolete classification/test artifacts are absent or demonstrably unused;
- `LICENSE` remains intact; and
- no new product feature has been introduced as part of cleanup.

No runtime implementation structure is prescribed by this specification. Acceptance is based on the observable documentation, public-surface, repository-cleanliness, and headless-suite outcomes described above.
