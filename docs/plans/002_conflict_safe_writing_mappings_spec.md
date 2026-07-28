# 002: Conflict-Safe Writing Mappings Specification

## 1. Context & Constraints

### Product goal

Pencil.nvim is a Neovim-native Lua writing workflow inspired by `preservim/vim-pencil`, but redesigned to provide explicit ownership, safe lifecycle behavior, and modern Neovim integration. This milestone adds writing-focused navigation and Insert-mode undo behavior to the safe core workflow delivered by milestone 001.

The outcome is that users can navigate by displayed lines while retaining explicit physical-line alternatives, receive useful undo boundaries during prose editing, configure either mapping group independently, and repeatedly enable and disable Pencil without losing or altering mappings that Pencil does not own.

This milestone does not add automatic formatting. It only defines mappings and their safe lifecycle.

### Platform and compatibility constraints

- Neovim 0.10 or newer is supported; Vim is not supported.
- No required runtime dependencies may be assumed.
- The Lua module remains `pencil`, loaded with `require("pencil")`.
- Existing setup, direct Lua controls, commands, aliases, buffer/window lifecycle behavior, and exact option restoration from milestone 001 remain supported.
- Pencil must not provide compatibility for legacy `g:pencil#...` variables, the undocumented `Mapkey()` function, or legacy opt-in commands such as `:DropPencil`.
- The existing MIT license attribution for derived material remains applicable.

### Repository and existing workflow

Milestone 001 established an installable plugin with:

- optional setup and built-in defaults;
- built-in prose presets and setup-gated automatic activation;
- direct Lua controls for enabling, disabling, toggling, mode reporting, and status reporting;
- the unified `:Pencil` command and core aliases;
- deterministic hard/soft/detect selection;
- buffer and window lifecycle handling across multiple buffers and windows;
- exact restoration of Pencil-owned state, while preserving user edits and unrelated buffers/windows;
- headless behavioral verification through public Lua and command seams.

The mapping behavior in this milestone must integrate with that existing lifecycle rather than creating a separate activation model. Existing enabled buffers must gain the configured mapping behavior, and disabling must remove only mappings that Pencil still owns.

### Decisions already made

The following decisions are fixed by the milestone research and must not be re-evaluated:

- Two mapping groups exist and are independently configurable:

  ```lua
  mappings = {
    navigation = true,
    undo_breaks = true,
  }
  ```

- Both groups are enabled by default.
- Navigation uses display-line movement for the simple writing keys and provides physical-line alternatives through the corresponding `g` commands.
- Navigation covers `j`, `k`, the Up and Down arrow keys, `0`, `$`, Home, and End.
- The corresponding physical-line commands remain available through `gj`, `gk`, `g0`, and `g$` behavior.
- Undo-break behavior covers `.`, `!`, `?`, `,`, `;`, `:`, `<C-U>`, and `<C-W>`.
- `<CR>` is included when it has no mapping conflict.
- If a default Pencil mapping conflicts with an existing buffer-local or global mapping, Pencil skips that mapping.
- A skipped conflict produces one warning per key per buffer, not repeated warnings during ordinary lifecycle transitions.
- Pencil never replaces, shadows, or later removes a conflicting mapping it did not install.
- A conflict with one mapping must not prevent other non-conflicting mappings or the other mapping group from being installed.
- `<CR>` follows the same conflict policy as every other mapping; it receives no special override behavior.
- Mapping teardown removes only mappings that still have the ownership and right-hand-side identity established by Pencil.
- Repeated enable/disable and soft/off/soft transitions must not duplicate mappings, leave stale mappings, or remove user mappings.
- Navigation and undo-break mappings are independently configurable and can each be disabled without disabling Pencil itself.
- The default mapping behavior is buffer-local in effect and must respect mappings belonging to the selected buffer.
- There is no default mapping for suspending autoformat during the next Insert; automatic formatting is deferred to milestone 003.

### Ownership and lifecycle constraints

Pencil may install only the mappings required by the enabled mapping groups. For every installed mapping, Pencil must be able to distinguish its own mapping from a mapping created or changed by the user or another plugin.

When a user or another plugin changes a Pencil-owned mapping while Pencil is active, Pencil must treat the current mapping as externally owned. Disabling or reconfiguring Pencil must not delete or overwrite that mapping. A mapping that remains unchanged from Pencil's installation may be removed during teardown.

