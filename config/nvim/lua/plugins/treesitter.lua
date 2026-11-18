local ensure_installed = {
  "bash", "c", "cpp", "lua", "rust", "cmake", "comment", "go", "java", "javascript", "json",
  "make", "python", "regex", "vim", "yaml", "kotlin", "markdown", "markdown_inline", "hlsl",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    cmd = { "TSUpdate", "TSInstall", "TSUninstall" },
    init = function()
      -- Neovim 0.12 starts already-installed parsers natively with zero plugin load.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
    config = function()
      local ts = require("nvim-treesitter")
      if type(ts.install) ~= "function" then
        vim.notify(
          "nvim-treesitter is on the legacy master branch. Run :Lazy sync to switch to main.",
          vim.log.levels.WARN
        )
        return
      end

      local ok_log, log = pcall(require, "nvim-treesitter.log")
      if ok_log and log.Logger then
        local levels = {
          info = vim.log.levels.INFO,
          warn = vim.log.levels.WARN,
          error = vim.log.levels.ERROR,
        }
        for name, level in pairs(levels) do
          log.Logger[name] = function(self, m, ...)
            local msg = select("#", ...) > 0 and m:format(...) or m
            local prefix = self.ctx and ("[nvim-treesitter/" .. self.ctx .. "] ") or "[nvim-treesitter] "
            vim.schedule(function()
              vim.notify(prefix .. msg, level)
            end)
            return msg
          end
        end
      end

      ts.setup({})

      local installed = require("nvim-treesitter.config").get_installed("parsers")
      local missing = vim.tbl_filter(function(lang)
        return not vim.tbl_contains(installed, lang)
      end, ensure_installed)

      if #missing > 0 then
        pcall(ts.install, missing)
      end
    end,
  },
}
