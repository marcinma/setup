local lspconfig = require("lspconfig")

lspconfig.tsserver.setup({
  on_attach = function(client, bufnr)
    -- Override built-in omnifunc for LSP-aware completion
    vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

    -- Optional: Keymaps for common LSP actions
    local opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "ca", vim.lsp.buf.code_action, opts)
  end,
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
  root_dir = lspconfig.util.root_pattern("package.json", ".git"),
  settings = {
    typescript = {
      -- Use project's TypeScript version if available
      inlayHints = {
        includeInlayParameterNameHints = "all",
        includeInlayParameterNameHintsWhenArgumentMatchesName = true,
      },
    },
  },
})
return {}
