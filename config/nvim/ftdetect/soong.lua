vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
  pattern = { "*.bp" },
  callback = function()
    vim.bo.filetype = "soong"
  end,
})
