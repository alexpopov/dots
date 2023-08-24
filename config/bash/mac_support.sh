# Don't forget to export PATH at the end

function jk_mac_fix_brew {
    echo "running sudo chown..."
    sudo chown -R $(whoami) /usr/local/bin /usr/local/lib /usr/local/sbin
    chmod u+w /usr/local/bin /usr/local/lib /usr/local/sbin
}

# Add bash keybindings for fzf
[ -f ~/.fzf.bash ] && source ~/.fzf.bash


# May want to gate this in the future:

# START: tools to build KOReader

if [[ -n $BUILD_KO_READER ]]; then
  PATH="/opt/homebrew/bin:$PATH"
  PATH="/opt/homebrew/opt/bison/bin:$PATH"
  # For compilers to find bison you may need to set:
  #  export LDFLAGS="-L/opt/homebrew/opt/bison/lib"

  PATH="/opt/homebrew/opt/grep/libexec/gnubin:$PATH"
  PATH="/opt/homebrew/opt/gnu-getopt/bin:$PATH"
  PATH="/opt/homebrew/opt/libtool/libexec/gnubin:$PATH"
  PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"

  PATH="/opt/homebrew/opt/binutils/bin:$PATH"
  # For compilers to find binutils you may need to set:
  #   export LDFLAGS="-L/opt/homebrew/opt/binutils/lib"
  #   export CPPFLAGS="-I/opt/homebrew/opt/binutils/include"

  # END: tools to build KOReader
fi

export PATH
