# Neovim Configuration Audit - TODO

## Critical Issues (Bugs)

1. [x] **Deprecated API: `vim.lsp.get_active_clients()`** - `lsp.lua:22,36`
   - `vim.lsp.get_active_clients()` is deprecated in Neovim 0.10+
   - Replace with `vim.lsp.get_clients()`

2. [ ] **Bug in `create_scratch_buffer`** - `utils.lua:15-17`
   - `buf.bufnr()` is invalid - `nvim_create_buf` returns a buffer number directly, not a table
   - Use `buf` directly: `vim.bo[buf].buftype = "nofile"` etc.

3. [x] **Broken reload mappings** - `mappings.lua:115-119`
   - Module names passed without quotes: `lua_init`, `lsp`, etc. are undefined variables
   - Wrap module names in quotes: `"lua_init"`, `"lsp"`, etc.

## Medium Priority (Inconsistencies & Deprecated Patterns)

4. [ ] **Conflicting `termguicolors` settings**
   - `init.vim:9` sets `notermguicolors`
   - `options.lua:44` conditionally sets `termguicolors = true`
   - The Lua setting runs later, potentially overriding the VimScript intent
   - Decide on one approach and consolidate

5. [ ] **Duplicate indentation logic**
   - VimScript functions `SetIndentTwo()`/`SetIndentFour()` in `init.vim:38-45`
   - Lua function `set_tabs()` in `options.lua:4-8`
   - Also `ftplugin/*.lua` files set indentation
   - Consolidate to one approach (preferably ftplugin or Lua)

6. [ ] **Mixed VimScript/Lua autocmds**
   - `init.vim:24-36` uses VimScript autocmds
   - LSP/other code uses Lua autocmds
   - Migrate all to Lua `vim.api.nvim_create_autocmd()`

7. [ ] **Duplicate icon plugin dependencies**
   - `nvim-tree.lua` uses `kyazdani42/nvim-web-devicons`
   - `lualine.nvim` uses `kyazdani42/nvim-web-devicons`
   - `oil.nvim` uses `nvim-mini/mini.icons`
   - Pick one icon provider consistently

8. [ ] **`<C-k>` mapping conflict** - `lsp.lua:63` vs `mappings.lua:21`
   - LSP maps `<C-k>` to `signature_help`
   - Mappings maps `<C-K>` to window movement
   - Potential conflict depending on terminal

9. [ ] **tree-climber mappings reference non-existent plugin** - `mappings.lua:107-110`
   - `tree-climber` is not in the plugin list
   - Either add the plugin or remove the mappings

10. [ ] **Old `nvim_set_keymap` API** - `mappings.lua:16-22`
    - Prefer `vim.keymap.set()` which is more ergonomic

11. [ ] **VimScript commands that have Lua equivalents** - `mappings.lua:8-11`
    - `cmd("command! WQ wq")` etc.
    - Use `vim.api.nvim_create_user_command` instead

## Plugin Issues

12. [ ] **trouble.nvim marked as not working** - `monolithic.lua:136`
    - Comment says "Doesn't work: I get errors. maybe try again later"
    - Either fix it or remove it

13. [ ] **Lazy-loaded plugins with no load trigger** - `monolithic.lua`
    - `vim-floaterm` is `lazy = true` but keymaps set in config (won't work until loaded)
    - `vim-antlr`, `thrift.vim`, `vim-bufkill`, `vim-windowswap`, `vim-logcat` marked lazy with no trigger
    - Add `keys`, `ft`, or `cmd` triggers, or remove `lazy = true`

14. [ ] **cmp sources missing explicit dependencies** - `monolithic.lua:100-106`
    - `nvim_lua` and `path` sources listed
    - `cmp-nvim-lua` and `cmp-path` exist as plugins but not in nvim-cmp's dependencies list

15. [ ] **`cmp-cmdline` never configured** - `monolithic.lua:116`
    - Plugin is declared but `cmp.setup.cmdline()` is never called

16. [ ] **Yanky `<c-p>` potential conflict** - `monolithic.lua:331`
    - Yanky maps `<C-p>` in normal mode
    - cmp maps `<C-p>` in insert mode
    - Should be fine but worth noting

## Cleanup (Low Priority)

17. [ ] **Dead/commented code to remove**
    - `init.vim:21-22`: commented autocmd for JSON comments
    - `monolithic.lua:56`: commented completeopt
    - `monolithic.lua:288-300`: commented bash highlighting patterns

18. [ ] **Unused exports to remove**
    - `options.lua` exports `M.set_tabs` but it's not used elsewhere
    - `lsp.lua` exports `M.on_attach` that's now empty (kept for backwards compat)

19. [ ] **Resolve existing TODOs in code**
    - `init.vim:12`: "TODO: set this in lua" (noswapfile/nobackup)
    - `init.vim:77`: "TODO: move to lua?" (DeleteHiddenBuffers function)
    - ~`init.vim:87`: "TODO: remove" (ViewDiff function)~ DONE
    - `mappings.lua:4`: "TODO: refactor this file into multiple files"

20. [ ] **Migrate init.vim to init.lua**
    - Stop using init.vim entirely
    - Migrate all remaining VimScript to Lua
    - Eliminates the need to `:source` VimScript separately

21. [x] **Use Telescope to pick module to reload**
    - Instead of hardcoded `\rvo`, `\rvl`, etc. mappings
    - Single binding that opens Telescope picker with available config modules
    - Select module to reload with `R()`

22. [ ] **Install `fd` for Telescope**
    - Telescope recommends `sharkdp/fd` for faster file finding
    - Add to bootstrap.sh or document as a dependency

23. [ ] **debugprint.nvim uses deprecated `vim.validate` API**
    - Will break in Neovim 1.0
    - Check for plugin updates or report issue upstream
    - Consider removing if not actively used

24. [ ] **Keybinding conflict: `<Leader>r` overlaps with `<Leader>rwp`**
    - `<Leader>r` clears search highlighting (init.vim:65)
    - `<Leader>rwp` is from debugprint.nvim
    - Remap one of them to avoid delay
