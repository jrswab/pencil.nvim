# 002: Conflict-Safe Writing Mappings Implementation Guide

## Context Summary

Pencil.nvim's safe core workflow already owns activation, mode selection, presentation, commands, and exact buffer/window restoration. This milestone adds two independently configurable, buffer-local mapping groups—display-line navigation and Insert-mode undo breaks—while preserving normal editing behavior and physical-line alternatives. Mapping installation must participate in the existing enable/disable lifecycle, skip pre-existing global or buffer-local conflicts with one warning per key per buffer, track ownership and right-hand-side identity, and never remove user or other-plugin replacements. The implementation targets Neovim 0.10+, has no runtime dependencies, keeps the existing `require("pencil")` and public controls unchanged, and excludes automatic formatting and other milestone-003 features.

## Implementation Checklist

### Slice 1 — Mapping configuration and effective activation settings

- [x] `lua/pencil/init.lua: defaults`, `validate()`, and `validate_enable()` — add `mappings.navigation` and `mappings.undo_breaks`, default both to `true`, validate that each is boolean, reject unknown mapping keys, and reject invalid setup or per-call values atomically before activation state changes.
- [x] `lua/pencil/init.lua: settings_for()` and `M.enable()` — apply the established precedence of per-call values, filetype-specific values, global setup values, and built-in defaults to the mapping-group settings; preserve the rule that a later `setup()` changes future activations only, while explicit re-enable applies the latest valid settings.
- [x] `tests/smoke.lua: mapping configuration assertions` — verify defaults, each group independently disabled, both groups disabled, valid filetype-specific overrides, valid per-call overrides if exposed by `M.enable()`, invalid values, and setup changes before versus after activation. Use real `nvim_buf_get_keymap()`/`nvim_get_keymap()` observations and confirm disabled groups do not install mappings.

### Slice 2 — Display-line navigation end to end

- [x] `lua/pencil/init.lua: navigation_mapping_specs()` — define the navigation mapping set for `j`, `k`, `<Down>`, `<Up>`, `0`, `$`, `<Home>`, and `<End>`, with displayed-line behavior and explicit preservation of the normal `gj`, `gk`, `g0`, and `g$` physical-line alternatives; keep the mappings buffer-local in effect and scoped to active buffers.
- [x] `lua/pencil/init.lua: install_mapping(state, spec)` and `apply_mappings(state)` — install only navigation mappings when the effective navigation group is enabled, using the existing active-buffer lifecycle rather than a separate activation path; record each installed mapping's mode, lhs, rhs, and buffer ownership identity.
- [x] `tests/smoke.lua: display-line navigation behavior` — in wrapped prose, verify equivalent `j`/`<Down>`, `k`/`<Up>`, `0`/`<Home>`, and `$`/`<End>` movement; verify `gj`, `gk`, `g0`, and `g$` remain usable for physical-line movement; cover short and wrapped lines, hard and soft modes, multiple buffers, and repeated activation transitions.

### Slice 3 — Insert-mode undo breaks end to end

- [x] `lua/pencil/init.lua: undo_break_mapping_specs()` — define Insert-mode mappings for `.`, `!`, `?`, `,`, `;`, `:`, `<C-U>`, and `<C-W>` that preserve each key's normal insertion or deletion result while adding an undo boundary; include `<CR>` as a conditional requested mapping subject to the same conflict policy.
- [x] `lua/pencil/init.lua: install_mapping(state, spec)` and `apply_mappings(state)` — install undo-break mappings only when `mappings.undo_breaks` is enabled, ensure mappings are Insert-mode-only, and keep their RHS identity available for ownership-safe teardown and external-change detection.
- [x] `tests/smoke.lua: Insert-mode undo behavior` — use real headless editing and undo operations to verify every punctuation key, both deletion keys, conflict-free `<CR>`, normal inserted/deleted results, and absence of changed behavior in Normal, Visual, Select, and Command-line modes.

### Slice 4 — Conflict detection and warning deduplication

- [x] `lua/pencil/init.lua: mapping_conflicts(buf, mode, lhs)` — inspect relevant buffer-local and global mappings before installation and determine whether the requested mapping would conflict; preserve existing behavior, including `<CR>`, without replacing or shadowing it.
- [x] `lua/pencil/init.lua: warn_mapping_conflict(state, lhs)` — emit one clear warning per conflicting key per buffer for the relevant activation lifecycle, suppress routine duplicate warnings while the conflict remains, and reset or update warning state only after a meaningful lifecycle reset or conflict-state change.
- [x] `lua/pencil/init.lua: apply_mappings(state)` — continue installing non-conflicting mappings after any conflict, keep navigation and undo-break conflicts independent, and keep a conflict on `<CR>` from aborting activation.
- [x] `tests/smoke.lua: conflict-safe installation assertions` — cover global conflicts, buffer-local conflicts, conflicts in every relevant mode, partial conflicts, conflicts in both mapping groups, repeated activation without repeated warnings, removal followed by explicit reactivation, and preservation of skipped mappings. Capture notifications through the established Neovim notification seam rather than mocking mapping behavior.

