vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
  pattern = "*.commit.hg.txt",
  callback = function()
    vim.bo.filetype = "gitcommit"
  end,
})
