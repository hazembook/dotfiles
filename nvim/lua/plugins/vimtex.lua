return {
  {
    "lervag/vimtex",
    lazy = false,
    init = function()
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_compiler_method = "tectonic"

      -- Force Tectonic to leave the helper files behind so TexLab can read them
      vim.g.vimtex_compiler_tectonic = {
        options = {
          "--synctex",
          "--keep-logs",
          "--keep-intermediates"
        }
      }
    end
  },
}
