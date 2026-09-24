-- vim.pack plugin management (Neovim 0.12+ built-in, replaces lazy.nvim).
-- Plugins live in: stdpath("data") .. "/site/pack/core/opt"
-- Lockfile: nvim-pack-lock.json (tracked in git, do not edit by hand).
-- Update plugins with: `:lua vim.pack.update()`  (review, then `:write` to confirm)
-- Add/remove specs below, then `:restart`.

local gh = function(repo) return "https://github.com/" .. repo end

-- Build hooks (replaces lazy.nvim `build = ...`).
-- Must be registered BEFORE vim.pack.add() so first installs trigger them.
vim.api.nvim_create_autocmd("PackChanged", {
  group = vim.api.nvim_create_augroup("pack-build-hooks", { clear = true }),
  callback = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if kind ~= "install" and kind ~= "update" then
      return
    end
    if name == "telescope-fzf-native.nvim" then
      vim.system({ "make" }, { cwd = ev.data.path }):wait()
    elseif name == "nvim-treesitter" then
      pcall(function()
        require("nvim-treesitter").update()
      end)
    elseif name == "markdown-preview.nvim" then
      if not ev.data.active then
        vim.cmd.packadd("markdown-preview.nvim")
      end
      pcall(vim.fn["mkdp#util#install"])
    end
  end,
})

