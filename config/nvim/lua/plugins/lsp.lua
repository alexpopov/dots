return {
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {},
    ensure_installed = { "lua_ls", "shellcheck" },
    dependencies = {
      {
        "mason-org/mason.nvim",
        opts = {
          pip = {
            install_args = { "--index-url", "https://pypi.org/simple"}
          }
        },
      },
      "neovim/nvim-lspconfig",
    },
  },
}
