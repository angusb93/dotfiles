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

### OpenRouter (pi)

`.zshrc` wraps `pi` so that `OPENROUTER_API_KEY` is populated from 1Password only when pi actually launches.
pi registers the OpenRouter provider from that variable alone, which is why there is no config file here carrying a provider block.

Deliberately *not* used here: any `auth login` flow that persists the key.
Those write it in plaintext into untracked machine-local state, which would have to be redone by hand on every machine - exactly what the golden rule at the top of `AGENTS.md` forbids.

On morty the same key is resolved by the `paseo` user unit instead, once at daemon start, because a daemon has no interactive shell to wrap.
paseo passes it down to every agent it launches.

The item is addressed by ID rather than by title.
Two items in the Private vault differ only by case (`OpenRouter`, an empty Google-sign-in login, and `Openrouter`, the API credential holding the key), and `op read` refuses to guess between them; an ID also survives a later rename.

Override the pointer from `.env.local` if the key ever moves:

```bash
export OPENROUTER_KEY_REF="op://Private/<item-id-or-unique-title>/credential"
```

To verify the wiring end to end:

```bash
# not_ready without the wrapper, ready with it
command pi auth check --provider openrouter
pi auth check --provider openrouter
```

Check the credit balance backing the key with:

```bash
curl -s -H "Authorization: Bearer $(op read --no-newline "$OPENROUTER_KEY_REF")" \
  https://openrouter.ai/api/v1/credits
```

Without credit a key can only reach `:free` models.

---

## Agents on morty (paseo)

`paseo` supervises the agent CLIs on morty - `pi` and `claude-code` - and gives the phone, desktop and web clients a way to drive them.
It ships no agent of its own; it launches whatever is on `PATH`.

The daemon is a user service declared in `nix/hosts/nas/default.nix`, listening on `127.0.0.1:6767` only.
It is reached through pairing rather than an open port:

```bash
paseo daemon pair --relay   # prints an offer URL / QR to open on the phone
```

That is a one-time interactive step and the only part of the setup that is not declarative.
The daemon's default model for `pi` and its listen address are re-asserted from the flake on every start, so a fresh morty needs neither.

Two things are broken in nixpkgs' paseo 0.9.1, both worked around in the unit rather than patched:

- `paseo daemon run` and `paseo daemon start` fail with `Cannot find module .../@getpaseo/server/dist/server/server/exports.js` - the package names an entry point it does not ship. The unit runs `paseo-server`, the supervisor entrypoint those commands wrap.
- `node-pty` has no native binary, so the *workspace terminal* feature throws. Agents themselves do not need a PTY and run fine.

---

## TODO

- [ ] change the prompt to something else that might run faster than starship (or at least benchmark it)
- [x] Add gcal to sketchybar so i dont miss meetings
- [ ] add raycast
