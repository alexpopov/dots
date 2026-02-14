return {
  {
    'rcarriga/nvim-notify',
    lazy = false,
    opts = {
      timeout = 2000, -- TODO: reconsider timeout; spammy errors are annoying but too fast is unreadable
      render = "simple",
    },
    config = function(_, opts)
      require("notify").setup(opts)
      vim.notify = require("notify")
    end,
  }
}
