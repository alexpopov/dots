local specs = {
  {
    "guns/xterm-color-table.vim",
    cmd = { "XtermColorTable" },
  },

  { "wesQ3/vim-windowswap", keys = { "<Leader>ww" } },
  { "gburca/vim-logcat",    ft = "logcat" },
  { "mechatroner/rainbow_csv", ft = { "csv", "tsv" } },

  {
    "nvimtools/none-ls.nvim",
    lazy = true,
    dependencies = { { "nvim-lua/plenary.nvim", lazy = true } },
  },

  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      { "hrsh7th/cmp-nvim-lsp", lazy = true },
      { "hrsh7th/cmp-buffer",   lazy = true },
      { "hrsh7th/cmp-path",     lazy = true },
      { "hrsh7th/cmp-nvim-lua", lazy = true },
    },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        mapping = {
          ["<C-p>"] = cmp.mapping.select_prev_item(),
          ["<C-n>"] = cmp.mapping.select_next_item(),
          ["<C-d>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.close(),
          ["<C-y>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Insert,
            select = true,
          }),
          ["<CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
          }),
          ["<Tab>"] = function(fallback)
            if cmp.visible() then
              cmp.confirm()
            else
              fallback()
            end
          end,
          ["<S-Tab>"] = function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            else
              fallback()
            end
          end,
        },
        sources = {
          { name = "nvim_lsp" },
          { name = "nvim_lua" },
          { name = "path" },
          { name = "buffer", keyword_length = 5 },
        },
        view = {
          entries = "custom",
        },
      })
    end,
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      local npairs = require("nvim-autopairs")
      local Rule = require("nvim-autopairs.rule")
      npairs.setup({})
      npairs.remove_rule("`")
      npairs.add_rule(Rule("```", "```", { "markdown", "conf", "text", "gitcommit" }))
    end,
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<Leader>f", group = "find" },
        { "<Leader>c", group = "comment" },
        { "<Leader>a", group = "LSP" },
        { "<Leader>aw", group = "workspace" },
        { "<Leader>ac", group = "code" },
        { "<localleader>e", group = "edit" },
        { "<localleader>b", group = "buffers" },
        { "<localleader>q", group = "config" },
        { "<localleader>r", group = "reload" },
        { "<localleader>t", group = "tabs" },
      },
    },
  },

  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup({})
    end,
  },

  {
    "nvim-lualine/lualine.nvim",
    config = function()
      local onelight = require("lualine.themes.onelight")
      require("lualine").setup({
        options = {
          theme = onelight,
          icons_enabled = false,
        },
        sections = {
          lualine_b = { "diff" },
          lualine_c = {
            { "filename", path = 1 },
          },
          lualine_x = { "encoding", "filetype" },
        },
      })
    end,
  },

  {
    url = "https://codeberg.org/andyg/leap.nvim",
    event = "VeryLazy",
    config = function()
      local leap = require("leap")
      vim.keymap.set({ "n", "x", "o" }, "s", function()
        leap.leap({})
      end)
      vim.keymap.set({ "n", "x", "o" }, "S", function()
        leap.leap({ backward = true })
      end)
      leap.opts.equivalence_classes = { " \t\r\n", "([{", ")]}", "'\"`" }
    end,
  },
  {
    "ggandor/flit.nvim",
    event = "VeryLazy",
    config = function()
      require("flit").setup({
        clever_repeat = true,
        opts = {
          case_sensitive = false,
          vim_opts = { ["go.ignorecase"] = false },
        },
      })
    end,
  },

  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    lazy = true,
    init = function()
      -- Load asynchronously after the markdown buffer paints so Ctrl-G prompt
      -- edits open instantly and markdown rendering pops in ~15ms later.
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        once = true,
        callback = function()
          vim.defer_fn(function()
            require("lazy").load({ plugins = { "render-markdown.nvim" } })
          end, 15)
        end,
      })
    end,
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      code = {
        conceal_delimiters = false,
        border = "none",
        language = false,
      },
      bullet = {
        icons = { "•", "◦", "•", "◦" },
      },
    },
  },
}

return specs
