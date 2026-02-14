return {
  {
    'rcarriga/nvim-notify',
    lazy = false,
    opts = {
      timeout = 2000,
      render = "simple",
    },
    config = function(_, opts)
      require("notify").setup(opts)
      vim.notify = require("notify")
    end,
  }
}
