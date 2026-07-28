# 005: User-Defined Filetype Behavior Implementation Guide

## Context Summary

Milestone 005 extends the existing M001–M004 filetype, formatting, ownership, status, and protected-region behavior with an explicit per-filetype safety policy. Keyed entries merge field-wise over built-in presets; `format_safety = "plain"` makes any configured filetype prose everywhere without invoking structural classification; a keyed synchronous `classifier` replaces built-in classification and is the only source of custom results; and unknown filetypes remain fail closed unless explicitly assigned one of those policies. Setup validation must be complete and atomic, active buffers must retain captured policy until explicit re-enable or filetype resolution, and all classification, formatting, status, callback, cleanup, and window/buffer isolation behavior must remain synchronous, quiet on routine callback failure, and compatible with Neovim 0.10+.

## Ordered end-to-end implementation slices

Each slice is an ordered vertical behavior. Complete and integrate every implementation task in a slice before starting the next slice. The tests listed for a slice must pass against the real Neovim behavior after that slice, without requiring later slices. There is no parallel work: every later slice depends on the preceding slice's captured policy and runtime behavior.

### Slice 1 — Baseline unknown fail-closed behavior and configuration merge

**Dependency:** none. This slice establishes the policy vocabulary and activation state used by every later slice. It must preserve the existing M004 path for unconfigured built-in structured filetypes.

- [ ] `lua/pencil/init.lua: presets`, `plain_filetypes`, `structured_filetypes`, and `settings_for(buf)` — represent the built-in safety category for all eight presets (`gitcommit`, `mail`, `text` plain; `markdown`, `rst`, `tex`, `asciidoc`, `textile` structured), and resolve a keyed entry by field-wise merge over the matching preset, global setup values, and defaults. An entry for one filetype must not inherit safety or a classifier from another filetype.
- [ ] `lua/pencil/init.lua: settings_for(buf)` and the activation state created by `M.enable(opts)` — capture the exact resolved filetype policy, including safety and classifier reference, for each enabled buffer activation. Empty and unknown filetypes resolve to explicit unknown safety; a simple-list unknown name remains unknown.
- [ ] `lua/pencil/init.lua: M.enable(opts)` — preserve existing per-call mode/fallback/width/autoformat/mapping/conceal precedence while leaving `format_safety` and `classifier` as filetype-policy fields. Explicit re-enable resolves current policy afresh; ordinary `setup()` does not mutate active states.
- [ ] `tests/smoke.lua: M005 Slice 1 — baseline policy resolution` — test no setup, `opts = {}`, simple-list replacement, keyed-table replacement, empty `filetypes`, all eight presets, ordinary keyed overrides, unknown keyed entries, empty filetypes, direct enable, explicit re-enable, disable/re-enable, and setup changes that leave an active buffer unchanged. Assert unknown hard mode is suspended and reports `H`, with no parser, syntax, or classifier access.

**Independently testable outcome:** existing built-in behavior still works, keyed settings merge field-wise, and every unconfigured or empty/unknown filetype is synchronously fail closed.

### Slice 2 — Explicit plain override

**Dependency:** Slice 1's resolved and activation-captured policy. Do not add custom callback behavior in this slice.

- [ ] `lua/pencil/init.lua: classify_location(buf, win)` — dispatch an effective plain policy directly to `"prose"`, before any Treesitter or syntax access. Support plain overrides for built-in structured filetypes and explicit plain policies for unknown keyed entries.
- [ ] `lua/pencil/init.lua: eligible_filetype(state)`, `reconcile_formatoptions(state)`, and `semantic_status(state)` — treat plain as whole-buffer prose while preserving M003 mode, suspension, ownership, temporary `formatoptions` `a`, and status rules.
- [ ] `lua/pencil/init.lua: reconcile_classification(state, win)` — record the plain result with its activation/window context without creating a structural classification result or callback dependency.
- [ ] `tests/smoke.lua: M005 Slice 2 — plain override` — configure Markdown, RST, TeX, AsciiDoc, and Textile as plain and verify prose/status/formatting behavior at protected-looking locations. Verify an unknown keyed plain filetype is also prose, and instrument the available parser/syntax seams to prove plain never queries them or invokes a classifier.

