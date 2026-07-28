# 003: Hard-Mode Automatic Formatting Specification

## 1. Context and authority

Milestone 003 adds automatic formatting for eligible plain prose while preserving the enable/disable, mapping, window, and exact-restoration contracts from milestones 001 and 002. This document is the contract for milestone 003. Milestone 000 is authoritative where this document is silent; the decisions below resolve the previously ambiguous points without expanding scope.

Supported Neovim versions remain 0.10 and newer. The module remains `require("pencil")`. No Vim compatibility, legacy `g:pencil#...` configuration, undocumented functions, or implementation-specific public seams are added.

The accepted defaults are:

- Hard mode starts with automatic formatting preference enabled.
- A suspension request applies to the current Insert remainder or the next eligible hard-mode Insert, does not queue, and is quiet outside hard mode.
- `formatoptions` contributes `t` and `n` in hard mode and temporarily contributes `a` during an eligible, unsuspended Insert.

## 2. Observable status

This milestone preserves the existing status contract: `S` means soft mode, while `A` and `H` refine hard mode only. No new status value is added.

| Observable state | Status |
|---|---|
| The buffer is in soft mode | `S` |
| The buffer is in hard mode, the filetype is eligible, the manual autoformat preference is enabled, Pencil still owns the complete `formatoptions` value, and there is no pending or current suspension | `A` (armed), including outside Insert mode. During an eligible Insert, Pencil currently contributes temporary `a`. |
| The buffer is in hard mode and any `A` condition is false, including disabled preference, suspension, ineligible filetype, or external `formatoptions` ownership | `H` |
| The buffer is not enabled | Existing off/untouched status value, unchanged |

The status function returns the configured display string for `S`, `A`, or `H`, and preserves the existing off/untouched value when the buffer is not enabled. If external ownership means Pencil cannot assert the effective formatting configuration, status is `H`. Status does not claim that formatting is currently running outside Insert: `A` means hard mode is eligible and armed, while the temporary `a` contribution exists only during an eligible Insert.

## 3. Eligibility

Eligibility in M003 is a whole-buffer, static filetype policy. It is reevaluated on InsertEnter and on mode/filetype changes that can affect hard-mode behavior. There is no cursor classifier, protected-region inspection, or classification-error path in this milestone.

- `text`, `gitcommit`, and `mail` are eligible plain prose.
- Markdown, reStructuredText, TeX, AsciiDoc, Textile, every other structured filetype, and unknown filetypes are wholly ineligible in M003. They use fail-closed/default-safe behavior until M004/M005 supplies the relevant policy or classifier.
- Eligibility is not inferred from cursor position, syntax, Treesitter, line contents, or an inspection result.
- An ineligible hard-mode buffer remains in hard mode but does not receive temporary `a`; it reports `H`.
- A filetype change while enabled reevaluates this policy. It must not silently alter the manual preference or pending suspension. The next Insert uses the new policy.

## 4. `formatoptions` contract and ownership

### 4.1 Hard-mode values

On the first hard-mode activation of a buffer, Pencil captures the exact complete `formatoptions` string as the activation baseline, including ordering, duplicate flags, and any `a`, `c`, or `q`. Pencil then contributes `t` and `n`, adding each only when absent. The final M003 contract explicitly supersedes the M001 provisional `tcq` contract: Pencil contributes `t+n`, not `t+c+q`.

Outside an eligible, unsuspended Insert, Pencil's owned effective value is the captured baseline with `t` and `n` present and every Pencil-owned temporary `a` removed. Thus a pre-existing baseline `a` is removed while Pencil owns the complete option; it is restored exactly on full disable. During an eligible, unsuspended Insert, Pencil adds `a` to that owned effective value. On InsertLeave, it removes only that temporary `a` contribution.

Pencil does not create, increment, renumber, or otherwise edit list markers. `n` only enables Neovim's native numbered-list behavior together with the buffer's existing `formatlistpat`.

### 4.2 Whole-value ownership

Pencil owns the complete `formatoptions` value only while the buffer's current value exactly equals the last value Pencil wrote. Any external mismatch—whether caused by the user or another plugin, during Insert or outside Insert—immediately transfers ownership for the remainder of the activation. After transfer:

- Pencil stops writing and does not reacquire `formatoptions`.
- InsertEnter, InsertLeave, mode changes, filetype changes, and disable preserve the externally current complete value.
- Pencil never overwrites an externally owned value to restore a baseline or to re-add `t`, `n`, or `a`.
- A fresh activation after full disable captures the then-current complete value as its new baseline.

