# 006: Release Readiness Specification

## 1. Context and authority

Milestone 006 makes `pencil.nvim` understandable, installable, testable, and safe to evaluate as a v0.1.0 Neovim plugin. The verified repository is [`jrswab/pencil.nvim`](https://github.com/jrswab/pencil.nvim). It documents the behavior delivered by milestones 001–005 and verifies the public workflow without adding release automation.

Milestone 000 is authoritative where this document is silent. Milestones 001–005 remain authoritative for behavior, precedence, lifecycle, classification, mappings, formatting, restoration, and configuration validation. This document defines the documentation, attribution, compatibility, CI, test-deliverable, and release-readiness contract; it does not redefine runtime behavior.

The repository contains the Lua module under `lua/pencil/`, the runtime command loader at `plugin/pencil.lua`, and isolated headless tests under `tests/`. The public implementation exposes `require("pencil")`, the functions in §4, the unified `:Pencil` command and aliases in §5, and the internal `pencil._test` module used by existing tests; only the first two categories are user-facing.

The product is a clean Neovim-native redesign inspired by `preservim/vim-pencil`, not a Vimscript compatibility port. Neovim 0.10 is the minimum supported version. There are no required runtime dependencies. M006 targets v0.1 readiness only: it does not create a tag, publish a release, add a changelog, or add a release workflow.

The documentation boundary is fixed: add a concise `README.md` and complete native help in `doc/pencil.txt`. The README links to native help; the help file is usable through `:help pencil` when the repository is on `runtimepath`.

## 2. Scope and non-goals

### In scope

- A README covering installation, supported versions, setup semantics, public Lua controls, commands, statusline use, safety behavior, and migration intent.
- Native help documenting the complete user-facing configuration and API contract.
- Exact documentation of the Lazy.nvim distinction between a bare plugin declaration and `opts = {}`.
- Concise migration guidance from the original Vimscript plugin without claiming compatibility that does not exist.
- Verified upstream attribution and license notices.
- GitHub Actions testing on Neovim 0.10 and current stable.
- Focused M006 test additions and repository test-runner scripts needed to exercise the release-readiness contract. These are M006 deliverables, not a contradiction of the test scope.
- A narrow runtime correction exception: M006 may modify runtime code solely to restore already-normative M001–M005/public contracts exposed by release verification, with regression tests. Examples are empty list filetype rejection, unsupported per-call option validation according to established schemas, and `format` command completion; this exception permits no new features.
- Exact acceptance checks for documentation, loading, commands, lifecycle safety, and the full behavior matrix in §9.

### Non-goals

M006 does not:

- add or change runtime features, behavior, commands, mappings, defaults, classifiers, formatting, or restoration, except for the narrow runtime correction exception stated in scope: restoring already-normative M001–M005/public contracts exposed by release verification, with regression tests (including empty list filetype rejection, unsupported per-call option validation according to established schemas, or `format` command completion);
- add Vim support or compatibility for `g:pencil#...`, `Mapkey()`, `:DropPencil`, or other legacy interfaces excluded by M000;
- add a `CHANGELOG`, tag, GitHub Release, package publication, release workflow, or version-bumping mechanism;
- promise API stability beyond the documented v0.1.0 surface;
- add spell-checking, distraction-free presentation, or unrelated writing features;
- require nvim-treesitter, a parser, a syntax plugin, or another runtime dependency.

A focused test or runner addition may expose an existing behavior through public calls. The only runtime implementation changes allowed are the narrow corrections stated in scope: restoring already-normative M001–M005/public contracts exposed by release verification, with regression tests; examples include empty list filetype rejection, unsupported per-call option validation according to established schemas, and `format` command completion. This exception does not permit features.

## 3. Documentation contract

### 3.1 README responsibilities

`README.md` is the short entry point. It must contain, in a discoverable order:

1. The project name, accurate writing-oriented description, verified repository URL, Neovim 0.10+ requirement, Vim unsupported statement, and no-required-runtime-dependencies statement.
2. A minimal installation example using `jrswab/pencil.nvim`.
3. Both valid Lazy.nvim forms:

   ```lua
   { "jrswab/pencil.nvim" }
   { "jrswab/pencil.nvim", opts = {} }
   ```

   It must state that the first loads built-in defaults for direct commands/Lua calls but does not start automatic filetype activation, while `opts = {}` calls `setup({})` and enables the built-in prose filetype set on `FileType`.
4. A compact setup example and a link to `:help pencil-configuration`.
5. The built-in filetypes and modes/fallbacks/widths, or an explicit pointer to the exhaustive help table.
6. Quick-start examples for `require("pencil")`, `:Pencil`, and statusline integration.
7. Exact restoration, conflict-safe mappings, fail-closed formatting, per-window presentation, quiet notifications, and no automatic statusline mutation.
8. Concise migration guidance under a named heading.
9. `LICENSE` and verified inspiration links/notices.

It must not imply that the two Lazy.nvim forms have identical activation behavior or document an option absent from the native-help/API contract.

### 3.2 Native help responsibilities and tags

`doc/pencil.txt` is normative and must use standard Vim help formatting. It must contain these exact stable tags, with these meanings:

- `*pencil*` — top-level overview;
- `*pencil-installation*` — requirements and installation;
- `*pencil-configuration*` — setup, precedence, filetypes, and complete schemas;
- `*pencil-api*` — public Lua functions and return meanings;
- `*pencil-commands*` — commands, aliases, completion, and format actions;
- `*pencil-status*` — status semantics and statusline examples;
- `*pencil-migration*` — migration and compatibility boundary.

It must cross-reference sections covering installation, setup precedence, Lazy.nvim activation, presets and filetype replacement/merge rules, modelines and width precedence, ownership/restoration, multi-window lifecycle, mappings and conflict policy, hard-mode formatting and protected-region safety, conceal/presentation, every public function in §4, every command and alias in §5, status indicators, notifications, migration, supported versions, testing expectations, license, and attribution. Examples must parse as Lua or Vim commands. It must not expose private implementation functions or `pencil._test` as public API.

The committed/generated help index is an M006 deliverable. Generate it exactly with:

```sh
nvim --headless --clean -u NONE +'lua local ok, err = pcall(vim.cmd, "helptags doc"); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") else assert(ok) end' +qa
```

The validation contract is that `doc/tags` exists, is committed, and contains all seven exact tags. Validate it exactly with:

```sh
set -euo pipefail
test -f doc/tags
for tag in pencil pencil-installation pencil-configuration pencil-api pencil-commands pencil-status pencil-migration; do
  grep -E "^${tag}[[:space:]]" doc/tags >/dev/null || exit 1
done
nvim --headless --clean -u NONE +'set rtp^=.' +'lua local ok, err = pcall(vim.cmd, "help pencil"); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") else assert(ok) end' +qa
```

### 3.3 Terminology

Use these terms consistently:

- **enabled buffer**: a buffer with an active Pencil mode and owned behavior;
- **disabled buffer**: a buffer explicitly or previously disabled, with Pencil behavior removed;
- **hard mode**: native hard wrapping using `textwidth` and formatting options;
- **soft mode**: displayed-line wrapping and writing navigation without changing `colorcolumn`;
- **detect mode**: mode selected by modeline and bounded content sampling;
- **protected**: structured content where automatic formatting is suspended;
- **prose**: content eligible for automatic formatting when all other hard-mode conditions hold;
- **unknown**: safety not established; formatting fails closed;
- **Pencil-owned**: a setting or mapping Pencil installed and can still identify as unchanged by Pencil;
- **exact restoration**: restoration of the value captured before Pencil acquired ownership, subject to preserving later external user edits.

Documentation must distinguish buffer-local settings from window-local presentation settings and must not call the original project a supported compatibility target.

## 4. Exact public Lua surface and schemas

The only public Lua functions are:

```lua
local pencil = require("pencil")

pencil.setup(config)
pencil.enable(opts)
pencil.disable(opts)
pencil.toggle(opts)
pencil.set_autoformat(action, opts)
pencil.mode(opts)
pencil.status(opts)
```

When an `opts` argument is supplied it must be a table. For all functions below, omitted `opts` targets the current buffer. The functions return no documented value except `mode()` and `status()`.

### 4.1 Complete setup schema

`setup(config)` requires a table. Its complete top-level schema is:

```lua
{
  mode = "hard" | "soft" | "detect",
  fallback = "hard" | "soft",
  textwidth = integer >= 1,
  autoformat = boolean,
  conceal = false | {
    level = integer 0..3,
    cursor = string of unique characters from "n", "v", "i", "c",
  },
  mappings = {
    navigation = boolean,
    undo_breaks = boolean,
  },
  status = {
    hard = string,
    auto = string,
    soft = string,
    off = string,
  },
  filetypes = string list | {
    [filetype] = {
      mode = "hard" | "soft" | "detect",
      fallback = "hard" | "soft",
      textwidth = integer >= 1,
      autoformat = boolean,
      conceal = false | { level = integer 0..3, cursor = unique "n"/"v"/"i"/"c" string },
      mappings = { navigation = boolean, undo_breaks = boolean },
      format_safety = "plain",
      classifier = function,
    },
  },
}
```

Every key shown is legal; unknown keys are invalid. `filetypes` may be omitted, an array-like list of nonempty strings with no duplicates, or a keyed table of nonempty filetype names to the shown entry schema. A list and keyed entries may not be mixed. `format_safety` and `classifier` are legal only under `filetypes.<name>` and are mutually exclusive. `format_safety` accepts only the exact string `"plain"`; `classifier` accepts only a function with the exact interface `classifier(ctx)`. It receives one context table containing integer `buf`, integer `win`, zero-based integer `row`, zero-based byte-column integer `col`, and string `filetype`; it returns exactly `"prose"`, `"protected"`, or `"unknown"`. Errors and invalid returns fail closed to `"unknown"` quietly.

The defaults are `mode = "detect"`, `fallback = "soft"`, `textwidth = 80`, `autoformat = true`, `conceal = { level = 2, cursor = "" }`, `mappings = { navigation = true, undo_breaks = true }`, and `status = { hard = "H", auto = "A", soft = "S", off = "" }`.

`setup(config)` validates the complete configuration atomically, installs it for future activations, and returns nil. Invalid configuration raises one aggregate Lua error and leaves the prior valid configuration and active buffers unchanged. A later valid setup affects future activation only; active buffers remain unchanged until explicit disable or re-enable.

### 4.2 Complete per-call schemas

`enable(opts)` accepts exactly these keys: `buf`, `mode`, `textwidth`, `autoformat`, `conceal`, and `mappings`. `buf` is an integer buffer handle; `mode` is `"hard"`, `"soft"`, or `"detect"`; `textwidth` is an integer >= 1; `autoformat` is boolean; `conceal` is `false` or the complete `{ level = integer 0..3, cursor = unique "n"/"v"/"i"/"c" string }` table; and `mappings` is `{ navigation = boolean, undo_breaks = boolean }`. It returns nil. A direct enable may request hard, soft, or detect.

`disable(opts)` and `toggle(opts)` accept exactly `{ buf = integer buffer handle }` when supplied and return nil. `disable()` removes Pencil behavior and restores exact owned state without removing conflicting or externally changed mappings/options. `toggle()` disables an enabled buffer or enables a disabled buffer with fresh detection.

`set_autoformat(action, opts)` accepts exactly the action `"enable"`, `"disable"`, `"toggle"`, or `"suspend"`; its optional table is exactly `{ buf = integer buffer handle }`. It returns nil. Hard-mode eligibility and next-Insert suspension semantics are normative. Enabling or toggling outside hard mode is unsuccessful, follows the quiet warning policy, and does not change state.

`mode(opts)` accepts `{ buf = integer buffer handle }` or omitted opts and returns `"hard"`, `"soft"`, `"off"`, or nil for untouched state. `status(opts)` accepts the same opts and returns the configured indicator string.

Status semantics are exact: `S` means enabled soft mode; `A` means hard mode is armed, eligible, and Pencil-owned, and it can appear outside Insert mode; `H` means hard mode is disabled from automatic formatting, suspended, protected, unknown, or externally unowned, as applicable; `off` is returned for disabled state. `A` is not restricted to Insert mode, and `H` does not mean only “currently in hard mode.”

### 4.3 Presets, precedence, and safety

The built-in presets are:

| Filetype | Mode | Fallback | Width | Safety |
|---|---|---|---:|---|
| `gitcommit` | hard | — | 72 | plain |
| `mail` | hard | — | 72 | plain |
| `markdown` | detect | soft | — | structured |
| `text` | detect | soft | — | plain |
| `rst` | detect | hard | 79 | structured |
| `tex` | detect | hard | 79 | structured |
| `asciidoc` | detect | hard | 79 | structured |
| `textile` | detect | soft | — | structured |

Omitted `filetypes` activates all built-ins after successful setup. A simple list replaces that automatic set; recognized names retain presets and unknown names use global detect/fallback settings but remain fail-closed. A keyed table replaces the automatic set and merges fields over the recognized preset, then global setup values, then built-in defaults. `filetypes = {}` disables automatic activation while retaining direct controls. Per-call options take precedence where legal. `format_safety` and `classifier` have no global or per-call placement.

Detect mode first honors a valid `textwidth` modeline: positive width selects hard, zero selects soft. Otherwise it samples nonblank content, returns soft immediately for a display width over 130, and after 20 nonblank lines uses the configured fallback. For hard mode, width precedence is per-call `textwidth`, positive modeline width, existing buffer `textwidth` when positive, then effective configured `textwidth`.

`format_safety = "plain"` marks the complete filetype as prose. A classifier has the exact interface `classifier(ctx)`: it receives one context table containing integer `buf`, integer `win`, zero-based integer `row`, zero-based byte-column integer `col`, and string `filetype`, and returns exactly `"prose"`, `"protected"`, or `"unknown"`. Structured classification prefers an existing current Treesitter tree and may fall back to active legacy syntax; missing, stale, ambiguous, malformed, or failing classification is unknown and never formatted automatically.

## 5. Exact command surface

The primary command and legal actions are:

```vim
:Pencil
:Pencil enable
:Pencil disable
:Pencil toggle
:Pencil hard
:Pencil soft
:Pencil detect
:Pencil format enable
:Pencil format disable
:Pencil format toggle
:Pencil format suspend
```

Bare `:Pencil` enables the current buffer using detection. Completion returns the seven top-level actions and the four format actions after `format`. Invalid or extra arguments produce a clear error.

| Alias | Exact meaning |
|---|---|
| `:HardPencil` | `:Pencil hard` |
| `:SoftPencil` | `:Pencil soft` |
| `:NoPencil`, `:PencilOff` | `:Pencil disable` |
| `:TogglePencil`, `:PencilToggle` | `:Pencil toggle` |
| `:PFormat` | `:Pencil format enable` |
| `:PFormatOff` | `:Pencil format disable` |
| `:PFormatToggle` | `:Pencil format toggle` |

Commands and direct Lua controls work with built-in defaults before `setup()`; automatic `FileType` activation starts only after successful setup. No excluded legacy command is supported.

## 6. Safety, lifecycle, and presentation guarantees

Pencil restores exact prior buffer and window-local values when it still owns them and preserves user changes made while active. Window-local wrapping and presentation are applied independently to every window displaying an enabled buffer, including windows opened after activation; cleanup does not leak into another buffer. Pencil changes only settings needed for wrapping, formatting, configured concealment, presentation, and its own mappings. It does not change unrelated settings such as `iskeyword`, `list`, `backspace`, indentation behavior, global display settings, or `colorcolumn`.

Mapping conflicts are skipped, warned once per key per buffer, and never replaced or removed by Pencil. Repeated enable/disable cycles do not remove mappings Pencil does not still own. Hard mode preserves the original `formatoptions` baseline, adds only required flags, adds temporary continuous formatting only during an eligible safe Insert, and fails closed in protected or unknown structured regions.

Conceal defaults to level 2 with markup visible on the cursor line (`cursor = ""`); `conceal = false` opts out. Soft mode leaves `colorcolumn` unchanged. Normal activation, detection, and routine suspension are quiet. Notifications are reserved for invalid configuration/commands, explicit operational failures, mapping conflicts, and attempts to enable autoformat outside hard mode. Pencil never modifies the statusline automatically; `status()` is intended for lualine or a custom statusline.

## 7. Migration and attribution

Migration must be concise and state that this is a clean Neovim redesign inspired by [`preservim/vim-pencil`](https://github.com/preservim/vim-pencil), not a drop-in Vim/Vimscript port. Use `require("pencil").setup({...})` rather than `g:pencil#...`; use the documented Lua API and unified `:Pencil` commands rather than `Mapkey()`, legacy `:DropPencil`, or unsupported compatibility commands; use Lua filetype policies/classifiers; expect exact ownership/restoration and conflict-safe mappings; use `pencil.status()` for statusline integration; and use Neovim 0.10+ because Vim is unsupported. Do not claim that every old option, command, mapping, formatting quirk, or syntax group has an equivalent.

Documentation must preserve and name the repository's MIT `LICENSE`, including its existing `Copyright (c) 2026 Jaron Swab` notice. It must identify the upstream inspiration and verified URL without implying endorsement. It must not invent upstream quotations, authorship, dates, or additional license terms.

## 8. CI and M006 test deliverables

GitHub Actions must run isolated headless tests on exactly Neovim 0.10 and the current stable Neovim selected by the CI configuration. The stable job must not silently use an unsupported development build. Each clean checkout puts the repository on `runtimepath`, loads `require("pencil")`, generates/validates help tags, and runs the smoke and M005 suites. Parser-dependent cases may be explicitly skipped when unavailable, but the reason must be printed and every non-parser safety/fallback case must run.

M006 may add focused tests and runner scripts. The required deliverables are the minimum-version error coverage, the full matrix in §9, and a deterministic runner that executes the isolated suite without adding a required third-party test plugin. These additions must test existing implementation behavior. The narrow runtime correction exception permits runtime changes solely to restore already-normative M001–M005/public contracts exposed by release verification, with regression tests; examples are empty list filetype rejection, unsupported per-call option validation according to established schemas, and `format` command completion. It permits no features.

The workflow must fail on syntax errors, failed tests, failed help/tag checks included in the runner, or `git diff --check` failures. It must record exact Neovim versions used.

## 9. Required complete test matrix

Focused tests and the runner must cover, through public behavior where applicable:

- module loading and the exact Neovim <0.10 error;
- bare installation versus `opts = {}` setup behavior;
- every built-in preset, list replacement, keyed replacement, field-wise merge, and `filetypes = {}`;
- every setup field, nested status/conceal/mappings schema, legal values, unknown-key rejection, and aggregate atomic validation;
- every per-call schema, buffer targeting, precedence, modelines, disabled modelines, 20-line sampling threshold, and width precedence;
- all Lua functions, nil/indicator return meanings, command actions, aliases, completion, mode, and status output;
- A/H semantics: A armed/eligible/owned outside Insert, H for disabled/suspended/protected/unknown/external unowned as applicable;
- navigation and undo-break mapping groups, conflicts including `<CR>`, and repeated lifecycle cycles;
- plain hard-mode formatting, Treesitter/syntax classification, custom `classifier(ctx)` callbacks with one context table containing integer `buf`, integer `win`, zero-based integer `row`, zero-based byte-column integer `col`, and string `filetype`, exact results, invalid classifier results/errors, and fail-closed behavior;
- exact option/formatoptions restoration, external edits, multiple buffers, multiple windows, late windows, filetype transitions, wipeout, and cleanup;
- conceal defaults/opt-out, statusline non-interference, notification quietness, and absence of unrelated option changes;
- README/help agreement, all seven help tags, `:help pencil`, and generated `doc/tags`.

## 10. Acceptance criteria and exact validation

M006 is accepted only when `README.md`, `doc/pencil.txt`, committed `doc/tags`, the CI workflow, and focused test/runner additions satisfy §§3, 8, and 9; README and help agree on all schemas, defaults, presets, commands, status meanings, setup boundaries, and compatibility statements; safety, migration, license, and attribution claims are verified; and any runtime change is limited to the narrow runtime correction exception: restoring already-normative M001–M005/public contracts exposed by release verification, with regression tests, without adding features.

The exact local validation commands are:

```sh
set -euo pipefail
nvim --headless --clean -u NONE +'set rtp^=.' +'lua local ok, err = pcall(require, "pencil"); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") else assert(ok) end' +qa
nvim --headless --clean -u NONE +'set rtp^=.' +'lua local ok, err = pcall(vim.cmd, "help pencil"); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") else assert(ok) end' +qa
nvim --headless --clean -u NONE -c 'helptags doc' -c 'qa'
test -f doc/tags
for tag in pencil pencil-installation pencil-configuration pencil-api pencil-commands pencil-status pencil-migration; do
  grep -E "^${tag}[[:space:]]" doc/tags >/dev/null || exit 1
done
nvim --version
git diff --check
git status --short
```

The CI runner must execute the full §9 matrix on the exact 0.10 and current-stable binaries and print each binary's `nvim --version`. If a matrix binary is unavailable locally, report it as unavailable rather than substituting another version.

## 11. Deliverables and boundaries

- `README.md` — concise entry point and installation/migration guide.
- `doc/pencil.txt` — complete native help reference.
- `doc/tags` — generated, committed native-help index.
- GitHub Actions workflow(s) — exactly Neovim 0.10 and current stable.
- Focused M006 tests and deterministic test-runner scripts covering the minimum-version error and full §9 matrix.
- Validation output demonstrating the checks above. If release verification exposes a runtime defect, the final diff may also include the narrow correction exception: runtime changes solely restoring already-normative M001–M005/public contracts, with regression tests, and no features.

README plus `doc/pencil.txt`, CI for Neovim 0.10 and stable, concise migration, and v0.1 readiness are the recommended boundaries. No tag, publish action, changelog, or release workflow is introduced. The final repository diff may include only these M006 deliverables plus runtime corrections allowed by the narrow exception (with regression tests); it may not include features. This specification-writing task itself modifies only `docs/plans/006_release_readiness_spec.md`.