### Slice 5 — Ownership-safe teardown and reconciliation

- [x] `lua/pencil/init.lua: mapping_identity()`, `mapping_matches(state, record)`, and `remove_owned_mapping(state, record)` — record enough mode/lhs/rhs/buffer identity to remove a mapping only when it still matches Pencil's installation; treat user or other-plugin changes to an installed mapping as externally owned and never overwrite or delete them.
- [x] `lua/pencil/init.lua: reconcile_mappings(state)` — on repeated enable, group reconfiguration, soft/off/soft transitions, and explicit reactivation, reconcile requested mappings without duplication, install newly available non-conflicting mappings, preserve externally changed mappings, and clear stale ownership and warning records after complete disable.
- [x] `lua/pencil/init.lua: cleanup(state, force)`, `M.disable()`, and lifecycle autocmd callbacks in `M._setup_autocmds()` — tear down only still-owned mappings for the target buffer; handle BufWinEnter/BufWinLeave, BufEnter/BufLeave, WinEnter, WinClosed, BufUnload, and BufWipeout without affecting unrelated buffers or windows.
- [x] `tests/smoke.lua: mapping lifecycle assertions` — inspect mappings before activation, while active, after external replacement/removal, after disable, after repeated enable/disable and toggle cycles, after group changes, after buffer/window transitions, and with simultaneous active buffers. Verify pre-existing global and buffer-local mappings, skipped conflicts, user replacements, and mappings from another buffer all survive.

### Slice 6 — Public API integration and end-to-end acceptance

- [x] `lua/pencil/init.lua: M.enable(), M.disable(), M.toggle(), M.mode(), M.status(), command(), and M._setup_autocmds()` — preserve the meanings and aliases of all existing Lua controls and `:Pencil` actions while routing activation through the mapping lifecycle; keep successful mapping operations and routine reconciliation quiet except for specified conflict warnings. Do not add a public mapping command unless required by the existing configuration contract.
- [x] `tests/smoke.lua: public workflow and integration assertions` — verify existing commands, aliases, modes, statuses, hard/soft/detect selection, and automatic activation remain unchanged with mappings enabled; run one end-to-end workflow combining navigation, undo breaks, conflicts, external mapping edits, repeated lifecycle transitions, multiple buffers, and multiple windows.
- [x] `tests/smoke.lua: final headless acceptance run` — execute the complete real-Neovim smoke suite with the milestone-002 assertions and confirm no milestone-001 behavior regresses. Test deletion of the mapping implementation as a failure check where practical: each mapping assertion must fail if the corresponding production mapping behavior is removed.
- [x] `lua/pencil/init.lua: mapping identity` — mark Pencil mappings with a unique description and compare behavior-defining mapping fields during teardown, preserving same-RHS external replacements with changed metadata.
- [x] `tests/smoke.lua: blocking review regressions` — verify physical-line alternative mappings, wrapped navigation execution, external same-RHS replacement preservation, and environment-tolerant deletion/CR undo mapping coverage.

## Parallel Work

After the mapping record format, conflict rules, and activation ownership seam are fixed, these tracks can proceed in parallel:

1. `lua/pencil/init.lua: validate()`, `validate_enable()`, `settings_for()`, with configuration assertions in `tests/smoke.lua`.
2. `lua/pencil/init.lua: navigation_mapping_specs()` and navigation behavior assertions in `tests/smoke.lua`.
3. `lua/pencil/init.lua: undo_break_mapping_specs()` and Insert-mode undo assertions in `tests/smoke.lua`.
4. `lua/pencil/init.lua: mapping_conflicts()`, `warn_mapping_conflict()`, ownership records, and conflict-focused assertions in `tests/smoke.lua`.
5. `lua/pencil/init.lua: reconcile_mappings()`, teardown/autocmd integration, and multi-buffer/window lifecycle assertions in `tests/smoke.lua`.

Integrate all tracks before acceptance. The final verification must use real Neovim mappings and editing behavior, with mocks limited to notification capture or router-level seams where applicable; it must exercise navigation, undo breaks, conflict handling, and teardown together.
