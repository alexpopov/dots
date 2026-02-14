# Neovim Configuration Audit - TODO

## Critical Issues (Bugs)

1. [x] **Deprecated API: `vim.lsp.get_active_clients()`** - `lsp.lua:22,36`
   - `vim.lsp.get_active_clients()` is deprecated in Neovim 0.10+
   - Replace with `vim.lsp.get_clients()`

2. [x] **Bug in `create_scratch_buffer`** - `utils.lua:15-17`
   - `buf.bufnr()` is invalid - `nvim_create_buf` returns a buffer number directly, not a table
   - Use `buf` directly: `vim.bo[buf].buftype = "nofile"` etc.

3. [x] **Broken reload mappings** - `mappings.lua:115-119`
   - Module names passed without quotes: `lua_init`, `lsp`, etc. are undefined variables
   - Wrap module names in quotes: `"lua_init"`, `"lsp"`, etc.

## Medium Priority (Inconsistencies & Deprecated Patterns)

4. [x] **Conflicting `termguicolors` settings**
   - Removed `notermguicolors` from init.vim
   - options.lua handles termguicolors based on COLORTERM env var
   - Using lua_xcode colorscheme only

5. [x] **Duplicate indentation logic**
   - Removed VimScript SetIndentTwo/SetIndentFour functions
   - All indentation now handled via ftplugin/*.lua files using options.set_tabs()

6. [x] **Mixed VimScript/Lua autocmds**
   - Migrated all autocmds to Lua in init.lua using `vim.api.nvim_create_autocmd()`

7. [x] **Duplicate icon plugin dependencies**
   - Standardized on `kyazdani42/nvim-web-devicons`
   - Changed oil.nvim from mini.icons to nvim-web-devicons

8. [ ] **`<C-k>` mapping conflict** - `lsp.lua` vs `mappings.lua`
   - LSP maps `<C-k>` to `signature_help`
   - Mappings maps `<C-K>` to window movement (keeping for now)
   - TODO in mappings.lua to revisit

9. [x] **tree-climber mappings reference non-existent plugin**
   - Dead reference, never used

10. [x] **Old `nvim_set_keymap` API** - `mappings.lua`
    - Migrated to `vim.keymap.set()` (noremap is default, cleaner syntax)

11. [x] **VimScript commands that have Lua equivalents** - `mappings.lua`
    - Converted `cmd("command! WQ wq")` etc. to `vim.api.nvim_create_user_command`

## Plugin Issues

12. [x] **trouble.nvim marked as not working** - `monolithic.lua:136`
    - Removed stale "doesn't work" comment, config is fine for trouble v3

13. [x] **Lazy-loaded plugins with no load trigger** - `monolithic.lua`
    - Added proper triggers: keys/cmd for floaterm, ft for language plugins, cmd for bufkill

14. [x] **cmp sources missing explicit dependencies**
    - Moved cmp-path and cmp-nvim-lua into nvim-cmp's dependencies list

15. [x] **`cmp-cmdline` never configured**
    - Removed, was dead code

16. [x] **Yanky `<c-p>` potential conflict**
    - Not a real conflict: Yanky is normal mode, cmp is insert mode

## Cleanup (Low Priority)

17. [x] **Dead/commented code to remove**
    - Already cleaned up in previous sessions

18. [x] **Unused exports to remove**
    - `options.set_tabs` IS used by ftplugin files
    - Removed unused `lsp.on_attach` export

19. [x] **Resolve existing TODOs in code**
    - `init.vim:12` noswapfile/nobackup → moved to options.lua
    - `init.vim:77` DeleteHiddenBuffers → moved to utils.lua
    - `mappings.lua:4`: "TODO: refactor this file" remains open

20. [x] **Migrate init.vim to init.lua**
    - Deleted init.vim, created init.lua
    - All config now 100% Lua

21. [x] **Use Telescope to pick module to reload**
    - Instead of hardcoded `\rvo`, `\rvl`, etc. mappings
    - Single binding that opens Telescope picker with available config modules
    - Select module to reload with `R()`

22. [x] **Install `fd` for Telescope**
    - Added to bootstrap.sh late packages with custom Ubuntu installer

23. [x] **debugprint.nvim uses deprecated `vim.validate` API**
    - Removed the plugin entirely (not used)

24. [x] **Keybinding conflict: `<Leader>r` overlaps with `<Leader>rwp`**
    - Resolved by removing debugprint.nvim

## Open

25. [ ] **Delete old vimscript colorschemes** - `colors/`
    - `xcode.vim`, `xcode_new.vim`, `xcode_debug.vim` are legacy files
    - Still reference dead groups like `pythonCustomFunc`
    - Decide: delete or keep for historical reference?

26. [ ] **nvim-autopairs `init` defeats lazy loading** - `monolithic.lua`
    - `init` calls `require('nvim-autopairs.rule')` which forces load before `InsertEnter` event
    - Same bug pattern as nvim-notify (fixed). Move rule setup into `config`.

27. [ ] **`honza/vim-snippets` lazy with no trigger** - `monolithic.lua`
    - `lazy = true` but no `keys`, `ft`, or `cmd` trigger
    - Will never load unless something else requires it. Remove or add trigger.

28. [ ] **Bootstrap: add brew cask installs for Mac apps**
    - Alfred, Maccy, Divvy, Rocket, Karabiner, Hammerspoon, Captin
    - Also skhd, yabai
    - Existing TODO in bootstrap.sh

29. [ ] **Treesitter: make `ensure_installed` configurable**
    - Existing TODO in treesitter.lua
    - Env var to skip parser installation on slow/metered machines?
