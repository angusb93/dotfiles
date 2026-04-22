vim.filetype.add({
  filename = {
    [".env"] = "dotenv",
  },
  pattern = {
    ["%.env"] = { "dotenv", { priority = 10 } },
    ["%.env%..*"] = { "dotenv", { priority = 10 } },
  },
})
