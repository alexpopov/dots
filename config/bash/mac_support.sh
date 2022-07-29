function fix_brew {
    echo "running sudo chown..."
    sudo chown -R $(whoami) /usr/local/bin /usr/local/lib /usr/local/sbin
    chmod u+w /usr/local/bin /usr/local/lib /usr/local/sbin
}

# Add bash keybindings for fzf
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
