# pencil.nvim

A Neovim-native writing plugin for wrapping, formatting, and focused prose editing. It requires **Neovim 0.10 or newer**, does not support Vim, and has no required runtime dependencies.

## Installation

With lazy.nvim:

```lua
return { "jrswab/pencil.nvim" }
```

Or, to enable automatic prose filetype activation:

```lua
return { "jrswab/pencil.nvim", opts = {} }
```

A bare declaration loads the built-in defaults for direct `:Pencil` commands and Lua calls, but does **not** start automatic filetype activation. `opts = {}` calls `require("pencil").setup({})` and enables the built-in prose filetype set on `FileType`.

Other plugin managers can install the repository at <https://github.com/jrswab/pencil.nvim>; keep it on Neovim's `runtimepath`.

## Configuration

```lua
require("pencil").setup({
  mode = "detect", fallback = "soft", textwidth = 80,
  autoformat = true,
  conceal = { level = 2, cursor = "" },
  mappings = { navigation = true, undo_breaks = true },
})
```

The built-in policies are `gitcommit`/`mail` hard at 72 columns; `markdown`/`text` detect with soft fallback; `rst`/`tex`/`asciidoc` detect with hard fallback at 79; and `textile` detect with soft fallback. The exhaustive schemas, precedence rules, classifiers, and validation rules are in [`:help pencil-configuration`](doc/pencil.txt).

## Quick start

Open a prose buffer and enable Pencil for the current buffer:

```vim
:Pencil
```

Or enable it from Lua, omitting options to target the current buffer:

```lua
require("pencil").enable()
```

## API and commands

```lua
local pencil = require("pencil")
pencil.enable({ mode = "hard" })
pencil.toggle()
pencil.set_autoformat("suspend")
print(pencil.mode(), pencil.status())
```

The public controls are `setup`, `enable`, `disable`, `toggle`, `set_autoformat`, `mode`, and `status`. The unified command is `:Pencil` with `enable`, `disable`, `toggle`, `hard`, `soft`, `detect`, and `format enable|disable|toggle|suspend`. Aliases include `:HardPencil`, `:SoftPencil`, `:NoPencil`, `:PencilOff`, `:TogglePencil`, `:PencilToggle`, `:PFormat`, `:PFormatOff`, and `:PFormatToggle`.

## Statusline

Pencil never changes the statusline. Add its indicator to lualine or a custom statusline:

```lua
{ function() return require("pencil").status() end }
```

`S` means enabled soft mode, `A` means hard formatting is armed and eligible, `H` means hard formatting is disabled, suspended, protected, unknown, or no longer owned, and the configured `off` value means disabled.

## Safety

Pencil restores the exact buffer and window-local values it still owns and preserves edits made externally while active. Presentation is tracked independently for every window, including windows opened after activation. In soft mode, Pencil owns the presentation and width-dependent `statuscolumn` padding used to wrap visually near the configured width; it leaves `colorcolumn` unchanged. Hard mode inserts real breaks via `textwidth` and does not soft-wrap. Conflicting mappings are skipped and warned once per key per buffer; they are never replaced or removed. Hard formatting fails closed for protected or unknown structured content. Conceal defaults to level 2 with markup visible on the cursor line and can be disabled with `conceal = false`. Routine activation and suspension are quiet; notifications are reserved for invalid input, explicit failures, and mapping conflicts.

## Migration

This is a clean Neovim redesign inspired by [`preservim/vim-pencil`](https://github.com/preservim/vim-pencil), not a drop-in Vim/Vimscript port. Use `require("pencil").setup({...})` instead of `g:pencil#...`, the documented Lua API and `:Pencil` commands instead of `Mapkey()` or legacy `:DropPencil`, and Lua filetype policies/classifiers. Expect exact ownership/restoration and conflict-safe mappings; use `pencil.status()` for statusline integration. Vim and legacy compatibility commands, options, mappings, formatting quirks, and syntax groups are not supported promises.

## Attribution and license

pencil.nvim is distributed under the repository's [MIT License](LICENSE), including the existing `Copyright (c) 2026 Jaron Swab` notice. It is inspired by the upstream project at <https://github.com/preservim/vim-pencil> without implying endorsement.

For the complete normative reference, see [`:help pencil`](doc/pencil.txt).
