# 004: Protected-Region Classification Specification

## 1. Context and authority

Milestone 004 adds fail-closed, cursor-aware automatic-formatting safety for the built-in structured filetypes. This document is the normative product and behavior contract for M004. Milestone 000 is authoritative where this document is silent. Milestone 003 remains authoritative for hard-mode formatting, `formatoptions` ownership, suspension, status, commands, exact restoration, and plain-text eligibility, except where this document explicitly extends structured-filetype eligibility.

Supported Neovim versions remain 0.10 and newer. The module remains `require("pencil")`. No Vim compatibility, legacy `g:pencil#...` configuration, required runtime dependency, or implementation-specific public seam is added.

M004 covers only built-in structured classification. Custom classifiers and declarations that mark an unknown filetype as plain text remain M005 scope and are not introduced, expanded, or required here.

## 2. Purpose, scope, and non-goals

### Purpose

Prevent hard-mode automatic formatting from changing structured markup while allowing ordinary prose in the same buffer to format automatically. Classification must work with modern Neovim highlighting, including configurations where legacy Vim regex highlighting is disabled, while retaining a practical fallback for installations without usable Treesitter highlighting.

### In scope

- Built-in classification for exactly `markdown`, `rst`, `tex`, `asciidoc`, and `textile`.
- Three results: `prose`, `protected`, and `unknown`.
- Treesitter as the preferred inspection path and legacy syntax-stack inspection as fallback.
- Fail-closed behavior for unavailable, ambiguous, malformed, stale, or erroring inspection.
- Classification at Insert lifecycle boundaries and immediate reclassification when the cursor or filetype crosses a safety boundary during Insert.

### Non-goals

Custom classifiers and explicit unknown-filetype safety declarations remain M005. M004 also does not add general parsing, formatting, structural wrap sampling, marker generation, new commands, mappings, status values, configuration keys, or guarantees for syntax not represented by the active parser or syntax definition.

## 3. Definitions and exhaustive path combination

A location is `prose` only when usable evidence establishes ordinary prose. `protected` means structured content, including its delimiter and governed content. `unknown` means that safety cannot be established. Only `prose` can permit temporary `formatoptions` flag `a`.

Each inspection path produces one of three path results: `prose`, `protected`, or `unknown` (the path cannot establish safety). A path result is `unknown` when its required inspection is unavailable, stale, malformed, erroring, or contains an unrecognized structure. `unknown` is not positive evidence and never turns another path's result into prose or protected by itself.

After the Treesitter and syntax paths have each produced their result, combine them exactly as follows:

| Treesitter path | Syntax path | Classification |
|---|---|---|
| `prose` | unavailable/`unknown` | `prose` |
| `protected` | unavailable/`unknown` | `protected` |
| `unknown` | `prose` | `prose` |
| `unknown` | `protected` | `protected` |
| `prose` | `prose` | `prose` |
| `protected` | `protected` | `protected` |
| `prose` | `protected` | `unknown` |
| `protected` | `prose` | `unknown` |
| `unknown` | unavailable/`unknown` | `unknown` |

“Unavailable” is the same non-usable path result as `unknown` for this table. Thus a usable result from either path is sufficient when the other path cannot inspect the location; two usable disagreeing results fail closed. There is no precedence exception and no cross-path containment exception. Within a path, evidence must likewise agree: conflicting probe evidence is `unknown`, except that prose probes wholly contained by the same protected ancestor may be classified `protected` as specified in §5. If there is no usable evidence, or an invalid probe/error is relevant to that path, that path is `unknown`.

Classification computes the §4 probe set, obtains one result from each path under §§5–7, and applies the table once. Treesitter is preferred for obtaining evidence, but has no overriding precedence; syntax is a secondary path, not an override. `text`, `gitcommit`, and `mail` retain M003 whole-buffer prose eligibility; no other unknown filetype becomes prose.

## 4. Exact insertion-point probing

Neovim cursor columns and Treesitter columns are byte columns. For the current window and target buffer, let `row` be the zero-based cursor row, `line` the bytes of that line, `L = #line`, and `p` the zero-based byte cursor column returned by the API. `0 <= p <= L` is required. The cursor must be at a UTF-8 character boundary; otherwise the result is `unknown`.

The insertion point is the boundary before byte `p`. The bounded probe set is:

- the point `(row,p)`;
- if `p < L`, the character beginning at `p` (its start and end range);
- if `p > 0`, the UTF-8 character immediately before `p` (its start and end range).

