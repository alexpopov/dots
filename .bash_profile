alias tmux="TERM=screen-256color-bce tmux"

PS1="\[\033[1;38m\]\]\[\$\] \[\033[0;38m\]"

# Add colors to `ls`
alias ls="ls -G"

# Set this to what editor you want to use if
# Bash needs to show you one
export EDITOR=/home/alexpopov/bin/vim

# Unbinds '\C-l'; usually it clears the screen. I find I do it by accident
# too often when I think I'm in vim
bind -r '\C-l'


# macOS specific section
if [-z "$IS_MACOS"]
then
    # bash completion
    if [ -f $(brew --prefix)/etc/bash_completion ]; then
      . $(brew --prefix)/etc/bash_completion
    fi

    # fuck config
    eval "$(thefuck --alias)"

fi