**Independently testable outcome:** explicit plain configuration makes each tested filetype prose everywhere, with no M004 classification access and correct hard/soft/ownership behavior.

### Slice 3 — Custom classifier and complete lifecycle

**Dependency:** Slice 2's policy dispatch and M003 reconciliation. Implement the runtime contract before adding validation or transition-specific behavior.

- [ ] `lua/pencil/init.lua: classify_custom(state, win)` (new helper) — create exactly one fresh context table containing `buf`, `win`, zero-based cursor `row`, zero-based byte `col`, and exact current `filetype`. Invoke the captured function synchronously under protected error handling. Accept only `"prose"`, `"protected"`, or `"unknown"`; convert all other results, errors, inability to call, and yields to quiet `"unknown"`.
- [ ] `lua/pencil/init.lua: classify_location(buf, win)` — dispatch in strict order: plain returns `"prose"`; custom invokes only `classify_custom`; built-in structured uses the complete M004 path; unknown returns `"unknown"` without parser, syntax, or callback access. Custom never combines with M004.
- [ ] `lua/pencil/init.lua: reconcile_classification(state, win)` — use captured policy, keep the latest result with its classification window, and invalidate stale results on activation/policy changes. A result cannot be reused across buffers, windows, filetypes, or activations.
- [ ] `lua/pencil/init.lua: M._setup_autocmds()` classification callbacks for `InsertEnter`, `CursorMovedI`, `TextChangedI`, `TextChangedP`, supported `CompleteChanged`, and `FileType` — classify custom policies synchronously on every required event, including equal-looking cursor locations; never invoke from `InsertCharPre`.
- [ ] `lua/pencil/init.lua: InsertLeave` handling in `M._setup_autocmds()` — clear the current custom result and callback lifecycle state without an extra callback, remove only Pencil-owned temporary formatting permission, and require fresh classification on the next Insert.
- [ ] `lua/pencil/init.lua: insert_char_pre(state, value)` — retain delimiter pre-safety inference only for built-in structured filetypes; custom and unknown policies do nothing at `InsertCharPre`.
- [ ] `lua/pencil/init.lua: M.enable(opts)` — establish the initial hard-mode safety boundary synchronously before granting automatic-formatting permission: do not add temporary `formatoptions` `a` until this activation's custom classifier has returned valid `prose`; protected, unknown, errors, invalid results, and failed calls remain suspended and quiet with status `H`. Perform at most one callback invocation for this required initial classification event, and do not defer the decision.
- [ ] `tests/smoke.lua: M005 Slice 3 — custom classifier lifecycle` — use real buffers/events and record callback count/order, exact `buf`/`win`/`filetype`, zero-based row, and zero-based byte column including multibyte text. Observe read-only context behavior: callback attempts to mutate context fields or add fields must not alter Pencil’s captured policy, activation state, subsequent context, or classification correctness; callback correctness must not depend on those mutations. Verify synchronous invocation on every required event, equal-looking cursor events, no `InsertCharPre` invocation, fresh `InsertEnter` classification, and no callback after `InsertLeave` cleanup. Verify `M.enable()` itself performs the required initial hard-mode classification synchronously: there is no `a` before a valid prose result, protected/unknown/error/invalid outcomes remain quiet with no temporary `a` and status `H`, and the callback count is at most once for that required initial classification event.
- [ ] `tests/smoke.lua: M005 Slice 3 — custom result failures` — test each invalid result separately in its own fixture and assertion: `nil`, boolean, number, table, malformed string (including wrong case/whitespace), and a thrown error. Add a separate non-callable classifier fixture at runtime if reachable after configuration. Each must be quiet, yield `"unknown"`, remove temporary `a` when Pencil owns it, and report hard status `H`; no invalid result may be treated as setup validation.
- [ ] `tests/smoke.lua: M005 Slice 3 — yielding classifier failure` — use a real Neovim buffer and a classifier that executes `coroutine.yield()` inside the callback while Pencil invokes it through its protected synchronous call. Assert the call is quiet, produces `"unknown"`, reports hard status `H`, leaves no temporary `formatoptions` `a`, and does not let the yield escape into the editor/event lifecycle. If the Neovim/Lua runtime cannot yield across `pcall`, assert that exact attempted-yield error is the captured expected error path and still verify the same quiet fail-closed behavior; do not replace this with a mocked callback or a non-runtime coroutine test.

