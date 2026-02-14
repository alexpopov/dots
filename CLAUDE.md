# dots

Personal dotfiles for alexpopov. Cross-platform (macOS, Ubuntu, Fedora, WSL, Raspberry Pi).

## Structure

```
bootstrap.sh              # Main setup script - installs packages, creates symlinks
config/
  nvim/                   # Neovim config (lazy.nvim plugin manager)
    init.lua              # Entry point - loads lua_init, sets providers
    colors/lua_xcode.lua  # Custom colorscheme (Xcode 5 Presentation Mode, light theme)
    lua/
      lua_init.lua        # Loads: lazy -> options -> mappings -> lsp -> globals
      options.lua         # Editor settings (4-space tabs, relative numbers)
      mappings.lua        # Keybindings (leader=, localleader=\)
      lsp.lua             # LSP config (lua_ls, csharp_ls, null-ls)
      globals.lua         # Debug helpers (P, RELOAD, R)
      utils.lua           # Session management, scratch buffers, buffer cleanup
      config/lazy.lua     # lazy.nvim bootstrap
      plugins/            # Plugin specs (monolithic.lua has most plugins)
    ftplugin/             # Per-filetype settings (lua/cpp=2 spaces)
    ftdetect/             # Custom filetype detection (shader, soong, hgcommit)
  bash/bash_profile.sh    # Shell config (aliases, prompt, PATH, functions)
  tmux/tmux.conf          # Actual tmux config (prefix=C-s, vi mode, 500k history)
  git/                    # Git aliases and gitignore
  skhd/                   # macOS hotkey daemon config
  yabai/                  # macOS tiling window manager config
  hammerspoon/            # macOS automation
  karabiner/              # macOS key remapping
tmux.conf                 # Root-level shim that sources config/tmux/tmux.conf (symlinked to ~/.tmux.conf)
bin/scripts/              # Utility scripts (yabai_utils, tmux_claude, git helpers) -> ~/.local/bin/scripts
```

## Conventions

- **Tabs**: 4 spaces default, 2 spaces for Lua/C++/HLSL (set in ftplugin/)
- **Colorscheme**: Light theme based on Xcode 5 Presentation Mode. Colors defined as `c.xcode_*` variables with both cterm and gui values. Custom `Xcode*` highlight groups are used as link targets.
- **Plugin manager**: lazy.nvim with specs in `lua/plugins/`. Most plugins live in `monolithic.lua`.
- **Leader**: `,` (comma). LocalLeader: `\` (backslash). Set in both `config/lazy.lua` and `mappings.lua` (lazy.nvim needs it early).
- **LSP**: Uses Neovim 0.11+ `vim.lsp.config()` pattern. Mason manages LSP server installs. Keymaps bound via `LspAttach` autocmd.
- **Bootstrap**: `bootstrap.sh` is both sourceable (for helper functions) and executable (full setup). Custom installers are `_install_package_<name>` functions.

## Useful commands

```bash
# Run bootstrap on a new machine
./bootstrap.sh

# Symlinks are created by create_links() in bootstrap.sh
# Main pattern: ~/.config/<name> -> ~/dots/config/<name>
```

## Working with the colorscheme

The colorscheme (`colors/lua_xcode.lua`) has two layers:
1. `group_colors` table: defines highlight groups with explicit fg/bg/cterm values
2. `links` table: links highlight groups to other groups (including treesitter `@` groups)

Custom `Xcode*` groups (XcodeGreen, XcodeTeal, XcodePink, etc.) act as the palette and are the preferred link targets.
