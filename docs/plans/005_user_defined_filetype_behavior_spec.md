# 005: User-Defined Filetype Behavior Specification

## 1. Context and authority

Milestone 005 adds user-defined filetype behavior to Pencil.nvim. It extends the built-in preset and protected-region safety policy established by milestones 000–004 without changing the existing enable/disable lifecycle, mode detection, mapping ownership, hard-mode formatting ownership, or status semantics except where this document explicitly defines custom-filetype classification.

Milestone 000 is authoritative where this document is silent. Milestones 001 and 002 remain authoritative for setup, filetype activation, mode selection, mappings, buffer/window isolation, and exact restoration. Milestone 003 remains authoritative for automatic-formatting preference, suspension, `formatoptions` ownership, and the `S`/`A`/`H` status meanings. Milestone 004 remains authoritative for built-in structured classification, its probe and lifecycle rules, fail-closed behavior, and synchronous status classification. M005 supersedes M004's built-in classification policy for a configured built-in filetype: an effective keyed `format_safety = "plain"` makes that filetype plain, and an effective keyed `classifier` makes it custom; neither runs M004 classification. Where a rule in this document concerns a user-defined policy, this document also supersedes the earlier generic unknown-filetype behavior.

Supported Neovim versions remain 0.10 and newer. Vim is not supported. The module remains `require("pencil")`; no required runtime dependency, legacy `g:pencil#...` configuration, undocumented function, or legacy command is added.

The outcome is a predictable configuration contract:

- keyed `filetypes` entries merge over the applicable built-in preset;
- an explicit `format_safety = "plain"` declaration opts a filetype into whole-buffer plain-prose formatting, even when that filetype has a built-in structured preset;
- a custom `classifier` replaces built-in classification for that filetype;
- `format_safety = "plain"` and `classifier` are mutually exclusive and are a validation error;
- unknown filetypes remain fail-closed unless one of those two explicit safety policies is supplied;
- configuration validation is atomic.

This is a specification, not an implementation plan. It defines externally observable behavior and test obligations, not module layout or private algorithms.

## 2. Definitions

### 2.1 Filetype policy

A **filetype policy** is the effective configuration for one exact buffer `&filetype`. Resolution is field-wise, never whole-table replacement. For every ordinary enable setting, the unambiguous order from highest to lowest is:

1. a value supplied in the current `enable()` call (or explicit re-enable), when that field is a legal per-call option;
2. the value supplied in the keyed entry for the exact current filetype;
3. the matching built-in preset value, when the current filetype is a recognized built-in and that preset defines the field;
4. the global setup value;
5. the built-in global default.

Thus a built-in preset beats a global value for fields that the preset explicitly defines, while global setup values fill fields the preset does not define and apply to unknown filetypes. A keyed entry never replaces the whole preset: an omitted keyed field retains the effective built-in result when one exists, otherwise the effective global/default result. A simple list has no keyed override and recognized names retain the same built-in-preset merge; unknown names resolve from global setup and built-in global defaults.

`format_safety` and `classifier` follow the same keyed-over-built-in policy selection, but have no legal per-call, global setup, or built-in-global-default value. Their only legal declaration site is the keyed entry for the exact filetype. The filetype policy controls mode, fallback, width, automatic-formatting preference, mapping groups, conceal behavior, and safety as applicable. Existing precedence rules remain in force for settings not discussed here.

### 2.2 Built-in, known, and unknown filetypes

The built-in preset set is exactly:

| Filetype | Mode | Fallback | Width | Default format safety |
|---|---|---:|---:|---|
| `gitcommit` | hard | — | 72 | plain |
| `mail` | hard | — | 72 | plain |
| `markdown` | detect | soft | — | structured |
| `text` | detect | soft | — | plain |
| `rst` | detect | hard | 79 | structured |
| `tex` | detect | hard | 79 | structured |
| `asciidoc` | detect | hard | 79 | structured |
| `textile` | detect | soft | — | structured |

A **known filetype** is one of the eight names above. An **unknown filetype** is any other nonempty filetype name, including a name selected by a simple list but not present in the built-in table.

