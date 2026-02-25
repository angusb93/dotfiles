-- [theme:generated] — do not edit, run theme/apply.sh
return {
  -- Disable LazyVim default colorschemes
  { "folke/tokyonight.nvim", enabled = false },
  { "catppuccin/nvim", enabled = false },

  {
    "RRethy/base16-nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("base16-colorscheme").setup({
        base00 = "#000000",
        base01 = "#121212",
        base02 = "#333333",
        base03 = "#505050",
        base04 = "#999999",
        base05 = "#c1c1c1",
        base06 = "#999999",
        base07 = "#c1c1c1",
        base08 = "#5f8787",
        base09 = "#aaaaaa",
        base0A = "#e78a43",
        base0B = "#fbcb97",
        base0C = "#aaaaaa",
        base0D = "#888888",
        base0E = "#999999",
        base0F = "#444444",
      })

      -- Override Snacks dashboard highlights
      local hl = vim.api.nvim_set_hl
      hl(0, "SnacksDashboardHeader", { fg = "#5f8787" })
      hl(0, "SnacksDashboardIcon", { fg = "#e78a43" })
      hl(0, "SnacksDashboardKey", { fg = "#e78a43" })
      hl(0, "SnacksDashboardDesc", { fg = "#999999" })
      hl(0, "SnacksDashboardFooter", { fg = "#505050" })
    end,
  },
}
-- [/theme:generated]
