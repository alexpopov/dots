#!/usr/bin/env /bin/bash

function maybe_back_to_normal {
    if [ "$1" = "back_to_default" ]; then
        skhd -k "escape"
    fi
}

function run_hs {
  script="$1"
  shift
  hs -c "$script"
  maybe_back_to_normal "$@"
}

function show_expose {
  skhd -k 'ctrl -0x7D'
}

function focus_window {
    direction="$1"
    shift
    case "$direction" in
        'stack.next')
            yabai -m window --focus stack.next || yabai -m window --focus stack.first
            ;;
        'stack.prev')
            yabai -m window --focus stack.prev || yabai -m window --focus stack.last
            ;;
        'most_reasonable')
            yabai -m window --focus mouse || (yabai -m window --focus largest || yabai -m window --focus first)
            ;;
        *)
            yabai -m window --focus $direction
            ;;
    esac
    maybe_back_to_normal "$@"
}

function swap_window {
    direction="$1"
    shift
    case "$direction" in
        'stack.next')
            yabai -m window --swap stack.next || yabai -m window --swap stack.first
            ;;
        'stack.prev')
            yabai -m window --swap stack.prev || yabai -m window --swap stack.last
            ;;
        *)
            yabai -m window --swap $direction
            ;;
    esac
    maybe_back_to_normal "$@"
}

function warp_window {
    direction="$1"
    shift
    case "$direction" in
        *)
            yabai -m window --warp $direction
            ;;
    esac
    maybe_back_to_normal "$@"
}

function config {
    type="$1"
    shift
    yabai -m config layout $type
    alert.sh simple "Layout mode: $type"
    maybe_back_to_normal "$@"
}

function reload_config {
    source ~/.yabairc
    alert.sh simple "Reloading config..."
    maybe_back_to_normal "$@"
}


function create_stack {
    direction="$1"
    shift
    yabai -m window --stack $direction
    alert.sh simple "Stacking $direction"
    maybe_back_to_normal "$@"
}

function unstack {
    window=$(yabai -m query --windows --window | jq -r '.id') && yabai -m window east --stack $window || (yabai -m window $window --toggle float && yabai -m window $window --toggle float)
    maybe_back_to_normal "$@"
}

function toggle_manage {
  window=$(yabai -m query --windows --window | jq -r '.id')
  yabai -m window $window --toggle float
  alert.sh simple "Toggling Managed Status"
  maybe_back_to_normal "$@"
}

function grid {
  type=$1
  shift
  case "$type" in
    'centre')
      yabai -m window --grid 9:9:2:1:5:6
      ;;

    'small-centre')
      yabai -m window --grid 8:8:2:2:4:4
      ;;

    'full')
      yabai -m window --grid 1:1:1:1:1:1
      ;;

    'equal')
      yabai -m query --windows --space | jq -r '.[] | select(."is-floating" == false) | .id'  | xargs -I{} yabai -m window {} --ratio abs:0.5
      ;;

    *)
      echo "unknown resize command $type"
      maybe_back_to_normal "$@"
      return
      ;;
  esac
  alert.sh simple "$type"
  maybe_back_to_normal "$@"
}

function toggle_fullscreen {
  yabai -m window --toggle zoom-fullscreen
  alert.sh simple "Toggle: Fullscreen"
  maybe_back_to_normal "$@"
}


USAGE="Usage: yabai_utils.sh focus west"

if [ "$#" == "0" ]; then
	echo "$USAGE"
	exit 1
fi

command="$1"
shift

case $command in
    'focus')
        focus_window "$@"
        ;;

    'config')
        config "$@"
        ;;

    'grid')
        grid "$@"
        ;;

    'swap')
        swap_window "$@"
        ;;

    'warp')
        warp_window "$@"
        ;;

    'reload_config')
        reload_config "$@"
        ;;

    'fullscreen')
        toggle_fullscreen "$@"
        ;;

    'stack')
        create_stack "$@"
        ;;

    'unstack')
        unstack "$@"
         ;;

    'toggle_manage')
        toggle_manage "$@"
        ;;

    'run_hs')
        run_hs "$@"
        ;;

    'show_expose')
      show_expose "$@"
      ;;

    *)
        hs -c 'hs.alert.show("yabai_utils: unhandled argument: $1")'
        ;;

esac
