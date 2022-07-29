# vi: ft=bash
# Keep oodles of command history (see https://fburl.com/bashhistory).
HISTFILESIZE=-1
HISTSIZE=1000000
shopt -s histappend

# Set up personal aliases, functions, etc.  See https://fburl.com/bash.
alias notify='echo SEND_TERMINAL_NOTIFICATION'
alias vimdiff='/home/alexpopov/bin/vim -d'
# Add colors to `ls`
alias ls="ls -G --color=always"
alias lg=lazygit


PS1="\[\033[1;38m\]\]\[\$\] \[\033[0;38m\]"
export PS1="\n$PS1"  # Add a new line so it's easier to find where long command start/end

PATH=$HOME/.local/bin:$PATH
export PATH
export NODE_PATH="/usr/local/lib/node_modules"
# Set this to what editor you want to use if
# Bash needs to show you one
export EDITOR=vim

test -e "${HOME}/.iterm2_shell_integration.bash" && source "${HOME}/.iterm2_shell_integration.bash"


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


# Unbinds '\C-l'; usually it clears the screen. I find I do it by accident
# too often when I think I'm in vim
bind -r '\C-l'

[ -f ~/.fzf.bash ] && source ~/.fzf.bash
