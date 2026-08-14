# Agent Guidelines for Dotfiles Repository

## Golden rule: this repo is the source of truth

Every machine's configuration is declared here and applied from here. Never
configure a machine imperatively - always change the source and re-apply.

- **Installing a program?** Add it to the Nix flake (`nix/`), not `brew install`
  / `npm i -g` / a manual download. `darwin-rebuild switch --flake ~/dotfiles/nix#macbook`
  (or `nixos-rebuild ... #nas`) applies it.
- **Adding/editing a config file?** Put it in the matching stow package here and
  let `stow` symlink it into place - don't hand-edit the file under `$HOME`. New
  packages that target `$HOME` (rather than `~/.config`) must be wired into
  `install.sh` like `zshrc` / `claude` / `ssh`.
- **Applying changes:** run `./install.sh` (stow + mise + MCP + theme) after a
  rebuild. The repo, pushed to `main`, syncs to every machine via `git pull`.

This repo is **public** - never commit secrets (keys, tokens, `known_hosts`).
Use `sops-nix` for anything sensitive; gitignore the rest.

## Build/Lint/Test Commands
- **Nix formatting**: `fd -e nix -E hardware-configuration.nix -x nixfmt` (the `nixfmt` binary is already RFC-style; passing it a directory is deprecated, hence `fd -x`, and the generated hardware config is left alone)
- **Nix linting**: `statix check .` (rule exclusions live in `statix.toml`)
- **Lua formatting**: `stylua .` (format Lua config files, 2-space indent, 120 char width)
- **System rebuild**: `darwin-rebuild switch --flake ~/dotfiles/nix#macbook`
- **Update flake**: `nix flake update && sudo darwin-rebuild switch --flake ~/dotfiles/nix#macbook`

## Code Style Guidelines

### Nix Files
- Use `nixfmt` for formatting (v1.x implements the RFC 166 style)
- Follow functional programming patterns
- Keep attribute sets clean and well-structured

### Lua Configuration (Neovim)
- 2-space indentation, 120 character line width
- Follow LazyVim conventions
- Use lazy.nvim for plugin management
- Keep config modular (options.lua, keymaps.lua, autocmds.lua)

### Shell Configuration
- Use ZSH with starship prompt
- Keep aliases simple and descriptive
- Use direnv for environment management

### General Principles
- Use GNU Stow for symlink management
- Keep configurations declarative where possible
- Prefer Nix packages over manual installations
- Maintain separation between system and user configs