vim.pack.add({
  -- colorscheme
  gh("ellisonleao/gruvbox.nvim"),

  -- core libs / icons (loaded first, others depend on them)
  gh("nvim-lua/plenary.nvim"),
  gh("echasnovski/mini.icons"),
  gh("echasnovski/mini.nvim"),
  gh("MunifTanjim/nui.nvim"),

  -- file explorer
  gh("stevearc/oil.nvim"),

  -- UI: vim.ui.input + vim.ui.select (replaces archived dressing.nvim)
  gh("folke/snacks.nvim"),

  -- picker
  gh("nvim-telescope/telescope.nvim"),
  gh("nvim-telescope/telescope-fzf-native.nvim"),

  -- completion
  { src = gh("saghen/blink.cmp"), version = vim.version.range("1.*") },
  gh("rafamadriz/friendly-snippets"),

  -- LSP config source (provides lsp/*.lua for vim.lsp.config, no setup() call)
  gh("neovim/nvim-lspconfig"),
  gh("folke/lazydev.nvim"),

  -- treesitter (main branch: native vim.treesitter, plugin provides parsers)
  { src = gh("nvim-treesitter/nvim-treesitter"), version = "main" },

  -- git / nav / diagnostics
  gh("kdheepak/lazygit.nvim"),
  { src = gh("ThePrimeagen/harpoon"), version = "harpoon2" },
  gh("folke/trouble.nvim"),
  gh("mbbill/undotree"),
  gh("j-hui/fidget.nvim"),

  -- debugger (nvim-dap-view replaces archived nvim-dap-ui; nvim-nio dropped)
  gh("mfussenegger/nvim-dap"),
  { src = gh("igorlfs/nvim-dap-view"), version = vim.version.range("1.*") },
  gh("leoluz/nvim-dap-go"),

  -- languages / tools
  gh("akinsho/flutter-tools.nvim"),
  gh("lervag/vimtex"),
  gh("iamcco/markdown-preview.nvim"),
  gh("yousefhadder/markdown-plus.nvim"),
  gh("adibhanna/nvim-notes"),

  -- AI completion (inline suggestions; blink.cmp handles the popup menu)
  gh("supermaven-inc/supermaven-nvim"),
})

-- ---------------------------------------------------------------------------
-- Plugin setup (replaces lazy.nvim `opts` / `config`). Order: libs first.
-- ---------------------------------------------------------------------------

-- icons (dependency of oil.nvim)
require("mini.icons").setup({})

-- colorscheme
require("gruvbox").setup({
  terminal_colors = true,
  undercurl = true,
  underline = true,
  bold = true,
  italic = {
    strings = false,
    emphasis = true,
    comments = true,
    operators = false,
    folds = true,
  },
  strikethrough = true,
  invert_selection = false,
  invert_signs = false,
  invert_tabline = false,
  inverse = true,
  contrast = "hard",
  palette_overrides = {},
  overrides = {},
  dim_inactive = false,
  transparent_mode = false,
})
vim.cmd.colorscheme("gruvbox")

-- statusline / editing (mini.nvim)
do
  require("mini.statusline").setup({ use_icons = true })
  require("mini.pairs").setup({})
  require("mini.surround").setup({})
  require("mini.align").setup({})
end

-- file explorer
require("oil").setup({
  float = { max_width = 0.5, max_height = 0.5 },
})

-- vim.ui.input + vim.ui.select (dressing.nvim replacement; keep minimal so
-- telescope remains the picker and oil remains the explorer)
require("snacks").setup({
  input = { enabled = true },
  picker = { enabled = true, ui_select = true },
})

-- diagnostics list
require("trouble").setup({})
vim.keymap.set("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Diagnostics (Trouble)" })
vim.keymap.set("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Buffer Diagnostics (Trouble)" })
vim.keymap.set("n", "<leader>cs", "<cmd>Trouble symbols toggle focus=false<cr>", { desc = "Symbols (Trouble)" })
vim.keymap.set("n", "<leader>cl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", { desc = "LSP (Trouble)" })
vim.keymap.set("n", "<leader>xL", "<cmd>Trouble loclist toggle<cr>", { desc = "Location List (Trouble)" })
vim.keymap.set("n", "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", { desc = "Quickfix List (Trouble)" })

-- file marks
do
  local harpoon = require("harpoon")
  harpoon:setup()
  vim.keymap.set("n", "<leader>a", function() harpoon:list():add() end)
  vim.keymap.set("n", "<C-e>", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)
  for _, idx in ipairs({ 1, 2, 3, 4, 5 }) do
    vim.keymap.set("n", string.format("<space>%d", idx), function()
      harpoon:list():select(idx)
    end)
  end
  vim.keymap.set("n", "<C-S-P>", function() harpoon:list():prev() end)
  vim.keymap.set("n", "<C-S-N>", function() harpoon:list():next() end)
end

-- picker
do
  require("telescope").setup({
    extensions = { fzf = {} },
  })
  pcall(require("telescope").load_extension, "fzf")

  local builtin = require("telescope.builtin")
  vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
  vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
  vim.keymap.set("n", "<leader>fh", builtin.help_tags, {})
  vim.keymap.set("n", "<C-g>", builtin.git_files, {})

  vim.keymap.set("n", "<space>en", function()
    builtin.find_files({ cwd = vim.fn.stdpath("config") })
  end)
  vim.keymap.set("n", "<space>ep", function()
    builtin.find_files({ cwd = vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt") })
  end)

  require("config.telescope.multigrep").setup()
end

-- completion menu (popup); supermaven below handles inline suggestions
require("blink.cmp").setup({
  keymap = { preset = "default" },
  appearance = { nerd_font_variant = "mono" },
  signature = { enabled = true },
  completion = { documentation = { auto_show = true } },
  sources = { default = { "lsp", "path", "snippets", "buffer" } },
  fuzzy = { implementation = "prefer_rust_with_warning" },
})

-- lua LSP annotations
require("lazydev").setup({
  library = {
    { path = "${3rd}/luv/library", words = { "vim%.uv" } },
  },
})

-- treesitter parsers (native vim.treesitter highlighting is enabled via
-- FileType autocmd in config.autocmds; this just ensures parsers exist,
-- installing only whatever is missing)
pcall(function()
  local wanted = {
    "bash",
    "c",
    "cpp",
    "css",
    "dart",
    "go",
    "html",
    "javascript",
    "lua",
    "markdown",
    "markdown_inline",
    "nix",
    "python",
    "query",
    "ruby",
    "rust",
    "tsx",
    "typescript",
    "typst",
    "vim",
    "vimdoc",
    "zig",
  }
  local missing = vim.tbl_filter(function(lang)
    return not pcall(vim.treesitter.language.add, lang)
  end, wanted)
  if #missing > 0 then
    require("nvim-treesitter").install(missing)
  end
end)

-- flutter
require("flutter-tools").setup({})

-- debugger (auto_toggle replaces the manual dap-ui open/close listeners)
do
  require("dap-go").setup()
  require("dap-view").setup({ auto_toggle = true })

  local dap = require("dap")
  vim.keymap.set("n", "<leader>db", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
  vim.keymap.set("n", "<leader>dt", dap.terminate, { desc = "Terminate session" })
  vim.keymap.set("n", "<leader>dc", dap.continue, { desc = "Continue" })
  vim.keymap.set("n", "<leader>dr", "<cmd>DapViewToggle<cr>", { desc = "Toggle debugger view" })
end

-- markdown
require("markdown-plus").setup({})

-- latex
vim.g.vimtex_view_method = "zathura"
vim.g.vimtex_compiler_method = "tectonic"
vim.g.vimtex_compiler_tectonic = {
  options = { "--synctex", "--keep-logs", "--keep-intermediates" },
}

-- LSP progress UI
require("fidget").setup({})

-- git UI (lazy-loaded by command; keymap defined here)
vim.keymap.set("n", "<leader>lg", "<cmd>LazyGit<cr>", { desc = "LazyGit" })

-- undo tree
vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle)

-- notes
require("nvim-notes").setup({ vault_path = "~/notes" })

-- AI inline suggestions (accept on <C-v>; no conflict with blink.cmp's
-- default preset, which uses <C-space>/<C-e>/<C-y>/<C-p>/<C-n>)
require("supermaven-nvim").setup({
  keymaps = { accept_suggestion = "<C-v>" },
})
