# 003: Hard-Mode Automatic Formatting Implementation Guide

## Context Summary

Milestone 003 adds automatic formatting for eligible plain-prose buffers while preserving the enable/disable, mode, mapping, window, and exact-restoration contracts from milestones 001 and 002. Hard mode owns the complete buffer-local `formatoptions` value only while its last write remains current: it captures the exact activation baseline, contributes `t` and `n`, and contributes temporary `a` only for an eligible, unsuspended Insert. It restores the baseline only while owned. Eligibility is static and fail-closed (`text`, `gitcommit`, and `mail` only); structured and unknown filetypes remain hard but report `H`. The implementation targets Neovim 0.10+, remains dependency-free, and excludes classifiers, structured-filetype formatting, custom list generation, new mappings, and unrelated presentation behavior.

## Dependencies and Invariants

- `lua/pencil/init.lua:M.enable()`, `M.disable()`, `reconcile_buffer()`, `cleanup()`, and `M._setup_autocmds()` remain the lifecycle seams; do not create a second activation system or modify `plugin/pencil.lua`.
- Hard mode contributes `t` and `n`, never newly contributes `c` or `q`. For captured baseline `B`, `H(B)` removes only baseline `a` and merges absent `t`/`n`; it preserves baseline `c`/`q`, ordering, duplicates, and unrelated flags. `I(B)` is `H(B)` plus one temporary `a`. Full owned disable restores exact `B`, including its original `a`.
- Ownership is whole-value. A buffer is owned only while `vim.bo[buf].formatoptions` equals the last complete value Pencil wrote. An `OptionSet` callback transfers ownership immediately on any mismatch; every later write, action, and status query must first use the shared `formatoptions_owned(buf, state)` check. Use a recursion guard around Pencil writes and a buffer-local constant/state record; never reacquire ownership during that activation.
- Status must first resolve semantic state (`off`, `soft`, `auto`, or `hard`), then map it to configured `status.off`, `status.soft`, `status.auto`, or `status.hard` strings. `A` is valid outside Insert when armed; it does not claim formatting is currently running.
- Setup validation is atomic. Setup changes affect future activations only; explicit re-enable resolves current configuration for the selected buffer. State, baselines, ownership, preference, and suspension are per buffer; windows remain a separate presentation concern.
- Tests use real Neovim buffers, options, mode events, commands, API calls, and native formatting. Do not mock formatting or option ownership.

## Implementation Checklist

### Slice 1 — Default eligible activation, Insert behavior, and status

- [x] `lua/pencil/init.lua: defaults`, `validate()`, `settings_for()`, and `validate_enable()` — add boolean `autoformat = true` to global defaults and the established keyed filetype/per-call settings; validate it at all three layers, reject unknown keys and invalid types through the aggregate atomic validation path, and preserve existing mode/width/presentation precedence.
- [x] `lua/pencil/init.lua: formatoptions_baseline(state)`, `formatoptions_hard_value(state)`, and `formatoptions_insert_value(state)` — capture exact `B` on first hard activation and construct `H(B)` by removing only baseline `a`, adding absent `t` and `n`, and preserving baseline `c`, `q`, duplicates, ordering, and unrelated flags; construct `I(B)` by adding only the temporary `a` contribution.
- [x] `lua/pencil/init.lua: eligible_filetype(state)` and `reconcile_buffer()` — implement static eligibility for exactly `text`, `gitcommit`, and `mail`; keep other and empty/unknown filetypes ineligible; apply owned `H(B)` outside eligible Insert and owned `I(B)` only for eligible unsuspended Insert without changing `formatlistpat`.
- [x] `lua/pencil/init.lua: formatoptions_insert_enter(state)`, `formatoptions_insert_leave(state)`, `semantic_status(state)`, and `M.status()` — add InsertEnter/InsertLeave behavior and resolve semantic state before selecting configured status strings; return `A` for eligible, enabled, owned, unsuspended hard mode even outside Insert, `H` for all other enabled hard states, `S` for soft, and configured off/untouched status when disabled.
- [x] `tests/smoke.lua: Slice 1 — default activation, Insert, and status` — verify default hard activation, `text`/`gitcommit`/`mail` eligibility, temporary `a` on InsertEnter and removal on InsertLeave including no-typing Insert, `tn` without newly added `c/q`, `S/A/H` semantics, custom `status.auto/hard/soft/off` strings, and real native Insert formatting.

### Slice 2 — Public preference controls, Lua API, commands, and completion