Exact baseline restoration is therefore guaranteed only while Pencil still owns `formatoptions`. External ownership is never overwritten.

### 4.3 Transition table

`B` is the exact captured baseline; `H(B)` is `B` merged with `t` and `n` and with Pencil's temporary `a` removed; `I(B)` is `H(B)` plus `a`; `E` is an external value that differs from Pencil's last write.

| Transition | Current state | Required value/result |
|---|---|---|
| Hard activation | baseline `B`, including `a`, `c`, or `q` | Capture `B`; while owned write `H(B)`; preserve all baseline flags and exact baseline for later restoration. |
| Eligible InsertEnter | owned `H(B)` | Write `I(B)`; status is `A`. |
| Ineligible InsertEnter | owned `H(B)` | Keep `H(B)`; do not add `a`; status is `H`. |
| InsertLeave | owned `I(B)` | Remove only temporary `a`, returning to `H(B)`; do not modify baseline flags. |
| Manual disable or suspension in Insert | owned `I(B)` | Remove temporary `a` and preserve the manual preference/suspension semantics below; do not rewrite unrelated flags. |
| Hard → soft | owned `H(B)` or `I(B)` | Remove Pencil's hard-mode contribution only while the current value is still owned; restore `B` for the soft interval. |
| Soft → hard, same activation | still owned | Reapply `H(B)` and use the current eligibility on the next Insert; do not capture a new baseline. |
| Any external edit | Pencil's last write becomes `E` | Transfer ownership immediately; preserve `E` for all remaining transitions. |
| Full disable | still owned | Restore exact `B`, including original `a`, `c`, `q`, ordering, and duplicates. |
| Full disable | externally owned | Leave the external current value unchanged. |

The same rules apply independently per buffer. Window changes do not create a second buffer baseline.

## 5. Configuration

The exact configuration key is a boolean named `autoformat` at each established configuration layer:

```lua
require("pencil").setup({
  autoformat = true,
  filetypes = {
    text = { autoformat = false },
  },
})
```

Per-call options use the same key and precedence shape as other per-call enable options:

```lua
pencil.enable({ buf = bufnr, mode = "hard", autoformat = false })
```

Precedence is, highest first: per-call `autoformat`, filetype override, global setup `autoformat`, then the built-in default `true`. The value must be exactly a boolean when supplied. Invalid values at any layer are reported by the existing aggregate validation mechanism; validation is atomic and installs no partial configuration.

A valid setup change affects future activations only. It does not silently change an active buffer's preference, suspension, mode, or `formatoptions`. A fresh full activation captures the configured default at that time. Explicitly re-enabling an already active buffer deterministically resolves the current configured value and any supplied per-call `autoformat` value using the same precedence and enable semantics as a fresh enable, then applies that result to the selected buffer: if false, clear pending/current suspension; if true, clear suspension and arm eligible hard mode. Setup alone does not mutate an active buffer. Re-enabling must not mutate unrelated active buffers.

Filetype entries use the repository's established keyed `filetypes = { name = { ... } }` shape. `autoformat` is the only M003 addition to that per-filetype settings table; it does not make an otherwise ineligible filetype eligible.

## 6. Public actions and commands

The unambiguous Lua action API is:

```lua
pencil.set_autoformat(action, opts)
```

`action` must be exactly one of `"enable"`, `"disable"`, `"toggle"`, or `"suspend"`. `opts.buf` selects a valid target buffer and otherwise the current buffer is used. Invalid actions or invalid buffer options error without changing state. The action applies only to the selected buffer.

- `enable` sets the persistent activation preference to enabled and clears any pending/current suspension.
- `disable` sets the preference to disabled and removes temporary `a` if owned.
- `toggle` flips the persistent preference; toggling to enabled also clears suspension.
- `suspend` does not change the persistent preference and follows the suspension rules in §7.

`enable`, `disable`, and `toggle` are accepted only in hard mode with the preference operation applicable to that hard-mode activation. Outside hard mode, `enable` and `toggle` are rejected with the established warning/no-change behavior; `disable` is a quiet no-op. `suspend` is a quiet no-op outside hard mode. No action enables formatting in soft mode.

The unified commands map directly to this API for the current buffer:

```vim
:Pencil format enable
:Pencil format disable
:Pencil format toggle
:Pencil format suspend
```

Invalid grammar is rejected without changing state. Aliases are exact:

- `:PFormat` → `enable`
- `:PFormatOff` → `disable`
- `:PFormatToggle` → `toggle`

The aliases do not mean toggle unless their names say toggle.

## 7. Suspension

Suspension is accepted only in hard mode with the manual preference enabled. Outside hard mode it is a quiet no-op and does not queue a later request.

