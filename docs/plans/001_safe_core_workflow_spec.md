# 001: Safe Core Workflow Specification

## 1. Context & Constraints

### Product goal

Pencil.nvim is a clean Neovim-native redesign of `preservim/vim-pencil`. This milestone delivers the first complete safe workflow: a user can install the plugin, optionally configure it, enable writing behavior for a prose buffer, edit in the selected wrapping mode, inspect the active mode, and disable Pencil without losing the editor state that existed beforehand.

This is not a compatibility-first port. Vim is not supported, legacy `g:pencil#...` variables are not supported, and old undocumented or legacy commands are not required. The supported platform starts at Neovim 0.10, with no required runtime dependencies. Unsupported Neovim versions must produce a clear error.

### Repository state

The repository currently contains the milestone research document and project license, but no plugin implementation or test suite. The implementation must preserve the MIT license attribution required for derived material.

### Decisions that apply to this milestone

- The Lua module name is `pencil`.
- `require("pencil").setup(config)` is the configuration entry point, but setup is optional for direct commands and Lua calls.
- Built-in defaults must work without calling `setup()`.
- Automatic filetype activation begins only after setup runs.
- Both a bare plugin declaration and Lazy.nvim `opts = {}` are valid; `opts = {}` starts automatic activation with built-in prose presets.
- An explicitly supplied `filetypes` value replaces the built-in automatic-activation set. An empty list disables automatic activation while leaving direct controls available.
- A simple filetype list retains built-in presets for recognized names. Keyed entries merge their values over the recognized preset. Unknown names use global detect/fallback settings unless otherwise configured in a later milestone.
- Existing enabled buffers are not reconfigured by a later valid `setup()` call. New activations use the latest valid configuration.
- Configuration validation is atomic: all validation errors are reported together, no partial configuration is installed, and the previous valid configuration remains active.
- Detection is deterministic and independent of Treesitter: supported modelines are read first; positive `textwidth` selects hard mode; `textwidth=0` selects soft mode; otherwise the first 20 non-blank lines are sampled; a sampled line over 130 display columns selects soft mode; otherwise the active preset fallback applies.
- Pencil may read `textwidth` from a modeline even when modeline execution is disabled, but it must not execute other modeline settings.
- Hard-mode width precedence is direct enable option, positive modeline value, existing nonzero buffer `textwidth`, active filetype preset, then global default.
- Manual mode selection lasts only until disable. Re-enabling performs fresh detection against current contents and the latest valid configuration.
- Pencil owns only behavior required for wrapping, formatting-related settings in this milestone, configured concealment, presentation, and its own mappings. It must not alter unrelated options such as `iskeyword`, `list`, `backspace`, indentation behavior, global display options, or `colorcolumn`.
- Buffer-local state belongs to the buffer. Window-local presentation state must be applied to every window displaying an enabled buffer, captured independently, and restored independently.
- Newly opened windows displaying an already-enabled buffer must receive the active presentation behavior.
- Disable must remove only behavior still owned by Pencil and restore exact prior values, not inherited defaults.
- The first milestone includes core wrap behavior and mode reporting, but not navigation mappings, undo-break mappings, hard-mode automatic formatting, structured-region classification, custom classifiers, release documentation, or migration material. Those belong to later milestones.

### Open questions resolved by the research

The milestone does not need to decide the plugin name, minimum Neovim version, setup semantics, preset set, detection threshold, restoration policy, multi-window policy, command names, status indicators, or notification policy. These are fixed by the research above and must not be re-evaluated during implementation.

## 2. Requirements

### Slice 1: Supported installation and direct control

A supported Neovim 0.10+ installation can load the `pencil` module and use its direct controls without prior setup.

The public Lua interface for this milestone is:

- `setup(config)` — validate and install configuration for future activation.
- `enable(opts)` — enable the selected or current buffer.
- `disable(opts)` — disable Pencil for the selected or current buffer.
- `toggle(opts)` — disable an enabled buffer or enable a disabled buffer with fresh detection.
- `mode(opts)` — return `"hard"`, `"soft"`, `"off"`, or `nil` according to the buffer state.
- `status(opts)` — return the configured display indicator.

Direct controls must target the requested buffer when an explicit buffer is supplied and the current buffer otherwise. An untouched buffer reports no active mode and an empty status indicator. A disabled buffer reports `"off"` through `mode()` and an empty status indicator.

The plugin must expose the primary `:Pencil` command with these actions:

- no argument: enable using detection;
- `enable`, `disable`, and `toggle`;
- `hard`, `soft`, and `detect`.

The command must provide completion for supported actions and reject invalid actions with a clear error. Familiar aliases required for this milestone are `:HardPencil`, `:SoftPencil`, `:NoPencil`, `:PencilOff`, `:TogglePencil`, and `:PencilToggle`, with the meanings defined by the research. Format commands are deferred to milestone 003.

Verification must demonstrate that commands and Lua controls produce equivalent observable buffer state, work before setup, and do not require a plugin-specific statusline integration.

### Slice 2: Built-in prose activation

After valid setup, a matching `FileType` event automatically enables Pencil using the applicable built-in preset. Normal automatic activation is quiet and does not require a notification.

The built-in automatic set and presets are:

| Filetype | Mode | Fallback | Width |
|---|---|---|---:|
| `gitcommit` | hard | — | 72 |
| `mail` | hard | — | 72 |
| `markdown` | detect | soft | — |
| `text` | detect | soft | — |
| `rst` | detect | hard | 79 |
| `tex` | detect | hard | 79 |
| `asciidoc` | detect | hard | 79 |
| `textile` | detect | soft | — |

