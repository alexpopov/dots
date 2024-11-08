return {
  {"neovim/nvim-lspconfig",
    dependencies = {"williamboman/mason.nvim"},
  },
  {
    "williamboman/mason.nvim",
    lazy = false,
  },
  {"williamboman/mason-lspconfig.nvim"},

  {'williamboman/nvim-lsp-installer'},
}
