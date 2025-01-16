-- TODO: Make this configurable
local update_treesitter = false
local ensure_installed
if (update_treesitter == true)  then
  ensure_installed = {
          "bash", "c", "cpp", "lua", "rust", "cmake", "comment", "go", "java", "javascript", "json",
          "make", "python", "regex", "vim", "yaml", "kotlin", "markdown", "markdown_inline"
        }
else
  ensure_installed = {}
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = true,
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = ensure_installed,
        auto_install = false,
        highlight = {
          enable = true,
          disable = { "latex" },
        },
        indent = {
          enable = true,
          disable = { "python", "latex" },
        },
      })
    end,
  },
  {"nvim-treesitter/nvim-treesitter-textobjects", lazy = true, dependencies = "nvim-treesitter/nvim-treesitter", },
  {'nvim-treesitter/playground', lazy = true, dependencies = "nvim-treesitter/nvim-treesitter", },
}