The point itself is always probed. The adjacent-character probes make a delimiter immediately before or after the insertion point part of the decision. No scan beyond these two adjacent characters is permitted. An adjacent delimiter is evidence for the same conflict rule in §3; it is not an unconditional override. Protected evidence may prevail only when every conflicting prose probe is fully contained by the same protected ancestor.

At EOL, `p == L`; only the point and the preceding character are probed. On an empty line, `L == p == 0` and only the point is probed. A delimiter at either end of a line is covered by the same rule. Multibyte characters are treated as whole UTF-8 characters: Pencil never decrements or increments into a continuation byte and never converts byte columns to display columns. These rules apply to every classification event in §8. `InsertCharPre` does not perform probing or parsing; it uses only the last valid classification result under the invalidation contract in §8.

For each probe, a node/range or syntax group must contain the insertion point or the probed character range. Merely finding a construct elsewhere on the line is insufficient.

## 5. Treesitter path: existing tree and bounded inspection

Treesitter is preferred only when the buffer has an already initialized parser for its current language and an existing current tree covering the requested row. M004 does not create a parser, synchronously parse the buffer, wait for a parse, or inspect a whole buffer. The implementation may obtain the parser/tree using APIs available in Neovim 0.10 and may use the current tree/root and node ranges; it must tolerate API differences without notifications.

For every probe, select the smallest named node whose range contains the point/character, then walk that node and its ancestors to the root. Anonymous punctuation nodes may be used only for delimiter coverage; classification is based on the smallest relevant named ancestor. A node is relevant only when its normalized name is in the exact table in §7 or matches a listed token-boundary prefix from that table. Generic `paragraph`, `text`, `heading`, `list`, and `item` nodes are prose unless a protected ancestor exists. An `ERROR` node or a node with an invalid/missing range makes the relevant evidence unusable and the result `unknown` when it is on the selected path or contains a probe.

The existing tree must be current for the buffer contents at inspection time. A parser marked invalid, a tree whose changed ranges include the target and has not been updated, a missing root, a root that does not cover the target, missing point evidence, or a parser/tree callback error makes the Treesitter path `unknown`. The syntax path is then evaluated independently and combined by §3. Work is bounded to the probe nodes and their ancestor chains, with a fixed maximum ancestor depth and no line or buffer scan.

A parser may expose a protected node that spans both markup and prose. The whole node contributes `protected` evidence. If a node is partly covered by an `ERROR` or an unrecognized embedded language, the Treesitter path is `unknown`; it is never silently downgraded to prose. Missing optional parser fields do not get guessed from text. An unrecognized node/group-like structure on the selected path is also `unknown` for the Treesitter path; it is not neutral evidence.

## 6. Syntax availability and fallback

The syntax fallback uses only Neovim 0.10-observable buffer state and `synstack()`/`synID()` APIs; it does not parse `:syntax` output or inspect display text. Syntax is demonstrably active for this decision only when all of these hold:

- `&syntax` is exactly the current structured filetype (or its documented active syntax name);
- `b:current_syntax` exists and is nonempty, and `:syntax` has not been explicitly disabled for the buffer; and
- bounded `synstack()`/`synID()` calls at the insertion probes complete without error, with at least one nonempty stack observed in the current buffer during a bounded probe of the current line and its immediately adjacent nonempty line, when one exists.

The last condition distinguishes an empty stack at ordinary prose from syntax being disabled or unavailable. Once syntax is proven active, an empty stack at the actual insertion point may mean prose. If no nonempty stack can be observed, or any availability check/API call errors, an empty stack means `unknown`, not prose. A syntax definition may legitimately have an empty stack on a prose point only after the bounded activity test succeeds.

For each probe, obtain the complete syntax stack and translated group names. Syntax evidence consists only of (1) syntax availability established by this section and (2) whether the stack matches one of the protected patterns in §7. When syntax is demonstrably active, a stack with no protected match is `prose`, including an empty stack. Unrecognized group names are neutral: they do not create evidence for either side and are not “unknown” merely because their names are not in §7. Thus syntax does not depend on a catalog of neutral prose groups. The syntax path is `unknown` only when syntax is not demonstrably active, a required API/probe operation errors, or a probe is malformed. A disagreement among syntax probes is `unknown`; an active stack with no protected match remains prose, regardless of neutral or unrecognized group names. The syntax path result is combined with the Treesitter result only by §3.

## 7. Deterministic format rules

Names are normalized before matching: split an ASCII lowercase letter or digit followed by an uppercase ASCII letter, lowercase the result, replace each run of non-ASCII-alphanumeric characters with one `_`, and trim `_`. Matching is either exact equality with a table entry or an explicitly listed prefix followed by a token boundary (`_`, end of name, or a digit-to-letter boundary); the prefix itself must begin and end on normalized token boundaries. No substring, inferred alias, or unspecified suffix matches. The following tables are exhaustive.

