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
      local code = vim.system({ "make" }, { cwd = ev.data.path }):wait()
      if code ~= 0 then
        vim.notify("telescope-fzf-native.nvim: `make` failed (exit " .. code .. ")", vim.log.levels.ERROR)
      end
    elseif name == "nvim-treesitter" then
      local ok, err = pcall(function()
        require("nvim-treesitter").update()
      end)
      if not ok then
        vim.notify("nvim-treesitter: update failed: " .. tostring(err), vim.log.levels.WARN)
      end
    elseif name == "markdown-preview.nvim" then
      -- Check rtp, not ev.data.active: with a custom `load` function the
      -- plugin is registered as active without being loaded, and the
      -- autoload call below needs it on rtp to work.
      if not vim.tbl_contains(vim.api.nvim_list_runtime_paths(), ev.data.path) then
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
  gh("yousefhadder/markdown-plus.nvim"),
  gh("adibhanna/nvim-notes"),

  -- AI completion (inline suggestions; blink.cmp handles the popup menu)
  gh("supermaven-inc/supermaven-nvim"),
})

-- markdown-preview.nvim: loaded lazily, in markdown buffers only (per its
-- README). `load` must be an add() option, not a spec field — a function
-- takes full responsibility for loading, keeping the plugin off
-- runtimepath until the FileType autocmd fires.
vim.pack.add({
  gh("iamcco/markdown-preview.nvim"),
}, {
  load = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "markdown",
      once = true,
      callback = function()
        vim.cmd.packadd("markdown-preview.nvim")
      end,
    })
  end,
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
    defaults = {
      -- `rg --hidden` also walks .git; keep the object store out of the picker.
      file_ignore_patterns = { "^%.git/" },
    },
    extensions = { fzf = {} },
  })
  pcall(require("telescope").load_extension, "fzf")

  local builtin = require("telescope.builtin")

  -- Dotfiles such as .bashrc are normal tracked files, not editor noise.
  local function find_files(opts)
    opts = vim.tbl_extend("force", { hidden = true }, opts or {})
    builtin.find_files(opts)
  end

  vim.keymap.set("n", "<leader>ff", function() find_files() end, {
    desc = "Find files (including hidden)",
  })
  vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
  vim.keymap.set("n", "<leader>fh", builtin.help_tags, {})
  vim.keymap.set("n", "<C-g>", builtin.git_files, {})

  vim.keymap.set("n", "<space>en", function()
    find_files({ cwd = vim.fn.stdpath("config") })
  end)
  vim.keymap.set("n", "<space>ep", function()
    find_files({ cwd = vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt") })
  end)

  require("config.telescope.multigrep").setup()
end

-- completion menu (popup); supermaven below handles inline suggestions
require("blink.cmp").setup({
  keymap = { preset = "default" },
  appearance = { nerd_font_variant = "mono" },
  signature = { enabled = true },
  completion = { documentation = { auto_show = true } },
  sources = {
    -- lazydev first (per lazydev.nvim README): module names in require(...),
    -- @module annotations; score_offset makes it top priority
    default = { "lazydev", "lsp", "path", "snippets", "buffer" },
    providers = {
      lazydev = {
        name = "LazyDev",
        module = "lazydev.integrations.blink",
        score_offset = 100,
      },
    },
  },
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
    "eex",
    "elixir",
    "go",
    "heex",
    "html",
    "javascript",
    "json",
    "lua",
    "markdown",
    "markdown_inline",
    "nix",
    "python",
    "query",
    "ruby",
    "rust",
    "toml",
    "tsx",
    "typescript",
    "typst",
    "vim",
    "vimdoc",
    "yaml",
    "zig",
  }
  -- vim.treesitter.language.add() *returns* nil + "No parser for language X"
  -- when the parser is missing, it does not throw -- so pcall() alone would
  -- always report "present" and the install below would never run.
  local missing = vim.tbl_filter(function(lang)
    local ok, loaded = pcall(vim.treesitter.language.add, lang)
    return not (ok and loaded)
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
