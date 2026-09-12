# ~/.zshrc

# --- Machine-local env (not tracked) ---
[[ -f ~/dotfiles/.env.local ]] && source ~/dotfiles/.env.local

# --- Environment ---
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export LANG="en_US.UTF-8"

# --- Claude vertex ---
# CLAUDE_CODE_USE_VERTEX is intentionally not exported globally; vcac sets it per-invocation
export CLOUD_ML_REGION=global
export ANTHROPIC_VERTEX_PROJECT_ID=generally-neat-seahorse
# To assist with cost attribution, include
export ANTHROPIC_CUSTOM_HEADERS="X-Vertex-AI-Labels: $(echo -n "{\"system\": \"claude-code\", \"user\": \"$(whoami | tr '[:upper:].' '[:lower:]-')\"}" | base64 | tr -d '\n')"

# --- PATH ---
# pnpm's home differs by OS (macOS uses ~/Library; Linux follows XDG).
if [[ "$OSTYPE" == darwin* ]]; then
  export PNPM_HOME="$HOME/Library/pnpm"
else
  export PNPM_HOME="$HOME/.local/share/pnpm"
fi
# /run/current-system/sw/bin is the Nix profile path on both nix-darwin and NixOS.
export PATH="/run/current-system/sw/bin:$PNPM_HOME:$HOME/.cargo/bin:$HOME/bin:$PATH"

# --- Prompt & Heavy Plugins ---
# Only load these in interactive shells to keep scripts/tmux fast
if [[ $- == *i* ]]; then
  # Cache directory for shell hooks
  ZSH_CACHE="$HOME/.cache/zsh"
  mkdir -p "$ZSH_CACHE"

  # Lazy/Cached loader for hooks
  load_hook() {
    local name="$1"
    local cmd="$2"
    local cache_file="$ZSH_CACHE/$name.zsh"
    local bin_path="$(command -v "${cmd%% *}" 2>/dev/null)"

    if [[ ! -f "$cache_file" ]] || [[ -n "$bin_path" && "$bin_path" -nt "$cache_file" ]]; then
      eval "$cmd" > "$cache_file" 2>/dev/null
    fi
    source "$cache_file"
  }

  load_hook "starship" "starship init zsh"
  export STARSHIP_CONFIG=~/.config/starship/starship.toml

  load_hook "direnv" "direnv hook zsh"
  load_hook "mise" "mise activate zsh"
  load_hook "fzf" "fzf --zsh"

fi

# --- opencode: OpenRouter key from 1Password ---
# A secret reference is a pointer, not a secret, so it lives in the repo while
# the key itself never touches disk. It is resolved lazily, at the moment
# opencode launches, rather than exported at shell start - so opening a terminal
# or a tmux pane never triggers a 1Password unlock prompt.
#
# The item is addressed by ID rather than by title ("Openrouter", an API
# Credential item in the Private vault). A title reference is ambiguous here -
# an older, empty "OpenRouter" login item differs only by case, and op refuses
# to guess between them - and an ID survives a later rename. Item IDs are
# identifiers, not credentials: useless without access to the vault.
# Point OPENROUTER_KEY_REF at a different item from .env.local to override.
export OPENROUTER_KEY_REF="${OPENROUTER_KEY_REF:-op://Private/tnp6iehqxngjupd4ejqq7b63nm/credential}"

# opencode reads OPENROUTER_API_KEY and auto-registers the OpenRouter provider
# from it, so no provider block is needed in opencode.json.
opencode() {
  if [[ -z "${OPENROUTER_API_KEY:-}" ]] && command -v op &>/dev/null; then
    local key
    if key="$(op read --no-newline "$OPENROUTER_KEY_REF" 2>/dev/null)"; then
      OPENROUTER_API_KEY="$key" command opencode "$@"
      return
    fi
    print -u2 "⚠ opencode: could not read $OPENROUTER_KEY_REF from 1Password - starting without OpenRouter"
  fi
  command opencode "$@"
}

# --- Aliases ---
alias ll="ls -lah"
alias gs="git status"
alias ..="cd .."
alias ...="cd ../.."
alias lg="lazygit"
alias cac="claude agents --cwd ./ --allow-dangerously-skip-permissions"
alias vcac="CLAUDE_CODE_USE_VERTEX=1 claude agents --cwd ./ --allow-dangerously-skip-permissions"
# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt inc_append_history
setopt share_history
setopt hist_ignore_dups
setopt hist_ignore_space

# --- Terminal title ---
precmd() { print -Pn "\e]0;%n@%m: %~\a" }