- [x] `lua/pencil/init.lua: settings_for()` and `M.enable()` — resolve `autoformat` with precedence per-call, filetype override, global setup, then built-in `true`; retain the resolved preference in buffer state without making setup mutate active buffers.
- [x] `lua/pencil/init.lua: M.set_autoformat(action, opts)` and `validate_autoformat_action_opts()` — accept exactly `enable`, `disable`, `toggle`, and `suspend`; validate `opts.buf` before mutation; apply only to the selected valid buffer; implement persistent preference changes and suspension clearing exactly as specified.
- [x] `lua/pencil/init.lua: command()`, `format_command_completion()`, and `M._setup_autocmds()` — keep all command definitions in `lua/pencil/init.lua`; use exact `vim.api.nvim_create_user_command()` calls, named completion helper, and grammar `:Pencil format {enable|disable|toggle|suspend}` with `nargs="*"`; reject missing, extra, and invalid arguments atomically; provide nested completion for `format` and actions; add exact `PFormat`→enable, `PFormatOff`→disable, and `PFormatToggle`→toggle aliases while preserving old commands/completion.
- [x] `tests/smoke.lua: Slice 2 — API, command grammar, and completion` — test all four API actions, invalid actions/buffers, selected-buffer isolation, command equivalence, missing/extra rejection, exact aliases, nested completion, and the existing six top-level completion entries/regressions; verify no command path changes `plugin/pencil.lua`.

### Slice 3 — Suspension and status truth table

- [x] `lua/pencil/init.lua: state autoformat fields`, `suspend_autoformat(state)`, `formatoptions_insert_enter(state)`, and `formatoptions_insert_leave(state)` — implement current-Insert remainder suspension and one pending next-eligible-Insert suspension, with no queueing; consume pending suspension on eligible InsertEnter even without typing, but not on ineligible or soft Insert; clear temporary `a` when current Insert is suspended.
- [x] `lua/pencil/init.lua: M.set_autoformat()` action guards and `semantic_status(state)` — reject `enable`/`toggle` outside hard mode with the established warning/no-change behavior; make `disable`/`suspend` quiet no-ops outside hard mode; ensure enable, disable, toggle-to-enabled, full disable, and fresh activation clear suspension as specified; make external ownership and any suspension resolve to semantic `hard` (`H`).
- [x] `tests/smoke.lua: Slice 3 — suspension and status truth table` — cover current remainder, next eligible Insert, repeated requests, no-typing consumption, ineligible/soft non-consumption, later eligibility, hard→soft→hard survival, enable/disable clearing, buffer isolation, custom strings, and every `S/A/H/off` branch.

### Slice 4 — Immediate external whole-value ownership

- [x] `lua/pencil/init.lua: formatoptions_owned(buf, state)`, `formatoptions_write(state, value)`, and buffer-local format state record — record baseline and last complete write separately from textwidth ownership; use a recursion guard for Pencil writes; before every formatoptions write/action/status, compare the current complete value with the last write and permanently mark external ownership on mismatch; never reacquire it.
- [x] `lua/pencil/init.lua: M._setup_autocmds()` `OptionSet` callback — install an OptionSet callback for buffer-local `formatoptions`, ignore only guarded Pencil writes, and transfer ownership immediately for external changes during or outside Insert; ensure all subsequent Insert, mode, filetype, transition, action, status, and disable paths call `formatoptions_owned(buf, state)` before acting.
- [x] `lua/pencil/init.lua: transition/reconcile_buffer()` — implement hard activation, InsertEnter/Leave, hard→soft→hard, suspension, and disable against whole values: preserve external `E` unchanged, restore `B` only while owned, and capture a fresh baseline only after full disable and a later activation.
- [x] `tests/smoke.lua: Slice 4 — ownership and transition matrix` — verify empty/unusual baselines, `a/c/q/t/n`, duplicates/order/unrelated flags, exact `B` restoration, `H(B)`/`I(B)` values, edits during and outside Insert, immediate status change on edit, no reassertion/reacquisition/restoration on every later transition, and fresh-baseline capture after full disable.

### Slice 5 — Configuration precedence and explicit re-enable

- [x] `lua/pencil/init.lua: validate()`, `settings_for()`, and `M.enable()` existing-active path — validate global/filetype/per-call `autoformat`, preserve keyed filetype shape, and make explicit re-enable resolve current configured preference with the same precedence as fresh enable; false disarms and clears suspension, true clears suspension and arms eligible hard mode, and neither mutates unrelated active buffers.
- [x] `lua/pencil/init.lua: activation transition helpers` — preserve one baseline across same-activation hard→soft→hard, restore `B` only while owned during soft intervals, and clear all per-activation format/preference/suspension records on full disable; setup alone must not alter active state.
- [x] `tests/smoke.lua: Slice 5 — configuration and re-enable` — verify default/global/filetype/per-call precedence, invalid values and atomic setup, setup-before/after activation, explicit false/true re-enable and suspension clearing, same-buffer transitions, fresh activation, and unrelated-buffer stability.

### Slice 6 — Filetype, multi-buffer/window behavior, list behavior, and cleanup

