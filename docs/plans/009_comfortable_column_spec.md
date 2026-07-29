# Comfortable Column Resize and Multi-Window Specification

## 1. Context & Constraints

### Product intent

Milestone 009 extends the working comfortable-column toggle from one window to the full buffer/window lifecycle. Pencil remains one binary, buffer-local state: a buffer is either on or off. While it is on, every window displaying that buffer presents the same preferred 80-character centered writing column, adjusted to that window's available width. Turning Pencil off removes the presentation from every affected window and restores each window's own prior presentation.

The primary writer-facing entry point remains the bare `:Pencil` toggle. The existing `enable`, `disable`, and `toggle` Lua functions remain equivalent control seams. This milestone changes lifecycle coverage, not the public product model.

### Research and repository evidence

- `docs/plans/008_comfortable_column_milestones.md` makes 009 the next uncompleted milestone after the 008 rewrite. Its explicit boundary is resize, all windows displaying an enabled buffer, and splits opened while Pencil is on.
- `docs/plans/008_comfortable_column_spec.md` establishes the 80-character default, visual-only wrapping, genuine centered presentation, buffer-local activation, exact restoration, ownership transfer after external edits, and the exclusion of width configuration.
- `docs/plans/008_comfortable_column_implement.md` identifies resize reconciliation and window propagation as the deferred 009 seam.
- `lua/pencil/init.lua` currently records active state by buffer but applies presentation only to the current window during `enable()`. Its `state.windows` table and per-window baseline records are the available current lifecycle seam; no resize, window-enter, or late-split reconciliation is currently registered.
- The current 008 acceptance test exercises only one window. `tests/run.sh` runs the comfortable-column and unsupported-version processes; 009 acceptance coverage belongs in that replacement suite or a narrowly scoped companion script.
- The current presentation uses window-local centered-margin state together with a buffer-local wrapping margin. The observable contract is per-window centered presentation; the implementation must not allow one window's width or baseline to corrupt another window's presentation or restoration.

### Decisions already made

- The preferred measure remains exactly 80 display columns. Milestone 009 does not add `setup({ width = ... })`, per-filetype widths, or any width command.
- Activation remains buffer-local. Enabling a buffer affects every current and subsequently displayed window for that buffer; disabling the buffer affects all windows still displaying it.
- Each window has independent presentation ownership and an independent pre-Pencil baseline. A split must not inherit a baseline belonging to another window merely because both show the same buffer.
- A window's presentation is recalculated against that window's current available text area. Spare space must remain symmetric around the writing column; a window narrower than 80 columns contracts safely.
- Buffer text is never modified. Wrapping remains visual only, and Pencil installs no mappings, conceal behavior, statusline integration, or auto-enable behavior.
- Existing user edits to Pencil-owned presentation values transfer ownership for that value. Disable and lifecycle transitions must not overwrite a value changed externally.
- Neovim 0.10+ and no runtime dependencies remain the supported platform constraints.

### Current gaps this milestone closes

1. Enabling in one window does not currently apply the presentation to sibling windows showing the same buffer.
2. A newly created split or newly displayed window does not currently receive Pencil presentation while the buffer is active.
3. A resize does not currently recompute the centered margins or safely contract the measure.
4. Disabling currently restores only the window records created during the one-window enable path, so multi-window and lifecycle ownership cannot yet be verified.

### Scope boundary

This milestone includes:

- Current multi-window activation for one enabled buffer.
- Windows created or switched to while that buffer is enabled.
- Window resize and global editor resize while Pencil is enabled.
- Independent window baselines, ownership, and restoration.
- Safe behavior for wide, exact-width, and narrow windows.
- Preservation of the existing 80-column, buffer-local, visual-only product.

This milestone excludes:

- Configurable preferred measure; milestone 010.
- Filetype-specific widths or filetype auto-enable.
- Documentation and final public-surface cleanup; milestone 011.
- Hard wrapping, autoformat, classification, concealment, mappings, navigation, and statusline features.
- New commands or a richer status API.

### Constraints and lifecycle rules

- Every window currently displaying an enabled buffer must converge to the active comfortable-column presentation after the relevant editor lifecycle event, without requiring the user to toggle Pencil again.
- A newly displayed enabled buffer must receive presentation using that window's state immediately after the lifecycle transition settles. A split created while Pencil is on must not remain in the off presentation.
- A window displaying another buffer must not receive Pencil presentation merely because another window displays an active buffer.
- When a window stops displaying the active buffer, Pencil must not leave its presentation altered for the next buffer. If the window later displays the active buffer again, the presentation must be based on the state appropriate to that window at re-entry, not a stale snapshot from a different buffer.
- Resize reconciliation may change only Pencil-owned presentation values. It must preserve user edits and must not create a new restoration baseline on every resize.
- Reconciliation must be idempotent. Repeated resize, window-enter, split, and buffer-display events must not compound margins, duplicate ownership, or lose the original baseline.
- Disable must restore each still-owned value to that window's pre-activation value. Values changed by the user remain as changed. Invalid windows and deleted buffers must be cleaned up without errors or leaked active state.
- Failed lifecycle reconciliation must not partially activate a new window or corrupt already-active windows. Existing valid presentation must remain usable, and the affected window must remain restorable.

## 2. Requirements

### Vertical slice A: Apply the active column to all current windows

1. When Pencil is enabled for a buffer that is visible in multiple windows, every window displaying that buffer must receive a centered visual-wrap presentation in the same activation cycle.
2. Each window must use its own available text width when calculating the presentation. A wide and narrow split may therefore have different margins, but both must represent the same preferred 80-column measure whenever their available space permits.
3. Every window must retain the unrelated presentation values it had before activation.
4. Disabling the buffer must remove Pencil's presentation from every still-valid window displaying that buffer.
5. Disabling from any one of the buffer's windows must have the same buffer-wide result; it must not disable only the current window.
6. The buffer's physical lines, line count, cursor text, and filetype must remain unchanged through activation and disable.

