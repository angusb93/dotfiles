#!/bin/bash

cd "$(dirname "$0")" || exit

# Ensure target directories exist
mkdir -p "$HOME/bin"

# Remove stale non-symlink files that would block stow
# (e.g. leftover configs from before dotfiles were managed)
for f in .zshrc .claude; do
  [[ -e "$HOME/$f" && ! -L "$HOME/$f" ]] && rm -rf "$HOME/$f"
done

# Stow everything using default .stowrc (into ~/.config)
stow -R --ignore=zshrc --ignore=claude --ignore=ralph .

# Create symlinks for packages that target $HOME
stow -R --target "$HOME" zshrc
stow -R --target "$HOME" claude
stow -R --target "$HOME" ralph

# Generate theme configs from centralized palette
./theme/apply.sh
