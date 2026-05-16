return {
  -- All tools managed by Nix — disable Mason entirely
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Nix
        nil_ls = {},
        -- Go
        gopls = {},
        -- Terraform
        terraformls = {
          on_attach = function(client, bufnr)
            client.server_capabilities.documentFormattingProvider = false
            client.server_capabilities.documentRangeFormattingProvider = false
          end,
        },
        -- TypeScript/JavaScript
        vtsls = {},
        eslint = {},
        -- Web
        svelte = {},
        tailwindcss = {},
        -- General
        lua_ls = {},
        bashls = {},
        jsonls = {},
        yamlls = {},
        marksman = {},
        taplo = {},
        biome = {},
      },
    },
  },

  -- Configure linting with nvim-lint
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        terraform = { "tflint" },
        tf = { "tflint" },
      },
      linters = {},
    },
  },

  -- Configure formatting with conform.nvim
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        terraform = { "terraform_fmt" },
        tf = { "terraform_fmt" },
        ["terraform-vars"] = { "terraform_fmt" },
        markdown = {},
        ["markdown.mdx"] = {},
      },
    },
  },
}