An unknown filetype has no implicit safety. Its hard-mode automatic formatting is ineligible and its status is fail-closed until the user explicitly supplies `format_safety = "plain"` or a valid custom `classifier`.

### 2.3 Format safety policy

The effective format safety policy is exactly one of:

- **plain** — the whole buffer is treated as ordinary prose for automatic-formatting eligibility; no cursor classifier runs;
- **built-in structured** — M004 classification applies for the five built-in structured filetypes;
- **custom structured** — the configured classifier supplies the cursor result;
- **unknown** — no policy establishes that formatting is safe, so classification is `unknown` and formatting remains suspended.

`format_safety = "plain"` is an explicit opt-in. It is not limited to unknown filetypes and may override a built-in structured default such as Markdown.

A `classifier` is an explicit custom structured policy. It replaces, rather than supplements or wraps, the built-in classifier for the filetype. The classifier's result is the complete classification result for the current location.

### 2.4 Classification results

The only classification results are:

- `"prose"` — automatic formatting may run, subject to M003 preference, suspension, mode, ownership, and lifecycle rules;
- `"protected"` — automatic formatting remains suspended;
- `"unknown"` — safety cannot be established; automatic formatting remains suspended.

Plain safety produces `"prose"` without invoking a callback. Unknown safety produces `"unknown"` without invoking a callback. Built-in structured safety uses the complete M004 result. A custom classifier is the only source of custom structured results.

## 3. Configuration shape and merge rules

### 3.1 Normative shape

The established configuration shape is extended as follows:

```lua
require("pencil").setup({
  filetypes = {
    markdown = {
      fallback = "hard",
      textwidth = 80,
      format_safety = "plain",
    },
    mymarkup = {
      mode = "hard",
      textwidth = 80,
      classifier = function(ctx)
        return "prose"
      end,
    },
  },
})
```

`format_safety` is valid only with the exact string value `"plain"`. It is not a general enum and no other value is accepted. It is legal only as a field in `filetypes.<name>`; global setup options, `enable()` options, and every other per-call placement are rejected.

`classifier` is a function. It may appear only as a field in `filetypes.<name>`. It is rejected in global setup options, in a simple filetype list, in `enable()` options, and in every other per-call placement. A simple list cannot carry either safety declaration.

A keyed entry may contain the existing per-filetype settings and exactly one of `format_safety` or `classifier`. It may omit both, in which case the built-in safety policy or unknown-filetype fail-closed policy remains in effect. Empty-string keyed names are invalid, so no empty-string entry can be represented; an empty `&filetype` is always unknown and fail closed.

### 3.2 Selection and merging

`filetypes` has the established replacement semantics:

- If omitted, automatic activation uses all built-in filetypes and their built-in presets.
- A simple list replaces the built-in automatic set. Recognized names retain their built-in presets. Unknown names use global detect/fallback settings and remain unknown safety unless configured by a keyed entry shape supported by the configuration contract.
- A keyed table replaces the built-in automatic set with its keys. Each key resolves by merging its supplied fields over the matching built-in preset, then global settings, then built-in defaults.
- `filetypes = {}` disables automatic activation while leaving direct Lua controls and commands available.

For a keyed entry, merge is field-wise and shallow at the documented settings level. An omitted `format_safety` does not erase a built-in structured policy. An omitted `classifier` does not erase a built-in classifier. A keyed override cannot accidentally inherit a classifier from a different filetype.

Examples:

```lua
filetypes = {
  markdown = { fallback = "hard" },
}
```

This remains built-in structured Markdown; only its fallback changes.

```lua
filetypes = {
  markdown = { format_safety = "plain" },
}
```

This remains the Markdown preset for mode and width, but its safety policy is plain and M004 classification does not run.

```lua
filetypes = {
  mymarkup = { mode = "hard", classifier = classify_mymarkup },
}
```

This creates an unknown-filetype entry with custom structured safety. It does not use any built-in structured classifier.

### 3.3 Precedence and activation boundaries

Per-call mode, fallback, width, and other already-established enable options retain their existing highest precedence. A per-call option cannot supply or override `format_safety` or `classifier`; safety is a filetype policy declaration, not an activation-local escape hatch.

