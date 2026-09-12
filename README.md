# Dotfiles

macOS development environment managed with Nix, nix-darwin, and GNU Stow.

## Stack

| Layer                    | Tool                                                                             |
| ------------------------ | -------------------------------------------------------------------------------- |
| System config & packages | [nix-darwin](https://github.com/LnL7/nix-darwin) + [nixpkgs](https://nixos.org/) |
| GUI apps                 | Homebrew casks (via nix-darwin)                                                  |
| Dotfile symlinks         | [GNU Stow](https://www.gnu.org/software/stow/)                                   |
| Language runtimes        | [mise](https://mise.jdx.dev/)                                                    |
| Terminal                 | [Ghostty](https://ghostty.org/)                                                  |
| Shell                    | zsh                                                                              |
| Multiplexer              | tmux                                                                             |
| Editor                   | Neovim                                                                           |
| Window manager           | [Aerospace](https://github.com/nikitabobko/AeroSpace)                            |
| Prompt                   | Starship                                                                         |
| Git UI                   | lazygit                                                                          |
| Fuzzy finder             | fzf                                                                              |

## How it works

### Nix manages the system

`nix/flake.nix` declares everything installed on the machine — CLI tools, GUI apps, and macOS system defaults (dock, trackpad, key repeat, etc.). Running `darwin-rebuild switch` applies the full system state.

### Stow manages dotfiles

Each top-level directory (e.g. `nvim/`, `tmux/`, `zshrc/`) is a stow package. `install.sh` symlinks them into `~/.config` or `$HOME` as appropriate. The repo lives at `~/dotfiles` and `install.sh` is safe to re-run at any time.

### mise manages language runtimes

Global runtime defaults (currently node) are declared in `mise/config.toml`, which stow symlinks to `~/.config/mise/config.toml`.
Projects override the global by pinning versions in their own `.mise.toml` or `.tool-versions`.
`install.sh` runs `mise install` so a fresh machine gets the pinned runtimes automatically.

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

## Runtime versions (mise)

The global defaults live in `mise/config.toml` (stowed to `~/.config/mise/config.toml`), so changes made with `mise use -g` show up as a git diff in this repo.

```bash
# Change the global default node version (writes to mise/config.toml)
mise use -g node@24

# Install everything pinned in the active mise configs
mise install

# Pin a version for one project (run from the project root; overrides the global)
mise use node@22

# Show which versions are active in the current directory and where they come from
mise current

# List all installed runtimes
mise ls
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

## Secrets (1Password)

API keys are never stored in this repo and never written to a config file on disk.
The repo holds only a 1Password *secret reference* - an `op://vault/item/field` pointer, which is useless without access to the vault - and the key itself is resolved at the moment it is needed.

Secrets are read lazily rather than exported at shell start.
An eager `op read` in `.zshrc` would fire a 1Password unlock prompt every time a terminal or tmux pane opens, so each integration instead resolves its key inside a thin wrapper function around the command that needs it.

### OpenRouter (opencode)

`.zshrc` wraps `opencode` so that `OPENROUTER_API_KEY` is populated from 1Password only when opencode actually launches.
opencode auto-registers the OpenRouter provider from that variable alone, which is why `opencode/opencode.json` carries no provider block.

Deliberately *not* used here: `opencode auth login`.
That writes the key in plaintext to `~/.local/share/opencode/auth.json`, which is untracked machine-local state and would have to be redone by hand on every machine - exactly what the golden rule at the top of `AGENTS.md` forbids.

The item is addressed by ID rather than by title.
Two items in the Private vault differ only by case (`OpenRouter`, an empty Google-sign-in login, and `Openrouter`, the API credential holding the key), and `op read` refuses to guess between them; an ID also survives a later rename.

Override the pointer from `.env.local` if the key ever moves:

```bash
export OPENROUTER_KEY_REF="op://Private/<item-id-or-unique-title>/credential"
```

To verify the wiring end to end:

```bash
# 0 without the wrapper, 367 with it
command opencode models | grep -c '^openrouter/'
opencode models | grep -c '^openrouter/'
```

Note that a free-tier OpenRouter key can only reach `:free` models until credits are added.

---

## TODO

- [ ] change the prompt to something else that might run faster than starship (or at least benchmark it)
- [x] Add gcal to sketchybar so i dont miss meetings
- [ ] add raycast