| Filetype | Exact protected Treesitter names | Protected Treesitter prefixes | Exact protected syntax names | Protected syntax prefixes |
|---|---|---|---|---|
| `markdown` | `fenced_code_block`, `indented_code_block`, `code_fence`, `front_matter`, `table`, `html_block`, `html_tag`, `link_reference_definition`, `math` | `embedded`, `raw` | `markdown_code`, `markdown_table`, `markdown_front_matter`, `markdown_link_definition`, `markdown_html`, `markdown_math` | `markdown_code`, `markdown_table`, `markdown_front_matter`, `markdown_link_definition`, `markdown_html`, `markdown_math` |
| `rst` | `directive`, `directive_argument`, `directive_option`, `literal_block`, `doctest_block`, `comment`, `target`, `substitution_definition`, `table`, `field_list`, `raw`, `parsed_literal` | none | `rst_directive`, `rst_literal_block`, `rst_doctest_block`, `rst_comment`, `rst_hyperlink_target`, `rst_substitution_definition`, `rst_table`, `rst_field_list` | `rst_raw_block` |
| `tex` | `comment`, `math`, `inline_formula`, `displayed_equation`, `verbatim`, `raw`, `command`, `label`, `reference`, `cite` | `preamble`, `control` | `tex_comment`, `tex_math`, `tex_math_zone`, `tex_verb`, `tex_verbatim`, `tex_listing`, `tex_minted`, `tex_cmd`, `tex_section`, `tex_label`, `tex_ref` | `tex_math_zone` |
| `asciidoc` | `source_block`, `listing_block`, `literal_block`, `example_block`, `sidebar`, `quote_block`, `table`, `attribute_entry`, `attribute_reference`, `comment`, `passthrough`, `block_title`, `block_id` | `block_option` | `asciidoc_block`, `asciidoc_listing_block`, `asciidoc_literal_block`, `asciidoc_table`, `asciidoc_attribute`, `asciidoc_comment`, `asciidoc_passthrough` | `asciidoc_delimiter`, `asciidoc_title`, `asciidoc_option` |
| `textile` | `code_block`, `pre_block`, `table`, `html`, `comment`, `block_attributes`, `raw`, `passthrough` | none | `textile_code`, `textile_pre`, `textile_table`, `textile_html`, `textile_comment`, `textile_block` | `textile_delimiter`, `textile_attribute` |

The nearest matching ancestor protects its complete range, including delimiters and governed content. A syntax stack containing any exact name or prefix match is protected. Ordinary headings, lists, list items, and paragraphs are prose only when no protected evidence applies. Exact protected TeX nodes such as `math`, `verbatim`, and `raw` retain the handling above; a generic TeX `environment` node is not itself protected. For a generic TeX environment node or ancestor, derive one exact normalized environment name from the node/ancestor text by a bounded local extraction of a `\\begin{...}` or `\\end{...}` delimiter and its name. Do not scan beyond the selected node/ancestor text or infer a name from unrelated text. The extraction is valid only when the delimiter, braces, and name are present, the name is nonempty and well formed, and the available begin/end names do not disagree; otherwise the environment evidence is `unknown`. Normalize the extracted name using the rules above.

The finite exact protected TeX environment-name set is `align`, `align_`, `alignat`, `alignat_`, `bmatrix`, `cases`, `comment`, `displaymath`, `equation`, `equation_`, `filecontents`, `filecontents_`, `flalign`, `flalign_`, `gather`, `gather_`, `lstlisting`, `listing`, `math`, `matrix`, `minted`, `multline`, `multline_`, `pmatrix`, `split`, `thebibliography`, `verbatim`, `verbatim_`, `vmatrix`, `xalignat`, `xalignat_`, `xxalignat`, and `xxalignat_`. A normalized name in this set is protected. The finite prose-environment allowlist is exactly `document`, `abstract`, `quote`, `quotation`, `verse`, `center`, `flushleft`, and `flushright`; a valid name in this allowlist provides prose evidence unless a more specific protected descendant or ancestor, such as math, verbatim, or listing, provides protected evidence. Every other TeX environment is unknown, including an unknown, absent, malformed, or mixed name; it is never presumed prose or protected. A generic syntax environment group likewise cannot by itself establish protection and is `unknown` unless the same bounded name extraction establishes one of these exact outcomes. Any construct exposed as raw, code, math, table, directive, comment, embedded content, or environment but not matched by these tables is unknown. Mixed protected/prose evidence is resolved only by §3.