A valid later `setup()` replaces configuration only for future activations. Existing enabled buffers retain their resolved mode, safety policy, classifier reference, formatting preference, suspension state, and active behavior. Setup alone never changes an active buffer or reclassifies it.

An explicit re-enable of an active buffer resolves the current configuration and filetype policy afresh, following the established re-enable semantics. It may therefore change the buffer's safety policy, but it must preserve all exact restoration and ownership guarantees. An explicit disable followed by enable also resolves fresh policy and fresh detection; no stale classifier or classification result survives the disable.

## 4. Custom classifier contract

### 4.1 Invocation context

The classifier is called synchronously with exactly one read-only context table:

```lua
{
  buf = 3,             -- target buffer handle
  win = 7,             -- window performing the classification
  row = 12,            -- zero-based cursor row
  col = 18,            -- zero-based cursor byte column
  filetype = "mymarkup",
}
```

`row` and `col` have the same meaning as M004: `row` is zero-based and `col` is a zero-based byte index, not a display column or character index. `buf` is the target buffer and `win` is the current window used for the classification. `filetype` is the exact current filetype string used to resolve the policy.

The context table and its fields are read-only for the duration of the call. Pencil does not promise that mutations attempted by a callback will be prevented by Lua mechanics, but any callback that mutates editor state violates this contract. Pencil must not rely on callback mutations for correctness and must not expose mutable internal policy or state through the context.

The classifier is synchronous and must return immediately. It must not yield, schedule work for classification, wait for parser updates, or require a later callback to decide whether formatting is safe.

### 4.2 Permitted result and failure behavior

A valid classifier return is exactly one of:

```lua
return "prose"
return "protected"
return "unknown"
```

Any other return value, including `nil`, a boolean, a number, a table, an error object, or a string with different casing or whitespace, is invalid and is treated as `"unknown"`.

If the callback raises an error, yields, cannot be called, or otherwise fails, Pencil treats the result as `"unknown"`. Routine callback errors and invalid returns are quiet; they do not notify, abort activation, or raise an error into the user's Insert lifecycle.

A callback result must not alter the buffer, window, cursor, options, mappings, undo history, filetype, or Pencil configuration. Pencil does not roll back callback side effects; such side effects are outside the contract and are the callback author's responsibility. Pencil's own safety behavior after any callback outcome is the returned-or-failed classification rule above.

### 4.3 Replacement and invocation exclusion

When a custom classifier is effective for a filetype:

- the M004 Treesitter path is not queried;
- the M004 syntax fallback is not queried;
- no built-in classifier result is combined with the callback result;
- the callback result alone determines `prose`, `protected`, or `unknown`;
- plain safety is not also applied;
- the callback is not invoked for a filetype other than the filetype entry that declares it.

When effective safety is plain, the classifier is never invoked. When effective safety is built-in structured, only M004 classification is used. When safety is unknown, no classifier is invoked and the result is `unknown`.

## 5. Validation and atomicity

### 5.1 Validation requirements

`setup()` validates the complete proposed configuration before installing any part of it. Validation errors must identify the relevant path, including the filetype name where applicable, and must be aggregated into one Lua error.

The following are invalid:

- a `filetypes` value with an unsupported type;
- a keyed filetype name that is not a nonempty string;
- a filetype entry with an unsupported type;
- `format_safety` with any value other than the exact string `"plain"`;
- `format_safety` in global setup options, `enable()` options, or any other per-call placement;
- `classifier` with any value other than a function;
- a classifier in global setup options;
- a classifier in `enable()` options or any other per-call options;
- either safety field in a simple filetype list or any location other than `filetypes.<name>`;
- both `format_safety` and `classifier` present in one keyed filetype entry;
- malformed mode, fallback, width, autoformat, mapping, conceal, or status settings covered by earlier specifications;
- duplicate or otherwise ambiguous filetype declarations if the input representation cannot resolve them deterministically.

A function in a keyed entry is accepted as a value during setup validation; it is not called during setup. Callback execution errors and invalid runtime returns are operational fail-closed outcomes, not setup validation errors.

### 5.2 Atomic result

If any validation error exists:

1. `setup()` raises one error containing every validation problem found in that call;
2. no new configuration is installed;
3. the prior valid configuration remains unchanged;
4. no automatic activation set is partially replaced;
5. no existing buffer is reconfigured, disabled, or reclassified;
6. no classifier is invoked.

