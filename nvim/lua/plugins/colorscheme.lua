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
        base01 = "#282828",
        base02 = "#494949",
        base03 = "#666666",
        base04 = "#afafaf",
        base05 = "#d7d7d7",
        base06 = "#afafaf",
        base07 = "#d7d7d7",
        base08 = "#5f8787",
        base09 = "#c0c0c0",
        base0A = "#e78a43",
        base0B = "#fbcb97",
        base0C = "#c0c0c0",
        base0D = "#9e9e9e",
        base0E = "#afafaf",
        base0F = "#5a5a5a",
      })

      -- Override Snacks dashboard highlights
      local hl = vim.api.nvim_set_hl
      hl(0, "SnacksDashboardHeader", { fg = "#5f8787" })
      hl(0, "SnacksDashboardIcon", { fg = "#e78a43" })
      hl(0, "SnacksDashboardKey", { fg = "#e78a43" })
      hl(0, "SnacksDashboardDesc", { fg = "#afafaf" })
      hl(0, "SnacksDashboardFooter", { fg = "#666666" })

      -- Picker
      hl(0, "SnacksPickerMatch", { fg = "#e78a43", bold = true })
      hl(0, "SnacksPickerBorder", { fg = "#666666" })
      hl(0, "SnacksPickerInputBorder", { fg = "#666666" })
      hl(0, "SnacksPickerListBorder", { fg = "#666666" })
      hl(0, "SnacksPickerPreviewBorder", { fg = "#666666" })
      hl(0, "SnacksPickerTitle", { fg = "#5f8787", bold = true })
      hl(0, "SnacksPickerInputTitle", { fg = "#5f8787", bold = true })
      hl(0, "SnacksPickerListTitle", { fg = "#5f8787", bold = true })
      hl(0, "SnacksPickerPreviewTitle", { fg = "#5f8787", bold = true })
      hl(0, "SnacksPickerListCursorLine", { bg = "#494949", bold = true })
      hl(0, "SnacksPickerPrompt", { fg = "#e78a43" })
      hl(0, "SnacksPickerDir", { fg = "#666666" })

      -- Floating windows (general)
      hl(0, "FloatTitle", { fg = "#5f8787", bold = true })
      hl(0, "FloatBorder", { fg = "#666666" })

      -- Lazygit (used by Snacks.lazygit theme mapping)
      hl(0, "LazyGitActiveBorder", { fg = "#5f8787" })
      hl(0, "LazyGitUnstaged", { fg = "#cc6666" })
      hl(0, "LazyGitSelectedLine", { bg = "#282828" })

      -- Override terminal ANSI red/green for lazygit staging & diffs
      vim.g.terminal_color_1  = "#cc6666"  -- red
      vim.g.terminal_color_2  = "#66cc66"  -- green
      vim.g.terminal_color_9  = "#cc6666"  -- bright red
      vim.g.terminal_color_10 = "#66cc66"  -- bright green

      -- Diagnostics
      hl(0, "DiagnosticError", { fg = "#cc6666" })
      hl(0, "DiagnosticWarn", { fg = "#e78a43" })
      hl(0, "DiagnosticInfo", { fg = "#9e9e9e" })
      hl(0, "DiagnosticHint", { fg = "#666666" })
      hl(0, "DiagnosticUnderlineError", { undercurl = true, sp = "#cc6666" })
      hl(0, "DiagnosticUnderlineWarn", { undercurl = true, sp = "#e78a43" })
      hl(0, "DiagnosticUnderlineInfo", { undercurl = true, sp = "#9e9e9e" })
      hl(0, "DiagnosticUnderlineHint", { undercurl = true, sp = "#666666" })

      -- Completion popup
      hl(0, "BlinkCmpMenuBorder", { fg = "#666666" })
      hl(0, "BlinkCmpDocBorder", { fg = "#666666" })
      hl(0, "BlinkCmpLabelMatch", { fg = "#e78a43", bold = true })
      hl(0, "BlinkCmpMenuSelection", { bg = "#494949" })
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
