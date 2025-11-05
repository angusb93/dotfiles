return {
  -- Disable Mason auto-install for LSPs we manage via Nix
  {
    "mason-org/mason-lspconfig.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      opts.automatic_installation = false
    end,
  },

  -- Configure LSPs
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = {
          mason = false, -- Don't use Mason for nil_ls
        },
      },
    },
  },
}
