-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>fa", function()
  Snacks.picker.files({ hidden = true, ignored = true, exclude = { "node_modules" } })
end, { desc = "Find All Files (no node_modules)" })

vim.keymap.set("n", "<leader>fA", function()
  Snacks.picker.files({ hidden = true, ignored = true })
end, { desc = "Find All Files" })
