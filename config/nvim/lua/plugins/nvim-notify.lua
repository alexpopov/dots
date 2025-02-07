local specs = {
  {
    'rcarriga/nvim-notify',
    init = function()
      -- vim.opt.termguicolors = true
      vim.notify = require("notify")
    end,
    opts = {
      timeout = 2,
      render = "simple",
    }
  }
}

return specs
