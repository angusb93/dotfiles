-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Disable swap files to avoid E325 ATTENTION errors
vim.opt.swapfile = false

-- Always use current working directory as root
vim.g.root_spec = { "cwd" }
