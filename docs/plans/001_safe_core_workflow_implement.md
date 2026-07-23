# 001: Safe Core Workflow Implementation Guide

## Context Summary

Pencil.nvim needs a Neovim-native, dependency-free safe writing workflow for Neovim 0.10+: optional setup with built-in defaults, direct Lua and command controls, configured prose auto-activation, deterministic modeline/line-sampling detection, hard/soft presentation, and exact buffer/window restoration. The implementation must be atomic at configuration boundaries, own only wrapping-related state, support multiple buffers and windows, and preserve the MIT attribution. Navigation, automatic formatting, structured classification, custom classifiers, and release documentation remain later milestones.

## Implementation Checklist

### Slice 1 — Loadable module and direct control

- [ ] `lua/pencil/init.lua: module initialization` — reject Neovim versions below 0.10 with a clear error and expose `require("pencil")` without setup.
- [ ] `lua/pencil/init.lua: M.enable(), M.disable(), M.toggle(), M.mode(), M.status()` — target `opts.buf` or the current buffer, maintain enabled/off state, and verify the public Lua controls in a headless Neovim smoke test.
- [ ] `lua/pencil/init.lua: command()` and `M._setup_autocmds()` — define `:Pencil` actions, completion, invalid-action errors, and all milestone aliases; verify command/Lua equivalence before setup.

### Slice 2 — Configured prose activation

- [ ] `lua/pencil/init.lua: M.setup(), validate(), preset()` — validate the documented global and filetype shape, resolve built-in presets, preserve recognized presets for list entries, merge keyed overrides, replace the automatic set for explicit lists, and keep an empty list direct-control-only.
- [ ] `lua/pencil/init.lua: FileType autocmd callback` — activate only after valid setup and only for selected filetypes, quietly; headless checks must cover all built-in presets, lists, keyed overrides, unknown entries, replacement, and empty configuration.

### Slice 3 — Deterministic selection

- [ ] `lua/pencil/init.lua: modeline_width()` — read only supported `textwidth` modeline forms without executing modeline settings, including disabled-modeline operation and malformed/negative handling.
- [ ] `lua/pencil/init.lua: detect()` — implement positive/zero modeline decisions, first-20-nonblank sampling, display-column threshold (>130), short-file behavior, and fallback selection; test threshold and display-width cases in isolated headless buffers.
- [ ] `lua/pencil/init.lua: M.enable()` — apply direct mode without detection and implement hard-width precedence for direct width, modeline, existing buffer width, preset, and global defaults; test every precedence level and fresh detection after disable.

### Slice 4 — Presentation and restoration

- [ ] `lua/pencil/init.lua: apply()` and `win_state()` — apply only hard/soft wrapping, required presentation, and configured conceal settings to every displaying window, capturing each window independently.
- [ ] `lua/pencil/init.lua: BufWinEnter/WinNew/WinEnter callbacks` — apply active presentation to newly opened windows displaying an enabled buffer without affecting unrelated buffers/windows.
- [ ] `lua/pencil/init.lua: M.disable()` and `BufWipeout callback` — restore captured buffer/window values only while Pencil still owns them, handle user edits, closed windows, wiped buffers, repeated cycles, and simultaneous buffers; verify exact observable restoration across multi-window lifecycle tests.

### Slice 5 — Integration verification

- [ ] `tests/smoke.lua: public workflow assertions` — run real headless Neovim checks for setup-before/after behavior, commands, aliases, modes, statuses, modelines, presets, option ownership, multi-window state, and repeated enable/disable transitions.
- [ ] `LICENSE: attribution` — confirm the existing MIT attribution remains present; do not add compatibility or release material outside this milestone.

## Parallel Work

After the public API and state ownership rules are fixed, configuration/preset validation, detection helpers, command definitions, presentation/restoration, and headless verification can be developed in parallel. Integrate all slices before acceptance; each verification task must exercise real Neovim behavior rather than mocks.
