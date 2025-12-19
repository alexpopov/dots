return {
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      ensure_installed = {
        "lua_ls",
        -- "shellcheck",
      },
    },
    dependencies = {
      {
        "mason-org/mason.nvim",
        opts = {
          pip = {
            install_args = { "--index-url", "https://pypi.org/simple" }
          }
        },
      },
      -- nvim-lspconfig is still useful for server command/filetype defaults
      -- but no longer required for the core LSP functionality in 0.11+
      "neovim/nvim-lspconfig",
    },
  },
}
