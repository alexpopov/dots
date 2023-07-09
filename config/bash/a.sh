
ALP_A_COMMAND_CHOOSE_TMUX="select tmux session"
ALP_A_COMMAND_EXAMPLE="dummy command!"
function a {
  initial_arg="$1"
  shift
  choice=$(exact_command "$initial_arg")

  if [[ -z $choice ]]; then
    choice="$(echo $(choices) | tr ':' '\n' |  gum filter --value "$initial_arg")"
  fi

  if [[ -n $ALP_DEBUG ]]; then echo "Select choice: $choice"; fi

  call_choice "$choice" $@
}


function choices {
  local choices="$ALP_A_COMMAND_CHOOSE_TMUX:$ALP_A_COMMAND_EXAMPLE"
  echo "$choices"
}

# let's you skip the first level of commands
function exact_command {
  arg="$1"
  case "$arg" in
    "tmux")
      echo "$ALP_A_COMMAND_CHOOSE_TMUX"
      ;;
  esac
}

function call_choice {
  local choice="$1"
  shift
  case "$choice" in
    "$ALP_A_COMMAND_CHOOSE_TMUX")
      select_tmux_session
      ;;
    "$ALP_A_COMMAND_EXAMPLE")
      print_congrats
      ;;
    *)
      error_unhandled $1
      ;;
  esac
}

function error_unhandled {
      echo "Unhandled command $1"
      shift
      echo "Probably a bug?"
      echo "Other args: $@ "
}

function select_tmux_session {
  tmux_ls="$(tmux ls > /dev/null 2>&1)"
  if [[ $? != 0 ]]; then
    gum format "No Tmux sessions available..."
    if $(gum confirm "Create new Tmux session?"); then
      tmux
    fi
  else
    if [[ -n $ALP_DEBUG ]]; then echo "Tmux ls was $tmux_ls"; fi
    local choice index
    if ! choice="$(tmux ls | gum filter)"; then
      gum format "Cancelling..."
      return -1
    fi
    # tmux ls failed: no servers!
    if [[ -n $ALP_DEBUG ]]; then echo choice is $choice; fi
    index=$(echo "$choice" | awk '{ print substr($1, 0, length($1) -1) }')
    if [[ -n $ALP_DEBUG ]]; then echo index is $index; fi
    if [[ -n $ALP_DEBUG ]]; then echo Command: tmux a -t "$index"; fi
    tmux a -t "$index"
  fi

  }

  function print_congrats {
    echo "congrats, you picked a dummy command!"
  }
