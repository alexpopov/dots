return {
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = true,
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "bash", "c", "cpp", "lua", "rust", "cmake", "comment", "go", "java", "javascript", "json",
          "make", "python", "regex", "vim", "yaml", "kotlin", "markdown", "markdown_inline"
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
  },
  {"nvim-treesitter/nvim-treesitter-textobjects", lazy = true, dependencies = "nvim-treesitter/nvim-treesitter", },
  {'nvim-treesitter/playground', lazy = true, dependencies = "nvim-treesitter/nvim-treesitter", },
}
