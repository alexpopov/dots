local specs = {
  {
    'rcarriga/nvim-notify',
    init = function()
      vim.notify = require("notify")
    end,
    opts = {
      timeout = 2000,
      render = "simple",
    }
  }
}

return specs
