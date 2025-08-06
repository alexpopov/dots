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
#
# https://ezprompt.net/
case "$HOSTNAME" in
  this_computer*)
    LAST_DEATH=/tmp/last_death
    if [[ ! -f $LAST_DEATH ]]; then
      echo $(date +%s) > "$LAST_DEATH"
    fi
    PROMPT_PREFIX="\[\e[1;33m\]Hel\[\e[m\]\[\e[1;34m\]heim\[\e[m\] "
    echo "I am Helheim"
    ansi_color_black="\[\e[1;30m\]"
    ansi_color_red="\[\e[1;31m\]"
    ansi_color_green="\[\e[0;32m\]"
    ansi_color_yellow="\[\e[1;33m\]"
    ansi_color_blue="\[\e[1;34m\]"
    ansi_color_reset="\[\e[m\]"
    function human_time {
      local T=$1
      local D=$((T/60/60/24))
      local H=$((T/60/60%24))
      local M=$((T/60%60))
      local S=$((T%60))
      (( D > 0 )) && printf '%d days, ' $D
      (( H > 0 )) && printf '%d hours, ' $H
      (( M > 0 )) && printf '%d minutes and ' $M
      printf '%d seconds\n' $S
    }
    function run_prompt_prefix {
      NORMAL_MESSAGE="${ansi_color_yellow}Hel${ansi_color_blue}heim${ansi_color_reset}"
      ERROR_MESSAGE="${ansi_color_red}YOU DIED${ansi_color_reset}"
      local last_return="$1"
      local ps1=""
      PROMPT_PREFIX=
      case "$last_return" in
        0 | 130)
          ps1+="$NORMAL_MESSAGE"
          ;;

        *)
          local now=$(date +%s)
          local time_since=$((now - $(cat $LAST_DEATH)))
          ps1+="$ERROR_MESSAGE (${ansi_color_blue}$(basename $(history 1 | awk '{ print $4; exit }'))${ansi_color_reset} killed you with ${ansi_color_blue}$last_return damage${ansi_color_reset}) ${ansi_color_red}You survived $(human_time $time_since)${ansi_color_reset}\n${ansi_color_red}Welcome back to ${ansi_color_yellow}Hel${ansi_color_reset}"
          echo $now > $LAST_DEATH
          ;;

      esac
      echo -e "$ps1 "
    }
    ;;
  *)
    PROMPT_PREFIX="\[\e[34m\]mysterious \[\e[m\]\[\e[36m\]stranger\[\e[m\] "
    ;;
esac


# Always run sanity checks at the end
. $SANITY_CHECK
