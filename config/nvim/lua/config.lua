
-- configure pasting back to Laptop... should probably gate this behind some
-- check eventually
vim.g.clipboard = {
  name = "Laptop Clipboard",
  copy = {
    ["*"] = {
      "ssh",
      "-i",
      "~/.ssh/copy_paste_key_ed25519",
      "-p",
      "9001",
      "localhost",
      "'pbcopy'"
    },
    ["+"] = {
      "ssh",
      "-i",
      "~/.ssh/copy_paste_key_ed25519",
      "-p",
      "9001",
      "localhost",
      "'pbcopy'"
    },
  },
  paste = {
    ["*"] = {
      "ssh",
      "-i",
      "~/.ssh/copy_paste_key_ed25519",
      "-p",
      "9001",
      "localhost",
      "'pbpaste'"
    },
    ["+"] = {
      "ssh",
      "-i",
      "~/.ssh/copy_paste_key_ed25519",
      "-p",
      "9001",
      "localhost",
      "'pbpaste'"
    },
  },
  cache_enabled = true,
}
