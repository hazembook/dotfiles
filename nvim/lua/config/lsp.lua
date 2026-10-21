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

-- Root markers only: hardcoding typstExtraArgs = { "main.typ" } would make
-- tinymist compile a nonexistent main.typ in projects whose entry file has
-- another name.
vim.lsp.config('tinymist', {
  root_markers = { 'main.typ', 'typst.toml', '.git' },
})

-- Lua config, kickstart-style (nvim-lua/kickstart.nvim): correct runtime +
-- workspace scoping. Two deliberate deviations from kickstart:
-- * formatting stays ON: our format-on-save uses lua_ls (no stylua here).
-- * no workspace.library: lazydev.nvim already provides it, and kickstart
--   itself notes the full-runtime library is slow (nvim-lspconfig#3189).
vim.lsp.config('lua_ls', {
  on_init = function(client)
    if client.workspace_folders then
      local path = client.workspace_folders[1].name
      if
        path ~= vim.fn.stdpath("config")
        and (
          vim.uv.fs_stat(path .. "/.luarc.json") or vim.uv.fs_stat(path .. "/.luarc.jsonc")
        )
      then
        return -- project has its own config; don't override
      end
    end
    client.config.settings.Lua = vim.tbl_deep_extend(
      "force",
      client.config.settings.Lua,
      {
        runtime = { version = "LuaJIT" },
        workspace = { checkThirdParty = false },
      }
    )
  end,
})

-- Native 0.12 Server Enablement.
-- vim.lsp.enable() does NOT check for the binary: it only marks the config
-- as enabled. The check happens later, at client-start time, in
-- can_start()/validate_cmd() (runtime/lua/vim/lsp.lua), and it only applies
-- when `cmd` is a table -- a function-form cmd (html, ruby_lsp) is spawned
-- anyway and logs "Spawning language server ... failed".
-- `:checkhealth vim.lsp` lists the missing ones ("'<binary>' is not
-- executable. Configuration will not be used."). Restart Neovim after
-- installing a tool.
vim.lsp.enable({
  "bashls",
  "clangd",
  "denols",
  "expert",
  "gopls",
  "harper_ls",
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
