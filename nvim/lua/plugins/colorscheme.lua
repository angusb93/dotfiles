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

      -- Picker
      hl(0, "SnacksPickerMatch", { fg = "#e78a43", bold = true })
      hl(0, "SnacksPickerBorder", { fg = "#505050" })
      hl(0, "SnacksPickerInputBorder", { fg = "#505050" })
      hl(0, "SnacksPickerListBorder", { fg = "#505050" })
      hl(0, "SnacksPickerPreviewBorder", { fg = "#505050" })
      hl(0, "SnacksPickerTitle", { fg = "#5f8787", bold = true })
      hl(0, "SnacksPickerInputTitle", { fg = "#5f8787", bold = true })
      hl(0, "SnacksPickerListTitle", { fg = "#5f8787", bold = true })
      hl(0, "SnacksPickerPreviewTitle", { fg = "#5f8787", bold = true })
      hl(0, "SnacksPickerListCursorLine", { bg = "#333333", bold = true })
      hl(0, "SnacksPickerPrompt", { fg = "#e78a43" })
      hl(0, "SnacksPickerDir", { fg = "#505050" })

      -- Floating windows (general)
      hl(0, "FloatTitle", { fg = "#5f8787", bold = true })
      hl(0, "FloatBorder", { fg = "#505050" })

      -- Lazygit (used by Snacks.lazygit theme mapping)
      hl(0, "LazyGitActiveBorder", { fg = "#5f8787" })
      hl(0, "LazyGitUnstaged", { fg = "#cc6666" })
      hl(0, "LazyGitSelectedLine", { bg = "#121212" })

      -- Override terminal ANSI red/green for lazygit staging & diffs
      vim.g.terminal_color_1  = "#cc6666"  -- red
      vim.g.terminal_color_2  = "#66cc66"  -- green
      vim.g.terminal_color_9  = "#cc6666"  -- bright red
      vim.g.terminal_color_10 = "#66cc66"  -- bright green

      -- Completion popup
      hl(0, "BlinkCmpMenuBorder", { fg = "#505050" })
      hl(0, "BlinkCmpDocBorder", { fg = "#505050" })
      hl(0, "BlinkCmpLabelMatch", { fg = "#e78a43", bold = true })
      hl(0, "BlinkCmpMenuSelection", { bg = "#333333" })
    end,
  },

  -- Snacks lazygit theme overrides
  {
    "folke/snacks.nvim",
    opts = {
      lazygit = {
        theme = {
          activeBorderColor          = { fg = "LazyGitActiveBorder", bold = true },
          inactiveBorderColor        = { fg = "FloatBorder" },
          selectedLineBgColor        = { bg = "LazyGitSelectedLine", bold = true },
          unstagedChangesColor       = { fg = "LazyGitUnstaged" },
          defaultFgColor             = { fg = "Normal" },
          searchingActiveBorderColor = { fg = "LazyGitActiveBorder", bold = true },
        },
      },
    },
  },
}
-- [/theme:generated]
