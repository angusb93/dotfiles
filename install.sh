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
  for f in CLAUDE.md settings.json; do
    rm -f "$HOME/.claude/$f"
  done
  rm -rf "$HOME/.claude/skills"
fi

# Ensure ~/.claude exists as a real directory before stowing
mkdir -p "$HOME/.claude"

# Stow everything using default .stowrc (into ~/.config)
# Ignore packages that target $HOME (handled below) and non-stow directories
stow -R \
  --ignore='\.claude' \
  --ignore=zshrc \
  --ignore=claude \
  --ignore=ralph \
  --ignore='glove80.*' \
  --ignore=chrome \
  --ignore=wallpapers \
  --ignore=theme \
  --ignore=result \
  .

# Create symlinks for packages that target $HOME
stow -R --target "$HOME" zshrc
stow -R --target "$HOME" --no-folding claude
stow -R --target "$HOME" ralph

# Generate theme configs from centralized palette
./theme/apply.sh

# Register Claude Code MCP servers (idempotent)
if command -v claude &>/dev/null; then
  claude mcp add -s user playwright bunx @playwright/mcp 2>/dev/null || true
fi

# Switch gh account if specified
if command -v gh &>/dev/null && [[ -n "${GH_DEFAULT_USER:-}" ]]; then
  gh auth switch --user "$GH_DEFAULT_USER"
fi

# Restart AeroSpace so the running app matches the freshly-installed binary.
# nix updates the binary but doesn't restart the running process, leaving the
# aerospace CLI and server on incompatible socket protocols until relaunch.
# Run install.sh after `darwin-rebuild switch` for this to take effect.
if [[ "$(uname)" == "Darwin" ]] && command -v aerospace &>/dev/null; then
  echo "Restarting AeroSpace to match the installed binary..."
  osascript -e 'quit app "AeroSpace"' 2>/dev/null || true
  # Wait for the old process to exit before relaunching (avoids single-instance race)
  for _ in {1..20}; do
    pgrep -x AeroSpace >/dev/null 2>&1 || break
    sleep 0.2
  done
  open -a AeroSpace 2>/dev/null || true
  # Repaint sketchybar's workspace items once the server is back up
  if command -v sketchybar &>/dev/null; then
    sleep 2
    "$HOME/.config/sketchybar/plugins/aerospace.sh" 2>/dev/null || true
  fi
fi
