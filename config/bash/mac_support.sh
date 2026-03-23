# Don't forget to export PATH at the end

# Add Homebrew to PATH (Apple Silicon location, Intel uses /usr/local)
PATH="/opt/homebrew/bin:$PATH"
PATH="/opt/homebrew/sbin:$PATH"

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

# Load Git completion (auto-download if missing)
_git_completion="$HOME/.local/bin/.git-completion.bash"
if [ ! -f "$_git_completion" ]; then
  mkdir -p "$(dirname "$_git_completion")"
  curl -so "$_git_completion" \
    https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash \
    && echo "Downloaded git-completion.bash" \
    || echo "Warning: failed to download git-completion.bash"
fi
[ -f "$_git_completion" ] && . "$_git_completion"


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

# Buckets budgeting app — used by budget-tool CLI (~/Development/budget_tools/)
export BUDGET_DB="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/Important/Budget/Our Budget.buckets"

# Meta work machine support
if [ -d /opt/facebook ]; then
  META_SUPPORT="$HOME/.config/bash/meta_macbook_support.sh"
  if [ -e "$META_SUPPORT" ]; then
    source "$META_SUPPORT"
  fi
fi

# Sync iCloud Books to Kobo eReader device
function kobo_sync_to_device {
  local kobo_path="/Volumes/KOBOeReader/"
  local source_path="/Users/alp/Library/Mobile Documents/com~apple~CloudDocs/Books/"

  if [[ ! -d "$kobo_path" ]]; then
    echo "Error: Kobo not found at $kobo_path"
    echo "Please connect your Kobo eReader via USB"
    return 1
  fi

  if [[ ! -d "$source_path" ]]; then
    echo "Error: Source directory not found at $source_path"
    return 1
  fi

  rsync -av --size-only --progress \
    --exclude='*.sdr/' \
    --exclude='Audiobooks/' \
    --exclude='German/' \
    --exclude='PDFs/' \
    --exclude='Pages/' \
    "$source_path" \
    "$kobo_path"
}

function calibre_export_select {
  local calibredb="/Applications/calibre.app/Contents/MacOS/calibredb"
  local dest="/Users/alp/Library/Mobile Documents/com~apple~CloudDocs/Books"
  local selected
  selected=$("$calibredb" list --fields title,authors --for-machine | python3 -c "
import json, sys
books = json.load(sys.stdin)
for b in sorted(books, key=lambda x: x.get('authors','')):
    print(f\"{b['id']}\t{b['authors']} - {b['title']}\")
" | fzf --multi --with-nth=2.. --delimiter='\t' --prompt='Select books> ' | cut -f1 | tr '\n' ',' | sed 's/,$//')
  if [[ -z "$selected" ]]; then
    echo "No books selected"
    return 1
  fi
  echo "Exporting IDs: $selected"
  "$calibredb" export "$selected" \
    --to-dir "$dest" \
    --formats epub \
    --dont-save-extra-files \
    --progress
}

function calibre_export_to_icloud {
  local calibredb="/Applications/calibre.app/Contents/MacOS/calibredb"
  local dest="/Users/alp/Library/Mobile Documents/com~apple~CloudDocs/Books"
  "$calibredb" export --all \
    --to-dir "$dest" \
    --formats epub \
    --dont-save-extra-files \
    --progress
}

# Backup Kobo eReader to iCloud
function kobo_backup_to_mac {
  local kobo_path="/Volumes/KOBOeReader/"
  local backup_path="/Users/alp/Library/Mobile Documents/com~apple~CloudDocs/Kobo Backup/"

  if [[ ! -d "$kobo_path" ]]; then
    echo "Error: Kobo not found at $kobo_path"
    echo "Please connect your Kobo eReader via USB"
    return 1
  fi

  rsync -av --progress \
    --exclude='.Trashes' \
    --exclude='.Spotlight-V100' \
    --exclude='.fseventsd' \
    "$kobo_path" \
    "$backup_path"
}
