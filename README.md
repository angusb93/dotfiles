# 🛠️ Dotfiles Setup Guide (macOS with Nix)

This guide will help you set up your development environment using [Nix](https://nixos.org/), `nix-darwin`, and your custom dotfiles.

---

## ✅ Prerequisites

1. **Install Nix**  
   Follow the instructions at [https://nixos.org/](https://nixos.org/)

---

## 📁 Set Up Dotfiles

2. **Clone Your Dotfiles Repository**

   ```bash
   git clone <your-dotfiles-repo-url> ~/dotfiles
   ```

3. **Apply System Configuration**

   ```bash
   nix run nix-darwin --extra-experimental-features "nix-command flakes" -- switch --flake ~/dotfiles/nix#macbook
   ```

   This will install your system config and necessary programs (including `stow`).

---

## 🔗 Configure Symlinks with Stow

4. **Create Symlinks**

   ```bash
   cd ~/dotfiles
   stow .
   ```

   > 💡 You may need to manually create the `~/.config` directory first.

---

## 🚀 Run Installation Script

5. **Make the script executable**

   ```bash
   chmod +x ~/dotfiles/install.sh
   ```

6. **Run the script**

   ```bash
   ~/dotfiles/install.sh
   ```

7. **Restart your computer**

   This ensures all changes are applied properly.

---

## 🧰 Set Up Tmux Plugins

8. **Install TPM (Tmux Plugin Manager)**

   ```bash
   git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
   ```

9. **Install Tmux Plugins**

   Press `prefix` (`Ctrl + A`), then press `I` to trigger TPM and install plugins.

10. **Source the Tmux config**

```bash
tmux source-file ~/dotfiles/tmux/.conf
```

---

✅ You’re all set! Enjoy your fully configured development environment.

## Docs

**Updating nix flake**
run these commands to update your system with the latest from nix packages

```bash
nix flake update
sudo darwin-rebuild switch --flake ~/dotfiles/nix#macbook
```

## Theme System

Centralized theming across Ghostty, tmux, Neovim, lazygit, and Starship. All configs are generated from a single base16 palette.

### How it works

`theme/colors.sh` sources the active palette from `theme/palettes/`. Running `theme/apply.sh` regenerates configs for all tools from that palette.

Generated files (do not edit directly):
- `ghostty/config` (theme block)
- `tmux/theme.conf`
- `nvim/lua/plugins/colorscheme.lua`
- `~/Library/Application Support/lazygit/config.yml`
- `starship/starship.toml`

### Commands

```bash
# Apply the default palette (set in colors.sh)
bash ~/dotfiles/theme/apply.sh

# Test a different palette without changing the default
PALETTE=dark-funeral bash ~/dotfiles/theme/apply.sh

# Change the default palette permanently
# Edit theme/colors.sh → PALETTE="${PALETTE:-dark-funeral}"

# Reload theme inside Neovim (after apply.sh has run)
:ReloadTheme
```

tmux reloads automatically when apply.sh runs inside a tmux session. Ghostty requires a restart.

### Available palettes

**Black Metal** ([source](https://github.com/metalelf0/base16-black-metal-scheme)) — plus a customized `bathory`:

`bathory` (default), `black-metal`, `burzum`, `dark-funeral`, `gorgoroth`, `immortal`, `khold`, `marduk`, `mayhem`, `nile`, `venom`

**Popular themes** ([source](https://github.com/tinted-theming/schemes)):

`tokyonight`, `tokyonight-storm`, `catppuccin-mocha`, `catppuccin-frappe`, `catppuccin-macchiato`, `catppuccin-latte` (light), `gruvbox-dark`, `rose-pine`, `rose-pine-moon`, `nord`, `kanagawa`

### Creating a new palette

```bash
cp theme/palettes/bathory.sh theme/palettes/mypalette.sh
# Edit BASE00–BASE0F values
PALETTE=mypalette bash ~/dotfiles/theme/apply.sh
```

### Notes

- Neovim and tmux use hex colors from the palette directly, so they're unaffected by terminal palette changes.
- Ghostty and Neovim terminal override ANSI red/green (slots 1/2/9/10) with `#cc6666`/`#66cc66` for clear staging/diff colors in lazygit and git CLI.
- Lazygit theme is configured both via its config.yml and via Snacks.lazygit in Neovim (which generates `~/.cache/nvim/lazygit-theme.yml` from Neovim highlight groups).

## Machine-local Config

Machine-specific values (GitHub user, palette overrides, etc.) live in `~/dotfiles/.env.local`, which is sourced by `.zshrc` but never tracked.

Create it before running `install.sh`:

```sh
# Personal machine
echo 'export GH_DEFAULT_USER=angusb93' >> ~/dotfiles/.env.local

# Work machine
echo 'export GH_DEFAULT_USER=angus-msquared' >> ~/dotfiles/.env.local
```

`install.sh` reads `GH_DEFAULT_USER` and runs `gh config set -h github.com user "$GH_DEFAULT_USER"` automatically.

## TODO

- Fix the prompt
- Disable minimise hotkey (cmd + m)
- Disable three finger swipe for mission control
- Disable click to desktop
