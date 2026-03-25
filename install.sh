#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")" || exit

# Ensure target directories exist
mkdir -p "$HOME/bin"

# Remove stale non-symlink files that would block stow
# (e.g. leftover configs from before dotfiles were managed)
for f in .zshrc; do
  [[ -e "$HOME/$f" && ! -L "$HOME/$f" ]] && rm -rf "$HOME/$f"
done

# Transition ~/.claude from directory-level symlink to real directory
# (preserves runtime data like history, projects, cache)
if [[ -L "$HOME/.claude" ]]; then
  echo "Migrating ~/.claude from directory symlink to real directory..."
  stow -D --target "$HOME" claude 2>/dev/null
  # Copy runtime data from stow package to a real directory
  cp -a "claude/.claude" "$HOME/.claude.tmp"
  mv "$HOME/.claude.tmp" "$HOME/.claude"
  # Remove config files that stow will replace with symlinks
  for f in CLAUDE.md ralph-agents.md settings.json; do
    rm -f "$HOME/.claude/$f"
  done
  rm -rf "$HOME/.claude/skills"
fi

# Ensure ~/.claude exists as a real directory before stowing
mkdir -p "$HOME/.claude"

# Stow everything using default .stowrc (into ~/.config)
stow -R --ignore=zshrc --ignore=claude --ignore=ralph .

# Create symlinks for packages that target $HOME
stow -R --target "$HOME" zshrc
stow -R --target "$HOME" --no-folding claude
stow -R --target "$HOME" ralph

# Generate theme configs from centralized palette
./theme/apply.sh

# Set GH default user if specified
if command -v gh &>/dev/null && [[ -n "$GH_DEFAULT_USER" ]]; then
  gh config set -h github.com user "$GH_DEFAULT_USER"
fi
