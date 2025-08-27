# ~/.zshrc

# ZSH="/home/harshith/.oh-my-zsh"

#Plugins
plugins=(git zsh-autosuggestions)
source $ZSH/oh-my-zsh.sh

# --- Environment ---
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export LANG="en_US.UTF-8"

# --- PATH ---
export PATH="$HOME/.cargo/bin:$HOME/bin:$PATH"

# --- Prompt ---
eval "$(starship init zsh)"  # Requires starship + ~/.config/starship.toml
export STARSHIP_CONFIG=~/.config/starship/starship.toml

# --- Aliases ---
alias ll="ls -lah"
alias gs="git status"
alias ..="cd .."
alias ...="cd ../.."
alias lg="LazyGit"

# --- Completions ---
# autoload -Uz compinit && compinit


# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt inc_append_history        # Save every command as it's typed
setopt share_history             # Share history across terminals

# --- Terminal title (optional) ---
precmd() { print -Pn "\e]0;%n@%m: %~\a" }  # Set terminal title to user@host: cwd

# --- line for direnv ---
eval "$(direnv hook zsh)"
