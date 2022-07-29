<<<<<<< HEAD
function jk_mac_fix_brew {
=======
function fix_brew {
>>>>>>> 51f3da8 (Lots of changes, added lots of mac-specific stuff)
    echo "running sudo chown..."
    sudo chown -R $(whoami) /usr/local/bin /usr/local/lib /usr/local/sbin
    chmod u+w /usr/local/bin /usr/local/lib /usr/local/sbin
}

# Add bash keybindings for fzf
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
