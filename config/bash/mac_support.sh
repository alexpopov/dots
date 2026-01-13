# Don't forget to export PATH at the end

function jk_mac_fix_brew {
    echo "running sudo chown..."
    sudo chown -R $(whoami) /usr/local/bin /usr/local/lib /usr/local/sbin
    chmod u+w /usr/local/bin /usr/local/lib /usr/local/sbin
}

# Add bash keybindings for fzf
if [ -f ~/.fzf.bash ]; then
  source ~/.fzf.bash
else
  echo "Warning: \$HOME/.fzf.bash missing"
  echo "If you have fzf installed, run the following to create it:"
  echo
  echo 'fzf --bash > ~/.fzf.bash'
fi

# Bash completion
[[ -r "/usr/local/etc/bash_completion" ]] && . "/usr/local/etc/bash_completion"

# Load Git completion
# Get it with: 
# curl -o ~/.local/bin/.git-completion.bash https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash
if [ -f ~/.local/bin/.git-completion.bash ]; then
  . ~/.local/bin/.git-completion.bash
else
  echo "Error: git-completion not installed. Check out mac_support.sh"
  echo "TODO: bootstrap this part"
fi


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

# Add Blender to PATH if installed
if [ -d "/Applications/Blender.app/Contents/MacOS" ]; then
  PATH="/Applications/Blender.app/Contents/MacOS:$PATH"
fi

export PATH

# Meta work machine support
if [ -d /opt/facebook ]; then
  META_SUPPORT="$HOME/.config/bash/meta_macbook_support.sh"
  if [ -e "$META_SUPPORT" ]; then
    source "$META_SUPPORT"
  fi
fi

function kobo_sync_to_device {
  local destination_path=
  local local_path="/Volumes/KOBOeReader/"
  local kobo_ssh="root@192.168.1.74"
  if [[ -d $local_path ]] ; then 
    # echo "Not plugged in..."
    # echo "Trying ssh..."
    destination_path="$local_path"
  # elif nc -z -w 3 192.168.1.74 2222 > /dev/null 2>&1 ; then 
  #   # we can ssh to kobo
  #   echo "Can ssh!"
  #   destination_path="kobo:/mnt/onboard/"
  else
    echo "Error: no kobo plugged in or on network"
    return 1
  fi
  rsync -av --size-only --progress \
    --exclude='*.sdr/' \
    --exclude='Audiobooks/' \
    --exclude="German/" \
    --exclude="PDFs/" \
    --exclude="Pages/" \
    /Users/alp/Library/Mobile\ Documents/com~apple~CloudDocs/Books/ \
    "$destination_path"
    # --exclude='*.pdf' \
}

function kobo_backup_to_mac {
  rsync -av --progress /Volumes/KOBOeReader/ /Users/alp/Library/Mobile\ Documents/com~apple~CloudDocs/Kobo\ Backup/
}
