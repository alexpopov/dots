return {
  {
    "rcarriga/nvim-notify",
    lazy = true,
    init = function()
      -- Lazy.nvim only auto-loads on cmd/keys/event/ft/require("notify").
      -- Callers invoke vim.notify(...), not require("notify"), so wrap vim.notify
      -- once to load nvim-notify on the first actual notification (0ms at startup).
      vim.notify = function(...)
        vim.notify = require("notify")
        return vim.notify(...)
      end
    end,
    opts = {
      timeout = 2000,
      render = "simple",
    },
    config = function(_, opts)
      local notify = require("notify")
      notify.setup(opts)
      vim.notify = notify
    end,
  },
}
