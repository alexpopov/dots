#!/usr/bin/env /bin/bash

function maybe_back_to_normal {
    if [ "$1" = "back_to_default" ]; then
        local action_name="$2"
        local context="$3"
        if [ -n "$action_name" ] && [ -n "$context" ]; then
            hs -c "skhdUI:exit_with_action('$action_name', '$context')"
        elif [ -n "$action_name" ]; then
            hs -c "skhdUI:exit_with_action('$action_name')"
        fi
        skhd -k "escape"
    fi
}

function run_hs {
  script="$1"
  shift
  local back_flag="$1"
  hs -c "$script"
  maybe_back_to_normal "$back_flag" "Run Script"
  if [ "$back_flag" != "back_to_default" ]; then
      hs -c "skhdUI:action('Run Script')" &
  fi
}

function show_expose {
  skhd -k 'ctrl -0x7D'
}

function focus_window {
    direction="$1"
    shift
    local back_flag="$1"

    local action_name
    case "$direction" in
        'west') action_name="Left" ;;
        'east') action_name="Right" ;;
        'north') action_name="Up" ;;
        'south') action_name="Down" ;;
        'stack.next') action_name="Stack Next" ;;
        'stack.prev') action_name="Stack Prev" ;;
        'most_reasonable') action_name="Focus" ;;
        *) action_name="$direction" ;;
    esac

    maybe_back_to_normal "$back_flag" "$action_name" "focus"
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
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('$action_name')" &
    fi
}

function focus_display {
    direction="$1"
    shift
    local back_flag="$1"

    local action_name
    case "$direction" in
        'west') action_name="Display Left" ;;
        'east') action_name="Display Right" ;;
        'north') action_name="Display Up" ;;
        'south') action_name="Display Down" ;;
        *) action_name="Display $direction" ;;
    esac

    maybe_back_to_normal "$back_flag" "$action_name" "focus"
    case "$direction" in
        *)
            yabai -m display --focus $direction
            ;;
    esac
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('$action_name')" &
    fi
}

function swap_window {
    direction="$1"
    shift
    local back_flag="$1"

    local action_name
    case "$direction" in
        'west') action_name="Left" ;;
        'east') action_name="Right" ;;
        'north') action_name="Up" ;;
        'south') action_name="Down" ;;
        *) action_name="$direction" ;;
    esac

    maybe_back_to_normal "$back_flag" "$action_name"
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
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('$action_name')" &
    fi
}

function warp_window {
    direction="$1"
    shift
    local back_flag="$1"

    local action_name
    case "$direction" in
        'west') action_name="Left" ;;
        'east') action_name="Right" ;;
        'north') action_name="Up" ;;
        'south') action_name="Down" ;;
        *) action_name="$direction" ;;
    esac

    maybe_back_to_normal "$back_flag" "$action_name"
    case "$direction" in
        *)
            yabai -m window --warp $direction
            ;;
    esac
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('$action_name')" &
    fi
}

function warp_display {
    direction="$1"
    shift
    local back_flag="$1"

    local action_name
    case "$direction" in
        'west') action_name="Display West" ;;
        'east') action_name="Display East" ;;
        'north') action_name="Display North" ;;
        'south') action_name="Display South" ;;
        *) action_name="Display $direction" ;;
    esac

    maybe_back_to_normal "$back_flag" "$action_name"
    case "$direction" in
        *)
          alert.sh simple "$direction"
          # TODO: also change focus there
          local current_window_id="$(yabai -m query --windows --window | jq '.id')"
          yabai -m window --display $direction
          yabai -m window --focus "$current_window_id"
          ;;
    esac
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('$action_name')" &
    fi
}

function config {
    type="$1"
    shift
    local back_flag="$1"

    local action_name
    case "$type" in
        'float') action_name="Float Layout" ;;
        'bsp') action_name="BSP Layout" ;;
        *) action_name="$type Layout" ;;
    esac

    maybe_back_to_normal "$back_flag" "$action_name"
    yabai -m config layout $type
    alert.sh simple "Layout mode: $type"
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('$action_name')" &
    fi
}

function reload_config {
    local back_flag="$1"
    maybe_back_to_normal "$back_flag" "Reload"
    source ~/.yabairc
    alert.sh simple "Reloading config..."
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('Reload')" &
    fi
}


function create_stack {
    direction="$1"
    shift
    local back_flag="$1"

    local action_name
    case "$direction" in
        'west') action_name="Stack Left" ;;
        'east') action_name="Stack Right" ;;
        'north') action_name="Stack Up" ;;
        'south') action_name="Stack Down" ;;
        *) action_name="Stack $direction" ;;
    esac

    maybe_back_to_normal "$back_flag" "$action_name"
    yabai -m window --stack $direction
    alert.sh simple "Stacking $direction"
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('$action_name')" &
    fi
}