A valid setup installs the complete new configuration as one update. Automatic activation begins only after setup has successfully completed. The optional no-setup built-in defaults do not include user-defined entries.

## 6. Lifecycle and classification behavior

### 6.1 Plain safety

An effective plain policy classifies every cursor location in the buffer as `prose`. It does not inspect Treesitter or syntax and does not invoke a callback. It therefore permits M003 automatic formatting in hard mode whenever the manual preference, suspension, and `formatoptions` ownership conditions permit it.

This behavior applies equally to unknown filetypes and built-in structured filetypes explicitly overridden with `format_safety = "plain"`. The declaration is the user's assertion that the entire filetype is safe to format as ordinary prose; Pencil does not attempt to detect exceptions within it.

### 6.2 Custom safety

An effective custom policy classifies the current location by invoking the classifier under §4. The callback runs at the same classification lifecycle points required by M004 for a structured policy:

- synchronously on `InsertEnter`;
- synchronously on every `CursorMovedI`, `TextChangedI`, `TextChangedP`, supported `CompleteChanged`, and `FileType` event while Insert is active;
- synchronously when `status()` is requested outside Insert for a hard-mode custom-classifier buffer;
- on any explicit classification needed to determine the current hard-mode safety state.

The callback is not invoked on `InsertCharPre`; that event never classifies or invalidates a result. `InsertCharPre` uses the M004 delimiter pre-safety behavior only for built-in structured formats. For custom classifiers there is no delimiter set and no pre-event inference: it does nothing, and post-change lifecycle events classify the resulting state.

The latest event classification is authoritative during Insert, even if equal to the previous result. InsertLeave clears the current classification. The next Insert always invokes a fresh callback. A callback result is per enabled buffer and current classification window/cursor; it cannot be reused by another buffer, window, filetype, or activation.

On `prose`, Pencil may add its temporary `formatoptions` `a` contribution only when all M003 conditions permit. On `protected` or `unknown`, Pencil removes only that temporary contribution if Pencil still owns `formatoptions`. External ownership prevents all such writes. Errors and invalid returns follow the same fail-closed, quiet path.

### 6.3 Unknown safety

An unknown filetype with no explicit policy always classifies as `unknown`. This includes the empty filetype: because empty keyed names are invalid, there is no exception for `&filetype == ""`. Direct `enable()` and a `FileType` transition to an empty filetype resolve the unknown policy, never invoke Treesitter, syntax inspection, or a callback, and leave hard-mode formatting suspended with status `H` (soft mode remains `S`).

An unknown filetype can become eligible only through a valid keyed entry with `format_safety = "plain"` or a valid keyed entry with `classifier = function`. A simple list entry alone never makes an unknown filetype plain.

### 6.4 Status semantics

M005 does not add a status value. The existing meanings remain:

| Condition | Status |
|---|---|
| enabled soft mode | `S` |
| enabled hard mode, safe formatting armed and owned | `A` |
| enabled hard mode, formatting disabled, suspended, protected, unknown, or externally not owned | `H` |
| disabled or untouched | existing off/untouched indicator |

For a plain policy, hard-mode status follows M003's whole-buffer prose eligibility and does not classify through a callback. For a custom policy, `status()` outside Insert synchronously invokes the classifier and returns `A` only for `prose` when the M003 preference is enabled, no suspension applies, and Pencil owns `formatoptions`; `protected` and `unknown` return `H`. During Insert, status uses the latest custom classification result under the M004 lifecycle rules. For an unknown policy, hard mode always returns `H`.

An unconfigured built-in structured filetype still follows M004 exactly. M005 supersedes that policy whenever its exact keyed entry resolves to plain or custom safety: explicit plain safety changes it from M004 cursor-aware status to whole-buffer prose status, and a custom classifier changes it to callback-defined status. This is intentional and is the observable consequence of policy precedence.

## 7. Buffer, window, filetype, and cleanup isolation

Safety policy and classification state are per enabled buffer. A callback receives the window currently performing classification, but its result must not leak to another window displaying the same buffer. Each window's cursor and filetype event can cause its own current classification state; a window switch must not cause Pencil to use a result computed for a different buffer or stale activation.

