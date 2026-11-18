return {
  {
    "mason-org/mason.nvim",
    cmd = "Mason",
    opts = {
      pip = {
        install_args = { "--index-url", "https://pypi.org/simple" },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    lazy = true,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    lazy = true,
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
  },
}
