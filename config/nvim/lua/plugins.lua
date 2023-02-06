local fn = vim.fn
local install_path = fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"

-- Bootstrap Packer
if fn.empty(fn.glob(install_path)) > 0 then
  packer_bootstrap = fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/wbthomason/packer.nvim",
    install_path,
  })
end

-- Run PackerCompile whenever we edit this file with `nvim`.
vim.cmd([[
  augroup packer_user_config
  autocmd!
  autocmd BufWritePost plugins.lua source <afile> | PackerCompile
  augroup end
]])

return require("packer").startup(function(use)
  -- Packer can manage itself
  use("wbthomason/packer.nvim")

  -- From VimPlug:
  use("machakann/vim-Verdin") -- ??autocomplete for vimscript
  use("guns/xterm-color-table.vim") -- color table
  use("junegunn/fzf") -- do fzf#install
  use("junegunn/fzf.vim") -- do fzf#install
  use("Vimjas/vim-python-pep8-indent") -- sane indentation for python
  use("easymotion/vim-easymotion")  -- move quickly; bindings at bottom

  use({
    "voldikss/vim-floaterm",
    config = function()
      vim.g.floaterm_keymap_new = '<F7>'
      vim.g.floaterm_keymap_prev = '<F8>'
      vim.g.floaterm_keymap_next = '<F9>'
      vim.g.floaterm_keymap_toggle = '<F5>'
      vim.g.floaterm_position = 'center'
      vim.g.floaterm_width = 0.6
    end
  })
  use("dylon/vim-antlr")
  use("solarnz/thrift.vim")
  use("qpkorr/vim-bufkill")
  use("wesQ3/vim-windowswap")

  -- use("numirias/semshi")
  -- Maybe it's time to say goodbye to Semshi

  use("gburca/vim-logcat")
  -- End VimPlug

  use("bfredl/nvim-luadev")

  use("neovim/nvim-lspconfig")

  use({
    "nvim-treesitter/nvim-treesitter",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "bash", "c", "cpp", "lua", "rust", "javascript", "cmake", "comment", "go", "java", "javascript", "json", "make", "python", "regex", "vim", "yaml", "kotlin",
        },
        highlight = {
          enable = true,
          disable = { "latex" },
        },
        indent = {
          enable = true,
          disable = { "python", "latex" },
        },
      })
    end,
  })
  use("nvim-treesitter/nvim-treesitter-textobjects")
  use 'nvim-treesitter/playground'


  use({
    "jose-elias-alvarez/null-ls.nvim",
    requires = { "nvim-lua/plenary.nvim" },
  })

  -- Can see LSP symbols or something, somewhere
  -- use({
  --   "liuchengxu/vista.vim",
  --   config = function()
  --     vim.g.vista_default_executive = "nvim_lsp"
  --     vim.g.vista_sidebar_position = "vertical topleft"
  --   end,
  -- })

  use("honza/vim-snippets")
  use({
    "L3MON4D3/LuaSnip",
    tag = "v<CurrentMajor>.*",
    config = function()
      local ls = require("luasnip")
      ls.config.set_config({
        region_check_events = "InsertEnter",
        delete_check_events = "TextChanged,InsertLeave",
      })
      require("luasnip.loaders.from_snipmate").lazy_load({paths = "./snippets"})
      require("luasnip.loaders.from_snipmate").load({paths = "./private/snippets"})
      require("luasnip.loaders.from_lua").load({paths = "./snippets"})
    end,
  })

  use({
    "hrsh7th/nvim-cmp",
    requires = { "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer" },
    after = "LuaSnip",
    config = function()
      -- vim.opt.completeopt = { "menu", "menuone", "noselect" }

      local luasnip = require("luasnip")
      local cmp = require("cmp")
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = {
          ["<C-p>"] = cmp.mapping.select_prev_item(),
          ["<C-n>"] = cmp.mapping.select_next_item(),
          ["<C-d>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.close(),
          ["<C-y>"] = cmp.mapping.confirm {
            behavior = cmp.ConfirmBehavior.Insert,
            select = true,
          },
          ["<CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
          }),
          ["<Tab>"] = function(fallback)
            if cmp.visible() then
              cmp.confirm()
              -- cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end,
          ["<S-Tab>"] = function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end,
        },
        sources = {
          { name = "luasnip", priority = 8},
          { name = "nvim_lsp" },
          { name = "nvim_lua" },
          { name = "path" },
          { name = "buffer", keyword_length = 5 },
        },
        view = {
          entries = "custom",
        },
      })


      -- cmp.setup.cmdline('/', {
      --   mapping = cmp.mapping.preset.cmdline(),
      --   sources = {
      --     { name = 'buffer' }
      --   }
      -- })

      -- -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
      -- cmp.setup.cmdline(':', {
      --   mapping = cmp.mapping.preset.cmdline(),
      --   sources = cmp.config.sources({
      --     { name = 'path' }
      --   }, {
      --       { name = 'cmdline' }
      --     })
      -- })
    end,
  })

  use "hrsh7th/cmp-path"
  use "hrsh7th/cmp-nvim-lua"
  use "hrsh7th/cmp-cmdline"

  use({
    "saadparwaiz1/cmp_luasnip",
    after = "nvim-cmp",
  })

  use({
    "windwp/nvim-autopairs",
    after = "nvim-cmp",
    config = function()
      require("nvim-autopairs").setup({})

      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      local cmp = require("cmp")
      cmp.event:on(
        "confirm_done",
        cmp_autopairs.on_confirm_done({ map_char = { tex = "" } })
      )
    end,
  })

  use({
    "nvim-telescope/telescope.nvim",
    requires = { "nvim-lua/plenary.nvim" },
    config = function()
      -- Allow multi select https://github.com/nvim-telescope/telescope.nvim/issues/1048
      local actions = require("telescope.actions")
      local action_state = require("telescope.actions.state")
      local custom_actions = {}

      function custom_actions._multiopen(prompt_bufnr, open_cmd)
        local picker = action_state.get_current_picker(prompt_bufnr)
        local num_selections = #picker:get_multi_selection()
        if num_selections > 1 then
          local cwd = picker.cwd
          if cwd == nil then
            cwd = ""
          else
            cwd = string.format("%s/", cwd)
          end
          vim.cmd("bw!") -- wipe the prompt buffer
          for _, entry in ipairs(picker:get_multi_selection()) do
            vim.cmd(string.format("%s %s%s", open_cmd, cwd, entry.value))
          end
          vim.cmd("stopinsert")
        else
          if open_cmd == "vsplit" then
            actions.file_vsplit(prompt_bufnr)
          elseif open_cmd == "split" then
            actions.file_split(prompt_bufnr)
          elseif open_cmd == "tabe" then
            actions.file_tab(prompt_bufnr)
          else
            actions.select_default(prompt_bufnr)
          end
        end
      end
      function custom_actions.multi_selection_open_vsplit(prompt_bufnr)
        custom_actions._multiopen(prompt_bufnr, "vsplit")
      end
      function custom_actions.multi_selection_open_split(prompt_bufnr)
        custom_actions._multiopen(prompt_bufnr, "split")
      end
      function custom_actions.multi_selection_open_tab(prompt_bufnr)
        custom_actions._multiopen(prompt_bufnr, "tabe")
      end
      function custom_actions.multi_selection_open(prompt_bufnr)
        custom_actions._multiopen(prompt_bufnr, "edit")
      end

      require("telescope").setup({
        defaults = {
          mappings = {
            i = {
              ["<esc>"] = actions.close,
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
              ["<tab>"] = actions.toggle_selection
                + actions.move_selection_next,
              ["<s-tab>"] = actions.toggle_selection
                + actions.move_selection_previous,
              ["<cr>"] = custom_actions.multi_selection_open,
              ["<c-v>"] = custom_actions.multi_selection_open_vsplit,
              ["<c-s>"] = custom_actions.multi_selection_open_split,
              ["<c-t>"] = custom_actions.multi_selection_open_tab,
            },
            n = {
              ["<esc>"] = actions.close,
              ["<tab>"] = actions.toggle_selection
                + actions.move_selection_next,
              ["<s-tab>"] = actions.toggle_selection
                + actions.move_selection_previous,
              ["<cr>"] = custom_actions.multi_selection_open,
              ["<c-v>"] = custom_actions.multi_selection_open_vsplit,
              ["<c-s>"] = custom_actions.multi_selection_open_split,
              ["<c-t>"] = custom_actions.multi_selection_open_tab,
            },
          },
        },
      })

      vim.api.nvim_set_keymap(
        "n",
        "<leader><space>",
        [[<cmd>lua require('telescope.builtin').buffers()<CR>]],
        { noremap = true, silent = true }
      )
      vim.api.nvim_set_keymap(
        "n",
        "<leader>sf",
        [[<cmd>lua require('telescope.builtin').find_files({previewer = false})<CR>]],
        { noremap = true, silent = true }
      )
      vim.api.nvim_set_keymap(
        "n",
        "<leader>sb",
        [[<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>]],
        { noremap = true, silent = true }
      )
    end,
  })

  use({
    "folke/which-key.nvim",
    config = function()
      require("which-key").setup({ })
    end,
  })

  use("folke/trouble.nvim")

  use("tpope/vim-commentary")
  use("tpope/vim-surround")
  use("tpope/vim-repeat")

  --use({
  --  "akinsho/bufferline.nvim",
  --  requires = { "kyazdani42/nvim-web-devicons" },
  --  --after = "tokyonight.nvim",
  --  config = function()
  --    --local colors = require("tokyonight.colors").setup({})

  --    require("bufferline").setup({
  --      options = {
  --        separator_style = "slant",
  --        offsets = {
  --          {
  --            filetype = "NvimTree",
  --            text = "File Explorer",
  --            highlight = "Directory",
  --            text_align = "left",
  --          },
  --        },
  --      },
  --      --highlights = {
  --      --  fill = {
  --      --    guibg = colors.bg_statusline,
  --      --  },
  --      --  separator = {
  --      --    guifg = colors.bg_statusline,
  --      --  },
  --      --  separator_selected = {
  --      --    guifg = colors.bg_statusline,
  --      --  },
  --      --  separator_visible = {
  --      --    guifg = colors.bg_statusline,
  --      --  },
  --      --},
  --    })

  --    vim.api.nvim_set_keymap(
  --      "n",
  --      "gn",
  --      ":BufferLineCycleNext<CR>",
  --      { noremap = true, silent = true }
  --    )
  --    vim.api.nvim_set_keymap(
  --      "n",
  --      "gp",
  --      ":BufferLineCyclePrev<CR>",
  --      { noremap = true, silent = true }
  --    )
  --    vim.api.nvim_set_keymap(
  --      "n",
  --      "gq",
  --      ":BufferLinePickClose<CR>",
  --      { noremap = true, silent = true }
  --    )
  --    vim.api.nvim_set_keymap(
  --      "n",
  --      "gh",
  --      ":BufferLinePick<CR>",
  --      { noremap = true, silent = true }
  --    )
  --    vim.api.nvim_set_keymap(
  --      "n",
  --      "gb",
  --      ":b#<CR>",
  --      { noremap = true, silent = true }
  --    )
  --    vim.api.nvim_set_keymap(
  --      "n",
  --      "g]",
  --      ":BufferLineMoveNext<CR>",
  --      { noremap = true, silent = true }
  --    )
  --    vim.api.nvim_set_keymap(
  --      "n",
  --      "g[",
  --      ":BufferLineMovePrev<CR>",
  --      { noremap = true, silent = true }
  --    )
  --  end,
  --})
  --

  use({
    "nvim-lualine/lualine.nvim",
    requires = "kyazdani42/nvim-web-devicons",
    config = function()
      local onelight = require("lualine.themes.onelight")


      require("lualine").setup({
        options = {
          theme = onelight,
        },
        sections = {
          lualine_b = {
            "diff"
          },
          lualine_c = {
            {
              "filename",
              path = 1,
            },
          },
          lualine_x = { 'encoding', 'filetype' }
        },
      })
    end,
  })

  use({
    "kyazdani42/nvim-tree.lua",
    requires = "kyazdani42/nvim-web-devicons",
    config = function()
      require("nvim-tree").setup({
        view = {
          adaptive_size = true,
        },
        actions = {
          open_file = {
            window_picker = {
              enable = false,
            },
          },
        },
      })
      local wk = require("which-key")
      wk.register({
        f = { name = " file tree",
          f = {':NvimTreeFocus' .. '<CR>', "focus tree" },
          t = {':NvimTreeToggle' .. '<CR>', "show tree" },
          c = {':NvimTreeFindFile' .. '<CR>', "show current"},
          h = {':NvimTreeCollapse' .. '<CR>', "collapse (hide) folder"}
        },
      }, { prefix = '<localleader>'})

    end,
  })

  use({
    "ggandor/leap.nvim",
    config = function()
      require("leap").set_default_keymaps()
    end
  })

  use({
    "ggandor/flit.nvim",
    config = function()
      require("flit").setup()
    end
  })

  use 'williamboman/nvim-lsp-installer'

  -- Possibly of limited usefulness...
  use({
    "andrewferrier/debugprint.nvim",
    config = function()
      require("debugprint").setup()
    end
  })

  use({
    "folke/paint.nvim",
    config = function()
      require("paint").setup({
        ---@type PaintHighlight[]
        highlights = {
          {

            -- filter can be a table of buffer options that should match,
            -- or a function called with buf as param that should return true.
            -- any use of @nocommit will become colored red
            filter = function() return true end,
            pattern = "@nocommit.*",
            hl = "Todo",
          },
          -- {
          --   -- bash variables
          --   filter = { filetype = bash },
          --   pattern = "$[%l_-]+",
          --   hl = "XcodeTeal",
          -- },
          -- {
          --   -- bash variables
          --   filter = { filetype = bash },
          --   pattern = "${.+}",
          --   hl = "XcodeTeal",
          -- },
        },
      })
    end,
  })

  use({
    "folke/persistence.nvim",
    event = "BufReadPre", -- this will only start session saving when an actual file was opened
    module = "persistence",
    config = function()
      require("persistence").setup()
    end,
  })


  if os.getenv("ENABLE_PRIVATE_FACEBOOK")
  then
    use({ "/usr/share/fb-editor-support/nvim", as = "meta.nvim" })
  end

  if packer_bootstrap then
    require("packer").sync()
  end
end)
