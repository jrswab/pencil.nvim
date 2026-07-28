# ✏️ pencil.nvim

Neovim-native writing tools for focused prose editing, visual wrapping, and safe formatting.

## ✨ Features

- soft mode wraps prose visually near the configured width without inserting breaks
- hard mode inserts real line breaks using `textwidth`
- automatic mode detection for supported prose filetypes
- optional safe automatic formatting for eligible prose
- concealment for markup, with syntax visible on the cursor line
- conflict-safe navigation and undo-break mappings
- exact ownership and restoration of buffer- and window-local settings
- per-buffer controls through a Lua API and unified `:Pencil` commands
- status indicators without changing your statusline
- quiet routine activation, detection, and suspension

## ⚡ Requirements

- **Neovim 0.10 or newer**
- Vim is unsupported
- No required runtime dependencies

## 📦 Installation

Install `jrswab/pencil.nvim` with your preferred plugin manager. With
[lazy.nvim](https://github.com/folke/lazy.nvim), use one of these forms:

### Enable on supported prose filetypes

```lua
return {
  "jrswab/pencil.nvim",
  opts = {},
}
```

`opts = {}` calls `require("pencil").setup({})` and enables the built-in prose
filetype set on `FileType`.

### Enable manually

```lua
return { "jrswab/pencil.nvim" }
```

A bare declaration loads the built-in defaults for direct `:Pencil` commands
and Lua calls, but does not enable automatic filetype activation. Enable a
buffer manually with `:Pencil` or `require("pencil").enable()`.

The repository is available at <https://github.com/jrswab/pencil.nvim>. Other
plugin managers can install it by adding the repository to Neovim's
`runtimepath`.

## ⚙️ Configuration

Call `setup()` once with a configuration table. The defaults are:

```lua
{
  mode = "detect",
  fallback = "soft",
  textwidth = 80,
  autoformat = true,
  conceal = {
    level = 2,
    cursor = "",
  },
  mappings = {
    navigation = true,
    undo_breaks = true,
  },
  status = {
    hard = "H",
    auto = "A",
    soft = "S",
    off = "",
  },
}
```

For example:

```lua
require("pencil").setup({
  mode = "detect",
  fallback = "soft",
  textwidth = 80,
  autoformat = true,
  conceal = { level = 2, cursor = "" },
  mappings = { navigation = true, undo_breaks = true },
})
```

The built-in policies are:

- `gitcommit` and `mail`: hard mode at 72 columns
- `markdown` and `text`: detect with a soft fallback
- `rst`, `tex`, and `asciidoc`: detect with a hard fallback at 79 columns
- `textile`: detect with a soft fallback

Use `filetypes` to replace the automatic activation set, or configure a named
filetype with mode, fallback, textwidth, autoformat, conceal, mappings,
`format_safety = "plain"`, or a classifier. See
[`:help pencil-configuration`](doc/pencil.txt) for the complete schema,
precedence rules, and validation behavior.

## 🚀 Usage

Enable Pencil for the current buffer:

```vim
:Pencil
```

Or use Lua:

```lua
local pencil = require("pencil")

pencil.enable()                 -- detect the mode for the current buffer
pencil.enable({ mode = "soft" })
pencil.toggle()
pencil.set_autoformat("suspend")
print(pencil.mode(), pencil.status())
```

`enable`, `disable`, `toggle`, `mode`, `status`, and `set_autoformat` accept an
optional `{ buf = bufnr }` table to target another valid buffer. `enable({})`
targets the current buffer with no per-call overrides.

### Commands

`:Pencil` detects the mode. The unified command also supports:

```text
:Pencil enable|disable|toggle|hard|soft|detect
:Pencil format enable|disable|toggle|suspend
```

Aliases are `:HardPencil`, `:SoftPencil`, `:NoPencil`, `:PencilOff`,
`:TogglePencil`, `:PencilToggle`, `:PFormat`, `:PFormatOff`, and
`:PFormatToggle`.

## 📊 Statusline

Pencil never changes the statusline. Add its indicator to lualine or a custom
statusline:

```lua
{ function() return require("pencil").status() end }
```

`S` means enabled soft mode. `A` means hard formatting is armed, eligible, and
Pencil-owned. `H` means hard formatting is disabled, suspended, protected,
unknown, or no longer owned. The configured `off` value means disabled. If you
customize `status`, use `pencil.status()` rather than checking these letters.

## 🛡️ Safety and tips

- Soft mode owns the presentation and width-dependent `statuscolumn` padding
  used to wrap visually near the configured width. It leaves `colorcolumn`
  unchanged.
- Hard mode uses `textwidth` and inserts real breaks; it does not soft-wrap.
- Settings changed externally while Pencil is active are preserved. Disable
  restores only exact values still owned by Pencil.
- Presentation is tracked independently for every window, including windows
  opened after activation.
- Conflicting mappings are skipped and warned once per key per buffer; they are
  never replaced or removed.
- Hard formatting fails closed for protected or unknown structured content.
- Set `conceal = false` to opt out of concealment. Routine activation and
  suspension are quiet; notifications are reserved for invalid input, explicit
  failures, and mapping conflicts.

For the normative reference, including classifier details and modeline behavior,
see [`:help pencil`](doc/pencil.txt).

## 🔄 Migration

This is a clean Neovim redesign inspired by
[`preservim/vim-pencil`](https://github.com/preservim/vim-pencil), not a drop-in
Vim/Vimscript port. Use `require("pencil").setup({...})` instead of
`g:pencil#...`, the Lua API and `:Pencil` commands instead of `Mapkey()` or
legacy `:DropPencil`, and Lua filetype policies/classifiers. Expect exact
ownership/restoration and conflict-safe mappings; old options, commands,
mappings, formatting quirks, and syntax groups are not supported promises.

## 📄 License and attribution

pencil.nvim is distributed under the repository's [MIT License](LICENSE),
including the existing `Copyright (c) 2026 Jaron Swab` notice. It is inspired
by the upstream project at
<https://github.com/preservim/vim-pencil> without implying endorsement.