### Vertical slice B: Reconcile resize without losing ownership

1. While Pencil is enabled, increasing a window's width must recenter the column and expose the additional symmetric margins without requiring a second toggle.
2. While Pencil is enabled, reducing a window's width must recalculate the presentation for the reduced space. It must never produce negative spacing, invalid display values, horizontal overflow caused by Pencil, or an accumulating left margin.
3. A window with exactly enough available text space for the preferred measure must have no artificial spare margin and must continue to wrap visually.
4. A window narrower than the preferred measure must contract the displayed measure to the available text area while remaining usable and visually centered.
5. Resizing one window must not change another window's margins, wrapping state, baseline, or ownership records except where Neovim itself changes shared state.
6. Repeated resize events at the same or alternating widths must converge to the same presentation as a single reconciliation at the final width.
7. A user edit to a Pencil-owned value before or between resize events must be preserved; resize reconciliation must not treat the user's value as a reason to reacquire ownership or overwrite it.
8. Disabling after any number of resizes must restore the original pre-enable value for each still-owned presentation value, not the value from the first or last resized layout.

### Vertical slice C: Handle splits and window lifecycle while active

1. Creating a split that displays an already-enabled buffer must apply the comfortable-column presentation to the new window automatically.
2. Opening a new window with another buffer must leave that window's presentation unchanged by Pencil.
3. Switching an existing window from another buffer to an enabled buffer must apply the active presentation using that window's current dimensions and preserve the window's pre-entry presentation for later restoration.
4. Switching an active window away from the enabled buffer must restore or preserve the presentation state that belongs to the newly displayed buffer; Pencil must not leak the active buffer's margins or wrapping into it.
5. Switching the window back to the enabled buffer must reapply the active presentation without compounding margins and without replacing the window's original baseline with the temporary state from the prior visit.
6. Closing a window must discard only that window's active presentation record. It must not disable the buffer or disturb sibling windows.
7. Deleting or wiping the enabled buffer must clean up its active state without errors. No later window event may apply stale Pencil presentation using the deleted buffer's state.
8. A split created while the buffer is active must be covered whether the split is created from the active buffer or the new window is subsequently navigated to the active buffer.
9. If a newly displayed window has user-configured wrapping or presentation values, those values must be restored when that window leaves the active buffer or when Pencil is disabled, subject to ownership transfer after an external edit.

### Vertical slice D: Preserve the binary public contract across windows

1. `:Pencil` must continue to toggle the current buffer's state, not merely the current window's state.
2. `require("pencil").enable({ buf = buffer })`, `disable({ buf = buffer })`, and `toggle({ buf = buffer })` must operate on all windows displaying the selected buffer with the same semantics as the command.
3. Repeated `enable()` while the buffer is active must be idempotent across all windows: it must not create fresh baselines, duplicate margins, or alter already transferred ownership.
4. Repeated `disable()` while the buffer is inactive must be a no-op for every window.
5. Toggling off and then on after a multi-window lifecycle must take fresh baselines for the new activation and restore those new baselines on the next disable.
6. The behavior must remain independent of filetype and must not require `setup()`.
7. Pencil must not install or remove user mappings, change conceal settings, alter statusline values, insert hard breaks, or modify unrelated buffer/window settings as a side effect of lifecycle reconciliation.

### Edge cases

- One buffer shown in two or more splits with different widths.
- A split exactly at 80 available display columns.
- A split narrower than 80 display columns, including the smallest usable width Neovim permits.
- Window numbers, relative numbers, signs, and fold columns changing the available text area during activation or resize.
- A window resize occurring before the newly enabled presentation has completed, or multiple resize events arriving in quick succession.
- A user changes wrapping or margin-related presentation in one window while another window remains untouched; ownership and restoration must remain independent.
- A user changes a Pencil-owned value, then resizes, then switches buffers, then disables; the changed value must survive all transitions.
- A split is created while active, then resized, then closed before disable.
- A window changes buffers several times and returns to the active buffer.
- The active buffer is wiped while displayed in one or more windows.
- Empty, short, long, Unicode, and tabbed lines remain unchanged and receive the same lifecycle behavior as in milestone 008.
- Non-prose filetypes remain eligible for manual activation; no filetype event may auto-enable an inactive buffer.

### Parallelizable work

- Current multi-window activation and independent restoration can be developed and verified independently of resize calculations once the buffer-wide state contract is fixed.
- Resize convergence tests for an already-active window can be developed independently of split/window-enter tests.
- Late-split and buffer-switch lifecycle tests can be developed independently of global resize tests, provided they assert the same per-window ownership rules.
- Cleanup tests for closed windows and wiped buffers can be developed independently of normal enable/disable tests.
- Command/API parity tests can run in parallel with presentation tests because the public behavior is a thin control seam over the same buffer-local state.

### Verification expectations

The milestone is complete only when isolated headless tests verify all of the following:

- Enabling a buffer visible in multiple windows applies centered visual wrapping to every such window.
- Each window computes safe margins from its own width and remains centered after expansion and contraction.
- Resize does not compound presentation or replace original restoration baselines.
- A split created while Pencil is active receives presentation automatically.
- Switching buffers does not leak presentation, and returning to an active buffer reapplies it safely.
- Closing windows and wiping buffers leave no stale active behavior.
- Disable restores each window's original values independently while preserving external edits.
- The command and Lua APIs retain buffer-wide toggle semantics, repeated operations are idempotent, and buffer text and unrelated settings remain unchanged.

No implementation structure is prescribed by this specification; acceptance is based on these observable lifecycle and ownership behaviors.
