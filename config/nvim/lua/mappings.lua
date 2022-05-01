local cmd = vim.cmd

--  write/quit typos
cmd("command WQ wq")
cmd("command Wq wq")
cmd("command W w")
cmd("command Q q")

vim.g.mapleader = ","
vim.g.maplocalleader = "\\"
