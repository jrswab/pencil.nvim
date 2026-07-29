# Comfortable Column Toggle Implementation

## Context Summary

Milestone 008 replaces the superseded hard/soft/detect product with one small writer-facing behavior: `:Pencil` and the `enable`/`disable`/`toggle` Lua interface turn a centered, visually wrapped 80-column presentation on and off for the current buffer and window. Buffer text, unrelated settings, mappings, and user edits to owned options must survive; unsupported Neovim versions must fail before registration or activation. Resize, multiple windows, configurable widths, and documentation cleanup remain deferred to later milestones.

## Implementation Checklist

### Slice A — Binary activation seam

- [ ] `lua/pencil/init.lua: module load and version check` — require Neovim 0.10+, expose only `enable`, `disable`, `toggle`, and optional `setup`, and register the bare `:Pencil` command without requiring setup.
- [ ] `lua/pencil/init.lua: enable()` / `disable()` / `toggle()` — track one buffer activation state, make repeated enable idempotent, and restore only values still owned by Pencil.
- [ ] `tests/comfortable_column.lua: command/API parity assertions` — exercise bare command and all three Lua calls in isolated buffers, including repeated toggles and disable while off.

### Slice B — Centered 80-column visual presentation

- [ ] `lua/pencil/init.lua: presentation_values()` / `apply()` — use native visual wrapping, a symmetric left status-column margin and right `wrapmargin`, contract safely below 80 columns, and preserve existing gutter rendering.
- [ ] `tests/comfortable_column.lua: layout assertions` — verify empty, short, long, Unicode, tabbed, exact-width, and narrow-window buffers receive safe centered presentation without changing lines.

### Slice C — Exact restoration and ownership transfer

- [ ] `lua/pencil/init.lua: snapshot()` / `restore()` — snapshot every changed window option, restore baselines after disable, and stop restoring an option after an external edit.
- [ ] `tests/comfortable_column.lua: restoration assertions` — verify non-default baselines, external edits, re-enable fresh baselines, unrelated options, mappings, and byte-for-byte buffer preservation.

### Slice D — Unsupported-version failure

- [ ] `tests/unsupported_version.lua: isolated module-load assertion` — override `vim.version()` only in a separate headless process, assert a clear 0.10 requirement error, and assert no command or active presentation was registered.
- [ ] `tests/run.sh: headless suite` — run the replacement acceptance scripts and parse-check the Lua module; do not retain superseded hard/soft/detect tests as milestone criteria.

Parallel work: layout cases and restoration cases can be developed independently after Slice A; supported loading and the isolated unsupported-version process can be verified independently of layout.
