# pencil.nvim

A small Neovim plugin for a centered, comfortably wrapped writing column.
Pencil is a binary, buffer-local presentation state: turn it on when writing,
and turn it off when you want the editor's previous presentation back.

## Requirements

- Neovim 0.10 or newer
- No runtime dependencies

## Installation

Install `jrswab/pencil.nvim` with your preferred plugin manager:

```lua
{ "jrswab/pencil.nvim" }
```

The plugin is also available at <https://github.com/jrswab/pencil.nvim>.
Loading the plugin makes the bare `:Pencil` command available. `setup()` is
optional.

## Usage

```vim
:Pencil
```

Bare `:Pencil` toggles the current buffer. It accepts no arguments and has no
aliases.

The Lua API is:

```lua
local pencil = require("pencil")

pencil.setup({ width = 80 }) -- optional; 80 is the default
pencil.enable()              -- current buffer
pencil.disable()             -- current buffer
pencil.toggle()              -- current buffer

-- Any control function may target another valid buffer:
pencil.enable({ buf = bufnr })
```

`setup(nil)` leaves the current preference unchanged and `setup({})` selects
the default width of 80. The only configuration key is `width`, a positive
integer display-column preference. Unknown keys and invalid values are errors,
and setup is atomic. A width larger than the window contracts safely to the
available text area. Changing setup affects future activations; an active
buffer keeps the width captured when it was enabled.

## Behavior and safety

When enabled, Pencil centers a preferred writing column in every applicable
window, wrapping long lines visually. Empty and short buffers receive the same
column. Wrapping never inserts hard line breaks: buffer contents, including
Unicode and tabs, remain unchanged.

The presentation follows window resize, splits, and buffer/window lifecycle
events. Each window has its own restoration baseline. Disabling restores values
still owned by Pencil exactly; a value changed externally while active is
preserved. Repeated enable and disable operations are idempotent and safe.

Pencil does not provide hard breaks, insert-time autoformat, filetype
auto-enable, per-filetype configuration, mappings, concealment, classifiers,
statusline integration, or compatibility aliases/configuration from older
pencil.nvim or vim-pencil releases.

## License and attribution

pencil.nvim is distributed under the repository's [MIT License](LICENSE),
including `Copyright (c) 2026 Jaron Swab`. It is inspired by
<https://github.com/preservim/vim-pencil> without implying compatibility or
endorsement.