**Independently testable outcome:** a valid custom classifier alone replaces M004 end to end, supplies exact synchronous context, drives formatting/status, and fails closed for every invalid result and callback error.

### Slice 4 — Validation and atomicity

**Dependency:** Slice 3's configuration shape and runtime contract. Validation must prevent invalid declarations from reaching that runtime, while preserving the already-tested valid behavior.

- [ ] `lua/pencil/init.lua: validate(value)` — accept `format_safety` only as exact `"plain"` and `classifier` only as a function in `filetypes.<nonempty-name>` entries. Reject unsupported filetypes/entry types, empty keyed names, invalid safety values, both fields together, simple-list fields, and misplaced global/per-call fields while retaining earlier validation rules.
- [ ] `lua/pencil/init.lua: validate_enable(opts)` — reject `format_safety` and `classifier` in `enable()` options with path-specific errors, including any nested/per-call placement represented by the established option shape.
- [ ] `lua/pencil/init.lua: M.setup(value)` — aggregate all proposed configuration errors before assignment; install no partial `config`, `user_config`, or automatic set on failure; preserve prior valid configuration and active buffers; never invoke a classifier during validation; install one complete update on success.
- [ ] `tests/smoke.lua: M005 Slice 4 — validation and atomicity` — test invalid filetypes types, non-string and empty keyed names, invalid entry types, each invalid `format_safety` value, non-function classifiers, both fields together, global/per-call/misplaced declarations, and safety fields in simple lists. Test non-callable config validation separately from runtime invalid returns. Assert one aggregate error contains multiple unrelated paths, callbacks are never called by setup, and failed setup leaves prior configuration, active state, status, formatting ownership, and automatic set unchanged.

**Independently testable outcome:** all valid Slice 3 behavior remains available, while every invalid declaration is rejected atomically with path-specific aggregate diagnostics.

### Slice 5 — Transitions, isolation, and cleanup

**Dependency:** Slices 1–4. Policy replacement must use validated configuration, and cleanup must invalidate the lifecycle state introduced by Slice 3.

- [ ] `lua/pencil/init.lua: FileType callback in M._setup_autocmds()` — invalidate the old result first and resolve the latest exact policy before classification. Cover custom→plain (no callback), custom→unknown (no old callback), custom→different custom (new callback only), custom→built-in structured (M004 only), and plain/unknown→custom (new callback only).
- [ ] `lua/pencil/init.lua: settings_for(buf)`, `M.enable(opts)`, and FileType reconciliation — preserve mode, formatting ownership, pending M003 suspension, and explicit re-enable semantics while replacing policy. Consume pending suspension only at an eligible prose hard-mode boundary. No stale classifier or result survives disable, wipeout, or full re-enable.
- [ ] `lua/pencil/init.lua: active state records`, `cleanup(state, force)`, `BufUnload`, `BufWipeout`, and window reconciliation in `M._setup_autocmds()` — discard classifier references, results, pending data, and callback state on cleanup; prevent callbacks after invalidation; keep results per buffer and classification window.
- [ ] `lua/pencil/init.lua: formatoptions_owned(state)`, `reconcile_formatoptions(state)`, and `cleanup(state, force)` — preserve M003 ownership, external edits, temporary `a`, exact `t`/`n` restoration, inactive cleanup, window switching, and wipeout safety for plain/custom/unknown outcomes without changing unrelated mappings, modeline, conceal, navigation, or commands.
- [ ] `tests/smoke.lua: M005 Slice 5 — transitions/isolation/cleanup` — exercise every policy transition pair, empty filetype, setup changes followed by ordinary events, explicit re-enable, disable/re-enable, multiple buffers/windows with distinct callbacks, window switching, wipeout, callback counts, stale-callback exclusion, status, temporary `a`, pending suspension, external ownership, and exact restoration.

