  if os.getenv("ENABLE_PRIVATE_FACEBOOK")
  then
    return {
      { "meta", dir = "/home/alexpopov/fbsource/fbcode/editor_support/nvim" },
      {
        dir = "~/fbsource/fbcode/scripts/alexpopov/task-oil.nvim",
        cmd = "TaskOil",
        keys = {
          { "<leader>to", "<cmd>TaskOil<cr>", desc = "Task Oil" },
          { "<leader>tp", "<cmd>TaskOil priority<cr>", desc = "Task Oil (priority)" },
          { "<leader>ts", "<cmd>TaskOil progress<cr>", desc = "Task Oil (progress)" },
        },
        opts = {},
      },
    }
  else
    return {}
  end