## 8. Insert lifecycle and exact invalidation contract

Classification runs synchronously on `InsertEnter`, including an Insert transition at EOL or on an empty line. While Insert is active it also runs synchronously on every `CursorMovedI`, `TextChangedI`, `TextChangedP`, `CompleteChanged` (when supported), and `FileType` event. Each such classification event first performs the §4 probes and gathers evidence, then compares the new result with the last valid result; it must not use a cached boundary/range as a reason to skip probing. A `FileType` event probes using the new filetype. The event result is authoritative even when it equals the previous result.

`InsertCharPre` is not a classification event and never invalidates or reclassifies the last result. It performs no probing, parsing, or tree/syntax access and uses the last classification. To fail closed at the safety boundary, it removes Pencil's temporary `a` contribution before the character only when all of these hold: the last classification is `prose`, ownership still holds, and `v:char` contains a structural delimiter byte in the exact set for the current structured filetype below. It removes nothing for a non-delimiter, an absent/invalid last result, or a plain type. The sets are byte sets (not character classes): `markdown` = `{0x60, 0x3C, 0x5B, 0x21}` (backtick, `<`, `[`, `!`); `rst` = `{0x3A, 0x2E, 0x5B, 0x5F}` (`:`, `.`, `[`, `_`); `tex` = `{0x5C, 0x25, 0x24, 0x7B, 0x7D}` (`\`, `%`, `$`, `{`, `}`); `asciidoc` = `{0x2D, 0x2A, 0x2E, 0x3D, 0x5B, 0x5D, 0x60, 0x3A}` (`-`, `*`, `.`, `=`, `[`, `]`, `` ` ``, `:`); and `textile` = `{0x22, 0x2A, 0x23, 0x2E, 0x3D, 0x7C, 0x3C, 0x3E}` (`"`, `*`, `#`, `.`, `=`, `|`, `<`, `>`). A multi-byte `v:char` removes `a` if any byte is in the set. This finite list is the complete M004 InsertCharPre safety set; it is not a claim that newly typed bytes can be pre-classified.

The mutation caused by `InsertCharPre` is not classified before it happens. `TextChangedI`/`TextChangedP` immediately reclassifies the post-mutation state and removes `a` when the result is protected or unknown. Consequently there is exactly a one-event lag between the character pre-event and post-mutation classification, with the delimiter set as its safety boundary. M004 does not promise prevention of formatting triggered by a single non-delimiter character that creates markup. Events are processed in Neovim dispatch order; an unsupported event is not registered and has no substitute. `CompleteChanged` is registered when supported; otherwise completion causes no extra classification. InsertEnter, CursorMovedI, TextChangedI, TextChangedP, and FileType behavior remains mandatory.

On a transition to `protected` or `unknown`, Pencil immediately removes only its temporary `a` contribution if ownership still holds. On a transition to `prose`, it immediately adds only temporary `a` when all M003 conditions, including manual suspension and ownership, permit it. External `formatoptions` ownership prevents both writes. InsertLeave removes only temporary `a` and clears the current classification. The next Insert always starts with a fresh probe.

A classification result is per enabled buffer and current Insert window/cursor; it is never reused by another buffer or window. Cleanup and wipeout discard it. Filetype changes preserve M003 preference and pending manual suspension while invalidating the classification.

## 9. Status and pending suspension consumption

No new status value is added. This explicitly overrides M003 status behavior for structured types: outside Insert, every `status()` call synchronously classifies the current cursor location (using the current buffer/filetype, not the last Insert result). It reports `A` iff that classification is `prose`, the M003 hard-mode conditions say formatting is armed, and Pencil still owns `formatoptions`; otherwise it reports `H`. During Insert, status uses the latest classification result from the lifecycle events in §8 and reports `A` iff it is `prose`, armed, and owned; `protected` and `unknown` report `H`. Soft mode remains `S`; disabled status is unchanged. Plain types retain M003 status behavior without this structured-type override.

Manual M003 suspension is separate from classification. A `protected` or `unknown` classification neither creates nor consumes a pending manual suspension. A pending manual suspension is consumed only when a hard-mode Insert reaches an eligible `prose` boundary with the manual preference enabled; this includes an Insert with no typing. A protected/unknown structured Insert does not consume it, and a soft or otherwise ineligible Insert does not consume it. Reclassification from protected/unknown to prose during the same Insert is the point at which the pending suspension is consumed. Reclassification back to protected/unknown does not create another pending suspension. All M003 enable/disable, queue, ownership, and exact-restoration rules remain authoritative.

## 10. Compatibility, parser behavior, and bounded work

