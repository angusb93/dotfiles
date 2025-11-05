return {
  -- Disable Mason auto-install for LSPs we manage via Nix
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      automatic_installation = false,
    },
  },

  -- Configure LSPs
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = {}, -- Nix LSP (installed via Nix)
      },
    },
  },
}
