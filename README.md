# Dotfiles

macOS development environment managed with Nix, nix-darwin, and GNU Stow.

## Stack

| Layer | Tool |
|---|---|
| System config & packages | [nix-darwin](https://github.com/LnL7/nix-darwin) + [nixpkgs](https://nixos.org/) |
| GUI apps | Homebrew casks (via nix-darwin) |
| Dotfile symlinks | [GNU Stow](https://www.gnu.org/software/stow/) |
| Terminal | [Ghostty](https://ghostty.org/) |
| Shell | zsh |
| Multiplexer | tmux |
| Editor | Neovim |
| Window manager | [Aerospace](https://github.com/nikitabobko/AeroSpace) |
| Prompt | Starship |
| Git UI | lazygit |
| Fuzzy finder | fzf |

## How it works

### Nix manages the system

`nix/flake.nix` declares everything installed on the machine — CLI tools, GUI apps, and macOS system defaults (dock, trackpad, key repeat, etc.). Running `darwin-rebuild switch` applies the full system state.

### Stow manages dotfiles

Each top-level directory (e.g. `nvim/`, `tmux/`, `zshrc/`) is a stow package. `install.sh` symlinks them into `~/.config` or `$HOME` as appropriate. The repo lives at `~/dotfiles` and `install.sh` is safe to re-run at any time.

### Theme system

Centralized theming across Ghostty, tmux, Neovim, lazygit, and Starship via a single base16 palette. See [Theme System](#theme-system) below.

### Machine-local config

Machine-specific values live in `~/dotfiles/.env.local` (gitignored). `.zshrc` sources it automatically. See [Machine-local Config](#machine-local-config) below.

---

## Fresh machine setup

### 1. Install Nix

Follow the instructions at [https://nixos.org/](https://nixos.org/)

### 2. Clone dotfiles

```bash
git clone <your-dotfiles-repo-url> ~/dotfiles
```

### 3. Create machine-local config

```bash
# Personal machine
echo 'export GH_DEFAULT_USER=angusb93' >> ~/dotfiles/.env.local

# Work machine
echo 'export GH_DEFAULT_USER=angus-msquared' >> ~/dotfiles/.env.local
```

See `.env.local.example` for all available vars.

### 4. Apply system configuration

```bash
nix run nix-darwin --extra-experimental-features "nix-command flakes" -- switch --flake ~/dotfiles/nix#macbook
```

Installs all packages (including `stow`) and applies macOS system defaults.

### 5. Run the install script

```bash
chmod +x ~/dotfiles/install.sh
~/dotfiles/install.sh
```

Symlinks dotfiles, applies themes, and sets GH user from `$GH_DEFAULT_USER`. Safe to re-run.

### 6. Set up Tmux plugins

```bash
git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
```

Then inside tmux: press `prefix` (`Ctrl+A`), then `I` to install plugins.

### 7. Restart

Ensures all system changes (dock, trackpad, etc.) take effect.

---

## Updating

**Update nix packages:**

```bash
nix flake update
sudo darwin-rebuild switch --flake ~/dotfiles/nix#macbook
```

**Re-apply dotfiles after changes:**

```bash
~/dotfiles/install.sh
```

---

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

---

## Machine-local Config

Machine-specific values (GitHub user, palette overrides, etc.) live in `~/dotfiles/.env.local`, which is sourced by `.zshrc` but never tracked.

See `.env.local.example` for available variables. `install.sh` reads `GH_DEFAULT_USER` and runs `gh config set -h github.com user "$GH_DEFAULT_USER"` automatically.

---

## TODO

- [ ] change the prompt to something else that might run faster than starship (or at least benchmark it)
- [ ] Disable minimise hotkey (cmd + m)