The implementation runs on Neovim 0.10 and newer without requiring a parser or syntax plugin. It performs no parser installation, whole-buffer parse, yielding, command execution, option mutation unrelated to `formatoptions`, or unbounded scan at Insert entry or boundary crossing. Treesitter work is limited to the existing current tree, bounded probe nodes, and a fixed-depth ancestor walk; syntax work is limited to the insertion probes and the bounded activity probes in §6. Routine parser absence, stale/error trees, empty stacks, unsupported names, and classification errors are quiet and fail closed.

Tests must be reproducible with isolated headless Neovim processes. The required parser-path tests must state and pin the parser/runtime availability used by the test fixture, load a representative parser when available, and exercise current-tree, stale/error, missing-node, `ERROR`, and mixed-span cases. The syntax-path tests must explicitly enable the relevant built-in syntax definitions, verify the §6 activity precondition, and separately test active empty-stack prose versus disabled/unavailable syntax. An environment without an optional parser must skip only parser-dependent cases with an explicit recorded reason and still run all fallback and fail-closed cases; it must not silently claim parser coverage.

## 11. Public API and configuration

M004 adds no public API, command, mapping, or configuration key. Existing M003 calls, command grammar, aliases, validation, status strings, suspension, and ownership behavior are unchanged. There is no M004 classifier callback, protected-node configuration, syntax-group configuration, or unknown-filetype declaration. Those are M005 scope.

## 12. Acceptance matrix

Implementation is accepted only if isolated headless Neovim tests observe:

| Area | Required observations |
|---|---|
| Structured set | Exactly `markdown`, `rst`, `tex`, `asciidoc`, and `textile` classify; `text`, `gitcommit`, and `mail` retain M003 prose eligibility; unknown filetypes fail closed. |
| Precedence | The §3 conflict algorithm is exercised, including unanimous evidence, disagreement, same-ancestor containment, fallback, and inspection errors. |
| Probe boundaries | InsertEnter variants, EOL, empty lines, delimiters on either side, UTF-8 multibyte boundaries, invalid byte positions, and no out-of-range probes are observed. |
| Treesitter | Existing current trees classify minimum ancestors; missing/stale/error trees, `ERROR` nodes, missing nodes, and mixed spans fail closed with bounded work. Generic TeX `environment` nodes derive an exact name using bounded local delimiter/name extraction: the listed prose environments classify as prose, the finite listed protected environments classify as protected, nested specific protected descendants/ancestors override prose, and unknown or malformed names fail closed. |
| Syntax | Every format has representative protected and ordinary heading/list/paragraph prose cases; syntax names match only the exhaustive exact-name and token-boundary prefix tables; active empty-stack prose differs from disabled/unavailable syntax. |
| Lifecycle | Synchronous classification probes run on InsertEnter, every CursorMovedI, TextChangedI, TextChangedP, supported CompleteChanged, and FileType; transitions immediately remove/add temporary `a`; InsertCharPre never reclassifies or invalidates, removes `a` only for the exact per-format delimiter sets in §8 when the last result is prose/owned, and TextChangedI/P immediately reclassify; InsertLeave removes it. |
| Suspension | Protected/unknown does not consume pending manual suspension; the first eligible prose Insert or prose reclassification consumes it, including no-typing cases; soft/ineligible cases do not. |
| Ownership/status | External `formatoptions` ownership is never overwritten; exact M003 restoration remains; structured status synchronously classifies outside Insert and uses the latest Insert result, with `A` iff prose/armed/owned; plain status retains M003; status is `S`, `A`, or `H` as §9 requires. |
| Isolation/cleanup | Buffers and windows do not leak classification or flags; cleanup during Insert leaves no stale state. |
| Optional parser testing | Parser-dependent coverage is reproducible or explicitly reported unavailable; fallback coverage still runs without a parser. |

## 13. Validation commands

From the repository root, run the repository's isolated headless behavior suite with the available supported Neovim versions and record each version and any unavailable optional parser. Validation wording must not require an environment to provide a particular Neovim binary or parser: unavailable versions are reported as unavailable, not replaced by an unrecorded substitute, while available versions still run all applicable tests.

At minimum, verify the document itself and repository scope with:

```sh
nvim --headless --clean -u NONE +'set rtp^=.' +'lua require("pencil")' +qa
nvim --version
git diff --check -- docs/plans/004_protected_region_classification_spec.md
git status --short -- docs/plans/004_protected_region_classification_spec.md
```

The final scope check must show that this task changed only `docs/plans/004_protected_region_classification_spec.md`. No M005 behavior, API, or declaration is to be added while validating M004.
