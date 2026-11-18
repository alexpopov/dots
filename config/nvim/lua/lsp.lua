local M = {}

function M.setup()
  if M._enabled then
    vim.notify("LSP already enabled", vim.log.levels.INFO)
    return
  end
  M._enabled = true

  -- Ensure Mason-installed binaries are on PATH
  local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
  if not vim.env.PATH:find(mason_bin, 1, true) then
    vim.env.PATH = mason_bin .. ":" .. vim.env.PATH
  end

  require("lazy").load({ plugins = { "nvim-lspconfig", "mason.nvim", "mason-lspconfig.nvim", "cmp-nvim-lsp", "none-ls.nvim" } })

  local ok_cmp, cmp_lsp = pcall(require, "cmp_nvim_lsp")
  local capabilities = ok_cmp and cmp_lsp.default_capabilities() or vim.lsp.protocol.make_client_capabilities()
  M.capabilities = capabilities

  -- Configure lua_ls
  vim.lsp.config("lua_ls", {
    settings = {
      Lua = {
        diagnostics = {
          globals = { "vim", "alp", "P", "RELOAD", "R" },
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
      local names = {}
      for _, client in pairs(vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })) do
        table.insert(names, client.name)
      end
      return names
    end,
  })

  -- Register LspAttach keymaps BEFORE enabling servers so existing buffers get them
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
    callback = function(ev)
      local bufnr = ev.buf
      vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"

      local function buf_opts(desc)
        return { buffer = bufnr, noremap = true, silent = true, desc = desc }
      end

      -- Navigation
      vim.keymap.set("n", "<Leader>aD", vim.lsp.buf.declaration, buf_opts("declaration"))
      vim.keymap.set("n", "<Leader>ad", vim.lsp.buf.definition, buf_opts("definition"))
      vim.keymap.set("n", "<Leader>ai", vim.lsp.buf.implementation, buf_opts("implementation"))
      vim.keymap.set("n", "gr", vim.lsp.buf.references, buf_opts("references"))
      vim.keymap.set("n", "K", vim.lsp.buf.hover, buf_opts("hover"))
      vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, buf_opts("signature help"))

      -- Workspace
      vim.keymap.set("n", "<Leader>awa", vim.lsp.buf.add_workspace_folder, buf_opts("add folder"))
      vim.keymap.set("n", "<Leader>awr", vim.lsp.buf.remove_workspace_folder, buf_opts("remove folder"))
      vim.keymap.set("n", "<Leader>awl", function()
        print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
      end, buf_opts("list folders"))

      -- Refactoring
      vim.keymap.set("n", "<Leader>ar", vim.lsp.buf.rename, buf_opts("rename"))
      vim.keymap.set("n", "<Leader>aca", vim.lsp.buf.code_action, buf_opts("code action"))

      -- Diagnostics
      vim.keymap.set("n", "<Leader>ae", vim.diagnostic.open_float, buf_opts("show diagnostic"))
      vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, buf_opts("prev diagnostic"))
      vim.keymap.set("n", "]d", vim.diagnostic.goto_next, buf_opts("next diagnostic"))
      vim.keymap.set("n", "<Leader>aq", vim.diagnostic.setloclist, buf_opts("diagnostics to loclist"))

      -- Formatting
      vim.keymap.set("n", "<Leader>aff", function()
        vim.lsp.buf.format({ timeout_ms = 5000 })
      end, buf_opts("format file"))
      vim.keymap.set("v", "<Leader>aff", function()
        vim.lsp.buf.format({
          timeout_ms = 5000,
          range = {
            ["start"] = vim.api.nvim_buf_get_mark(0, "<"),
            ["end"] = vim.api.nvim_buf_get_mark(0, ">"),
          },
        })
      end, buf_opts("format selection"))

      vim.diagnostic.config({
        virtual_text = {
          source = "always",
          format = function(diagnostic)
            local nl = diagnostic.message:find("\n")
            return nl and diagnostic.message:sub(1, nl) or diagnostic.message
          end,
        },
      })
    end,
  })

  -- Enable Mason-installed servers (vim.lsp.enable also attaches to already-open buffers)
  local ok_mlsp, mlsp = pcall(require, "mason-lspconfig")
  if ok_mlsp then
    mlsp.setup({ ensure_installed = { "lua_ls" } })
  end

  -- none-ls configs
  local ok_null, null_ls = pcall(require, "null-ls")
  if ok_null then
    if not null_ls.is_registered("csharpier") then
      null_ls.setup({
        sources = {
          null_ls.builtins.formatting.csharpier,
        },
      })
    end
    pcall(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          require("null-ls.client").try_add(buf)
        end
      end
    end)
  end

  vim.notify("LSP enabled", vim.log.levels.INFO)
end

return M