A mapping conflict is determined against the relevant existing buffer-local and global mapping behavior before Pencil installs the mapping. Existing mappings must remain behaviorally intact when skipped.

Mapping behavior must remain correct when:

- the same buffer is enabled repeatedly;
- a buffer is disabled and re-enabled;
- a buffer changes between soft and hard mode;
- one mapping group is toggled in configuration or enable options;
- a buffer is displayed in multiple windows;
- a new window displays an already-enabled buffer;
- a buffer leaves and later re-enters a window;
- a buffer or window is closed;
- multiple buffers have different mapping states;
- mappings are added, changed, or removed externally while Pencil is active.

### Open questions resolved by research

The milestone does not need to decide the navigation key set, physical-line alternatives, undo-break key set, conflict policy, warning frequency, `<CR>` behavior, mapping ownership policy, or the independent configuration of mapping groups. Those choices are fixed above and must be implemented as observable behavior.

## 2. Requirements

### Slice 1: Configurable mapping groups

The configuration accepts the two mapping-group settings `mappings.navigation` and `mappings.undo_breaks`. Each setting is boolean and defaults to `true`.

A valid setup can enable or disable either group independently. A configuration that disables navigation still permits undo-break mappings, and a configuration that disables undo breaks still permits navigation mappings. Disabling both groups leaves Pencil's wrapping, presentation, and other milestone-001 behavior available without installing Pencil mappings.

Per-call enable options may override the effective mapping-group settings for that activation when the public enable interface supports per-call behavior. The effective settings must follow the established configuration precedence: per-call values, filetype-specific values, global setup values, then built-in defaults. Invalid mapping-group values must be rejected before activation changes are applied.

A valid setup change affects future activations. An already-enabled buffer is not silently reconfigured by a later setup call. Explicit re-enable or disable-and-enable behavior must apply the latest valid mapping configuration while preserving the lifecycle guarantees in this specification.

Verification must cover defaults, each group independently disabled, both groups disabled, valid filetype-specific overrides, valid per-call overrides if exposed, invalid values, and setup changes before versus after activation.

### Slice 2: Display-line navigation

When the navigation group is enabled for an active buffer, Pencil provides writing-oriented movement using displayed lines:

- `j` moves down by one displayed line.
- `k` moves up by one displayed line.
- Down and Up arrow keys provide the corresponding displayed-line movement.
- `0` moves to the first displayed line position of the current logical line.
- `$` moves to the last displayed line position of the current logical line.
- Home and End provide the corresponding displayed-line boundary behavior.

The navigation behavior must work with wrapped prose and must use the same observable movement semantics for equivalent key pairs. It must not make physical-line movement unavailable.

The corresponding physical-line alternatives remain available through:

- `gj` and `gk` for physical-line movement equivalents;
- `g0` and `g$` for physical-line boundary equivalents.

Pencil must not remap those physical-line alternatives in a way that prevents their normal use. A user must be able to choose displayed-line movement through the simple writing keys and physical-line movement through the `g` commands.

Navigation mappings are installed only when the navigation group is active and are removed only when Pencil still owns them. Turning the group off must not affect undo-break mappings or unrelated mappings.

Verification must cover short and wrapped lines, all navigation keys, physical-line alternatives, hard and soft modes, multiple buffers, and repeated activation transitions.

### Slice 3: Insert-mode undo breaks

When the undo-break group is enabled for an active buffer, Pencil provides Insert-mode undo boundaries after the following punctuation keys:

- `.`
- `!`
- `?`
- `,`
- `;`
- `:`

It also provides undo boundaries for the Insert-mode deletion commands:

- `<C-U>`
- `<C-W>`

The mappings must preserve the normal editing result of each key while adding the requested undo segmentation. They must not alter the inserted character or deletion behavior.

`<CR>` receives the same undo-break treatment only when Pencil can install it without conflicting with an existing buffer-local or global mapping. If `<CR>` conflicts, Pencil skips it, warns according to the standard once-per-key policy, and leaves the existing behavior unchanged.

Undo-break mappings apply in Insert mode only. They must not change Normal, Visual, Select, or Command-line mode behavior. Their effect must be observable by undoing after separate punctuation, deletion, or safe-`<CR>` operations.

Verification must cover each punctuation key, both deletion keys, conflict-free `<CR>`, conflicting `<CR>`, behavior in non-Insert modes, and preservation of the normal editing result.

### Slice 4: Conflict-safe installation

