-- Detect .env files as dotenv before anything else loads
vim.filetype.add({
  pattern = {
    ["%.env"] = "dotenv",
    ["%.env%..*"] = "dotenv",
  },
})

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
