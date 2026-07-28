# 004: Protected-Region Classification Implementation Guide

## Context Summary

Milestone 004 makes hard-mode automatic formatting fail closed for the five built-in structured filetypes—`markdown`, `rst`, `tex`, `asciidoc`, and `textile`—while preserving ordinary prose formatting within those buffers. Classification is cursor- and insertion-point-aware, uses an existing current Treesitter tree when available and bounded legacy syntax inspection as an independent fallback, and yields only `prose`, `protected`, or `unknown`; only `prose` may add Pencil's temporary `formatoptions` `a` flag. The implementation must preserve all M003 ownership, suspension, restoration, status, command, and plain-filetype behavior, remain synchronous and bounded on Neovim 0.10+, add no public API or M005 custom-filetype behavior, and be validated with isolated headless Neovim tests that explicitly record parser/runtime availability.

## Implementation Checklist

### Slice 1 — Classification state, structured eligibility, and fail-closed default

- [x] `lua/pencil/init.lua: structured_filetypes`, `classification_result(state)`, and the buffer state record — add per-buffer/current-Insert-window classification state with no cross-buffer or cross-window reuse; represent only `prose`, `protected`, and `unknown`, defaulting unavailable or malformed evidence to `unknown`; preserve classification invalidation on filetype changes, cleanup, and wipeout without adding a public classifier API.
- [x] `lua/pencil/init.lua: eligible_filetype(state)` and `reconcile_formatoptions(state)` — extend M003 eligibility only from plain `text`/`gitcommit`/`mail` to the exact five structured filetypes, but permit temporary `a` only when the structured classifier's current result is `prose`; keep unknown filetypes fail closed and retain all M003 ownership, `t`/`n`, suspension, and exact-restoration rules.
- [x] `lua/pencil/init.lua: semantic_status(state)` and `M.status()` — make structured status classification synchronous outside Insert using the current cursor/filetype, use the latest lifecycle result during Insert, and report `A` only for prose/armed/owned hard mode; report `H` for protected or unknown while retaining M003 soft, disabled, and plain-type behavior.
- [x] `tests/smoke.lua: Slice 1 — structured eligibility and fail-closed baseline` — use real hard-mode buffers to verify the exact structured set is eligible only after classification, protected/unknown structured locations do not receive `a`, ordinary plain types retain M003 behavior, unknown filetypes remain fail closed, and status returns `A`/`H` according to classification without changing public APIs or configuration.

### Slice 2 — Exact insertion probes and normalization/rule tables

- [x] `lua/pencil/init.lua: insertion_probes(buf, win)`, `utf8_boundary(line, col)`, and `adjacent_character_ranges(line, col)` — implement the exact zero-based byte-column probe set: the insertion point, the character beginning at the point when present, and the immediately preceding UTF-8 character when present; handle EOL, empty lines, delimiter-at-line-ends, multibyte boundaries, invalid positions, and out-of-range positions without scanning beyond the two adjacent characters.
- [x] `lua/pencil/init.lua: normalize_structure_name(name)`, `protected_treesitter_rules`, and `protected_syntax_rules` — encode the exhaustive M004 exact names and prefixes for all five structured filetypes; normalize camel-case and non-ASCII-alphanumeric separators exactly as specified; match only exact names or token-boundary prefixes, never substrings, inferred aliases, or unspecified suffixes.
- [x] `lua/pencil/init.lua: match_protected_name(filetype, name, rules)` and `classify_evidence(results)` — implement per-path `prose`/`protected`/`unknown` evidence and the exact nine-case Treesitter/syntax combination table, including disagreement failure, unavailable-as-unknown behavior, and same-protected-ancestor containment handling; do not give Treesitter precedence over syntax.
- [x] `tests/smoke.lua: Slice 2 — probe boundaries, normalization, and combination truth table` — exercise cursor positions before/after delimiters, EOL, empty lines, UTF-8 character boundaries, invalid byte columns, exact/prefix/token-boundary matches, near-miss names, and every path-combination row including unanimous, fallback, disagreement, and containment cases through real classification behavior.

### Slice 3 — Treesitter current-tree inspection