**Independently testable outcome:** active buffers transition safely between all policies, callbacks and results never leak across buffers/windows/activations, and cleanup restores prior state exactly.

### Slice 6 — Final compatibility and acceptance coverage

**Dependency:** Slice 5. This slice adds no new policy semantics; it proves compatibility and closes the complete acceptance matrix.

- [ ] `tests/smoke.lua: M005 compatibility and acceptance matrix` — cover all eight built-in presets, omitted setup, `opts = {}`, simple-list/keyed replacement, empty automatic set, field-wise merge, plain/custom/unknown parser and syntax non-invocation, all callback context and invalid-result cases, aggregate validation, status, suspension, ownership, transitions, isolation, cleanup, and all prior M001–M004 smoke behavior.
- [ ] `lua/pencil/init.lua: classify_location(buf, win)`, `reconcile_classification(state, win)`, `semantic_status(state)`, and `M._setup_autocmds()` — verify existing unconfigured built-in plain and structured behavior remains unchanged, unknown remains fail closed, routine callback failures remain quiet, and no callback/parser/syntax work is added outside the specified lifecycle.
- [ ] `tests/smoke.lua: M005 runtime verification` — run isolated headless Neovim processes for each available supported Neovim 0.10+ binary, record `nvim --version` and parser availability, and skip only optional parser-dependent M004 cases with explicit reasons. Plain, custom, and unknown tests must run without an optional parser.

**Independently testable outcome:** the complete M005 matrix passes and M001–M004 compatibility is demonstrated without optional parser requirements for new plain/custom/unknown coverage.

## Acceptance / verification

- [ ] Read `docs/plans/005_user_defined_filetype_behavior_spec.md` and confirm every Context & Constraints decision is represented without adding behavior outside the specification.
- [ ] Run the isolated headless Neovim smoke suite and added M005 cases for every available supported Neovim 0.10+ binary; record version output and unavailable supported binaries.
- [ ] Record optional Treesitter/parser availability and explicit reasons for any parser-dependent skips.
- [ ] Verify callback context exactness and read-only-context observations, synchronous lifecycle invocation, no scheduling/yield dependency, no `InsertCharPre` invocation, and no invocation after invalidation or cleanup.
- [ ] Verify the `M.enable()` initial hard-mode safety boundary: no temporary `a` before valid prose, synchronous initial classification at the required boundary, protected/unknown/error/invalid results fail closed with `H`, and callback count is at most once per required classification event.
- [ ] Verify separately that `nil`, boolean, number, table, malformed string, and thrown-error classifier outcomes each fail closed quietly; verify non-callable classifier configuration is rejected atomically.
- [ ] Verify the real yielding-classifier case with `coroutine.yield()` inside a callback invoked through the protected synchronous call: no escaped yield, quiet `"unknown"`/`H`/no temporary `a`; when the runtime forbids yielding across `pcall`, the exact attempted-yield error is the expected captured error path.
- [ ] Run `git diff --check -- docs/plans/005_user_defined_filetype_behavior_implement.md` and inspect the plan with `git diff --no-index /dev/null docs/plans/005_user_defined_filetype_behavior_implement.md` to confirm this file contains only an implementation guide, no production code, no test code, no placeholders, and exact repository-relative paths/function names.
- [ ] Run `git status --short -- docs/plans/005_user_defined_filetype_behavior_implement.md` and verify this task edits only `docs/plans/005_user_defined_filetype_behavior_implement.md`. Pre-existing M004 working changes in `lua/pencil/init.lua`, `tests/smoke.lua`, `lua/pencil/_test.lua`, `lua/pencil/classification.lua`, and related untracked plan/spec files are out of scope and must not be interpreted as changes from this task.
