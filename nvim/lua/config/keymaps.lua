-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>fa", function()
  Snacks.picker.files({ hidden = true, ignored = true, exclude = { "node_modules" } })
end, { desc = "Find All Files (no node_modules)" })

vim.keymap.set("n", "<leader>fA", function()
  Snacks.picker.files({ hidden = true, ignored = true })
end, { desc = "Find All Files" })

vim.keymap.set("n", "<leader>sd", function()
  Snacks.picker.grep({ dirs = { vim.fn.input("Dir: ", "", "dir") } })
end, { desc = "Grep in Directory" })

-- Lazygit: when you switch worktrees/repos inside lazygit and quit, cd nvim
-- there too, instead of snapping back to the directory you opened it from.
-- Mirrors the LAZYGIT_NEW_DIR_FILE shell-wrapper pattern lazygit documents,
-- since Snacks.terminal has no shell wrapper to catch the exit itself.
--
-- Watches for the file via libuv fs_event rather than hooking TermClose:
-- Snacks' own auto_close TermClose handler (registered first) wipes the
-- terminal buffer, which silently stops any TermClose autocmd registered
-- after it on the same buffer from ever firing.
--
-- Sets LAZYGIT_NEW_DIR_FILE via vim.env (inherited by the spawned job)
-- rather than opts.env: Snacks hashes opts.env into the terminal's identity,
-- so a fresh value on every call would defeat toggle/reuse of an
-- already-open lazygit terminal and spawn a new one each press.
--
-- lazygit rewrites this file on every worktree/repo switch, not just at
-- quit, so the watcher must keep running across multiple writes in the
-- same session (e.g. switching to another worktree, then back to main)
-- rather than stopping after the first one.
local function lazygit_cd(opts)
  opts = opts or {}
  local newdir_file = vim.fn.tempname()
  local watch_dir = vim.fn.fnamemodify(newdir_file, ":h")
  local watch_name = vim.fn.fnamemodify(newdir_file, ":t")
  vim.env.LAZYGIT_NEW_DIR_FILE = newdir_file

  local fs_event = vim.uv.new_fs_event()
  local function stop()
    if fs_event then
      fs_event:stop()
      fs_event:close()
      fs_event = nil
    end
    os.remove(newdir_file)
  end

  local ok = fs_event:start(
    watch_dir,
    {},
    vim.schedule_wrap(function(err, filename)
      if err or filename ~= watch_name then
        return
      end
      local f = io.open(newdir_file, "r")
      if not f then
        return
      end
      local dir = vim.trim(f:read("*a") or "")
      f:close()
      if dir ~= "" and vim.fn.isdirectory(dir) == 1 then
        vim.cmd.cd(dir)
        vim.notify("cwd -> " .. dir)
      end
    end)
  )
  if not ok then
    stop()
  end
  vim.defer_fn(stop, 10 * 60 * 1000) -- stop watching once lazygit is done / left open unused

  Snacks.lazygit(opts)
end

vim.keymap.set("n", "<leader>gg", function()
  lazygit_cd({ cwd = LazyVim.root.git() })
end, { desc = "Lazygit (Root Dir)" })
vim.keymap.set("n", "<leader>gG", function()
  lazygit_cd()
end, { desc = "Lazygit (cwd)" })