The active buffer's resolved policy is captured for the activation. A direct `enable()` resolves the exact current `&filetype`, including an empty value as unknown; it does not retain a prior filetype's policy. A `FileType` change while enabled resolves the new exact filetype policy according to the latest valid configuration and invalidates the old classification before doing any new classification. During Insert, only the newly effective policy may run: a transition to plain runs no callback and becomes `prose`, a transition to unknown (including empty) runs no callback and becomes `unknown`, and a transition to a different classifier invokes only that new classifier. A transition to a built-in structured policy invokes only M004 classification; a custom classifier that overrides built-in plain text likewise invokes only the custom callback. The old callback is never invoked for the transition or afterward. A pending M003 manual suspension is preserved across filetype changes, but it is consumed only by an eligible `prose` hard-mode boundary as specified by M004.

Disabling, wiping out, or fully re-enabling a buffer discards its classifier reference, current result, pending classification data, and callback-specific lifecycle state. Closing a window must not leave a callback result attached to an unrelated window. Multiple buffers may use different policies and callbacks concurrently without shared mutable state or cross-buffer invocation.

A callback must never be invoked for a disabled or untouched buffer, for an unrelated filetype, or after the buffer's activation has been invalidated. If an event races with cleanup, the safe outcome is no callback and no formatting permission.

## 8. Compatibility and performance requirements

The feature works without a parser, syntax plugin, or required dependency. Plain and unknown policies must not access Treesitter or syntax APIs. Custom classification is bounded by one synchronous callback invocation per required classification event; Pencil must not add whole-buffer scanning, parser installation, yielding, or unbounded work around the callback contract.

Routine callback errors, invalid returns, unknown-filetype fail-closed behavior, and normal protected classification remain quiet. Existing notification rules for invalid setup, explicit command failures, mapping conflicts, and attempts to enable autoformat outside hard mode remain unchanged.

Existing configurations that omit M005 fields are backward compatible:

- built-in plain filetypes retain plain behavior;
- built-in structured filetypes retain M004 classification;
- unknown filetypes retain fail-closed behavior;
- existing setup and enable calls need no changes;
- no existing status string changes.

A configuration that adds `format_safety = "plain"` deliberately opts out of structural protection. A configuration that adds a classifier deliberately assumes responsibility for safe callback behavior and correct classification.

## 9. Normative examples

### 9.1 Structured built-in remains protected

```lua
filetypes = {
  markdown = { textwidth = 80 },
}
```

Markdown keeps its built-in detect/soft fallback, width override, and M004 Treesitter/syntax classification. No callback runs.

### 9. Plain override of a built-in structured format

```lua
filetypes = {
  markdown = {
    format_safety = "plain",
    mode = "hard",
    textwidth = 80,
  },
}
```

Markdown uses hard mode at width 80 and is prose at every cursor location. M004 classification is not run. Code fences, tables, and front matter are not protected by Pencil under this explicit declaration.

### 9. Unknown filetype remains fail-closed

```lua
filetypes = {
  notes = { mode = "hard", textwidth = 80 },
}
```

`notes` uses the supplied hard-mode settings but has unknown safety. Automatic formatting remains suspended and hard status is `H`.

### 9. Unknown filetype explicitly marked plain

```lua
filetypes = {
  notes = {
    mode = "hard",
    textwidth = 80,
    format_safety = "plain",
  },
}
```

`notes` is prose everywhere, does not invoke a callback, and may report `A` in an armed, owned hard-mode state.

### 9. Custom classifier replaces built-in classification

```lua
filetypes = {
  markdown = {
    classifier = function(ctx)
      if ctx.row == 0 then
        return "protected"
      end
      return "prose"
    end,
  },
}
```

The callback is the only classifier for Markdown. Treesitter and syntax are not queried. The callback receives the exact buffer, window, zero-based row, zero-based byte column, and `"markdown"` filetype.

### 9. Mutually exclusive declaration is invalid

```lua
filetypes = {
  notes = {
    format_safety = "plain",
    classifier = function() return "prose" end,
  },
}
```

