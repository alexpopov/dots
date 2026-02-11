-- TODO: Make this configurable
local update_treesitter = true
local ensure_installed
if (update_treesitter == true)  then
  ensure_installed = {
          "bash", "c", "cpp", "lua", "rust", "cmake", "comment", "go", "java", "javascript", "json",
          "make", "python", "regex", "vim", "yaml", "kotlin", "markdown", "markdown_inline", "hlsl"
        }
else
  ensure_installed = {}
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- lazy = true,
    config = function()
      require("nvim-treesitter").setup({
        ensure_installed = ensure_installed,
        auto_install = false,
      })
    end,
  },
  {"nvim-treesitter/nvim-treesitter-textobjects", lazy = true, dependencies = "nvim-treesitter/nvim-treesitter", },
}
