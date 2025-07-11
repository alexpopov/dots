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
    maybe_back_to_normal "$@"
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
}

function focus_display {
    direction="$1"
    shift
    maybe_back_to_normal "$@"
    case "$direction" in
        *)
            yabai -m display --focus $direction
            ;;
    esac
}

function swap_window {
    direction="$1"
    shift
    maybe_back_to_normal "$@"
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
}

function warp_window {
    direction="$1"
    shift
    maybe_back_to_normal "$@"
    case "$direction" in
        *)
            yabai -m window --warp $direction
            ;;
    esac
}

function warp_display {
    direction="$1"
    shift
    maybe_back_to_normal "$@"
    case "$direction" in
        *)
          alert.sh simple "$direction"
          # TODO: also change focus there
          local current_window_id="$(yabai -m query --windows --window | jq '.id')"
          yabai -m window --display $direction
          yabai -m window --focus "$current_window_id"
          ;;
    esac
}

function config {
    type="$1"
    shift
    maybe_back_to_normal "$@"
    yabai -m config layout $type
    alert.sh simple "Layout mode: $type"
}

function reload_config {
    maybe_back_to_normal "$@"
    source ~/.yabairc
    alert.sh simple "Reloading config..."
}


function create_stack {
    direction="$1"
    shift
    maybe_back_to_normal "$@"
    yabai -m window --stack $direction
    alert.sh simple "Stacking $direction"
}

function unstack {
    maybe_back_to_normal "$@"
    window=$(yabai -m query --windows --window | jq -r '.id') && yabai -m window east --stack $window || (yabai -m window $window --toggle float && yabai -m window $window --toggle float)
}

function toggle_manage {
  maybe_back_to_normal "$@"
  window=$(yabai -m query --windows --window | jq -r '.id')
  yabai -m window $window --toggle float
  alert.sh simple "Toggling Managed Status"
}

function grid {
  type=$1
  shift
  maybe_back_to_normal "$@"
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

    'balance')
      yabai -m space --layout bsp
      ;;

    'rotate')
      yabai -m space --rotate 270
      ;;

    *)
      echo "unknown resize command $type"
      return
      ;;
  esac
  alert.sh simple "$type"
}

function resize {
  local type=$1
  shift
  local amount=${1:-20}
  shift
  maybe_back_to_normal "$@"
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
      return
      ;;
  esac
  # alert.sh simple "$type"
}

function toggle_fullscreen {
  maybe_back_to_normal "$@"
  yabai -m window --toggle zoom-fullscreen
  # alert.sh simple "Toggle: Fullscreen is buggy WARNING"
}

function auto_hide_dock {
  action="$1"
  shift
  maybe_back_to_normal "$@"
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
  maybe_back_to_normal "$@"

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

}

function manage {
  local action="$1"
  shift
  maybe_back_to_normal "$@"

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