`setup()` rejects this atomically. No part of the proposed configuration is installed, and the previous valid configuration remains active.

## 10. Exhaustive acceptance matrix

The implementation is accepted only when isolated headless Neovim tests observe every applicable cell below through public setup, Lua controls, commands, options, mappings, mode, status, and callback observations.

| Policy/input | Effective safety | Classifier invocation | Classification | Hard-mode formatting/status |
|---|---|---|---|---|
| omitted `filetypes`; `text` | built-in plain | never | `prose` | M003 plain behavior; `A` when armed/owned, otherwise `H` |
| omitted `filetypes`; `markdown` | built-in structured | never custom; M004 paths used | M004 result | M004 `A`/`H` result |
| omitted `filetypes`; unknown | unknown | never | `unknown` | suspended; `H` |
| simple list containing `markdown` | built-in structured | no custom callback | M004 result | M004 behavior |
| simple list containing unknown name | unknown | never | `unknown` | suspended; `H` |
| keyed built-in entry with ordinary override | built-in default | no custom callback | built-in result | existing preset behavior retained |
| keyed built-in structured entry with `format_safety = "plain"` | plain | never | `prose` everywhere | formatting may run; `A` when armed/owned |
| keyed built-in plain entry with `format_safety = "plain"` | plain | never | `prose` | unchanged plain behavior |
| keyed unknown entry without safety field | unknown | never | `unknown` | suspended; `H` |
| keyed unknown entry with `format_safety = "plain"` | plain | never | `prose` everywhere | formatting may run; `A` when armed/owned |
| keyed built-in structured entry with classifier returning `prose` | custom | required lifecycle calls | `prose` | formatting may run; `A` when armed/owned |
| keyed built-in structured entry with classifier returning `protected` | custom | required lifecycle calls | `protected` | suspended; `H` |
| keyed built-in structured entry with classifier returning `unknown` | custom | required lifecycle calls | `unknown` | suspended; `H` |
| keyed unknown entry with classifier returning `prose` | custom | required lifecycle calls | `prose` | formatting may run; `A` when armed/owned |
| classifier raises an error | custom failure | attempted synchronously | `unknown` | suspended; `H`; quiet |
| classifier returns `nil`, boolean, number, table, or other string | custom failure | attempted synchronously | `unknown` | suspended; `H`; quiet |
| classifier yields or cannot be called | custom failure | attempted synchronously | `unknown` | suspended; `H`; quiet |
| both `format_safety` and classifier | invalid config | none | prior configuration remains | no state changes |
| `format_safety` in global setup options | invalid config | none | prior configuration remains | no state changes |
| `format_safety` in `enable()` options | invalid config | none | prior configuration remains | no state changes |
| `format_safety` or classifier in a simple list | invalid config | none | prior configuration remains | no state changes |
| classifier outside `filetypes.<name>` | invalid config | none | prior configuration remains | no state changes |
| invalid format safety value | invalid config | none | prior configuration remains | no state changes |
| empty-string keyed filetype | invalid config | none | prior configuration remains | no state changes |
| direct enable with empty `&filetype` | unknown | never | `unknown` | suspended; `H` |
| multiple unrelated validation errors | invalid config | none | prior configuration remains | one aggregate error |

The following lifecycle matrix is also mandatory for every custom classifier that can be active:

