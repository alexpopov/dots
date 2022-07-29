# Files to load
MAIN_BASH_PROFILE="$HOME/.config/bash/bash_profile.sh"
HG_SUPPORT="$HOME/.config/bash/hg_support.sh"

# Optional, platform-specific files
MAC_SUPPORT="$HOME/.config/bash/mac_support.sh"
OTHER_SCRIPT="$HOME/.config/bash/private/other_support.sh"

# Sanity-check files
SANITY_CHECK="$HOME/.config/bash/sanity_check.sh"

for file in $MAIN_BASH_PROFILE $HG_SUPPORT
do
    if [ -e "$file" ]; then
        . $file
    else
        echo "WARNING: Could not source $file; file does not exist"
    fi
done

### Uncomment Features:

## Source optional platform files:
# . $MAC_SUPPORT
# . $OTHER_SCRIPT

## *After* you create a neovim virtual environment, consider using this line:
# export NVIM_PYTHON="$HOME/.local/virtualenvs/nvim/bin/python3"

## Enable private work features:
# export ENABLE_PRIVATE_FACEBOOK=1


# Always run sanity checks at the end
. $SANITY_CHECK
