# Comfortable column — product design

## 1. Context
- Directory: /home/jaron/dev/pencil.nvim/master (jrswab/pencil.nvim)
- Actor: Writer editing longform prose in Neovim 0.10+
- Current state: Neovim-native plugin inspired by preservim/vim-pencil; soft/hard wrap, autoformat, classification, conflict-safe mappings; large single-module implementation; interaction model still tracks vim-pencil more than the desired UX
- Constraint from user: rewrite led from UX; primary outcome is comfortable reading/writing measure, not vim-pencil parity
- Runtime: Neovim plugin only (commands + setup + buffer/window behavior)

## 2. Jobs
Primary (ranked):
1. Writer makes column width and visual line wrapping comfortable for reading and writing longform prose in the current buffer — by narrowing to a centered text column at a preferred measure
2. Writer toggles that experience on and off with `:Pencil` at any time, regardless of filetype or prior state

Deferred secondary:
- Per-filetype auto-enable when opening matching buffers
- Per-filetype default widths applied when Pencil is turned on
- Hard wrap / real line breaks / insert-time autoformat
- Plugin-owned navigation or undo mappings
- Conceal management
- Statusline integration beyond minimal on/off if needed later
- Custom classifiers / structured-region format safety (only relevant to hard autoformat)

## 3. Surface kind
Primary: Neovim plugin (Ex commands + optional `require("pencil").setup`, buffer/window-local behavior).

Rationale: actor already lives in Neovim; job is live buffer presentation. Rejected: standalone TUI/CLI (leaves the editor); web UI (irrelevant); heavy Lua API surface before the toggle path is right.

## 4. Design

### Entry points
- `:Pencil` — toggle Pencil for the current window/buffer pairing (on → off restores prior presentation; off → on applies comfortable column)
- Optional later aliases only if they stay one-syllable mental model; do not recreate Hard/Soft/PFormat command families
- `require("pencil").setup({ ... })` — optional global defaults (width, filetype width map); not required to use `:Pencil`
- No auto-activation on FileType for v1 of this redesign

### Information architecture
Concepts the writer needs:
- **Pencil on/off** — single binary state per buffer (or per window if implementation requires; prefer one obvious state)
- **Measure** — preferred column width in characters (default 80 unless setup overrides)
- **Centered column** — prose content visually confined to the measure, centered in the window; soft/visual wrap only inside that column

Drop from the writer-facing model: soft vs hard mode, detect, autoformat armed, prose/protected/unknown, ownership tokens, mapping groups.

### Core flows

**Turn on (success)**
1. Writer runs `:Pencil` in a buffer where Pencil is off
2. Window presents a centered column at the configured measure
3. Long lines wrap visually within the column; no new hard breaks inserted by Pencil
4. Feedback: immediate layout change is the success signal; optional minimal echo only if layout change could be ambiguous

**Turn on (empty / short buffer)**
- Same layout: centered measure still appears so the writing column is obvious before text exists

**Turn off (success)**
1. Writer runs `:Pencil` while on
2. Pencil restores the exact window/buffer presentation it changed
3. No leftover mappings, width hacks, or partial options

**Error / unavailable**
- Unsupported Neovim version: clear error, no partial enable
- If centering cannot be applied (edge case): fail with a short message; leave buffer unchanged

**Resize**
- While on, window resize recenters/recomputes the column so measure stays preferred width

**Width**
- Global default measure via setup (recommend 80)
- Deferred: filetype-specific widths when enabling; until then one default is enough
- Do not require a command family to change width on day one; setup is enough for primary jobs

### Affordances and feedback
- One primary command: `:Pencil` toggle
- Success = visible centered column / restored layout
- State for statusline optional later (`on` vs empty); not required for primary jobs
- No plugin keymaps installed
- Config keys stay minimal: e.g. `width` (number), maybe `filetypes` width map only when auto-enable or per-ft width returns

### Implementation notes (intent only, not spec lock)
- Prefer Neovim-native window presentation (existing codebase used soft wrap + statuscolumn padding; redesign may keep or replace as long as UX matches)
- Must not insert hard line breaks
- Must not take over `j`/`gj` or insert undo-break maps
- Must restore owned options exactly on disable

## 5. Non-goals
- Hard mode, textwidth-driven breaking, formatoptions autoformat, suspend/resume autoformat
- Treesitter/syntax “safe autoformat” classification
- Built-in navigation or undo-break keymaps
- Conceal level management
- Drop-in vim-pencil or pre-rewrite pencil.nvim config compatibility
- Auto-enable on filetype (explicitly deferred)
- Release automation, version marketing, distraction-free UI chrome unrelated to measure

## 6. Open questions (non-blocking)
- Exact default width if not 80
- Whether state is buffer-local vs window-local when one buffer has split windows
- Whether a Lua `toggle`/`enable`/`disable` API is exposed in the first slice or only `:Pencil`
- When to reintroduce per-filetype widths vs auto-enable
- Whether a thin statusline helper is worth keeping
