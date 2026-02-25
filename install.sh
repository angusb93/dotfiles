#!/bin/bash

cd "$(dirname "$0")" || exit

# Stow everything using default .stowrc (into ~/.config)
stow --ignore=zshrc --ignore=claude --ignore=ralph .

# Create symlinks for packages that target $HOME
stow --target "$HOME" zshrc
stow --target "$HOME" claude
stow --target "$HOME" ralph

# Generate theme configs from centralized palette
./theme/apply.sh
