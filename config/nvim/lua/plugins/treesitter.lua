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
    -- The `main` branch is the only one that supports Neovim 0.11+/0.12.
    -- The legacy `master` branch is deprecated and breaks on 0.12
    -- (e.g. the markdown `set-lang-from-info-string!` directive throws
    -- "attempt to call method 'range' (a nil value)").
    branch = "main",
    build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")

      -- The `main` branch exposes `install()`; the legacy `master` branch
      -- does not. Guard so a half-migrated machine degrades gracefully
      -- instead of throwing on `install` being nil.
      if type(ts.install) ~= "function" then
        vim.notify(
          "nvim-treesitter is on the legacy `master` branch, which does not "
            .. "support Neovim 0.11+. Run `:Lazy sync` to switch to `main`.",
          vim.log.levels.WARN
        )
        return
      end

      -- On the `main` branch `setup()` only configures the install dir;
      -- parsers are installed via `install()`, not `ensure_installed`.
      -- (`install()` downloads parser tarballs with curl + tar into
      -- `stdpath('data')/site/parser`.)
      ts.setup({})

      -- Only install parsers that are missing, so we don't spawn the
      -- installer on every startup once they're present.
      local installed = require("nvim-treesitter.config").get_installed("parsers")
      local missing = vim.tbl_filter(function(lang)
        return not vim.tbl_contains(installed, lang)
      end, ensure_installed)

      if #missing > 0 then
        -- pcall so a missing tool / offline machine can't break startup.
        pcall(ts.install, missing)
      end

      -- Enable treesitter highlighting for any buffer that has a parser
      -- installed. `vim.treesitter.start` no-ops (and we pcall it anyway)
      -- when no parser is available for the filetype.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    lazy = true,
    dependencies = "nvim-treesitter/nvim-treesitter",
  },
}
