# Agent Guidelines for Dotfiles Repository

## Build/Lint/Test Commands
- **Nix formatting**: `nixfmt-rfc-style .` (format Nix files)
- **Lua formatting**: `stylua .` (format Lua config files, 2-space indent, 120 char width)
- **System rebuild**: `darwin-rebuild switch --flake ~/dotfiles/nix#macbook`
- **Update flake**: `nix flake update && sudo darwin-rebuild switch --flake ~/dotfiles/nix#macbook`

## Code Style Guidelines

### Nix Files
- Use `nixfmt-rfc-style` for formatting
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