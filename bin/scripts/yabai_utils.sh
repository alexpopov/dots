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

function focus_display {
    direction="$1"
    shift
    case "$direction" in
        *)
            yabai -m display --focus $direction
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

function warp_display {
    direction="$1"
    shift
    case "$direction" in
        *)
          # TODO: also change focus there
          local current_window_id="$(yabai -m query --windows --window | jq '.id')"
          yabai -m window --display $direction
          yabai -m window --focus "$current_window_id"
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

function resize {
  local type=$1
  shift
  local amount=${1:-20}
  shift
  case "$type" in
    'left')
      yabai -m window --resize "right:-${amount}:0" 2> /dev/null || yabai -m window --resize "left:-${amount}:0" 2> /dev/null
      ;;

    'right')
      yabai -m window --resize "right:${amount}:0" 2> /dev/null || yabai -m window --resize "left:${amount}:0" 2> /dev/null
      ;;

    'down')
      yabai -m window --resize "bottom:0:${amount}" 2> /dev/null || yabai -m window --resize "top:0:${amount}" 2> /dev/null
      ;;

    'up')
      yabai -m window --resize "bottom:0:-${amount}" 2> /dev/null || yabai -m window --resize "top:0:-${amount}" 2> /dev/null
      ;;

    *)
      echo "unknown resize command $type"
      maybe_back_to_normal "$@"
      return
      ;;
  esac
  # alert.sh simple "$type"
  maybe_back_to_normal "$@"
}

function toggle_fullscreen {
  yabai -m window --toggle zoom-fullscreen
  # alert.sh simple "Toggle: Fullscreen is buggy WARNING"
  maybe_back_to_normal "$@"
}

function auto_hide_dock {
  action="$1"
  shift
  case "$action" in
    "show")
      osascript -e 'tell application "System Events" to set the autohide of the dock preferences to false'
      yabai -m config left_padding 8
      alert.sh simple "Show dock"
      ;;
    "hide")
      osascript -e 'tell application "System Events" to set the autohide of the dock preferences to true'
      yabai -m config left_padding 8
      alert.sh simple "Hide dock"
      ;;
    *)
      alert.sh simple "Unknown dock option $action"
      ;;
  esac
  maybe_back_to_normal "$@"
}

function manage_apps {
  local rule="$1"
  for app in "$@"; do
    yabai -m rule --remove "$app"
    yabai -m rule --add label="$app" app="$app" manage="$rule"
    yabai -m rule --apply "$app"
  done
  yabai -m rule --apply
}

function style {
  local action="$1"
  shift

  case "$action" in
    "condensed")
      local padding=8
      yabai -m config top_padding    $padding
      yabai -m config bottom_padding $padding
      yabai -m config left_padding   $padding
      yabai -m config right_padding  $padding
      yabai -m config window_gap     $padding
      ;;

    "airy")
      local padding=120
      yabai -m config top_padding    $padding
      yabai -m config bottom_padding $padding
      yabai -m config left_padding   $padding
      yabai -m config right_padding  $padding
      yabai -m config window_gap     30
      ;;

    *)
      echo "error, unknown action $action"

  esac

  maybe_back_to_normal "$@"
}

function manage {
  local action="$1"
  shift

  local apps=(
    "Books"
    "Calendar"
    "Discord"
    "Finder"
    "Messages"
    "Messenger"
    "Music"
    "Notion"
    "Numbers"
    "Pages"
    "Photos"
    "Preview"
    "Safari"
    "Sheets"
    "Slack"
    "Spark"
    "Telegram"
    "Things"
    "WhatsApp"
    "Workplace Chat"
  )
  local nomanagerule="No Manage"

  case "$action" in
    "less")
      yabai -m rule --remove "$nomanagerule"
      manage_apps off "${apps[@]}"
      ;;

    "more")
      yabai -m rule --remove "$nomanagerule"
      manage_apps on "${apps[@]}"
      ;;

    "none")
      yabai -m rule --add label="$nomanagerule" app=".*" manage="off"
      yabai -m rule --apply
      ;;
    *)
      echo "error, unknown action $action"

  esac

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

  'focus_display')
    focus_display "$@"
    ;;

  'config')
    config "$@"
    ;;

  'grid')
    grid "$@"
    ;;

  'resize')
    resize "$@"
    ;;

  'swap')
    swap_window "$@"
    ;;

  'warp')
    warp_window "$@"
    ;;

  'warp_display')
    warp_display "$@"
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

  'dock')
    auto_hide_dock "$@"
    ;;

  'style')
    style "$@"
    ;;

  'manage')
    manage "$@"
    ;;

  *)
    hs -c "hs.alert.show(\"yabai_utils: unhandled argument: $1\")"
    ;;

  esac