A simple explicit list preserves recognized presets. A keyed entry overrides only the supplied fields while retaining the recognized preset's other values. An explicit filetype set replaces, rather than extends, the built-in set. An empty set prevents automatic activation but does not disable direct commands or Lua functions.

Verification must cover each built-in preset, a recognized filetype in a simple list, a keyed override, an unknown filetype in a simple list, a replacement list, and an empty list.

### Slice 3: Deterministic mode selection

Enabling with detection selects hard or soft mode according to this exact sequence:

1. Read supported `textwidth` modeline forms.
2. A positive modeline value selects hard mode.
3. A modeline value of zero selects soft mode.
4. If no relevant modeline exists, inspect the first 20 non-blank lines.
5. If any sampled line exceeds 130 display columns, select soft mode.
6. Otherwise select the active filetype fallback.

Sampling includes structured regions and is based on display columns. Blank lines do not count toward the 20-line sample. A file with fewer than 20 non-blank lines uses all available non-blank lines. A line exactly 130 display columns long does not trigger the soft-mode threshold; a line longer than 130 does.

For hard mode, the effective width is selected in this order:

1. A direct value supplied to `enable()`.
2. A positive modeline value.
3. The buffer's existing nonzero `textwidth`.
4. The active filetype preset.
5. The global default.

A direct mode request (`hard` or `soft`) must not run detection. A direct hard-mode request still applies the width precedence unless a direct width is supplied. A direct soft-mode request must not change `colorcolumn`.

Modeline parsing must not execute arbitrary settings. Malformed, negative, or unsupported `textwidth` modelines do not select a mode and do not override width. Detection must remain usable when Neovim modeline execution is disabled.

Verification must cover modeline precedence, disabled modelines, zero and positive values, malformed values, fewer than 20 non-blank lines, exactly 20 sampled lines, the 130-column boundary, display-width differences, and every hard-width precedence level.

### Slice 4: Wrap presentation and exact lifecycle restoration

When enabled in hard mode, the buffer uses hard wrapping with the selected width and the minimum required formatting behavior. When enabled in soft mode, displayed lines wrap for writing-oriented viewing without changing `colorcolumn`. Neither mode may change unrelated editor settings.

The active presentation behavior must be visible in every window displaying the enabled buffer. If another window starts displaying that buffer after activation, it must receive the same active presentation behavior. Each window's prior window-local values must be restored to that window's own values when Pencil is disabled or the window stops displaying the buffer.

Disabling must restore every affected buffer-local and window-local value exactly as it was immediately before Pencil first changed it. Restoration must work when:

- values were inherited rather than explicitly set;
- the user changed an affected value while Pencil was active;
- one of several windows displaying the buffer is closed;
- the buffer is wiped out;
- the buffer is enabled, disabled, and enabled again repeatedly;
- multiple buffers use different modes simultaneously.

Pencil must not reset values to generic defaults and must not restore a value captured from another buffer or window. It must not leak presentation or behavior into unrelated buffers or windows. Re-enabling after disable must perform fresh detection and must not reuse a stale previous-mode snapshot.

Verification must inspect observable options and behavior before enable, during enable, after disable, across multiple buffers, across multiple windows, after opening a new window, and across repeated lifecycle transitions.

### Slice 5: Configuration validation and update boundaries

`setup()` accepts the documented configuration shape and rejects invalid values with one error containing every validation problem found in that call. Invalid setup must leave the prior configuration unchanged and must not partially change automatic activation behavior.

Valid repeated setup calls replace configuration only for future activations. Buffers already enabled remain unchanged until explicitly disabled or re-enabled. A later re-enable uses current buffer contents and the latest valid configuration.

The milestone's configuration surface must include the global defaults, filetype selection and overrides, mode/fallback settings, hard-wrap width settings, conceal settings, and status indicators needed by the research decisions. Conceal defaults are level 2 with an empty cursor value; `conceal = false` opts out of Pencil's conceal changes. Conceal behavior must be applied and restored only where configured and supported by the active mode/filetype.

Invalid configuration includes unsupported types, invalid mode or fallback names, invalid widths, malformed filetype entries, invalid conceal values, and invalid status indicators. Validation errors must identify the invalid setting sufficiently for a user to correct it.

Verification must compare configuration and observable state before and after invalid setup, test multiple simultaneous validation failures, and confirm that valid setup updates affect only future activation.

### Parallelization

The following work can proceed in parallel after the shared public behavior and state-restoration rules are agreed:

1. Configuration validation and preset resolution.
2. Modeline parsing, line sampling, and mode/width selection.
3. Command and alias behavior.
4. Buffer/window presentation and lifecycle restoration.
5. Headless behavioral verification across the public Lua and command interfaces.

Integration of these slices must occur before the milestone is considered complete, because the required outcome is one safe end-to-end enable–edit–disable workflow rather than independent subsystems.

### Out of scope

The following are explicitly excluded from this milestone:

- Writing navigation mappings and physical-line alternatives.
- Insert-mode undo-break mappings and mapping conflict policy.
- Automatic hard-mode formatting lifecycle, numbered-list handling, manual format controls, and next-Insert suspension.
- Protected-region classification, Treesitter integration, legacy syntax fallback, and custom classifiers.
- User-defined custom filetype safety behavior beyond the preset selection and validation needed here.
- Release documentation, migration guidance, complete licensing attribution documentation, and the full release test matrix.
