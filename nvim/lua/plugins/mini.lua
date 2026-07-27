return {
  {
    'echasnovski/mini.nvim',
    enabled = true,
    config = function()
      local statusline = require('mini.statusline')
      local pairs = require("mini.pairs")
      local surround = require('mini.surround')
      local align = require('mini.align')

      statusline.setup { use_icons = true }
      pairs.setup {}
      surround.setup {}
      align.setup {}
    end
  },
}
