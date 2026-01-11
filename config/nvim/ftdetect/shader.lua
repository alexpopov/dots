vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
  pattern = { "*.shader", "*.hlsl" },
  callback = function()
    vim.bo.filetype = "hlsl"
  end,
})
