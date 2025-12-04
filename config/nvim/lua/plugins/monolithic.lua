local specs = {
  { "guns/xterm-color-table.vim" }, -- color table
  -- { "junegunn/fzf",                 dir = "~/.fzf", build = "./install --all" },
  { "junegunn/fzf.vim" },
  { "Vimjas/vim-python-pep8-indent" }, -- sane indentation for python
  {
    "voldikss/vim-floaterm",
    lazy = true,
    config = function()
      vim.g.floaterm_keymap_new = '<F7>'
      vim.g.floaterm_keymap_prev = '<F8>'
      vim.g.floaterm_keymap_next = '<F9>'
      vim.g.floaterm_keymap_toggle = '<F5>'
      vim.g.floaterm_position = 'center'
      vim.g.floaterm_width = 0.6
    end,
  },

  { "dylon/vim-antlr",      lazy = true, },
  { "solarnz/thrift.vim",   lazy = true, },
  { "qpkorr/vim-bufkill",   lazy = true, },
  { "wesQ3/vim-windowswap", lazy = true, },
  { "gburca/vim-logcat",    lazy = true, },

  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
  },

  {
    "honza/vim-snippets",
    lazy = true,
  },
  {
    "L3MON4D3/LuaSnip",
    lazy = true,
    version = "v2.*",
    enabled = true,
    build = "make install_jsregexp",
    config = function()
      local ls = require("luasnip")
      ls.config.set_config({
        region_check_events = "InsertEnter",
        delete_check_events = "TextChanged,InsertLeave",
      })
      require("luasnip.loaders.from_snipmate").lazy_load({ paths = "./snippets" })
      require("luasnip.loaders.from_snipmate").load({ paths = "./private/snippets" })
      require("luasnip.loaders.from_lua").load({ paths = "./snippets" })
    end,
  },

  {
    "hrsh7th/nvim-cmp",
    dependencies = { "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer", "L3MON4D3/LuaSnip", },
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
          { name = "luasnip", priority = 8 },
          { name = "nvim_lsp" },
          { name = "nvim_lua" },
          { name = "path" },
          { name = "buffer",  keyword_length = 5 },
        },
        view = {
          entries = "custom",
        },
      })
    end,
  },

  { "hrsh7th/cmp-path" },
  { "hrsh7th/cmp-nvim-lua" },
  { "hrsh7th/cmp-cmdline" },

  {
    "saadparwaiz1/cmp_luasnip",
    dependencies = "nvim-cmp",
  },

  {
    'windwp/nvim-autopairs',
    event = "InsertEnter",
    config = true
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },

  {
    -- Doesn't work: I get errors. maybe try again later
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = {},
    keys = {
      {
        "<leader>txx",
        "<cmd>Trouble diagnostics toggle<cr>",
        desc = "Diagnostics (Trouble)",
      },
      {
        "<leader>txX",
        "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
        desc = "Buffer Diagnostics (Trouble)",
      },
      {
        "<leader>tcs",
        "<cmd>Trouble symbols toggle focus=false<cr>",
        desc = "Symbols (Trouble)",
      },
      {
        "<leader>tcl",
        "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
        desc = "LSP Definitions / references / ... (Trouble)",
      },
      {
        "<leader>txL",
        "<cmd>Trouble loclist toggle<cr>",
        desc = "Location List (Trouble)",
      },
      {
        "<leader>txQ",
        "<cmd>Trouble qflist toggle<cr>",
        desc = "Quickfix List (Trouble)",
      },
    },
  },

  { "tpope/vim-commentary" },
  { "tpope/vim-repeat" },
  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup({
        -- Configuration here, or leave empty to use defaults
      })
    end,
  },


  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "kyazdani42/nvim-web-devicons" },
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
  },

  {
    "kyazdani42/nvim-tree.lua",
    dependencies = { "kyazdani42/nvim-web-devicons", "folke/which-key.nvim" },
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
      wk.add(
        {
          { "<localleader>f",  group = " file tree" },
          { "<localleader>fc", ":NvimTreeFindFile<CR>", desc = "show current" },
          { "<localleader>ff", ":NvimTreeFocus<CR>",    desc = "focus tree" },
          { "<localleader>fh", ":NvimTreeCollapse<CR>", desc = "collapse (hide) folder" },
          { "<localleader>ft", ":NvimTreeToggle<CR>",   desc = "show tree" },
        }
      )
    end,
  },

  {
    "ggandor/leap.nvim",
    config = function()
      local leap = require("leap")
      vim.keymap.set({'n', 'x', 'o'}, 's', function ()
          leap.leap {}
      end)
      vim.keymap.set({'n', 'x', 'o'}, 'S', function ()
          leap.leap {backward = true}
      end)
      leap.opts.equivalence_classes = { ' \t\r\n', '([{', ')]}', '\'"`' }
    end
  },
  {
    "ggandor/flit.nvim",
    config = function() require("flit").setup() end
  },

  -- Possibly of limited usefulness...
  {
    "andrewferrier/debugprint.nvim",
    opts = {},
    lazy = false,
    version = '*',
  },
  {
    'echasnovski/mini.nvim',
    version = '*'
  },
  { "mechatroner/rainbow_csv" },

  {
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
  },

  {
    "folke/persistence.nvim",
    event = "BufReadPre", -- this will only start session saving when an actual file was opened
    opts = {},
  },

  { "powerman/vim-plugin-AnsiEsc" },

  -- Open alternative files for the current buffer
  {
    "rgroli/other.nvim",
    config = function()
      require("other-nvim").setup({})
    end,
  },

  {
    "gbprod/yanky.nvim",
    config = function()
      require("yanky").setup({})
      vim.keymap.set({ "n", "x" }, "p", "<Plug>(YankyPutAfter)")
      vim.keymap.set({ "n", "x" }, "P", "<Plug>(YankyPutBefore)")
      vim.keymap.set({ "n", "x" }, "gp", "<Plug>(YankyGPutAfter)")
      vim.keymap.set({ "n", "x" }, "gP", "<Plug>(YankyGPutBefore)")
      vim.keymap.set("n", "<c-n>", "<Plug>(YankyCycleForward)")
      vim.keymap.set("n", "<c-p>", "<Plug>(YankyCycleBackward)")
    end,
  },
  {
    'stevearc/oil.nvim',
    ---@module 'oil'
      ---@type oil.SetupOpts
      opts = {},
    -- Optional dependencies
      dependencies = { { "nvim-mini/mini.icons", opts = {} } },
    -- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if you prefer nvim-web-devicons
      -- Lazy loading is not recommended because it is very tricky to make it work correctly in all situations.
      lazy = false,
  }

}

return specs
