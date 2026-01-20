# ~/.zshrc

# --- Environment ---
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export LANG="en_US.UTF-8"

# --- PATH ---
export PATH="/run/current-system/sw/bin:$HOME/.cargo/bin:$HOME/bin:$PATH"

# --- Prompt & Heavy Plugins ---
# Only load these in interactive shells to keep scripts/tmux fast
if [[ $- == *i* ]]; then
  eval "$(starship init zsh)"
  export STARSHIP_CONFIG=~/.config/starship/starship.toml

  eval "$(direnv hook zsh)"
  eval "$(fzf --zsh)"

  export NVM_DIR="$HOME/.nvm"
  [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && \. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
  [ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && \. "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
fi

# --- Aliases ---
alias ll="ls -lah"
alias gs="git status"
alias ..="cd .."
alias ...="cd ../.."
alias lg="lazygit"

# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt inc_append_history
setopt share_history

# --- Terminal title ---
precmd() { print -Pn "\e]0;%n@%m: %~\a" }
