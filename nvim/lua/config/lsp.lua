-- Neovim 0.12 syntax for applying server-specific settings
vim.lsp.config('texlab', {
  settings = {
    texlab = {
      build = {
        executable = "tectonic",
        args = {
          "-X", "compile", "%f",
          "--synctex",
          "--keep-logs",
          "--keep-intermediates"
        },
        onSave = true,
        forwardSearchAfter = false,
      }
    }
  }
})

vim.lsp.config('pyright', {
  settings = {
    pyright = { disableOrganizeImports = true },
    python = { analysis = { ignore = { '*' } } },
  },
})

vim.lsp.config('harper_ls', {
  settings = {
    ["harper-ls"] = {
      linters = {
        SentenceCapitalization = false,
        SpellCheck = false
      }
    }
  },
})

vim.lsp.config('tinymist', {
  root_markers = { 'main.typ', 'typst.toml', '.git' },
  settings = {
    typstExtraArgs = { "main.typ" }
  }
})

-- Native 0.12 Server Enablement
vim.lsp.enable({
  "bashls",
  "clangd",
  "denols",
  "gopls",
  "herb_ls",
  "html",
  "lua_ls",
  "nil_ls",
  "pyright",
  "rubocop",
  "ruby_lsp",
  "ruff",
  "rust_analyzer",
  "texlab",
  "tinymist",
  "zls",
})

-- Diagnostic Config
vim.diagnostic.config({
  virtual_text = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "✘",
      [vim.diagnostic.severity.WARN]  = "▲",
      [vim.diagnostic.severity.HINT]  = "⚑",
      [vim.diagnostic.severity.INFO]  = "»",
    },
  },
  float = {
    focusable = false,
    style = "minimal",
    border = "rounded",
    source = true,
    header = "",
    prefix = "",
  },
})
