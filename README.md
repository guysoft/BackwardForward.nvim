# BackwardForward.nvim

VS Code-style cursor navigation history (back/forward) for Neovim.

[![Tests](https://github.com/guysoft/BackwardForward.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/guysoft/BackwardForward.nvim/actions/workflows/test.yml)

## Features

- **Custom position stack** — records on buffer switches, large jumps (>10 lines), and cursor idle. Not a thin wrapper around the native jumplist.
- **Mouse back/forward buttons** — X1Mouse/X2Mouse mapped by default.
- **Persistence across sessions** — per-project history saved to disk, restored on startup.
- **Optional bufferline.nvim integration** — ◀ ▶ buttons in the tab bar.
- **User commands** — `:NavigateBack`, `:NavigateForward`.

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "guysoft/BackwardForward.nvim",
  lazy = false,
  config = function()
    require("backward-forward").setup()
  end,
}
```

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "guysoft/BackwardForward.nvim",
  config = function()
    require("backward-forward").setup()
  end,
}
```

## Configuration

All options with their defaults:

```lua
require("backward-forward").setup({
  enabled = true,
  mouse_buttons = true,       -- map X1Mouse/X2Mouse (mouse back/forward)
  bufferline_buttons = false, -- show ◀ ▶ in bufferline.nvim tab bar
  persist = true,             -- save/restore history across sessions (per-project)
  persist_max = 50,           -- max entries to persist to disk
  max_history = 100,          -- max entries in memory
  min_jump_lines = 10,        -- minimum line delta to auto-record within same file
  keys = {
    back = nil,               -- extra keymap for back (native <C-o> still works)
    forward = nil,            -- extra keymap for forward (native <C-i> still works)
  },
})
```

## How It Works

The plugin maintains its own position stack (independent of Neovim's native jumplist). Positions are recorded when:

1. **You switch buffers** — always recorded
2. **You jump >10 lines** in the same file — recorded automatically
3. **Your cursor is idle** (`CursorHold`) — captures where you've been reading/working

When you navigate back/forward, the plugin moves through this stack without adding new entries (preventing the "stuck" oscillation problem).

### Persistence

History is saved per-project (based on `cwd`) to `~/.local/share/nvim/backward-forward/`. On restart, the previous session's history is restored so you can pick up where you left off.

## Bufferline Integration

To show ◀ ▶ buttons in your tab bar:

```lua
require("bufferline").setup({
  options = {
    custom_areas = {
      left = function()
        return require("backward-forward").get_bufferline_components()
      end,
    },
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:NavigateBack` | Go back in cursor position history |
| `:NavigateForward` | Go forward in cursor position history |

## API

```lua
local bf = require("backward-forward")
bf.go_back()          -- navigate backward
bf.go_forward()       -- navigate forward
bf.can_go_back()      -- returns boolean
bf.can_go_forward()   -- returns boolean
```

## License

MIT
