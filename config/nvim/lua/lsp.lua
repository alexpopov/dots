local M = {}

local capabilities = require("cmp_nvim_lsp").default_capabilities()
M.capabilities = capabilities

-- New vim.lsp.config approach (Neovim 0.11+)
-- Configure lua_ls
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      diagnostics = {
        globals = { "vim" },
      },
    },
  },
  capabilities = capabilities,
})

-- Configure csharp_ls (doesn't have mason-schemas, so auto-register won't pick it up)
vim.lsp.config("csharp_ls", {
  cmd = { "csharp-ls" },
  filetypes = { "cs" },
  root_markers = { "*.sln", "*.csproj" },
  capabilities = capabilities,
})
vim.lsp.enable("csharp_ls")

vim.api.nvim_create_user_command("LspStopByName", function(opts)
  local target = opts.args
  local bufnr = vim.api.nvim_get_current_buf()
  for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == target then
      client.stop()
      vim.notify("Stopped " .. target .. " LSP", vim.log.levels.INFO)
      return
    end
  end
  vim.notify("No active LSP client named: " .. target, vim.log.levels.WARN)

end, {
    nargs = 1,
    complete = function()
      -- provide completion of active client names
      local names = {}
      for _, client in pairs(vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })) do
        table.insert(names, client.name)
      end
      return names
    end
  })

-- LSP servers are auto-enabled via lsp_auto_register.lua

-- Use LspAttach autocommand for keymaps (replaces on_attach)
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
  callback = function(ev)
    local bufnr = ev.buf

    -- Enable completion triggered by <c-x><c-o>
    vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"

    -- Mappings
    local opts = { buffer = bufnr, noremap = true, silent = true }

    -- See `:help vim.lsp.*` for documentation on any of the below functions
    vim.keymap.set("n", "<Leader>aD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "<Leader>ad", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "<Leader>ai", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
    vim.keymap.set("n", "<Leader>awa", vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set("n", "<Leader>awr", vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set("n", "<Leader>awl", function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, opts)
    vim.keymap.set("n", "<Leader>ar", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<Leader>aca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "<Leader>ae", vim.diagnostic.open_float, opts)
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
    vim.keymap.set("n", "<Leader>aq", vim.diagnostic.setloclist, opts)
    vim.keymap.set("n", "<Leader>aff", function()
      vim.lsp.buf.format({ timeout_ms = 5000 })
    end, opts)
    vim.keymap.set("v", "<Leader>aff", function()
      vim.lsp.buf.format({
        timeout_ms = 5000,
        range = {
          ["start"] = vim.api.nvim_buf_get_mark(0, "<"),
          ["end"] = vim.api.nvim_buf_get_mark(0, ">"),
        },
      })
    end, opts)

    vim.diagnostic.config({
      virtual_text = {
        source = "always",
        format = function(diagnostic)
          local new_line_location = diagnostic.message:find("\n")
          if new_line_location ~= nil then
            return diagnostic.message:sub(1, new_line_location)
          else
            return diagnostic.message
          end
        end,
      },
    })
  end,
})

-- null-ls configs
local null_ls = require("null-ls")
null_ls.setup({
  -- null-ls still uses the traditional on_attach pattern
  -- but keymaps are now handled by the LspAttach autocmd
  sources = {
    null_ls.builtins.formatting.csharpier,
  },
})

return M