- [x] `lua/pencil/init.lua: treesitter_path(buf, win, probes)`, `treesitter_parser_and_tree(buf, filetype, row)`, and `treesitter_probe_evidence(tree, probe, rules)` — inspect only an already initialized parser and existing current tree for the current language and target row; tolerate Neovim API differences quietly; reject missing parser/root, stale or invalid trees, changed target ranges not yet updated, missing point coverage, callback errors, and invalid ranges as `unknown` without creating parsers, synchronously parsing, yielding, or scanning the buffer.
- [x] `lua/pencil/init.lua: smallest_named_node(node, probe)`, `treesitter_ancestor_chain(node, max_depth)`, and `treesitter_node_evidence(node, filetype, rules)` — select the smallest named node containing each point/range, allow anonymous punctuation only for delimiter coverage, walk a fixed maximum ancestor depth, treat generic paragraph/text/heading/list/item nodes as prose unless a protected ancestor exists, and treat `ERROR`, unrecognized selected-path structures, malformed ranges, and unrecognized embedded spans as unusable evidence.
- [x] `lua/pencil/init.lua: tex_environment_name(node, max_bytes)`, `tex_environment_evidence(node)`, and `treesitter_probe_evidence()` — for generic TeX `environment` nodes, perform bounded extraction only from selected node/ancestor text for valid `\\begin{...}`/`\\end{...}` delimiters; reject absent, malformed, mixed, or unknown names; classify exactly the finite protected and prose environment sets, with protected descendants/ancestors overriding prose evidence as required.
- [x] `tests/smoke.lua: Slice 3 — parser-backed structured classification` — pin and print the parser/runtime availability used by the fixture, load representative parsers when available, and test current trees, minimum relevant ancestors, delimiters, protected spans, ordinary prose, stale/error trees, missing nodes, `ERROR` nodes, mixed spans, bounded work, and all TeX environment outcomes; skip only parser-dependent cases with an explicit reason when the optional parser is unavailable.

### Slice 4 — Syntax availability and bounded fallback

- [x] `lua/pencil/init.lua: syntax_available(buf, filetype, probes)`, `syntax_activity_probes(buf, row)`, and `syntax_stack_evidence(buf, probe, rules)` — establish syntax availability only from exact `&syntax`, nonempty `b:current_syntax`, no explicit syntax disablement, bounded current-line/adjacent-line activity probing, and successful `synstack()`/`synID()` calls; distinguish active empty-stack prose from disabled/unavailable syntax and fail closed on any required API error or malformed probe.
- [x] `lua/pencil/init.lua: syntax_path(buf, win, probes)` and `translate_syntax_groups(stack)` — inspect complete syntax stacks only at the bounded insertion probes, translate group names, classify exhaustive protected exact/prefix matches as protected and all other active stacks (including empty and unrecognized neutral groups) as prose, and return unknown only for unavailable/erroring/malformed inspection or conflicting probe evidence.
- [x] `tests/smoke.lua: Slice 4 — syntax fallback and availability` — explicitly enable each relevant built-in syntax definition, verify the activity precondition, test protected and ordinary heading/list/paragraph cases for all five formats, exact and token-boundary prefix matching, active empty-stack prose, disabled/unavailable syntax, API errors, malformed probes, and syntax-probe disagreement.

### Slice 5 — Combined classifier integration and lifecycle probing

- [x] `lua/pencil/init.lua: classify_location(buf, win)`, `classification_event(state, event)`, and `reconcile_classification(state)` — run exact probes first, evaluate Treesitter and syntax independently, combine them once with the M004 table, and update the per-buffer/current-window last result synchronously; keep parser absence, stale/error trees, syntax absence, unsupported names, and routine classification errors quiet and fail closed.
- [x] `lua/pencil/init.lua: M._setup_autocmds()` lifecycle callbacks — register mandatory synchronous classification on `InsertEnter`, every `CursorMovedI`, `TextChangedI`, `TextChangedP`, and `FileType`, plus `CompleteChanged` only when supported; ensure every event re-probes even when the result would be unchanged, and make FileType use the new filetype before classification.
- [x] `lua/pencil/init.lua: InsertEnter/InsertLeave transition handling` — on protected/unknown transitions remove only Pencil's temporary `a` while ownership holds; on prose transitions add only when M003 hard-mode, preference, suspension, and ownership conditions permit; clear classification on InsertLeave and preserve exact M003 restoration and per-buffer state.
- [x] `tests/smoke.lua: Slice 5 — synchronous lifecycle and transitions` — trigger each supported lifecycle event in isolated real buffers, observe probes and immediate `a` transitions, verify FileType changes in both directions, cursor movement and text changes across boundaries, supported/unsupported `CompleteChanged`, InsertEnter at EOL/empty lines, InsertLeave cleanup, and no classification work from unrelated events.

### Slice 6 — InsertCharPre boundary and post-mutation safety

- [x] `lua/pencil/init.lua: structural_delimiter_bytes`, `insert_char_pre(state, vchar)`, and the `InsertCharPre` autocmd callback — use only the last valid classification, ownership, and exact per-filetype byte sets from M004; remove `a` before a multi-byte `v:char` when any byte matches, perform no probing/parsing/tree/syntax access, and do nothing for plain types, non-delimiters, invalid/absent results, or externally owned values.
- [x] `lua/pencil/init.lua: TextChangedI/TextChangedP classification path` — immediately reclassify the post-mutation buffer after `InsertCharPre`, remove `a` for protected/unknown outcomes, and preserve the specified one-event lag without attempting to pre-classify newly created markup from non-delimiter characters.
- [x] `tests/smoke.lua: Slice 6 — InsertCharPre and post-mutation safety` — verify every exact byte set for all five structured types, multi-byte `v:char`, non-delimiter and plain cases, no-probe behavior during InsertCharPre, post-mutation reclassification through TextChangedI/P, one-event lag, ownership preservation, and InsertLeave cleanup.

### Slice 7 — Suspension, status, ownership, and isolation regression

