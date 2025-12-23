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

## TODO

- Fix the prompt
- Disable minimise hotkey (cmd + m)
- Disable three finger swipe for mission control
- Disable click to desktop