function unstack {
    local back_flag="$1"
    maybe_back_to_normal "$back_flag" "Unstack"
    window=$(yabai -m query --windows --window | jq -r '.id') && yabai -m window east --stack $window || (yabai -m window $window --toggle float && yabai -m window $window --toggle float)
    if [ "$back_flag" != "back_to_default" ]; then
        hs -c "skhdUI:action('Unstack')" &
    fi
}

function toggle_manage {
  local back_flag="$1"
  maybe_back_to_normal "$back_flag" "Toggle Float"
  window=$(yabai -m query --windows --window | jq -r '.id')
  yabai -m window $window --toggle float
  alert.sh simple "Toggling Managed Status"
  if [ "$back_flag" != "back_to_default" ]; then
      hs -c "skhdUI:action('Toggle Float')" &
  fi
}

function grid {
  type=$1
  shift

  local action_name
  case "$type" in
    'centre') action_name="Center" ;;
    'small-centre') action_name="Small Center" ;;
    'full') action_name="Full" ;;
    'equal') action_name="Equal" ;;
    'balance') action_name="Balance" ;;
    'rotate') action_name="Rotate" ;;
    '3') action_name="Grid 3x3" ;;
    '4') action_name="Grid 4x4" ;;
    '5') action_name="Grid 5x5" ;;
    *) action_name="$type" ;;
  esac

  # For 3/4/5 cases, the first remaining arg is 'where', not back_to_default.
  # For other cases, the first remaining arg may be back_to_default.
  local back_flag
  case "$type" in
    '3' | '4' | '5')
      # $1 is 'where' sub-arg, $2 would be back_to_default
      back_flag="$2"
      ;;
    *)
      back_flag="$1"
      ;;
  esac

  maybe_back_to_normal "$back_flag" "$action_name"
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

    '3' | '4' | '5')
      # <rows>:<cols>:<start-x>:<start-y>:<width>:<height>
      local grid="$type"
      local where="$1"
      echo "Grid: $type, where: $where"
      shift
      local grid_size="$grid:$grid"
      local window_placement=
      local window_length=$((grid - 2))
      local window_size=
      local grid_specifier=
      case "$where" in
        d)
          window_placement="1:1"
          window_size="$window_length:$window_length"
          grid_specifier="${grid_size}:${window_placement}:${window_size}"
          ;;
        *)
          echo "unknown area: '$where'"
      esac
      echo "Grid specifier: $grid_specifier"
      yabai -m window --grid "$grid_specifier"
      ;;

    *)
      echo "unknown resize command $type"
      return
      ;;
  esac
  alert.sh simple "$type"
  if [ "$back_flag" != "back_to_default" ]; then
      hs -c "skhdUI:action('$action_name')" &
  fi
}

function resize {
  local type=$1
  shift
  local amount=${1:-20}
  shift
  local back_flag="$1"

  local action_name
  case "$type" in
    'left') action_name="Left" ;;
    'right') action_name="Right" ;;
    'up') action_name="Up" ;;
    'down') action_name="Down" ;;
    *) action_name="$type" ;;
  esac

  maybe_back_to_normal "$back_flag" "$action_name"
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
  if [ "$back_flag" != "back_to_default" ]; then
      hs -c "skhdUI:action('$action_name')" &
  fi
}

function toggle_fullscreen {
  local back_flag="$1"
  maybe_back_to_normal "$back_flag" "Fullscreen"
  yabai -m window --toggle zoom-fullscreen
  # alert.sh simple "Toggle: Fullscreen is buggy WARNING"
  if [ "$back_flag" != "back_to_default" ]; then
      hs -c "skhdUI:action('Fullscreen')" &
  fi
}

function auto_hide_dock {
  action="$1"
  shift
  local back_flag="$1"

  local action_name
  case "$action" in
    "show") action_name="Show Dock" ;;
    "hide") action_name="Hide Dock" ;;
    *) action_name="Dock $action" ;;
  esac

  maybe_back_to_normal "$back_flag" "$action_name"
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
  if [ "$back_flag" != "back_to_default" ]; then
      hs -c "skhdUI:action('$action_name')" &
  fi
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
  local back_flag="$1"

  local action_name
  case "$action" in
    "condensed") action_name="Condensed" ;;
    "airy") action_name="Airy" ;;
    *) action_name="$action" ;;
  esac

  maybe_back_to_normal "$back_flag" "$action_name"

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
  if [ "$back_flag" != "back_to_default" ]; then
      hs -c "skhdUI:action('$action_name')" &
  fi
}

function manage {
  local action="$1"
  shift
  local back_flag="$1"

  local action_name
  case "$action" in
    "less") action_name="Manage Less" ;;
    "more") action_name="Manage More" ;;
    "none") action_name="Manage None" ;;
    *) action_name="Manage $action" ;;
  esac

  maybe_back_to_normal "$back_flag" "$action_name"

  local apps=(
    "Books"
    "Calendar"
    "Discord"
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
  if [ "$back_flag" != "back_to_default" ]; then
      hs -c "skhdUI:action('$action_name')" &
  fi
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
