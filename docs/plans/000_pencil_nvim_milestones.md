# Pencil.nvim Milestones

## 1. Research Findings

### Project goal

Create a new, Neovim-native Lua plugin named `pencil.nvim`, inspired by [`preservim/vim-pencil`](https://github.com/preservim/vim-pencil). The new plugin is a clean redesign rather than a line-for-line port. It should retain the useful writing workflow while fixing the original plugin's state-management, mapping, and modern-Neovim integration problems.

The implementation will live in a new repository. This document records exploration and decisions only; it does not implement the plugin.

The intended Lazy.nvim installation experience is:

```lua
return {
  "<owner>/pencil.nvim",
  opts = {},
}
```

The Lua module name will remain `pencil`:

```lua
require("pencil")
```

### Source repository findings

The source material is `preservim/vim-pencil`, whose stated purpose is “Rethinking Vim as a tool for writers.” At the time of exploration, the implementation was concentrated in two Vimscript files:

- `plugin/pencil.vim` — 213 lines
  - Defines defaults through `g:pencil#...` variables.
  - Defines user commands and aliases.
  - Defines the global `PencilMode()` statusline helper.
- `autoload/pencil.vim` — 542 lines
  - Implements initialization and wrap-mode selection.
  - Detects modelines and samples lines.
  - Changes options and installs mappings.
  - Controls Insert-mode autoformat.
  - Uses syntax groups to avoid formatting structured regions.
- `README.markdown` documents installation, configuration, and behavior.
- `doc/vim-pencil.txt` provides Vim help.
- `LICENSE` is MIT. The new project must preserve the required copyright and license attribution for any derived material.
- No automated test suite was found.

The source repository's latest implementation commits found during exploration were from April 2023. Its open issues include reports involving mapping teardown, repeated enable/disable cycles, `<CR>` conflicts, unexpected `colorcolumn` and `iskeyword` changes, incomplete setting restoration, list formatting, and autoformat behavior.

### Original behavior inventory

The original plugin provides:

1. Per-buffer hard wrap, soft wrap, disabled, toggle, and detected modes.
2. Wrap detection from a `textwidth` modeline, followed by initial-line sampling.
3. Hard mode using Neovim/Vim `textwidth` and `formatoptions`.
4. Soft mode using displayed-line wrapping.
5. Display-line navigation mappings for prose editing.
6. Separate physical-line movement through the corresponding `g` commands.
7. Insert-mode undo breaks after common punctuation, deletion commands, and optionally `<CR>`.
8. Automatic formatting during Insert mode in hard mode.
9. Suspension of automatic formatting in code blocks, tables, front matter, math, and similar structured regions.
10. Syntax-group blacklists and whitelists for protected-region detection.
11. A manually requested suspension of autoformat for the next Insert.
12. Conceal settings for markup-oriented formats.
13. A statusline indicator for hard, autoformat-active, soft, and off states.
14. Commands including `:Pencil`, `:HardPencil`, `:SoftPencil`, `:PencilOff`, `:PencilToggle`, and `:PFormatToggle`, with several aliases.

### Problems in the original design

The redesign must not blindly reproduce the following behavior:

- Disabling generally resets options to inherited values rather than restoring the exact values present before Pencil was enabled.
- Mapping teardown can remove mappings by key without proving Pencil still owns them.
- Repeated soft/off/soft transitions have an open issue reporting broken navigation mappings.
- The `<CR>` mapping can conflict with completion and Insert-mode plugins.
- Global or global-local settings can leak into unrelated buffers.
- Window-local presentation settings are treated as though they belong only to a buffer.
- Multiple Pencil buffers can interfere through `virtualedit` and buffer-enter/buffer-leave behavior.
- The original changes unrelated or surprising settings such as `iskeyword`, `list`, `backspace`, indentation options, global display behavior, and `colorcolumn`.
- The original mapping-resolution helper parses command output and is fragile.
- Syntax-stack protected-region detection is tied to legacy Vim syntax highlighting.

### Modern Neovim constraint

The explored Neovim configuration uses Treesitter with legacy regex highlighting disabled:

```lua
additional_vim_regex_highlighting = false
```

The original plugin relies on `synstack()`. A direct port could therefore fail to recognize Markdown code fences and other protected regions. The redesign must support Treesitter-based classification and may use legacy syntax information as a fallback.

### Product and compatibility decisions

#### Clean redesign

- This is a clean Neovim redesign, not a compatibility-first port.
- Preserve the core writing workflow and familiar commands where useful.
- Fix state ownership, restoration, and lifecycle errors rather than preserving quirks.
- Do not support Vim.
- Do not support old `g:pencil#...` configuration variables.
- Do not preserve the undocumented `Mapkey()` function.
- Do not retain the old opt-in legacy commands such as `:DropPencil`.
- Do not add unrelated prose features such as spell-check, distraction-free mode, or new formatting operators.

#### Platform

- Minimum supported version: Neovim 0.10.
- No required runtime dependencies.
- The plugin must raise a clear error on unsupported Neovim versions.

#### Setup and Lazy.nvim behavior

- `require("pencil").setup(opts)` is the configuration entry point.
- `setup()` is optional.
- Commands and direct Lua functions work with built-in defaults without calling `setup()`.
- Automatic filetype activation begins only after `setup()` runs.
- Therefore both of these Lazy.nvim forms are valid:

```lua
{ "<owner>/pencil.nvim" }
```

```lua
{ "<owner>/pencil.nvim", opts = {} }
```

- `opts = {}` automatically enables Pencil for built-in prose filetypes.
- An explicit `filetypes` value replaces the built-in auto-enable set; it does not extend it.
- `filetypes = {}` disables automatic activation while leaving commands and Lua functions available.
- Repeated valid `setup()` calls replace configuration only for future activations. Existing enabled buffers remain unchanged until disabled or explicitly re-enabled.
- Configuration validation is atomic. If any value is invalid, `setup()` raises one Lua error containing every validation problem, installs no partial configuration, and keeps the previous valid configuration unchanged.

### Built-in filetype presets

The accepted built-in auto-enable set and presets are:

| Filetype | Mode | Fallback | Width | Formatting safety |
|---|---|---:|---:|---|
| `gitcommit` | hard | — | 72 | Plain text |
| `mail` | hard | — | 72 | Plain text |
| `markdown` | detect | soft | — | Structured classifier |
| `text` | detect | soft | — | Plain text |
| `rst` | detect | hard | 79 | Structured classifier |
| `tex` | detect | hard | 79 | Structured classifier |
| `asciidoc` | detect | hard | 79 | Structured classifier |
| `textile` | detect | soft | — | Structured classifier |

Further rules:

- A simple explicit list retains built-in presets for recognized names:

```lua
filetypes = { "markdown", "gitcommit" }
```

- Unknown names in a simple list use the global detect/fallback settings.
- A keyed filetype entry merges over that filetype's built-in preset:

```lua
filetypes = {
  gitcommit = { textwidth = 68 },
  markdown = { fallback = "hard", textwidth = 80 },
}
```

- In the example above, `gitcommit` remains hard mode while only its width changes.

### Wrap detection

Detection is intentionally predictable and independent of Treesitter:

1. Read supported modeline forms first.
2. A positive modeline `textwidth` selects hard mode.
3. A modeline `textwidth=0` selects soft mode.
4. When no relevant modeline exists, inspect the first 20 non-blank lines.
5. If any sampled line exceeds 130 display columns, select soft mode.
6. Otherwise use the active filetype preset's fallback.
7. Structured regions are not excluded from sampling.
8. Pencil may read `textwidth` from a modeline even when Neovim modeline execution is disabled.
9. Pencil reads only `textwidth`; it never executes other modeline settings.

For hard mode, `textwidth` precedence is:

1. A value passed directly to `enable()`.
2. A positive value read from a modeline.
3. The buffer's existing nonzero `textwidth`.
4. The active filetype preset.
5. The global default.

Manual mode changes last only until Pencil is disabled. Re-enabling a disabled buffer performs fresh detection using current contents and the latest valid configuration. Disabled buffers retain no stale mode snapshot.

### State ownership and restoration

- Pencil must restore the exact prior editor state when disabled, rather than resetting options to inherited defaults.
- Pencil must change only settings directly needed for wrapping, formatting, configured concealment, and its mappings.
- Pencil must not change unrelated settings including `iskeyword`, `list`, `backspace`, indentation behavior, global display options, or `colorcolumn`.
- Buffer mode and buffer-local mappings belong to the buffer.
- Window-local wrap and presentation settings must be applied to every window displaying an enabled buffer.
- Each window's previous settings must be captured and restored independently.
- A newly opened window displaying an already-enabled buffer must receive the active presentation behavior.
- Closing a buffer or window must not leak state or leave stale behavior.
- Disabling must remove only mappings and behavior still owned by Pencil.

### Mapping behavior

Two mapping groups are independently configurable and enabled by default:

```lua
mappings = {
  navigation = true,
  undo_breaks = true,
}
```

Navigation behavior covers:

- `j` and `k`.
- Up and Down arrow keys.
- `0` and `$`.
- Home and End.
- The corresponding `gj`, `gk`, `g0`, and `g$` commands remain available for physical-line movement while the simpler keys use visual-line movement.

Undo-break behavior covers:

- `.`, `!`, `?`, `,`, `;`, and `:`.
- `<C-U>` and `<C-W>`.
- `<CR>` when it has no mapping conflict.

Conflict policy:

- If a default Pencil mapping conflicts with an existing buffer-local or global mapping, Pencil skips that mapping.
- It warns once per key per buffer.
- It does not replace or remove the conflicting mapping.
- `<CR>` follows the same policy rather than receiving special override behavior.

### Hard-mode formatting behavior

- Hard mode enables automatic formatting during Insert mode by default.
- Plain-text presets (`text`, `mail`, and `gitcommit`) may autoformat without a parser.
- Structured presets suspend autoformat in protected regions such as code blocks, tables, front matter, directives, and math.
- Built-in protected-region support in the first release covers Markdown, reStructuredText, TeX, AsciiDoc, and Textile.
- Protected-region detection prefers Treesitter when available and uses legacy syntax information as a fallback.
- Detection fails closed: if Pencil cannot classify the cursor location or encounters an inspection error, autoformat remains suspended for that Insert.
- Routine suspension is silent.
- Unknown/custom filetypes also fail closed in hard mode unless explicitly marked as plain text or supplied with a classifier.
- No default mapping is installed for suspending autoformat during the next Insert.
- Users can use `:Pencil format suspend` or map the corresponding Lua function themselves.
- Hard mode preserves the existing `formatoptions`, changes only flags needed for automatic text wrapping and numbered-list handling, temporarily enables continuous formatting during a safe Insert, and restores the exact original value when disabled.

### Custom classifiers

Users may provide a classifier for a custom structured filetype. It returns one of three results:

```lua
classifier = function(ctx)
  return "prose"      -- autoformat may run
  -- or "protected"   -- autoformat remains suspended
  -- or "unknown"     -- autoformat remains suspended
end
```

The classifier receives read-only context:

```lua
{
  buf = 3,
  win = 7,
  row = 12,       -- zero-based
  col = 18,       -- zero-based byte index
  filetype = "mymarkup",
}
```

Rules:

- A classifier runs synchronously when Insert mode begins and must return immediately.
- It should not modify editor state.
- Errors and invalid return values are treated as `"unknown"`.
- Classifier errors fail closed and remain quiet during routine Insert entry.

An unknown filetype may instead explicitly declare plain-text safety:

```lua
filetypes = {
  myprose = {
    mode = "hard",
    textwidth = 80,
    format_safety = "plain",
  },
}
```

### Conceal and presentation

Default conceal behavior is:

```lua
conceal = {
  level = 2,
  cursor = "",
}
```

This allows supported markup to be concealed while keeping markup visible on the cursor line. Users can opt out of Pencil's conceal changes with:

```lua
conceal = false
```

Soft mode leaves `colorcolumn` unchanged.

### Public Lua interface

The accepted small external interface is:

```lua
local pencil = require("pencil")

pencil.setup(config)
pencil.enable(opts)
pencil.disable(opts)
pencil.toggle(opts)
pencil.set_autoformat(enabled, opts)
pencil.mode(opts)
pencil.status(opts)
```

Expected meanings:

- `setup(config)` validates and installs configuration for future activation.
- `enable(opts)` enables the selected or current buffer using explicit mode settings or detection.
- `disable(opts)` restores state and removes Pencil-owned behavior.
- `toggle(opts)` disables an enabled buffer or enables a disabled buffer with fresh detection.
- `set_autoformat(enabled, opts)` enables, disables, toggles, or suspends automatic formatting as exposed by the command interface.
- `mode(opts)` returns a stable machine-readable mode such as `"hard"`, `"soft"`, `"off"`, or `nil`.
- `status(opts)` returns the configured display indicator.

Configuration precedence is:

1. Per-call options.
2. Filetype-specific settings.
3. Global `setup()` settings.
4. Built-in defaults.

### Command interface

The primary command is unified and provides completion:

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

Bare `:Pencil` enables the current buffer using detection.

Familiar aliases remain:

- `:HardPencil` → `:Pencil hard`
- `:SoftPencil` → `:Pencil soft`
- `:NoPencil` and `:PencilOff` → `:Pencil disable`
- `:TogglePencil` and `:PencilToggle` → `:Pencil toggle`
- `:PFormat`, `:PFormatOff`, and `:PFormatToggle` → their corresponding format actions

### Status and notifications

Pencil does not modify statuslines automatically. It exposes `require("pencil").status()` for statusline plugins such as lualine and for custom statuslines.

Default indicators are ASCII for reliable rendering:

```lua
{
  hard = "H",
  auto = "A",
  soft = "S",
  off = "",
}
```

- `A` means hard mode is active and automatic formatting is currently active.
- `H` means hard mode is active but autoformat is disabled or suspended.
- `S` means soft mode.
- Untouched and disabled buffers return an empty status string.

Notifications are quiet by default. Pencil notifies only for:

- Invalid configuration or commands.
- Explicit operational failures.
- Mapping conflicts, once per key per buffer.
- Attempts to enable autoformat outside hard mode.

It does not notify for normal auto-enabling, successful mode detection, or routine autoformat suspension.

### Testing and quality constraints

Testing should use real, isolated, headless Neovim processes rather than relying on a required plugin test dependency. Tests should verify behavior through agreed public seams rather than internal implementation details.

The important seams are:

- Lua setup and buffer-control functions.
- The unified command and aliases.
- Observable buffer/window options, mappings, mode, and status.
- Automatic activation on `FileType` after setup.
- Insert-mode formatting behavior in plain and structured content.

The test matrix must cover:

- Minimum Neovim 0.10 and a current stable Neovim.
- Optional setup and `opts = {}` automatic activation.
- Atomic invalid setup and repeated valid setup.
- List and keyed-table filetype configuration.
- Every built-in preset.
- Explicit hard, soft, detect, toggle, and disable behavior.
- Modelines, disabled Neovim modelines, non-blank line sampling, threshold boundaries, and width precedence.
- Exact option restoration.
- Multiple buffers with different modes.
- Multiple windows showing one enabled buffer.
- Windows opened after a buffer is already enabled.
- Mapping conflicts and repeated enable/disable cycles.
- Undo behavior including `<CR>` conflicts.
- Plain-text autoformat.
- Built-in structured classifiers.
- Treesitter classification, syntax fallback, unavailable classification, errors, and fail-closed behavior.
- Custom classifiers and plain-text opt-in for unknown filetypes.
- Command completion, aliases, mode, and status output.
- Buffer/window cleanup without leaked state.

### Approaches considered and rejected

- **Compatibility-first port:** rejected because the goal is a clean design, not continued support for Vimscript globals and old quirks.
- **Line-for-line Vimscript translation:** rejected because it would preserve broken state ownership and legacy syntax assumptions.
- **No default auto-enable set:** rejected; `opts = {}` should be immediately useful for prose editing.
- **Extending default filetypes when `filetypes` is supplied:** rejected; explicit configuration replaces the set for predictability.
- **One generic preset for every prose type:** rejected in favor of opinionated defaults such as hard-wrapped Git commits and soft-fallback Markdown.
- **Structural wrap sampling:** rejected in favor of a simple modeline/line-length heuristic that works without parsers.
- **Continuing autoformat when classification fails:** rejected because accidental reformatting of structured text is worse than skipping autoformat.
- **Treating every unknown filetype as plain text:** rejected; unknown formats fail closed unless explicitly declared safe.
- **Overriding and later restoring conflicting mappings:** rejected; Pencil skips conflicts instead.
- **Aborting buffer activation on one mapping conflict:** rejected; non-conflicting behavior can remain useful.
- **Omitting the `<CR>` undo mapping:** rejected; retain it when safe and skip it on conflict.
- **Only remapping `j` and `k`:** rejected in favor of the complete writing-focused navigation set.
- **Automatically modifying statuslines:** rejected; expose a status function without plugin-specific statusline coupling.
- **Verbose routine notifications:** rejected; normal behavior should be quiet.
- **Unicode default indicators:** rejected in favor of predictable ASCII indicators.
- **Remembering the previous mode after disable:** rejected; each enable performs fresh detection.
- **Automatically reconfiguring active buffers after another `setup()`:** rejected as disruptive and difficult to reconcile with exact restoration.
- **Conceal level 3 and cursor concealment:** rejected in favor of the less aggressive level 2 with markup visible on the cursor line.
- **Hiding `colorcolumn` in soft mode:** rejected as surprising and unrelated to core behavior.
- **Copying broad prose option changes:** rejected; the plugin should change only what its core behavior requires.

### Open questions and answers

All planning questions raised during exploration have been answered:

- **Port style?** Clean redesign.
- **Repository name?** `pencil.nvim`, despite unrelated repositories with the same name; the full GitHub owner path disambiguates installation.
- **Minimum Neovim?** 0.10.
- **Required dependencies?** None.
- **Automatic activation?** Yes after `setup()`, with built-in opinionated presets.
- **Explicit filetypes extend or replace defaults?** Replace.
- **Simple-list built-in names retain presets?** Yes.
- **Keyed entries merge over presets?** Yes.
- **Structured detection failure behavior?** Fail closed.
- **Unknown filetype formatting behavior?** Fail closed unless declared plain or given a classifier.
- **Custom classifiers?** Supported, synchronous, three-state, and non-mutating.
- **Mapping conflicts?** Skip and warn once.
- **Map `<CR>`?** Yes when conflict-free.
- **Navigation scope?** Full original writing-focused set, including swapped `g` movements.
- **Multiple windows?** Apply to every window and restore each independently.
- **Bare `:Pencil`?** Enable using detection.
- **Unified commands and aliases?** Both.
- **Default suspend key?** None.
- **Automatic statusline integration?** None.
- **Notification style?** Quiet.
- **Setup optional?** Yes, but required to start auto-activation.
- **Invalid setup?** Raise one aggregate error and apply nothing.
- **Repeated setup?** Future activations only.
- **Conceal defaults?** Level 2, cursor empty, with `false` opt-out.
- **Soft-mode colorcolumn behavior?** Leave untouched.
- **Existing textwidth?** Preserve it unless overridden by a direct value or positive modeline.
- **Read modeline width when modelines are disabled?** Yes, without executing anything else.
- **Formatoptions behavior?** Preserve and minimally adjust, then restore exactly.
- **Manual mode persistence?** Only until disable; re-enable detects again.

## 2. Milestones

- [ ] 001: Deliver an installable Neovim 0.10+ plugin whose optional setup, built-in prose presets, automatic activation, unified commands, wrap detection, mode reporting, multi-window behavior, and exact disable restoration form a complete safe enable–edit–disable workflow.
- [ ] 002: Deliver conflict-safe writing navigation and Insert undo behavior, including physical-line alternatives, configurable mapping groups, and reliable repeated activation without disturbing user mappings.
- [ ] 003: Deliver hard-mode automatic formatting for plain prose, including safe Insert lifecycle control, numbered-list handling, manual format controls, suspension for the next Insert, and exact restoration.
- [ ] 004: Deliver fail-closed automatic formatting for all built-in structured formats using protected-region classification across supported modern and fallback highlighting paths.
- [ ] 005: Deliver user-defined filetype behavior, including merged preset overrides, unknown-filetype safety, explicit plain-text formats, and custom protected-region classifiers.
- [ ] 006: Deliver a documented, tested, and release-ready `pencil.nvim` experience covering Lazy.nvim installation, Lua and command interfaces, statusline integration, migration intent, licensing attribution, supported Neovim versions, and the complete lifecycle and safety matrix.