- [x] `lua/pencil/init.lua: FileType/InsertEnter/mode callbacks in M._setup_autocmds()` and `eligible_filetype(state)` — reevaluate static eligibility immediately after every filetype change and relevant mode change without changing preference or queuing suspension; FileType always reconciles active buffers, while automatic activation remains gated by setup; during the current Insert, an eligible→ineligible change immediately removes temporary `a` ownership permitting and reports `H`, while an ineligible→eligible change immediately adds temporary `a` only when the preference is enabled, the buffer is unsuspended, hard mode is active, and ownership is retained; preserve externally owned complete values. Insert state is tracked by buffer autocmd state rather than global mode.
- [x] `lua/pencil/init.lua: cleanup(state, force)`, `M.disable()`, `BufUnload`, and `BufWipeout` callbacks — remove temporary `a`, restore exact `B`, or leave external current values according to ownership; clear all format state and suspension; tolerate active/suspended Insert cleanup and invalid/wiped buffers without stale references.
- [x] `lua/pencil/init.lua: buffer/window lifecycle integration` — keep independent baselines, preferences, ownership, status, mappings, and presentation for multiple buffers and windows; do not create a second baseline when switching windows or displaying one buffer in multiple windows.
- [x] `tests/smoke.lua: Slice 6 — filetype, cleanup, and isolation` — verify immediate current-Insert eligibility reevaluation in both directions: eligible→ineligible removes temporary `a` and reports `H`, while ineligible→eligible adds temporary `a` only with enabled preference, no suspension, hard mode, and retained ownership; verify manual activation without setup, explicit per-buffer Insert state, non-current suspension remaining pending, and reconciliation not adding `a` to a non-current buffer; also verify next-Insert reevaluation, two or more buffers with distinct state, window switches/closes, disable from another window, wipeout during Insert/suspension, and no leaked `a` or stale ownership/state.
- [x] `lua/pencil/init.lua: hard-mode formatoptions contribution` and `tests/smoke.lua: native numbered-list section` — contribute only native `n`, leave existing `formatlistpat` unchanged, and use real native formatting to verify an existing numbered marker is preserved; verify Pencil never invents, increments, renumbers, or repairs markers.
- [x] `tests/smoke.lua: M001/M002 regression section` — retain and rerun real checks for existing modes, detection/modelines, textwidth/exact restoration, mappings/conflicts, presentation, aliases, multi-window behavior, and cleanup; each regression must fail if the corresponding prior behavior is removed.

## Parallel Work

Do not parallelize the initial ownership seam. First agree on the state record, exact `B`/`H(B)`/`I(B)` construction, `OptionSet` recursion guard, and Insert/filetype event ordering in Slice 1 and Slice 4. After that seam is stable, these tracks may proceed in parallel:

1. `lua/pencil/init.lua: defaults`, `validate()`, `validate_enable()`, `settings_for()`, and the Slice 1/5 configuration tests.
2. `lua/pencil/init.lua: eligible_filetype()`, Insert lifecycle callbacks, and Slice 1/6 eligibility tests.
3. `lua/pencil/init.lua: suspend_autoformat()`, `semantic_status()`, and Slice 3 status/suspension tests after the lifecycle seam exists.
4. `lua/pencil/init.lua: M.set_autoformat()`, `command()`, `format_command_completion()`, aliases, and Slice 2 API/command tests after state fields and guards exist.
5. `lua/pencil/init.lua: cleanup()`/autocmd lifecycle and Slice 6 multi-buffer/window tests after ownership is integrated.
6. Native list assertions and M001/M002 regression assertions after `tn` ownership is complete.

Integrate in slice order. Run the complete real-Neovim smoke suite after each integration point.

## Acceptance / Verification

- [x] Run exactly `nvim --headless -u NONE -i NONE -c 'set rtp^=.' -c 'runtime plugin/pencil.lua' -c 'luafile tests/smoke.lua'` with Neovim 0.10.x, and run the same command separately with the current stable Neovim; if either version is unavailable in CI/environment, record that limitation rather than substituting a different version.
- [x] Confirm the headless run retains and passes the M001/M002 regression sections and the complete M003 acceptance cases: `tn` baseline migration, exact `a` handling, ownership, Insert policy, status strings, API/commands/completion, suspension, config/re-enable, lists, and cleanup/isolation.
- [ ] Run `git diff --no-index /dev/null docs/plans/003_hard_mode_autoformat_implement.md` to inspect the untracked guide, then run `git diff -- docs/plans/003_hard_mode_autoformat_implement.md`; confirm only this guide is touched and production files/plans are unchanged.
- [ ] Check every checklist item has an exact repo-relative path plus an existing or proposed function/helper/test section, contains no production code, and preserves Context Summary, Dependencies/Invariants, Parallel Work, and Acceptance/Verification.
