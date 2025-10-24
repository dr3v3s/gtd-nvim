## Dependencies

GTD-Nvim has been designed to be lightweight with minimal dependencies:

### Required Dependencies

#### Core
- **Neovim >= 0.9.0** - Modern Neovim with Lua support

#### Fuzzy Finder (choose one)
GTD-Nvim supports both fuzzy finders with automatic fallback:

**Recommended:**
- **[fzf-lua](https://github.com/ibhagwan/fzf-lua)** - Fast, native fzf integration (primary, 104 integrations)
  ```lua
  { "ibhagwan/fzf-lua" }
  ```

**Alternative:**
- **[telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)** - Popular fuzzy finder (fallback, 22 integrations)
  ```lua
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" }
  }
  ```

### Optional but Recommended

- **[which-key.nvim](https://github.com/folke/which-key.nvim)** - Keybinding hints and menu registration
  ```lua
  { "folke/which-key.nvim" }
  ```
  Used by: GTD keybinding integration

- **[plenary.nvim](https://github.com/nvim-lua/plenary.nvim)** - Lua utility functions
  ```lua
  { "nvim-lua/plenary.nvim" }
  ```
  Required by: Telescope (if using), various utility functions

### UI Enhancement Plugins (Optional)

These plugins enhance the visual experience but are NOT required:

- **[mini.nvim](https://github.com/echasnovski/mini.nvim)** - Collection of minimal plugins
  - `mini.icons` - File type icons
  - `mini.statusline` - Status line integration
  
- **[render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)** - Beautiful markdown rendering in buffers

- **[nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)** or **[oil.nvim](https://github.com/stevearc/oil.nvim)** - File browser integration for navigating GTD directories

### External Tools (System Dependencies)

For full functionality, install these system tools:

**macOS:**
```bash
brew install fzf ripgrep fd
```

**Linux (Debian/Ubuntu):**
```bash
apt install fzf ripgrep fd-find
```

**Arch Linux:**
```bash
pacman -S fzf ripgrep fd
```

- **fzf** - Fuzzy finder (required for fzf-lua)
- **ripgrep** - Fast text search (for live grep)
- **fd** - Fast file finder (for file searches)

### Complete Installation Example

Here's a complete setup with all recommended dependencies:

```lua
{
  "dr3v3s/gtd-nvim",
  dependencies = {
    -- Required: Choose your fuzzy finder
    "ibhagwan/fzf-lua",                    -- Recommended
    -- OR
    -- { 
    --   "nvim-telescope/telescope.nvim",  -- Alternative
    --   dependencies = { "nvim-lua/plenary.nvim" }
    -- },
    
    -- Recommended
    "folke/which-key.nvim",                -- Keybinding hints
    "nvim-lua/plenary.nvim",               -- Utility functions
    
    -- Optional UI enhancements
    "echasnovski/mini.nvim",               -- Icons and statusline
    "MeanderingProgrammer/render-markdown.nvim", -- Pretty markdown
  },
  config = function()
    require("gtd-nvim").setup({
      gtd_dir = vim.fn.expand("~/.gtd/"),
      zk_dir = vim.fn.expand("~/Documents/Notes/"),
    })
  end,
}
```

### Minimal Installation

For a minimal installation with just the essentials:

```lua
{
  "dr3v3s/gtd-nvim",
  dependencies = {
    "ibhagwan/fzf-lua",  -- Just the fuzzy finder
  },
  config = function()
    require("gtd-nvim").setup()
  end,
}
```

The plugin will work with this minimal setup and gracefully handle missing optional dependencies.

