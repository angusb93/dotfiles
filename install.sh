#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")" || exit

# Ensure target directories exist
mkdir -p "$HOME/bin"

# Move aside real files that would block stow - leftovers from before dotfiles
# managed them. stow refuses to overwrite anything that is not already a symlink
# it owns, so these have to go before the corresponding `stow` call below.
#
# Backed up rather than deleted: a hand-written config may hold settings worth
# migrating (~/.ssh/config especially, since host entries are deliberately
# untracked here and belong in ~/.ssh/config.d/*.conf). Only the named file is
# touched - never the directory - so ssh keys and known_hosts are left alone.
for f in .zshrc .ssh/config .config/mise/config.toml; do
  target="${HOME:?}/$f"
  [[ -e "$target" && ! -L "$target" ]] || continue
  backup="$target.pre-dotfiles"
  [[ -e "$backup" ]] && backup="$backup.$(date +%Y%m%d%H%M%S)"
  echo "Backing up pre-existing $f -> ${backup#"$HOME/"}"
  mv "$target" "$backup"
done

# Transition ~/.claude from directory-level symlink to real directory
# (preserves runtime data like history, projects, cache)
if [[ -L "$HOME/.claude" ]]; then
  echo "Migrating ~/.claude from directory symlink to real directory..."
  stow -D --target "$HOME" claude 2>/dev/null
  # Copy runtime data from stow package to a real directory
  cp -a "claude/.claude" "$HOME/.claude.tmp"
  mv "$HOME/.claude.tmp" "$HOME/.claude"
  # Remove config files that stow and the settings step below recreate
  for f in CLAUDE.md settings.json; do
    rm -f "$HOME/.claude/$f"
  done
  rm -rf "$HOME/.claude/skills"
fi

# Ensure ~/.claude exists as a real directory before stowing
mkdir -p "$HOME/.claude"

# Stow everything using default .stowrc (into ~/.config)
# Ignore packages that target $HOME (handled below) and non-stow directories.
# Built as one array (never empty) so `set -u` stays happy on bash 3.2, the
# /bin/bash macOS ships - there, expanding an empty array is an "unbound
# variable" error.
stow_ignores=(
  --ignore='\.claude'
  --ignore=zshrc
  --ignore=claude
  --ignore=ssh
  --ignore='glove80.*'
  --ignore=chrome
  --ignore=wallpapers
  --ignore=theme
  --ignore=result
)

# When stowing on Linux (e.g. the NAS), skip things that don't belong there:
#  - macOS-only GUI app configs (aerospace/sketchybar/ghostty) - apps absent
#  - gh: the server manages its own gh auth; don't clobber ~/.config/gh
#  - nix: never fold ~/.config/nix -> the flake dir (NixOS reads ~/.config/nix/)
#  - non-config top-level items that shouldn't land in ~/.config at all
if [[ "$(uname)" != "Darwin" ]]; then
  stow_ignores+=(
    --ignore=aerospace --ignore=sketchybar --ignore=ghostty
    --ignore=gh --ignore=nix --ignore=scripts
    --ignore=install.sh --ignore=AGENTS.md --ignore=CLAUDE.md
    --ignore='.env.local.example'
  )
fi

stow -R "${stow_ignores[@]}" .

# Create symlinks for packages that target $HOME
stow -R --target "$HOME" zshrc
stow -R --target "$HOME" --no-folding claude

# ~/.claude/settings.json is written from the repo copy rather than symlinked
# (it is in claude/.stow-local-ignore). Claude Code saves runtime state into
# this file - the current model on every /model or /fast switch, and it reorders
# keys - which through a symlink dirtied the repo and blocked pulls.
#
# The repo copy wins wholesale, so removing a key here removes it live too. The
# only exception is claude_runtime_keys, which keep their live value. Anything
# else that only exists live (e.g. a /config change) is printed as a diff before
# it is overwritten, so it can be copied into the repo.
command -v jq &>/dev/null || {
  echo "jq is required to install Claude Code settings - apply the nix flake first" >&2
  exit 1
}
claude_settings_repo=claude/.claude/settings.json
claude_settings_live="$HOME/.claude/settings.json"
claude_runtime_keys='["model"]'
claude_live_settings='{}'
if [[ -e "$claude_settings_live" ]]; then
  if ! claude_live_settings=$(jq -e 'objects' "$claude_settings_live" 2>/dev/null); then
    echo "⚠ $claude_settings_live is not a JSON object - replacing it with the repo copy"
    claude_live_settings='{}'
  else
    # shellcheck disable=SC2016 # $k and $runtime are jq variables
    strip_runtime='with_entries(select(.key as $k | any($runtime[]; . == $k) | not))'
    if ! diff -u --label "live $claude_settings_live" --label "repo $claude_settings_repo" \
      <(jq -S --argjson runtime "$claude_runtime_keys" "$strip_runtime" <<<"$claude_live_settings") \
      <(jq -S --argjson runtime "$claude_runtime_keys" "$strip_runtime" "$claude_settings_repo"); then
      echo "⚠ Live-only Claude Code settings above (- lines) are being overwritten; copy any worth keeping into $claude_settings_repo"
    fi
  fi
fi
claude_settings_tmp=$(mktemp "$claude_settings_live.XXXXXX")
# shellcheck disable=SC2016 # $k and $runtime are jq variables
jq -s --argjson runtime "$claude_runtime_keys" \
  '.[1] + (.[0] | with_entries(select(.key as $k | any($runtime[]; . == $k))))' \
  <(printf '%s' "$claude_live_settings") "$claude_settings_repo" >"$claude_settings_tmp"
# mv replaces a leftover stow symlink itself rather than writing through it
mv "$claude_settings_tmp" "$claude_settings_live"

# --no-folding so stow symlinks ~/.ssh/config individually rather than the whole
# ~/.ssh dir (which holds keys and known_hosts that must stay real local files).
stow -R --target "$HOME" --no-folding ssh
# Host entries live in ~/.ssh/config.d/*.conf and are deliberately NOT managed
# here: they name private infrastructure and this repo is public. Nothing is
# created for them on purpose - the Include in ssh/.ssh/config is a glob, which
# exits 0 when the directory is absent, so dotfiles installs and works fully
# without them. Host aliases are an optional overlay, never a dependency.

# Generate theme configs from centralized palette.
# macOS only: the generator uses BSD-specific tooling (sed -i '') and writes to
# mac app paths. On Linux the already-generated theme files (nvim colorscheme,
# tmux/theme.conf, starship.toml) are committed and stowed, so no regen needed -
# only re-run this on a Mac when changing the palette.
if [[ "$(uname)" == "Darwin" ]]; then
  ./theme/apply.sh
fi

# Install mise-managed global runtimes (e.g. node) from ~/.config/mise/config.toml.
# Non-fatal: a runtime download hiccup shouldn't abort the whole stow install.
if command -v mise &>/dev/null; then
  mise install --yes || echo "⚠ mise install failed (continuing)"
fi

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
