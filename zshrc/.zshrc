# ~/.zshrc

# --- Machine-local env (not tracked) ---
[[ -f ~/dotfiles/.env.local ]] && source ~/dotfiles/.env.local

# --- Environment ---
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export LANG="en_US.UTF-8"

# --- PATH ---
export PNPM_HOME="$HOME/Library/pnpm"
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

# --- Aliases ---
alias ll="ls -lah"
alias gs="git status"
alias ..="cd .."
alias ...="cd ../.."
alias lg="lazygit"

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
