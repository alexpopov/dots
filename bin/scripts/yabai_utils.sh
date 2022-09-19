#!/usr/bin/env /bin/bash

function maybe_back_to_normal {
    if [ "$1" = "back_to_default" ]; then
        skhd -k "escape"
    fi
}

function focus_window {
    direction="$1"
    shift
    yabai -m window --focus $direction
    maybe_back_to_normal "$@"
}

function config {
    type="$1"
    shift
    yabai -m config layout $type
    alert.sh simple "Layout mode: $type"
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

    *)
    hs -c 'hs.alert.show("unhandled argument: $1")'
    ;;

esac