- [x] `lua/pencil/init.lua: manual suspension consumption`, `semantic_status(state)`, `formatoptions_owned(state)`, and `cleanup(state, force)` — consume pending M003 suspension only at an eligible prose hard-mode Insert boundary, including no-typing and same-Insert protected/unknown→prose transitions; never consume or recreate it for protected/unknown, soft, or ineligible states; retain immediate ownership checks, exact restoration, and cleanup invalidation.
- [x] `lua/pencil/init.lua: FileType, BufUnload, and BufWipeout callbacks` — preserve preference and pending suspension across filetype changes while invalidating classification, discard classification and temporary flags on cleanup/wipeout, and prevent stale state from leaking between buffers or windows.
- [x] `tests/smoke.lua: Slice 7 — suspension, ownership, status, cleanup, and M003 regressions` — cover pending-suspension truth tables, no-typing prose consumption, reclassification transitions, external `formatoptions` edits, exact restoration, structured synchronous status versus latest Insert result, plain status compatibility, multiple buffers/windows, cleanup during Insert, and the complete M001–M003 smoke/regression behavior.

## Parallel Work

Do not parallelize the initial classification seam. First establish the state record, exact probe representation, result vocabulary, normalization/rule-table format, combination algorithm, and the interface between classification and M003 `reconcile_formatoptions()`/`semantic_status()`. The integration must be able to run fail-closed before any parser or syntax implementation is added.

After that seam is stable, these tracks may proceed in parallel:

1. `lua/pencil/init.lua: insertion_probes()`, UTF-8 boundary helpers, normalization, rule tables, and Slice 2 probe/rule tests.
2. `lua/pencil/init.lua: treesitter_path()`, node/range/ancestor helpers, TeX environment extraction, and Slice 3 parser-dependent tests.
3. `lua/pencil/init.lua: syntax_available()`, syntax probes/stacks, group translation, and Slice 4 fallback tests.
4. `lua/pencil/init.lua: classify_location()`, path combination, lifecycle autocmd registration, and Slice 5 event tests after the probe/path seams exist.
5. `lua/pencil/init.lua: InsertCharPre delimiter handling` and Slice 6 post-mutation tests after lifecycle classification is integrated.
6. Suspension/status/cleanup integration and Slice 7 isolation/regression tests after classification transitions are authoritative.

Integrate in slice order. Run the complete real-Neovim smoke suite after each integration point, recording the exact Neovim version and optional parser availability.

## Acceptance / Verification

- [x] Run the repository's isolated headless behavior suite with every available supported Neovim version, recording each version and reporting unavailable versions rather than substituting an unrecorded binary.
- [x] Record parser/runtime availability in the test output; parser-dependent cases must either use the pinned representative parser/current-tree fixture or be skipped with an explicit reason, while all syntax fallback and fail-closed cases still run without a parser.
- [x] Confirm the exact structured set (`markdown`, `rst`, `tex`, `asciidoc`, `textile`), M003 plain set (`text`, `gitcommit`, `mail`), and unknown-filetype behavior.
- [x] Confirm the §3 combination table, same-ancestor containment rule, path disagreement failure, and independent fallback behavior.
- [x] Confirm exact insertion probes, UTF-8 byte boundaries, EOL/empty-line behavior, delimiter adjacency, invalid positions, and bounded/no-out-of-range inspection.
- [x] Confirm Treesitter current-tree requirements, fixed-depth ancestor work, protected-name tables, stale/error/missing/`ERROR`/mixed-span fail-closed behavior, and bounded TeX environment extraction.
- [x] Confirm syntax activity preconditions, active empty-stack prose, disabled/unavailable syntax distinction, exhaustive protected matching, and neutral unrecognized groups.
- [x] Confirm synchronous InsertEnter, CursorMovedI, TextChangedI, TextChangedP, supported CompleteChanged, and FileType behavior; confirm InsertCharPre never classifies or invalidates and uses only the exact delimiter bytes.
- [x] Confirm protected/unknown transitions remove only temporary `a`, prose transitions add it only when M003 conditions permit, TextChangedI/P reclassify post-mutation state, and InsertLeave clears it.
- [x] Confirm pending manual suspension consumption, hard/soft/ineligible exclusions, structured status truth, external ownership, exact restoration, buffer/window isolation, and cleanup behavior.
- [x] Run `nvim --headless --clean -u NONE +'set rtp^=.' +'lua require("pencil")' +qa` and `nvim --version` for each available supported Neovim binary.
- [x] Run `git diff --check -- docs/plans/004_protected_region_classification_spec.md` and verify the specification remains unchanged.
- [x] Run `git status --short -- docs/plans/004_protected_region_classification_implement.md` and a final scope check confirming only `docs/plans/004_protected_region_classification_implement.md` was changed by this planning task; do not add M005 behavior, API, or declarations.
- [x] Inspect the guide with `git diff --no-index /dev/null docs/plans/004_protected_region_classification_implement.md` and confirm every checklist item names an exact repo-relative file path and function/helper/test section, contains no production code, and preserves the normative Context & Constraints decisions.