Before installing a requested mapping, Pencil checks whether a buffer-local or global mapping already provides behavior for that key and mode. When an existing mapping conflicts, Pencil:

1. leaves the existing mapping unchanged;
2. does not install the Pencil mapping for that key;
3. continues installing other requested mappings that do not conflict;
4. emits one clear warning for that key and buffer during the relevant activation lifecycle.

A conflict in navigation must not suppress undo-break mappings, and a conflict in undo breaks must not suppress navigation mappings. A conflict on `<CR>` must not cause an error or abort activation.

If the same buffer is enabled again while the conflict remains, Pencil must not repeatedly warn for the same key during routine reconciliation. A warning may be emitted again only after a meaningful lifecycle reset or when the conflict state has changed, consistent with the once-per-key-per-buffer policy.

If the user removes the conflicting mapping and explicitly re-enables or otherwise requests mapping reconciliation, Pencil may install the now-available mapping. If the user changes a Pencil-installed mapping to another mapping, Pencil must not overwrite the replacement or treat it as Pencil-owned.

Verification must cover global conflicts, buffer-local conflicts, conflicts in every relevant mode, partial conflicts, repeated activation, conflict removal followed by reactivation, and external replacement of an installed mapping.

### Slice 5: Safe teardown and repeated lifecycle

When Pencil is disabled, it removes only mappings that Pencil installed and that still match the mapping identity Pencil recorded at installation time. It preserves:

- pre-existing global mappings;
- pre-existing buffer-local mappings;
- mappings installed by another plugin after Pencil activation;
- user replacements of Pencil mappings;
- conflicting mappings that Pencil skipped.

Disabling one buffer must not remove mappings from another buffer. Closing or wiping a buffer must not leave Pencil mappings active in a replacement buffer or unrelated window. Window transitions must not duplicate mappings or remove mappings belonging to another active buffer.

Repeated lifecycle operations must be idempotent and safe:

- enable an already-enabled buffer;
- disable an already-disabled buffer;
- toggle repeatedly;
- enable hard, switch to soft, disable, and re-enable;
- enable, externally change a mapping, then disable;
- enable with one mapping group, re-enable with another, then disable;
- activate multiple buffers with different conflict and mapping states.

After a complete disable, a later enable must start from the current mapping state and must not reuse stale ownership or warning state in a way that removes or suppresses valid behavior incorrectly.

Verification must inspect mappings before activation, while active, after user edits, after disable, after repeated cycles, after buffer/window transitions, and with simultaneous active buffers.

### Slice 6: Public command and Lua behavior

The existing public Lua controls and unified command remain usable with mapping behavior enabled. The mapping feature must not change the meanings of `enable`, `disable`, `toggle`, explicit hard/soft/detect selection, `mode`, or `status`.

The existing command aliases continue to work. Any command or Lua interface introduced specifically to configure or toggle mapping groups must have explicit behavior, completion where applicable, and the same conflict and ownership guarantees. No additional public interface is required unless needed to expose the configuration decisions above.

Normal successful mapping installation, skipped conflict-safe behavior, and routine lifecycle reconciliation remain quiet except for the specified conflict warnings. Explicit invalid configuration or operational failures continue to produce clear errors through the established notification policy.

### Parallelization

After the shared mapping ownership and conflict rules are agreed, the following work can proceed in parallel:

1. Mapping-group configuration validation and precedence behavior.
2. Display-line navigation behavior and physical-line alternative verification.
3. Insert-mode undo-break behavior, including safe `<CR>` handling.
4. Conflict detection, warning deduplication, ownership tracking, and teardown verification.
5. Headless lifecycle tests covering multiple buffers, windows, external mapping changes, and repeated activation.

Integration is required before acceptance. The final verification must exercise navigation, undo breaks, conflicts, and teardown in one end-to-end enabled-buffer workflow.

### Out of scope

The following are explicitly excluded from this milestone:

- automatic hard-mode formatting;
- numbered-list handling;
- protected-region classification, Treesitter integration, legacy syntax fallback, or custom classifiers;
- manual format controls or a next-Insert autoformat suspension command/mapping;
- new prose-editing features unrelated to navigation and undo boundaries;
- changes to statusline integration;
- changes to modeline parsing, wrap detection, conceal behavior, or the core option-restoration contract except where required to preserve mapping lifecycle safety;
- compatibility with Vimscript configuration, Vim, legacy globals, undocumented functions, or legacy commands;
- release documentation, migration guidance, and the complete release test matrix.
