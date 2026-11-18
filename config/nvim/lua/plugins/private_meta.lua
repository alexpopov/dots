if not os.getenv("ENABLE_PRIVATE_FACEBOOK") then
  return {}
end

local specs = {}
local uv = vim.uv or vim.loop

local meta_dir = vim.fn.expand("~/fbsource/fbcode/editor_support/nvim")
if uv.fs_stat(meta_dir) then
  table.insert(specs, { "meta", dir = meta_dir, event = "VeryLazy" })
end

local task_oil_dir = vim.fn.expand("~/fbsource/users/al/alexpopov/task-oil.nvim")
if uv.fs_stat(task_oil_dir) then
  table.insert(specs, {
    dir = task_oil_dir,
    cmd = "TaskOil",
    keys = {
      { "<leader>to", "<cmd>TaskOil<cr>", desc = "Task Oil" },
      { "<leader>tp", "<cmd>TaskOil priority<cr>", desc = "Task Oil (priority)" },
      { "<leader>ts", "<cmd>TaskOil progress<cr>", desc = "Task Oil (progress)" },
    },
    opts = {},
  })
end

return specs
