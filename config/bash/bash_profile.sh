# vi: ft=bash
# Keep oodles of command history (see https://fburl.com/bashhistory).
HISTFILESIZE=-1
HISTSIZE=1000000
shopt -s histappend

# Control-D won't kill shell
IGNOREEOF=10

# Set up personal aliases, functions, etc.  See https://fburl.com/bash.
alias notify='echo SEND_TERMINAL_NOTIFICATION'
alias vimdiff='nvim -d'
# Add colors to `ls`
if [[ "$OSTYPE" == "darwin"* ]]; then
  alias ls="ls -G"
else
  alias ls="ls --color=always"
fi
alias lg=lazygit


# Default prompt prefix based on platform (can be overridden before sourcing)
if [[ -z "$PROMPT_PREFIX" ]] && ! declare -F run_prompt_prefix > /dev/null; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    PROMPT_PREFIX=""
  elif grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    PROMPT_PREFIX="\[\e[1;32m\]pi\[\e[m\] "
  else
    PROMPT_PREFIX="\[\e[34m\]\h\[\e[m\] "
  fi
fi

function set_ps1 {
  local last_exit_code=$?
  if declare -F run_prompt_prefix > /dev/null; then
    PS1="$(run_prompt_prefix $last_exit_code)"
  else
    PS1="$PROMPT_PREFIX"
  fi
  PS1+="\[\033[1;38m\]\]\[\$\] \[\033[0;38m\]"
  export PS1="\n$PS1"  # Add a new line so it's easier to find where long command start/end
}
PROMPT_COMMAND=set_ps1

PATH="$HOME/.local/bin:$PATH"
PATH="$PATH:$HOME/.local/bin/scripts"
export PATH
export NODE_PATH="/usr/local/lib/node_modules"
export NVIM_PYTHON="$HOME/.local/virtualenvs/nvim/bin/python3"

# Set editor to nvim if available, otherwise vim
if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim
else
  export EDITOR=vim
fi

test -e "${HOME}/.iterm2_shell_integration.bash" && source "${HOME}/.iterm2_shell_integration.bash"


# OSC52 clipboard (pbcopy shim for remote terminals)
if ! command -v pbcopy >/dev/null 2>&1; then
  pbcopy() { printf '\033]52;c;%s\a' "$(base64 < "${1:-/dev/stdin}")"; }
fi

# My Functions

function agr {
    ag -0 -l "$1" | AGR_FROM="$1" AGR_TO="$2" xargs -r0 perl -pi -e 's/$ENV{AGR_FROM}/$ENV{AGR_TO}/g';
}

# tmux resizing
function jk_tmux_resize_third () {
    ~/.tmux/scripts/resize-adaptable.sh -p 33 -l main-vertical
}

function jk_tmux_resize_small () {
    ~/.tmux/scripts/resize-adaptable.sh -p 25 -l main-vertical
}

function jk_tmux_resize_equal () {
    tmux select-layout even-horizontal
}

function vime {
  nvr --remote $@
}

function nvr {
  local window_name=""

  # Get tmux window name if in tmux session
  if [[ -n "$TMUX" ]]; then
    window_name=$(tmux display-message -p '#W')
  fi

  # If not in tmux or window name is "bash", prompt for a new name
  if [[ -z "$TMUX" ]] || [[ "$window_name" == "bash" ]]; then
    local new_name=$(gum input --placeholder "Enter a name for this nvr session")
    if [[ -z "$new_name" ]]; then
      echo "Error: No name provided"
      return 1
    fi
    # Rename the tmux window if we're in tmux
    if [[ -n "$TMUX" ]]; then
      tmux rename-window "$new_name"
    fi
    window_name="$new_name"
  fi

  # Create socket directory if it doesn't exist
  mkdir -p ~/.local/state

  # Use nvr-classic with the named socket
  local socket_path="$HOME/.local/state/nvr-$window_name"
  nvr-classic --servername "$socket_path" "$@"
}

function jk_choose_dirs_v {
  (IFS=$'\n'; gum filter $(dirs -v) | awk '{ print "+" $1 }')
}

# fd respects gitignores
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git --exclude node_modules'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

alias dv="pushd \$(jk_choose_dirs_v)"

# Unbinds '\C-l'; usually it clears the screen. I find I do it by accident
# too often when I think I'm in vim
bind -r '\C-l'

[ -f ~/.config/fzf/fzf.bash ] && source ~/.config/fzf/fzf.bash

# Platform-specific support
BASH_CONFIG_DIR="$HOME/.config/bash"
if grep -qi microsoft /proc/version 2>/dev/null; then
  [ -f "$BASH_CONFIG_DIR/wsl_support.sh" ] && . "$BASH_CONFIG_DIR/wsl_support.sh"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  [ -f "$BASH_CONFIG_DIR/mac_support.sh" ] && . "$BASH_CONFIG_DIR/mac_support.sh"
elif grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
  [ -f "$BASH_CONFIG_DIR/pi_support.sh" ] && . "$BASH_CONFIG_DIR/pi_support.sh"
fi

# Mercurial support (only if hg is installed)
command -v hg >/dev/null 2>&1 && [ -f "$BASH_CONFIG_DIR/hg_support.sh" ] && . "$BASH_CONFIG_DIR/hg_support.sh"

# Tmux pane observatory
[ -f "$BASH_CONFIG_DIR/tmux_observatory.sh" ] && . "$BASH_CONFIG_DIR/tmux_observatory.sh"

# Sanity check (always last)
[ -f "$BASH_CONFIG_DIR/sanity_check.sh" ] && . "$BASH_CONFIG_DIR/sanity_check.sh"