- During Insert, it applies to the remainder of the current Insert. If `a` is currently owned and present, Pencil removes only that temporary contribution.
- Outside Insert, it applies to the next eligible hard-mode Insert.
- A pending suspension is consumed only by that next eligible hard-mode Insert, including an Insert with no typing. An ineligible hard-mode Insert and any soft-mode Insert do not consume it; a later filetype change can make a subsequent hard-mode Insert eligible.
- It does not queue: repeated requests still produce at most one applicable suspension.
- It survives a temporary hard → soft → hard transition when no Insert occurs between the transitions.
- A soft-mode Insert never consumes it.
- Manual `disable` and full Pencil disable clear it.
- `enable` clears it, as does `toggle` when it changes the preference to enabled.
- It is per activation and per buffer; it cannot leak across buffers, windows, fresh activations, or wipeout cleanup.

A suspended hard-mode buffer reports `H`, while an armed eligible buffer outside Insert reports `A`.

## 8. Numbered-list promise

M003 promises only the native behavior enabled by `formatoptions+=n` and the buffer's existing `formatlistpat`. Pencil does not generate markers, increment numbers, renumber lists, or repair malformed markers.

For example, with `formatoptions` containing `n`, a suitable existing `formatlistpat`, and a hard width that wraps the item, this input:

```text
1. This numbered item contains enough prose that its continuation wraps
   onto another display line.
```

continues through Neovim's native formatting behavior with the existing `1.` marker unchanged. The exact continuation indentation and wrapping remain Neovim's behavior; M003 promises no behavior beyond what `n` and the existing `formatlistpat` provide.

## 9. Behavioral acceptance cases

The implementation is accepted only if headless tests observe all of the following through public commands, API, options, mappings, mode, and status:

1. **Commands/API/config:** validate every action and invalid action; verify command-to-action mapping and all three aliases; verify global, filetype, and per-call `autoformat` precedence; verify atomic invalid setup; verify setup changes do not alter active buffers; verify fresh activation uses the configured default; verify explicit re-enable of an active buffer resolves current config/per-call `autoformat` deterministically, clears suspension for false and clears suspension plus arms eligible hard mode for true, without mutating unrelated buffers.
2. **Status:** verify the preserved S/A/H truth table: `S` in soft mode; in hard mode, `A` only with an eligible filetype, enabled preference, Pencil ownership, and no pending/current suspension; `H` for every other hard-mode state, including external ownership. Verify off/untouched status remains unchanged when not enabled.
3. **Every transition:** verify hard activation, eligible and ineligible InsertEnter, InsertLeave, repeated Inserts, manual actions, hard→soft→hard, full disable, fresh enable, disable during Insert, and cleanup during active/suspended Insert.
4. **Pre-existing flags:** verify empty, unusual ordering, duplicates, and baselines containing `a`, `c`, `q`, `t`, `n`, and unrelated flags; verify exact baseline restoration while owned.
5. **External ownership:** edit `formatoptions` during Insert and outside Insert, then verify no reassertion, no reacquisition, and preservation on leave, mode change, and disable.
6. **Filetypes:** verify `text`, `gitcommit`, and `mail` are eligible; structured and unknown filetypes are wholly ineligible; filetype changes reevaluate eligibility without changing preference or queuing suspension.
7. **Suspension:** verify current-Insert remainder, next eligible hard-mode Insert behavior, repeated requests not queuing, no-typing eligible Insert consumption, ineligible hard-mode and soft-mode Inserts not consuming, later eligibility consuming the pending suspension, hard→soft→hard survival without an Insert, enable/disable clearing, and buffer isolation.
8. **Lists:** verify native `n`/`formatlistpat` continuation with an unchanged marker and verify Pencil does not invent or renumber markers.
9. **Multi-buffer/window cleanup:** verify independent preferences, baselines, suspension, and ownership for multiple buffers and windows; verify buffer switches, window closes, buffer wipeout, and full disable leave no temporary `a`, stale state, or leaked presentation/mapping behavior.

## 10. Out of scope

- Cursor or syntax classification, Treesitter, legacy syntax fallback, protected-region detection, and classification errors.
- Automatic formatting for structured or unknown filetypes; custom classifiers and explicit later plain-text declarations.
- Marker generation, incrementing, renumbering, or custom list formatting beyond native `n` and `formatlistpat` behavior.
- New formatting operators, spell checking, statusline installation, default suspension mappings, Vim support, legacy configuration, release documentation, and unrelated changes to wrapping, modelines, conceal, colorcolumn, navigation, undo mappings, or presentation behavior.
