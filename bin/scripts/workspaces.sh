#!/usr/bin/env bash

source $HOME/.local/bin/scripts/color.sh

export _WORKSPACES_SCRIPT_WHOAMI="${BASH_SOURCE[0]}"
export _WORKSPACES_DEBUG_LOGS=0

echo "Welcome to Workspaces!"

function wo {
  if [ -z "$1" ]; then
    workspace_do_shortlist
    return 0
  fi

  local verb="$1"
  shift

  if [[ -z "$ALP_CURRENT_WORKSPACE" ]]; then
    case "$verb" in
      "setup" | "reload" | "last")
        # allow setup and reload to run without a workspace
        ;;
      *)
        _w_print_error "No workspace selected"
        return 1
        ;;
    esac
  fi

  local command="workspace_do_${verb}"
  local help_command="workspace_help_${verb}"

  if ! command -v "$command" > /dev/null 2>&1; then
    _w_fail_error 1 "Unknown sub-command ${color_blue}$verb${color_red}. Does a function ${color_blue}${command}${color_red} exist?"
  fi

  case "$verb" in
    "setup" | "reload" | "last")
      # Some commands edit environment, so they must run in this shell
      _w_print_debug_log "Running $verb in current shell"
      $command "$@"
      ;;

    *)
      # Run everything else in subshell
      _w_print_debug_log "Running $verb in subshell"
      ($command "$@")
      ;;
  esac
  _w_save_last_command
}

function workspace_do_shortlist {
  echo "shortlist not implemented, printing help instead"
  workspace_do_help
}

function workspace_do_last {
  if [[ -f $ALP_WORKSPACES_STATE_LAST_COMMAND ]]; then
    COMMAND="$(cat $ALP_WORKSPACES_STATE_LAST_COMMAND)"
    history -s "$COMMAND"
    . $ALP_WORKSPACES_STATE_LAST_COMMAND
  else
    _w_fail_error 1 "Last command unknown: $ALP_WORKSPACES_STATE_LAST_COMMAND"
  fi
}

export ALP_WORKSPACES_STATE_DIR="$HOME/.local/state/workspaces"
export ALP_WORKSPACES_STATE_LAST_COMMAND="${ALP_WORKSPACES_STATE_DIR}/last_command"

function _w_save_last_command {
  mkdir -p "$ALP_WORKSPACES_STATE_DIR"
  touch "$ALP_WORKSPACES_STATE_LAST_COMMAND"
  echo "$@" > $ALP_WORKSPACES_STATE_LAST_COMMAND
}

function _w_get_option {
  local option=$(echo "$@" | sort -u | gum choose $@)

  if [[ -z "$option" ]]; then
    return 1
  fi
  echo "$option"
}

function workspace_do_reload {
  if test -f "$_WORKSPACES_SCRIPT_WHOAMI"; then
    source "$_WORKSPACES_SCRIPT_WHOAMI"
  else
    _w_print_error "I can't find myself..."
    _w_print_error "Looked in: ${color_blue}$_WORKSPACES_SCRIPT_WHOAMI"
    return 1
  fi

  if [[ -n $ALP_CURRENT_WORKSPACE && -f $ALP_CURRENT_WORKSPACE ]]; then
    source $ALP_CURRENT_WORKSPACE
  else
    _w_print_error "I can't find the workspace..."
    _w_print_error "Looked in: ${color_blue}${ALP_CURRENT_WORKSPACE:-unset}"
    return 1
  fi
}

function workspace_do_help {
  echo "Beginner's guide:"
  echo "1. write a workspace script"
  echo "2. append it to \$ALP_WORKSPACES like the PATH variable"
  echo "    with : as a separator"
  echo "3. w setup"
}

function workspace_do_setup {
  # TODO: wipe all previous workspace commands when switching
  local workspaces workspace_script

  if [[ -z "$ALP_WORKSPACES" ]]; then
    _w_print_error "Error, \$ALP_WORKSPACES is empty! Please add a workspace script"
    return 1
  fi

  workspaces=$(echo $ALP_WORKSPACES | tr ':' '\n' | sort -u)
  if ! workspace_script=$(_w_get_option "$workspaces"); then
    _w_fail_error 1 "no workspace selected?"
  fi
  _w_print_debug_log "sourcing $workspace_script"
  source $workspace_script
  export ALP_CURRENT_WORKSPACE="$workspace_script"
}

function _w_fail_error {
  local code="$1"
  shift
  _w_print_error "$@"
  return $code
}

function _w_print_warn {
  >&2 echo -e "${color_yellow}WARN${color_reset}:  $@"
}

function _w_print_error {
  >&2 echo -e "${color_red}ERROR${color_reset}: $@"
}

function _w_print_debug_log {
  if [[ $_WORKSPACES_DEBUG_LOGS == 1 ]]; then
    >&2 echo -e "${color_purple}DEBUG${color_reset}: $@"
  fi
}
