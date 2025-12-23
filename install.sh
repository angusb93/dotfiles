#!/bin/bash

cd "$(dirname "$0")" || exit

# Stow everythng using default .stowrc (into ~/.config)
stow --ignore=zshrc .

# create symlinks for specific packages that need to be in the home directory
stow --target "$HOME" zshrc
