-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight when yanking (copying) text",
  group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- format on save
vim.api.nvim_create_autocmd("BufWritePre", {
  desc = "Format buffer on save",
  group = vim.api.nvim_create_augroup("lsp-format-on-save", { clear = true }),
  callback = function(args)
    vim.lsp.buf.format({
      bufnr = args.buf,
      filter = function(client)
        return client:supports_method("textDocument/formatting")
      end,
    })
  end,
})

-- Native Neovim 0.12 Treesitter Highlighting + Large File Check
vim.api.nvim_create_autocmd("FileType", {
  desc = "Enable native Treesitter with large file protection",
  group = vim.api.nvim_create_augroup("native-treesitter", { clear = true }),
  callback = function(args)
    -- 1. Let VimTeX handle LaTeX syntax highlighting natively!
    local ft = vim.bo[args.buf].filetype
    if ft == "tex" or ft == "latex" then
      return
    end

    -- 2. Skip Treesitter on huge files
    local max_filesize = 100 * 1024 -- 100 KB
    local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(args.buf))
    if ok and stats and stats.size > max_filesize then
      return
    end

    -- 3. Enable native treesitter for everything else
    pcall(vim.treesitter.start, args.buf)
  end,
})
