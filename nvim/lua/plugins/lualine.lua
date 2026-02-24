return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      -- Replace the default pretty_path component with full relative path
      opts.sections.lualine_c = {
        { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
        { "filename", path = 1 },
      }
    end,
  },
}
