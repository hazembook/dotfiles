vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- for long lines
vim.opt.wrap = true

vim.opt.swapfile = false
vim.opt.backup = false
-- Fixed undo dir (deliberately NOT stdpath("state"), which is volatile).
-- Neovim does not create undodir itself — undo persistence silently fails
-- if the directory is missing.
local undodir = vim.fn.expand("~/.vim/undodir")
vim.fn.mkdir(undodir, "p")
vim.opt.undodir = undodir
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"

vim.opt.updatetime = 50

-- vim.opt.colorcolumn = "140"

-- 0.12's default already contains inline:char; drop it so the effective
-- value is unambiguous instead of relying on parse order.
vim.opt.diffopt:remove("inline:char")
vim.opt.diffopt:append("inline:word")
