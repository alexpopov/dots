local specs = {
  {"machakann/vim-Verdin"},          -- ??autocomplete for vimscript
  {"guns/xterm-color-table.vim"},    -- color table
  {"junegunn/fzf", dir = "~/.fzf", build = "./install --all" },
  {"junegunn/fzf.vim"},
  {"Vimjas/vim-python-pep8-indent"}, -- sane indentation for python
  {"easymotion/vim-easymotion"},     -- move quickly; bindings at bottom
  {"neoclide/jsonc.vim"},

  {
    "voldikss/vim-floaterm",
    config = function()
      vim.g.floaterm_keymap_new = '<F7>'
      vim.g.floaterm_keymap_prev = '<F8>'
      vim.g.floaterm_keymap_next = '<F9>'
      vim.g.floaterm_keymap_toggle = '<F5>'
      vim.g.floaterm_position = 'center'
      vim.g.floaterm_width = 0.6
    end,
  },

  {"dylon/vim-antlr"},
  {"solarnz/thrift.vim"},
  {"qpkorr/vim-bufkill"},
  {"wesQ3/vim-windowswap"},
  {"gburca/vim-logcat"},

  {"bfredl/nvim-luadev"},

  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
  },

  {"honza/vim-snippets"},
  {
    "L3MON4D3/LuaSnip",
    lazy = true,
    enabled = false,
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
    dependencies = { "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer", "LuaSnip", },
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

  { "hrsh7th/cmp-path"},
  { "hrsh7th/cmp-nvim-lua"},
  { "hrsh7th/cmp-cmdline"},

  {
    "saadparwaiz1/cmp_luasnip",
    dependencies = "nvim-cmp",
  },

  {
    "windwp/nvim-autopairs",
    dependencies = "nvim-cmp",
    config = function()
      require("nvim-autopairs").setup({})

      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      local cmp = require("cmp")
      cmp.event:on(
      "confirm_done",
      cmp_autopairs.on_confirm_done({ map_char = { tex = "" } })
      )
    end,
  },

  {
    'nvim-telescope/telescope-fzf-native.nvim',
    build = 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release'
  },


  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "junegunn/fzf", },
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
          layout_strategy = "vertical",
        },
        extensions = {
          fzf = {
            fuzzy = true,                   -- false will only do exact matching
            override_generic_sorter = true, -- override the generic sorter
            override_file_sorter = true,    -- override the file sorter
            case_mode = "smart_case",       -- or "ignore_case" or "respect_case"
            -- the default case_mode is "smart_case"
          }
        }
      })

      -- vim.api.nvim_set_keymap(
      --   "n",
      --   "<leader><space>",
      --   [[<cmd>lua require('telescope.builtin').buffers()<CR>]],
      --   { noremap = true, silent = true }
      -- )
      -- vim.api.nvim_set_keymap(
      --   "n",
      --   "<leader>sf",
      --   [[<cmd>lua require('telescope.builtin').find_files({previewer = false})<CR>]],
      --   { noremap = true, silent = true }
      -- )
      -- vim.api.nvim_set_keymap(
      --   "n",
      --   "<leader>sb",
      --   [[<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>]],
      --   { noremap = true, silent = true }
      -- )
    end,
  },


  {
    "folke/which-key.nvim",
    config = function()
      require("which-key").setup({})
    end,
  },

  {"folke/trouble.nvim"},

  {"tpope/vim-commentary"},
  {"tpope/vim-surround"},
  {"tpope/vim-repeat"},


  {
    "nvim-lualine/lualine.nvim",
    dependencies =  {"kyazdani42/nvim-web-devicons"},
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
    config = function() require("leap").set_default_keymaps() end
  },
  {
    "ggandor/flit.nvim",
    config = function() require("flit").setup() end
  },

  -- Possibly of limited usefulness...
  { "andrewferrier/debugprint.nvim" },
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
        module = "persistence",
        config = function()
          require("persistence").setup()
        end,
      },

      {"powerman/vim-plugin-AnsiEsc"},

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

    }

    -- To get fzf loaded and working with telescope, you need to call
    -- load_extension, somewhere after setup function:
    require('telescope').load_extension('fzf')

    return specs