| Event or operation | Required callback behavior | Required safety behavior |
|---|---|---|
| enable in hard mode | classify at the first required hard-mode safety boundary; no deferred asynchronous decision | no formatting permission until a valid `prose` result is available |
| `InsertEnter` | invoke synchronously with current context | apply `a` only for `prose` and all M003 conditions |
| `CursorMovedI` | invoke synchronously, even if location appears unchanged | transition immediately between `prose`, `protected`, and `unknown` behavior |
| `TextChangedI` / `TextChangedP` | invoke synchronously on post-change content | fail closed for non-prose result |
| supported `CompleteChanged` | invoke synchronously | same transition rules |
| `FileType` during Insert | invalidate the old result, resolve the new exact policy, and run only that policy: no callback for plain/unknown, M004 only for built-in structured, or only the new custom callback | transition immediately; plain becomes `prose`, unknown (including empty) becomes `unknown`, and protected/unknown remove temporary `a` |
| `FileType` from custom classifier to plain | never invoke the old or any callback | plain `prose`; remove/add only according to M003 |
| `FileType` from custom classifier to unknown | never invoke the old callback | `unknown`; remove temporary `a` and report `H` |
| `FileType` from custom classifier to a different classifier | invoke only the new classifier | use only the new result; old result and callback are discarded |
| `FileType` from custom classifier to built-in structured | do not invoke the old callback; use only M004 | use only the M004 result |
| custom classifier keyed for built-in plain `text` | invoke only the custom classifier, never a plain shortcut | use only the callback result |
| `status()` outside Insert in hard mode | invoke synchronously | `A` only for valid `prose` plus M003 armed/owned conditions |
| `InsertCharPre` | never invoke; no custom delimiter inference | retain current result until post-change classification; do not add permission |
| `InsertLeave` | no new classification required | remove temporary `a`; clear current result |
| callback error/invalid result | quiet fail-closed result | remove temporary `a` if owned; report `H` |
| disable/wipeout | never invoke after cleanup | discard result and callback state; restore according to M003 |
| window switch/multiple windows | use the active context; never reuse another buffer's result | no cross-window or cross-buffer leakage |

## 11. Required testing and runtime verification

Tests must use isolated headless Neovim processes and public behavior seams. They must record the supported Neovim version(s) used and must not require an optional parser for plain, custom, or unknown policy coverage.

Required coverage includes:

- omitted setup, `opts = {}`, simple-list replacement, keyed-table replacement, and empty filetype sets;
- every built-in preset and every built-in safety category;
- field-wise keyed merging over built-in mode, fallback, width, autoformat, mappings, conceal, and status settings;
- explicit plain overrides for Markdown, RST, TeX, AsciiDoc, and Textile;
- unknown filetypes with no declaration, plain declaration, and classifier declaration;
- callback context exactness: buffer handle, window handle, zero-based row, zero-based byte column, and exact filetype;
- callback invocation and non-invocation at every lifecycle point in the matrix;
- synchronous behavior, read-only contract observations, invalid returns, errors, yields where testable, and quiet fail-closed results;
- replacement of built-in classification, with no Treesitter or syntax calls for custom policy fixtures;
- plain policy with no Treesitter or syntax calls;
- custom policy in multiple buffers and windows with distinct callbacks and no cross-leakage;
- filetype changes, setup changes, explicit re-enable, disable/re-enable, and wipeout cleanup;
- M003 pending suspension consumption for prose, protected, unknown, soft mode, and filetype transitions;
- M004 structured status behavior retained by default and replaced exactly by plain/custom status behavior when configured;
- exact `formatoptions` ownership, temporary `a`, external ownership, and disable restoration for all safety outcomes;
- aggregate atomic validation with mutually exclusive declarations, misplaced classifiers, invalid returns not treated as setup errors, and unchanged prior configuration;
- quiet routine callback failure and notification behavior for explicit configuration failures.

At minimum, verify the document and repository scope with:

```sh
git diff --check -- docs/plans/005_user_defined_filetype_behavior_spec.md
git status --short -- docs/plans/005_user_defined_filetype_behavior_spec.md
```

The final scope check must show that this milestone task changed only `docs/plans/005_user_defined_filetype_behavior_spec.md`. No implementation code, implementation plan, command, mapping, or unrelated documentation is part of M005.

## 12. Non-goals

M005 does not add:

- implementation details or an implementation task breakdown;
- a new status value or statusline integration;
- a new command or mapping for classifiers or format safety;
- arbitrary syntax-group or Treesitter-node configuration;
- parser installation, a required parser, or a general-purpose markup parser;
- a callback in global setup, enable options, or any location other than `filetypes.<name>`;
- callback composition with built-in classification;
- automatic inference that an unknown filetype is plain;
- partial or live mutation of active buffers after ordinary `setup()`;
- changes to modeline parsing, wrap detection, navigation, undo mappings, conceal defaults, or unrelated options;
- Vim compatibility, legacy configuration, undocumented APIs, or legacy commands;
- new prose features such as spell checking, distraction-free mode, or formatting operators.
